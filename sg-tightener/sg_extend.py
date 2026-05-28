#!/usr/bin/env python3
"""sg_extend.py — strictly additive break-glass ingress extender.

Adds ingress rules to one or more security groups WITHOUT removing
anything. Designed to be run quickly under incident pressure to unblock
DR failovers, supplier IP changes, or any case where the standard
plan/apply loop is too slow. The worst-case outcome of a wrong invocation
is a broader permission set — never an outage.

Every invocation writes a timestamped manifest recording exactly what
was added so the next tightening cycle can fold the changes back into
the evidence base.

Usage:
  sg_extend.py --groups sg-aaaa,sg-bbbb
               --cidrs 10.1.2.0/24,10.1.3.0/24
               --ports 443,5432
               [--protocol tcp]
               [--description "DR failover 2026-05-28"]
               [--region us-east-1]
               [--max-rules 60]
               [--yes]
"""

from __future__ import annotations

import argparse
import datetime as dt
import ipaddress
import json
import logging
import re
import sys
from typing import Sequence

try:
    import boto3
    import botocore
    from botocore.config import Config as BotoConfig
except ImportError:
    boto3 = None
    botocore = None
    BotoConfig = None

LOG = logging.getLogger("sg_extend")

GROUP_ID_RE = re.compile(r"^sg-[0-9a-f]{8,17}$")
PORT_SPEC_RE = re.compile(r"^(\d{1,5})(?:-(\d{1,5}))?$")


def parse_cidr(value: str) -> str:
    """Validate a CIDR. Must include a prefix length. Returns canonical form."""
    if "/" not in value:
        raise ValueError(f"CIDR must include prefix length: {value!r}")
    net = ipaddress.ip_network(value.strip(), strict=False)
    return str(net)


def parse_port_spec(value: str) -> tuple[int, int]:
    """Parse '443' or '8000-8100' into (from_port, to_port). Raises on garbage."""
    m = PORT_SPEC_RE.match(value.strip())
    if not m:
        raise ValueError(f"invalid port spec: {value!r}")
    lo = int(m.group(1))
    hi = int(m.group(2)) if m.group(2) else lo
    if not (0 <= lo <= 65535 and 0 <= hi <= 65535):
        raise ValueError(f"port out of range: {value!r}")
    if hi < lo:
        raise ValueError(f"port range hi < lo: {value!r}")
    return lo, hi


def parse_group_id(value: str) -> str:
    if not GROUP_ID_RE.match(value.strip()):
        raise ValueError(f"not a security-group id: {value!r}")
    return value.strip()


# --------------------------------------------------------------------------- #
# Apply
# --------------------------------------------------------------------------- #

def _require_boto3():
    if boto3 is None:
        sys.stderr.write("boto3 is required. Activate the venv from ./install.sh\n")
        sys.exit(2)


def _rule_count(sg: dict) -> int:
    n = 0
    for perm in sg.get("IpPermissions", []):
        n += len(perm.get("IpRanges", []))
        n += len(perm.get("Ipv6Ranges", []))
        n += len(perm.get("UserIdGroupPairs", []))
        n += len(perm.get("PrefixListIds", []))
    return n


def _build_perms(
    cidrs: list[str],
    ports: list[tuple[int, int]],
    protocol: str,
    description: str,
) -> list[dict]:
    return [
        {
            "IpProtocol": protocol,
            "FromPort": lo,
            "ToPort": hi,
            "IpRanges": [{"CidrIp": c, "Description": description} for c in cidrs],
        }
        for lo, hi in ports
    ]


def main(argv: Sequence[str] | None = None) -> int:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    p = argparse.ArgumentParser(prog="sg_extend.py")
    p.add_argument("--groups", required=True, help="comma-separated SG ids")
    p.add_argument("--cidrs", required=True, help="comma-separated CIDRs")
    p.add_argument("--ports", required=True, help="comma-separated ports or ranges")
    p.add_argument("--protocol", default="tcp")
    p.add_argument("--description", default="sg-extend break-glass")
    p.add_argument("--region")
    p.add_argument("--max-rules", type=int, default=60)
    p.add_argument("--yes", action="store_true", help="bypass the 'extend' prompt")
    args = p.parse_args(argv)

    try:
        groups = [parse_group_id(g) for g in args.groups.split(",") if g.strip()]
        cidrs = [parse_cidr(c) for c in args.cidrs.split(",") if c.strip()]
        ports = [parse_port_spec(p_) for p_ in args.ports.split(",") if p_.strip()]
    except ValueError as exc:
        sys.exit(f"input error: {exc}")

    if not groups or not cidrs or not ports:
        sys.exit("must supply at least one group, one cidr, and one port")

    if not args.yes:
        try:
            answer = input("Type 'extend' to apply: ").strip().lower()
        except EOFError:
            answer = ""
        if answer != "extend":
            sys.exit("aborted")

    _require_boto3()
    cfg = BotoConfig(retries={"max_attempts": 10, "mode": "adaptive"})
    ec2 = boto3.client("ec2", region_name=args.region, config=cfg)

    perms = _build_perms(cidrs, ports, args.protocol, args.description)
    new_rule_count_per_group = len(cidrs) * len(ports)

    manifest = {
        "schema": "sg-extend.manifest/v1",
        "applied_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "region": args.region,
        "description": args.description,
        "cidrs": cidrs,
        "ports": [f"{lo}-{hi}" if hi != lo else str(lo) for lo, hi in ports],
        "protocol": args.protocol,
        "groups": [],
    }

    sg_desc = ec2.describe_security_groups(GroupIds=groups)["SecurityGroups"]
    sg_by_id = {sg["GroupId"]: sg for sg in sg_desc}

    for gid in groups:
        sg = sg_by_id.get(gid)
        if sg is None:
            manifest["groups"].append({"group_id": gid, "status": "NOT_FOUND"})
            LOG.warning("%s not found — skipped", gid)
            continue
        existing = _rule_count(sg)
        if existing + new_rule_count_per_group > args.max_rules:
            manifest["groups"].append({
                "group_id": gid,
                "status": "SKIPPED_BUDGET",
                "existing_rules": existing,
                "would_add": new_rule_count_per_group,
                "max_rules": args.max_rules,
            })
            LOG.warning(
                "%s skipped: %d existing + %d new > %d max",
                gid, existing, new_rule_count_per_group, args.max_rules,
            )
            continue
        try:
            ec2.authorize_security_group_ingress(GroupId=gid, IpPermissions=perms)
            manifest["groups"].append({
                "group_id": gid,
                "status": "ADDED",
                "rules": perms,
            })
            LOG.info("added %d rules to %s", new_rule_count_per_group, gid)
        except botocore.exceptions.ClientError as exc:
            err = str(exc)
            if "InvalidPermission.Duplicate" in err:
                manifest["groups"].append({
                    "group_id": gid,
                    "status": "PARTIAL_DUPLICATE",
                    "error": err,
                })
                LOG.info("some rules already existed on %s", gid)
            else:
                manifest["groups"].append({
                    "group_id": gid,
                    "status": "ERROR",
                    "error": err,
                })
                LOG.error("authorize failed on %s: %s", gid, exc)

    ts = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    manifest_path = f"sg_extend-manifest-{ts}.json"
    with open(manifest_path, "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=2)
    LOG.info("manifest written to %s", manifest_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
