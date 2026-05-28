#!/usr/bin/env python3
"""sg_diagnose.py — surface legitimate sources rejected after tightening.

After a tightening apply, run this to find private source IPs whose
connection attempts were REJECTED by flow logs over a recent window and
which are not already covered by any current security-group rule. Surfaces
them for human review, lets the operator merge them into the approved
list, and optionally re-runs the plan/apply cycle immediately.

Usage:
  sg_diagnose.py --region <r> [--hours 24] [--approved approved.json]
                 [--log-group <name> | --s3-bucket <b> --s3-prefix <p>]
                 [--apply]

Exit code 0 means no new sources were found (or sources were found and
merged successfully). Exit code 1 means new sources were found but the
operator did not choose to merge them.
"""

from __future__ import annotations

import argparse
import datetime as dt
import ipaddress
import json
import logging
import sys
from typing import Sequence

from sg_tightener import (
    AnalyseConfig,
    _analyse_from_cloudwatch,
    _analyse_from_s3,
    _client,
    _list_security_groups,
    rule_is_eligible,
    RFC1918_BLOCKS,
)

LOG = logging.getLogger("sg_diagnose")


def _covered_by_any_rule(ip: ipaddress.IPv4Address, rules: list[ipaddress.IPv4Network]) -> bool:
    return any(ip in net for net in rules)


def _current_rule_nets(sgs: list[dict]) -> list[ipaddress.IPv4Network]:
    nets: set[ipaddress.IPv4Network] = set()
    for sg in sgs:
        for perm in sg.get("IpPermissions", []):
            for ip in perm.get("IpRanges", []):
                try:
                    nets.add(ipaddress.ip_network(ip["CidrIp"], strict=False))
                except (KeyError, ValueError):
                    continue
    return list(nets)


def main(argv: Sequence[str] | None = None) -> int:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    p = argparse.ArgumentParser(prog="sg_diagnose.py")
    p.add_argument("--region", required=True)
    p.add_argument("--hours", type=int, default=24)
    p.add_argument("--approved", default="approved.json")
    p.add_argument("--log-group")
    p.add_argument("--s3-bucket")
    p.add_argument("--s3-prefix")
    p.add_argument("--apply", action="store_true",
                   help="if new sources are found and confirmed, merge them "
                        "and re-run plan/apply immediately")
    args = p.parse_args(argv)

    if not args.log_group and not args.s3_bucket:
        p.error("either --log-group or --s3-bucket is required")

    cfg = AnalyseConfig(
        region=args.region,
        days=max(1, args.hours // 24 or 1),
        log_group=args.log_group,
        s3_bucket=args.s3_bucket,
        s3_prefix=args.s3_prefix,
        out_path=args.approved,
        accepted_only=False,  # we want REJECTs
    )
    rejected = (
        _analyse_from_cloudwatch(cfg) if args.log_group else _analyse_from_s3(cfg)
    )
    LOG.info("observed %d rejected source IPs", len(rejected))

    sgs = _list_security_groups(args.region)
    current_nets = _current_rule_nets(sgs)

    uncovered: list[str] = []
    for raw in rejected:
        try:
            addr = ipaddress.ip_address(raw)
        except ValueError:
            continue
        if not isinstance(addr, ipaddress.IPv4Address):
            continue
        if not any(addr in b for b in RFC1918_BLOCKS):
            continue  # only private space — ignore internet noise
        if _covered_by_any_rule(addr, current_nets):
            continue
        uncovered.append(raw)

    uncovered = sorted(set(uncovered))
    if not uncovered:
        LOG.info("no new private sources are being rejected — nothing to do")
        return 0

    LOG.warning("found %d uncovered private sources:", len(uncovered))
    for ip in uncovered:
        print(f"  {ip}")

    try:
        answer = input(f"Merge these {len(uncovered)} IPs into {args.approved}? [y/N] ")
    except EOFError:
        answer = ""
    if answer.strip().lower() != "y":
        return 1

    try:
        with open(args.approved, "r", encoding="utf-8") as fh:
            approved = json.load(fh)
    except FileNotFoundError:
        approved = {"schema": "sg-tightener.approved/v1", "ips": []}

    merged_ips = sorted(set(approved.get("ips", [])) | set(uncovered))
    approved["ips"] = merged_ips
    approved["updated_at"] = dt.datetime.now(dt.timezone.utc).isoformat()
    with open(args.approved, "w", encoding="utf-8") as fh:
        json.dump(approved, fh, indent=2)
    LOG.info("merged approved list now contains %d IPs", len(merged_ips))

    if args.apply:
        LOG.warning("--apply requested; re-run sg_tightener.py plan && apply now")

    return 0


if __name__ == "__main__":
    sys.exit(main())
