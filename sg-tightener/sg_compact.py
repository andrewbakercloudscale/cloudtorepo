#!/usr/bin/env python3
"""sg_compact.py — widen CIDR blocks to compact a security group's rule count.

AWS allows at most 60 rules per security group. When a group is approaching
that ceiling, ``sg_compact`` reclaims rule budget by merging existing RFC 1918
ingress CIDRs into fewer, wider blocks — without reading flow logs and without
ever removing access (every widened block is a superset of the blocks it
replaces).

The operator supplies a *compaction ratio*: the fraction of unused
(never-covered) IP addresses tolerated inside a widened CIDR. A ratio of 0.5
permits a block to be used to cover a set of CIDRs even when half of that
block's addresses are not currently allowed by any of them. A higher ratio
tolerates bigger gaps and therefore compacts harder — which is what you want
as a group nears the 60-rule limit.

Scope: only strict RFC 1918 IPv4 ingress CIDRs are candidates. Public CIDRs,
IPv6 ranges, 0.0.0.0/0, security-group references, and prefix lists are never
touched and are counted as fixed rules.

Modes:
  plan     Read the live SG inventory and report, with no AWS writes:
             * a ranking of groups by current rule count (where the rules are),
             * a sweep showing the projected rule count at several ratios.
           If --ratio is given, also write a plan.json for that ratio.
  apply    Execute a plan.json (revoke the narrow CIDRs, authorise the widened
           ones). Reuses sg_tightener's staleness check, manifest, and revert.
  revert   Restore pre-apply state from a manifest.

Part of the CloudToRepo project: https://cloudtorepo.com

Usage:
  sg_compact.py plan   --region <r> [--ratio 0.5]
                       [--ratios 0,0.1,0.25,0.5,0.75,0.9]
                       [--max-rules 60] [--out plan.json]
  sg_compact.py apply  --plan plan.json [--yes]
  sg_compact.py revert --manifest manifest-<ts>.json [--yes]
"""

from __future__ import annotations

import argparse
import datetime as dt
import ipaddress
import json
import logging
import os
import sys
from typing import Sequence

from sg_tightener import (
    DEFAULT_MAX_RULES,
    _client,  # noqa: F401 — re-exported indirectly via list helper
    _is_strict_rfc1918,
    _list_security_groups,
    _smallest_covering,
    apply_plan,
    revert_from_manifest,
    state_hash,
)

LOG = logging.getLogger("sg_compact")

DEFAULT_RATIOS = [0.0, 0.10, 0.25, 0.50, 0.75, 0.90]
IPRANGE_KINDS = ("Ipv6Ranges", "UserIdGroupPairs", "PrefixListIds")


# --------------------------------------------------------------------------- #
# Eligibility & counting (pure)
# --------------------------------------------------------------------------- #

def compactable_net(cidr: str | None) -> ipaddress.IPv4Network | None:
    """Return the IPv4Network if this CIDR is a merge candidate, else None.

    A candidate is any strict RFC 1918 IPv4 CIDR — at *any* prefix length,
    unlike sg_tightener's eligibility which only targets broad rules. Here we
    want narrow /24s and /32s too, because merging them is the whole point.
    """
    if not cidr:
        return None
    try:
        net = ipaddress.ip_network(cidr, strict=False)
    except ValueError:
        return None
    if not isinstance(net, ipaddress.IPv4Network):
        return None
    if not _is_strict_rfc1918(net):
        return None
    return net


def count_group(sg: dict) -> tuple[int, int]:
    """Return (total_rule_count, compactable_rule_count) for a security group."""
    total = 0
    eligible = 0
    for perm in sg.get("IpPermissions", []):
        for ip in perm.get("IpRanges", []):
            total += 1
            if compactable_net(ip.get("CidrIp")) is not None:
                eligible += 1
        for kind in IPRANGE_KINDS:
            total += len(perm.get(kind, []))
    return total, eligible


# --------------------------------------------------------------------------- #
# Range-aware widening
# --------------------------------------------------------------------------- #

def compact_nets(
    nets: Sequence[ipaddress.IPv4Network],
    ratio: float,
) -> list[ipaddress.IPv4Network]:
    """Merge CIDRs into fewer wider blocks while wasted space stays <= ratio.

    Coverage-preserving (the union of the result always contains the union of
    the input) and never merges across an RFC 1918 home-block boundary.

    Unlike sg_tightener's IP-set collapse, this works on whole ranges: the
    "covered" address count of a block is tracked as a running total, so a /16
    never has to be enumerated host by host.
    """
    if not nets:
        return []
    # collapse_addresses performs all the lossless, zero-waste merges first
    # (adjacent equal blocks, subnets absorbed) and returns disjoint networks.
    current = list(ipaddress.collapse_addresses(set(nets)))
    covered: dict[ipaddress.IPv4Network, int] = {n: n.num_addresses for n in current}

    while len(current) > 1:
        current.sort(key=lambda n: (int(n.network_address), n.prefixlen))
        best = None  # (score, super_net, members, covered_in_super)
        for i in range(len(current) - 1):
            super_net = _smallest_covering(current[i], current[i + 1])
            if super_net is None:
                continue  # different RFC 1918 home blocks — never merge
            members = [n for n in current if n.subnet_of(super_net)]
            if len(members) < 2:
                continue
            cov = sum(covered[n] for n in members)
            waste = (super_net.num_addresses - cov) / super_net.num_addresses
            if waste > ratio:
                continue
            # Prefer the merge that removes the most rules, then the least waste.
            score = (-(len(members) - 1), waste)
            if best is None or score < best[0]:
                best = (score, super_net, members, cov)
        if best is None:
            break
        _score, super_net, members, cov = best
        for n in members:
            current.remove(n)
            del covered[n]
        current.append(super_net)
        covered[super_net] = cov

    current.sort(key=lambda n: (int(n.network_address), n.prefixlen))
    return current


# --------------------------------------------------------------------------- #
# Plan building (pure — operates on SG dicts)
# --------------------------------------------------------------------------- #

def _perm(proto, from_p, to_p, nets, description: str | None = None) -> dict:
    ordered = sorted(nets, key=lambda n: (int(n.network_address), n.prefixlen))
    perm: dict = {
        "IpProtocol": proto,
        "IpRanges": [
            ({"CidrIp": str(n), "Description": description}
             if description else {"CidrIp": str(n)})
            for n in ordered
        ],
    }
    if from_p is not None:
        perm["FromPort"] = from_p
    if to_p is not None:
        perm["ToPort"] = to_p
    return perm


def analyse_group(sg: dict, ratio: float) -> dict:
    """Compute the revoke/authorise perms and projected counts for one group."""
    buckets: dict[tuple, list[ipaddress.IPv4Network]] = {}
    fixed = 0
    total = 0
    for perm in sg.get("IpPermissions", []):
        key = (perm.get("IpProtocol"), perm.get("FromPort"), perm.get("ToPort"))
        for ip in perm.get("IpRanges", []):
            total += 1
            net = compactable_net(ip.get("CidrIp"))
            if net is None:
                fixed += 1
            else:
                buckets.setdefault(key, []).append(net)
        for kind in IPRANGE_KINDS:
            n = len(perm.get(kind, []))
            total += n
            fixed += n

    revoke_perms: list[dict] = []
    authorise_perms: list[dict] = []
    projected_eligible = 0
    for (proto, from_p, to_p), nets in buckets.items():
        compacted = compact_nets(nets, ratio)
        projected_eligible += len(compacted)
        orig = set(nets)
        new = set(compacted)
        to_revoke = orig - new
        to_auth = new - orig
        if to_revoke:
            revoke_perms.append(_perm(proto, from_p, to_p, to_revoke))
        if to_auth:
            authorise_perms.append(
                _perm(proto, from_p, to_p, to_auth, description="sg-compact widened")
            )

    projected_total = fixed + projected_eligible
    return {
        "current_total": total,
        "eligible_count": total - fixed,
        "fixed_count": fixed,
        "projected_total": projected_total,
        "rules_saved": total - projected_total,
        "revoke": revoke_perms,
        "authorise": authorise_perms,
    }


def build_compact_plan(
    sgs: list[dict],
    *,
    ratio: float,
    max_rules: int,
    region: str,
) -> dict:
    plan_groups = []
    for sg in sgs:
        a = analyse_group(sg, ratio)
        if a["rules_saved"] <= 0:
            continue
        plan_groups.append({
            "group_id": sg["GroupId"],
            "group_name": sg.get("GroupName"),
            "vpc_id": sg.get("VpcId"),
            "revoke": a["revoke"],
            "authorise": a["authorise"],
            "current_rule_count": a["current_total"],
            "projected_rule_count": a["projected_total"],
            "rules_saved": a["rules_saved"],
        })
    snapshot = [
        {"group_id": sg["GroupId"], "rules": sg.get("IpPermissions", [])} for sg in sgs
    ]
    return {
        "schema": "sg-tightener.plan/v1",
        "tool": "sg_compact",
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "region": region,
        "ratio": ratio,
        "max_rules": max_rules,
        "groups": plan_groups,
        "snapshot_hash": state_hash(snapshot),
    }


# --------------------------------------------------------------------------- #
# Reporting
# --------------------------------------------------------------------------- #

def print_ranking(sgs: list[dict], max_rules: int) -> None:
    rows = []
    for sg in sgs:
        total, eligible = count_group(sg)
        if total == 0:
            continue
        rows.append((total, eligible, sg["GroupId"], sg.get("GroupName") or "-"))
    rows.sort(reverse=True)
    print("\nGroups by rule count (largest first):")
    print(f"  {'rules':>6}  {'compactable':>11}  {'group':<22}  name")
    for total, eligible, gid, name in rows[:25]:
        flag = "  <-- AT/OVER LIMIT" if total >= max_rules else ""
        print(f"  {total:>6}  {eligible:>11}  {gid:<22}  {name}{flag}")
    if len(rows) > 25:
        print(f"  ... and {len(rows) - 25} more group(s)")


def print_sweep(sgs: list[dict], ratios: list[float], max_rules: int) -> None:
    total_now = sum(count_group(sg)[0] for sg in sgs)
    print(
        f"\nCompaction ratio sweep "
        f"(current total: {total_now} rules across {len(sgs)} group(s)):"
    )
    print(f"  {'ratio':>6}  {'rules after':>11}  {'saved':>6}  {'groups>limit':>12}")
    for r in ratios:
        after = 0
        over = 0
        for sg in sgs:
            a = analyse_group(sg, r)
            after += a["projected_total"]
            if a["projected_total"] > max_rules:
                over += 1
        print(f"  {r:>6.2f}  {after:>11}  {total_now - after:>6}  {over:>12}")


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #

def _parse_ratios(spec: str) -> list[float]:
    out = []
    for piece in spec.split(","):
        piece = piece.strip()
        if not piece:
            continue
        v = float(piece)
        if not 0.0 <= v <= 1.0:
            raise ValueError(f"ratio out of range 0.0-1.0: {piece}")
        out.append(v)
    return out


def _confirm(action: str) -> None:
    try:
        answer = input(f"Type 'yes' to {action}: ").strip().lower()
    except EOFError:
        answer = ""
    if answer != "yes":
        sys.exit("aborted")


def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="sg_compact.py", description=__doc__.splitlines()[0])
    sub = p.add_subparsers(dest="mode", required=True)

    pl = sub.add_parser("plan", help="report compaction stats and (optionally) write a plan")
    pl.add_argument("--region", required=True)
    pl.add_argument("--ratio", type=float,
                    help="compaction ratio (fraction 0.0-1.0 of unused IPs "
                         "allowed in a widened CIDR); writing a plan requires it")
    pl.add_argument("--ratios", default=",".join(str(r) for r in DEFAULT_RATIOS),
                    help="comma-separated ratios for the sweep table")
    pl.add_argument("--max-rules", type=int, default=DEFAULT_MAX_RULES)
    pl.add_argument("--out", default="plan.json")

    ap = sub.add_parser("apply", help="execute a compaction plan")
    ap.add_argument("--plan", required=True)
    ap.add_argument("--yes", action="store_true")

    rv = sub.add_parser("revert", help="restore pre-apply state from a manifest")
    rv.add_argument("--manifest", required=True)
    rv.add_argument("--yes", action="store_true")
    return p


def main(argv: Sequence[str] | None = None) -> int:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    args = _build_parser().parse_args(argv)

    if args.mode == "plan":
        if args.ratio is not None and not 0.0 <= args.ratio <= 1.0:
            sys.exit("--ratio must be between 0.0 and 1.0")
        try:
            ratios = _parse_ratios(args.ratios)
        except ValueError as exc:
            sys.exit(f"input error: {exc}")

        sgs = _list_security_groups(args.region)
        if not sgs:
            LOG.info("no security groups found in %s", args.region)
            return 0

        print_ranking(sgs, args.max_rules)
        print_sweep(sgs, ratios, args.max_rules)

        if args.ratio is None:
            print("\nNo --ratio given; not writing a plan. Re-run with --ratio "
                  "<r> once you have chosen one from the sweep above.")
            return 0

        plan = build_compact_plan(
            sgs, ratio=args.ratio, max_rules=args.max_rules, region=args.region
        )
        with open(args.out, "w", encoding="utf-8") as fh:
            json.dump(plan, fh, indent=2)
        saved = sum(g["rules_saved"] for g in plan["groups"])
        print(
            f"\nWrote plan for ratio {args.ratio:.2f} to {args.out}: "
            f"{len(plan['groups'])} group(s), {saved} rule(s) reclaimed.\n"
            f"Review it, then: sg_compact.py apply --plan {args.out}"
        )
        return 0

    if args.mode == "apply":
        with open(args.plan, "r", encoding="utf-8") as fh:
            plan = json.load(fh)
        if not args.yes:
            _confirm("apply this compaction plan")
        region = (
            plan.get("region")
            or os.environ.get("AWS_REGION")
            or os.environ.get("AWS_DEFAULT_REGION")
        )
        if not region:
            sys.exit("region not present in plan and AWS_REGION is not set")
        ts = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        manifest_path = f"sg_compact-manifest-{ts}.json"
        apply_plan(plan, region, manifest_path=manifest_path)
        return 0

    if args.mode == "revert":
        if not args.yes:
            _confirm("revert from manifest")
        revert_from_manifest(args.manifest)
        return 0

    return 2


if __name__ == "__main__":
    sys.exit(main())
