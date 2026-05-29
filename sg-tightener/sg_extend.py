#!/usr/bin/env python3
"""sg_extend.py — flow-log-driven break-glass ingress extender.

Break-glass tool for live incidents. Reads VPC flow logs over a recent
window (default: the last 24 hours), finds the source IPs whose traffic was
REJECTED, and adds ingress rules to the operator-named security groups so
that the blocked traffic is unblocked immediately — without waiting for the
standard analyse/plan/apply loop.

Design guarantees:
  * Strictly additive. It only ever calls AuthorizeSecurityGroupIngress and
    never revokes anything. The worst-case outcome of a wrong invocation is
    a broader permission set, never an outage.
  * Rule-budget aware. The discovered source IPs are grouped into the
    smallest CIDR blocks allowed by ``--tolerance`` — the fraction of unused
    (never-observed) addresses tolerated inside a grouping block. A tolerance
    of 0.5 lets a CIDR be used to cover a set of IPs even when half of that
    block's addresses were never seen. Grouping is done per protocol/port, so
    a rule only ever opens the port that was actually rejected. Raise the
    tolerance to fit more sources into fewer rules under the per-group limit.
  * Private by default. Only RFC 1918 source IPs are added; internet REJECT
    noise is ignored unless ``--include-public`` is given.

Every invocation writes a timestamped manifest recording exactly what was
added so the next tightening cycle can fold the changes back into the
evidence base. Part of the CloudToRepo project: https://cloudtorepo.com

Usage:
  sg_extend.py --region us-east-1
               --groups sg-aaaa,sg-bbbb
               (--log-group <name> | --s3-bucket <b> [--s3-prefix <p>])
               [--hours 24]
               [--tolerance 0.5]         # fraction of unused IPs allowed per CIDR
               [--ports 443,5432]        # restrict to these dst ports/ranges
               [--include-public]        # also add non-RFC1918 sources
               [--description "DR failover 2026-05-28"]
               [--max-rules 60]
               [--yes]
"""

from __future__ import annotations

import argparse
import datetime as dt
import gzip
import ipaddress
import json
import logging
import re
import sys
import time
from typing import Sequence

try:
    import boto3
    import botocore
except ImportError:
    boto3 = None
    botocore = None

from sg_tightener import (
    DEFAULT_TOLERANCE,
    RFC1918_BLOCKS,
    _client,
    collapse_ips_to_cidrs,
)

LOG = logging.getLogger("sg_extend")

GROUP_ID_RE = re.compile(r"^sg-[0-9a-f]{8,17}$")
PORT_SPEC_RE = re.compile(r"^(\d{1,5})(?:-(\d{1,5}))?$")

# VPC flow logs record the IANA protocol number. We only build ingress
# rules for the port-bearing protocols that account for essentially all
# application traffic; anything else (ICMP, ESP, ...) is skipped with a
# warning because a port-scoped break-glass rule would be meaningless.
PROTO_NUM_TO_NAME = {"6": "tcp", "17": "udp"}


# --------------------------------------------------------------------------- #
# Input validation (kept stable — imported by the regression suite)
# --------------------------------------------------------------------------- #

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
# Pure flow-shaping helpers (testable without AWS)
# --------------------------------------------------------------------------- #

def proto_name(num: str | None) -> str | None:
    """Map an IANA protocol number (as a string) to an EC2 IpProtocol.

    Returns None for protocols we do not build port-scoped rules for.
    """
    if num is None:
        return None
    return PROTO_NUM_TO_NAME.get(str(num).strip())


def _port_allowed(port: int, specs: list[tuple[int, int]] | None) -> bool:
    if specs is None:
        return True
    return any(lo <= port <= hi for lo, hi in specs)


def filter_flows(
    flows: set[tuple[str, str, int]],
    *,
    include_public: bool,
    port_specs: list[tuple[int, int]] | None,
) -> set[tuple[str, str, int]]:
    """Keep only valid IPv4 flows that pass the privacy and port filters."""
    out: set[tuple[str, str, int]] = set()
    for src, proto, port in flows:
        try:
            addr = ipaddress.ip_address(src)
        except ValueError:
            continue
        if not isinstance(addr, ipaddress.IPv4Address):
            continue
        if not include_public and not any(addr in b for b in RFC1918_BLOCKS):
            continue  # ignore internet REJECT noise unless asked
        if not _port_allowed(port, port_specs):
            continue
        out.add((src, proto, port))
    return out


def build_perms(
    flows: set[tuple[str, str, int]],
    description: str,
    *,
    tolerance: float,
    max_rules: int,
) -> list[dict]:
    """Collapse flows into IpPermissions, grouping source IPs into CIDRs.

    Sources are grouped per (protocol, port) and collapsed with
    ``collapse_ips_to_cidrs`` so a CIDR block may be used whenever the
    fraction of never-observed addresses inside it is <= ``tolerance``.
    """
    by_pp: dict[tuple[str, int], list[str]] = {}
    for src, proto, port in flows:
        by_pp.setdefault((proto, port), []).append(src)
    perms: list[dict] = []
    for (proto, port), ips in sorted(by_pp.items()):
        cidrs = collapse_ips_to_cidrs(ips, max_rules=max_rules, tolerance=tolerance)
        perms.append({
            "IpProtocol": proto,
            "FromPort": port,
            "ToPort": port,
            "IpRanges": [
                {"CidrIp": c, "Description": description} for c in cidrs
            ],
        })
    return perms


def perm_rule_count(perms: list[dict]) -> int:
    return sum(len(p.get("IpRanges", [])) for p in perms)


def _rule_count(sg: dict) -> int:
    n = 0
    for perm in sg.get("IpPermissions", []):
        n += len(perm.get("IpRanges", []))
        n += len(perm.get("Ipv6Ranges", []))
        n += len(perm.get("UserIdGroupPairs", []))
        n += len(perm.get("PrefixListIds", []))
    return n


def _existing_nets_for(
    sg: dict, proto: str, port: int
) -> list[ipaddress.IPv4Network]:
    """IPv4 networks already permitted on this group for proto/port.

    A rule with protocol "-1" (all) or a port range spanning ``port`` counts.
    """
    nets: list[ipaddress.IPv4Network] = []
    for perm in sg.get("IpPermissions", []):
        if perm.get("IpProtocol") not in (proto, "-1"):
            continue
        fp, tp = perm.get("FromPort"), perm.get("ToPort")
        if fp is not None and tp is not None and not (fp <= port <= tp):
            continue
        for ip in perm.get("IpRanges", []):
            try:
                nets.append(ipaddress.ip_network(ip["CidrIp"], strict=False))
            except (KeyError, ValueError):
                continue
    return nets


def filter_existing(perms: list[dict], sg: dict) -> list[dict]:
    """Drop candidate CIDRs already covered by an existing rule on the same
    protocol/port, so the budget is honest and we avoid duplicate errors."""
    out: list[dict] = []
    for perm in perms:
        existing = _existing_nets_for(sg, perm["IpProtocol"], perm["FromPort"])
        keep = []
        for ip in perm.get("IpRanges", []):
            try:
                cand = ipaddress.ip_network(ip["CidrIp"], strict=False)
            except ValueError:
                continue
            if any(cand.subnet_of(e) for e in existing):
                continue  # already permitted
            keep.append(ip)
        if keep:
            out.append({**perm, "IpRanges": keep})
    return out


# --------------------------------------------------------------------------- #
# Flow-log readers (AWS)
# --------------------------------------------------------------------------- #

def read_rejected_flows_cloudwatch(
    region: str, log_group: str, hours: int
) -> set[tuple[str, str, int]]:
    """Query CloudWatch Logs Insights for REJECTed flows in the window."""
    logs = _client("logs", region)
    end = dt.datetime.now(dt.timezone.utc)
    start = end - dt.timedelta(hours=hours)
    query = (
        "fields srcAddr, dstPort, protocol "
        '| filter action = "REJECT" '
        "| stats count() as hits by srcAddr, dstPort, protocol "
        "| limit 10000"
    )
    resp = logs.start_query(
        logGroupName=log_group,
        startTime=int(start.timestamp()),
        endTime=int(end.timestamp()),
        queryString=query,
    )
    qid = resp["queryId"]
    while True:
        result = logs.get_query_results(queryId=qid)
        if result["status"] in ("Complete", "Failed", "Cancelled", "Timeout"):
            break
        time.sleep(1)

    flows: set[tuple[str, str, int]] = set()
    if result["status"] != "Complete":
        LOG.warning("flow-log query ended with status %s", result["status"])
        return flows
    for row in result.get("results", []):
        cells = {c["field"]: c["value"] for c in row}
        proto = proto_name(cells.get("protocol"))
        if proto is None:
            continue
        try:
            port = int(cells["dstPort"])
        except (KeyError, ValueError):
            continue
        src = cells.get("srcAddr", "").strip()
        if src:
            flows.add((src, proto, port))
    return flows


def read_rejected_flows_s3(
    region: str, bucket: str, prefix: str | None, hours: int
) -> set[tuple[str, str, int]]:
    """Parse VPC flow-log objects in S3 (default format) for REJECTed flows."""
    s3 = _client("s3", region)
    end = dt.datetime.now(dt.timezone.utc)
    start = end - dt.timedelta(hours=hours)
    prefix = (prefix or "").rstrip("/")
    flows: set[tuple[str, str, int]] = set()
    total = 0
    failed = 0
    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        for obj in page.get("Contents", []):
            if obj["LastModified"] < start or obj["LastModified"] > end:
                continue
            total += 1
            try:
                body = s3.get_object(Bucket=bucket, Key=obj["Key"])["Body"].read()
                if obj["Key"].endswith(".gz"):
                    body = gzip.decompress(body)
                for line in body.decode("utf-8", errors="ignore").splitlines():
                    parts = line.split()
                    # Default format: ... srcaddr[3] ... dstport[6] protocol[7] ... action[12]
                    if len(parts) < 14:
                        continue
                    src, dstport, proto_num, action = (
                        parts[3], parts[6], parts[7], parts[12],
                    )
                    if action != "REJECT":
                        continue
                    proto = proto_name(proto_num)
                    if proto is None:
                        continue
                    try:
                        port = int(dstport)
                    except ValueError:
                        continue
                    flows.add((src, proto, port))
            except Exception as exc:  # noqa: BLE001 — broad on purpose
                failed += 1
                LOG.warning("failed to read s3://%s/%s: %s", bucket, obj["Key"], exc)
    if total and failed / total > 0.10:
        raise RuntimeError(
            f"S3 flow-log read failure ratio {failed}/{total} exceeds 10% — refusing "
            "to act on a partial view. Check IAM and bucket policies."
        )
    return flows


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #

def main(argv: Sequence[str] | None = None) -> int:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    p = argparse.ArgumentParser(prog="sg_extend.py")
    p.add_argument("--region", required=True)
    p.add_argument("--groups", required=True, help="comma-separated SG ids to add to")
    p.add_argument("--log-group", help="CloudWatch Logs group containing VPC flow logs")
    p.add_argument("--s3-bucket", help="S3 bucket containing VPC flow logs")
    p.add_argument("--s3-prefix", help="S3 prefix under --s3-bucket")
    p.add_argument("--hours", type=int, default=24, help="flow-log window (default 24)")
    p.add_argument("--tolerance", type=float, default=DEFAULT_TOLERANCE,
                   help="fraction (0.0-1.0) of unused IPs allowed inside a "
                        "grouping CIDR; higher packs more sources into fewer "
                        f"rules (default {DEFAULT_TOLERANCE})")
    p.add_argument("--ports", help="restrict to these dst ports/ranges, e.g. 443,5432")
    p.add_argument("--include-public", action="store_true",
                   help="also add non-RFC1918 (public) source IPs")
    p.add_argument("--description", default="sg-extend break-glass")
    p.add_argument("--max-rules", type=int, default=60)
    p.add_argument("--yes", action="store_true", help="bypass the 'extend' prompt")
    args = p.parse_args(argv)

    if not args.log_group and not args.s3_bucket:
        p.error("either --log-group or --s3-bucket is required")
    if args.hours < 1:
        p.error("--hours must be >= 1")
    if not 0.0 <= args.tolerance <= 1.0:
        p.error("--tolerance must be between 0.0 and 1.0")

    try:
        groups = [parse_group_id(g) for g in args.groups.split(",") if g.strip()]
        port_specs = (
            [parse_port_spec(x) for x in args.ports.split(",") if x.strip()]
            if args.ports else None
        )
    except ValueError as exc:
        sys.exit(f"input error: {exc}")
    if not groups:
        sys.exit("must supply at least one group")

    # --- discover rejected traffic --------------------------------------- #
    if args.log_group:
        flows = read_rejected_flows_cloudwatch(args.region, args.log_group, args.hours)
    else:
        flows = read_rejected_flows_s3(
            args.region, args.s3_bucket, args.s3_prefix, args.hours
        )
    flows = filter_flows(
        flows, include_public=args.include_public, port_specs=port_specs
    )

    scope = "" if args.include_public else "private "
    if not flows:
        LOG.info(
            "no rejected %ssources found in the last %dh — nothing to do",
            scope, args.hours,
        )
        return 0

    LOG.warning(
        "found %d rejected %sflow(s) over the last %dh:", len(flows), scope, args.hours
    )
    for src, proto, port in sorted(flows):
        print(f"  {src}/32  {proto}/{port}")

    if not args.yes:
        try:
            answer = input(
                "Type 'extend' to add these to the security groups: "
            ).strip().lower()
        except EOFError:
            answer = ""
        if answer != "extend":
            sys.exit("aborted")

    # Collapse the rejected sources into CIDR rules once (region-wide flows).
    perms_all = build_perms(
        flows, args.description, tolerance=args.tolerance, max_rules=args.max_rules
    )
    LOG.info(
        "collapsed %d flow(s) into %d candidate rule(s) at tolerance %.2f",
        len(flows), perm_rule_count(perms_all), args.tolerance,
    )

    # --- apply (strictly additive) --------------------------------------- #
    ec2 = _client("ec2", args.region)

    manifest = {
        "schema": "sg-extend.manifest/v1",
        "applied_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "region": args.region,
        "description": args.description,
        "source": "cloudwatch" if args.log_group else "s3",
        "window_hours": args.hours,
        "tolerance": args.tolerance,
        "include_public": args.include_public,
        "discovered_flows": [
            {"cidr": f"{s}/32", "protocol": pr, "port": po}
            for s, pr, po in sorted(flows)
        ],
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

        # Drop CIDRs already covered on this group so the budget is honest.
        perms = filter_existing(perms_all, sg)
        if not perms:
            manifest["groups"].append({"group_id": gid, "status": "ALREADY_PRESENT"})
            LOG.info("%s already covers every discovered source — nothing to add", gid)
            continue

        would_add = perm_rule_count(perms)
        existing = _rule_count(sg)
        if existing + would_add > args.max_rules:
            manifest["groups"].append({
                "group_id": gid,
                "status": "SKIPPED_BUDGET",
                "existing_rules": existing,
                "would_add": would_add,
                "max_rules": args.max_rules,
            })
            LOG.warning(
                "%s skipped: %d existing + %d new > %d max — raise --tolerance to "
                "pack into fewer rules, run sg_compact to reclaim budget, or raise "
                "the SG quota",
                gid, existing, would_add, args.max_rules,
            )
            continue

        try:
            ec2.authorize_security_group_ingress(GroupId=gid, IpPermissions=perms)
            manifest["groups"].append({
                "group_id": gid,
                "status": "ADDED",
                "added_rules": would_add,
                "rules": perms,
            })
            LOG.info("added %d rule(s) to %s", would_add, gid)
        except botocore.exceptions.ClientError as exc:
            err = str(exc)
            if "InvalidPermission.Duplicate" in err:
                manifest["groups"].append({
                    "group_id": gid, "status": "PARTIAL_DUPLICATE", "error": err,
                })
                LOG.info("some rules already existed on %s", gid)
            else:
                manifest["groups"].append({
                    "group_id": gid, "status": "ERROR", "error": err,
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
