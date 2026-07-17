#!/usr/bin/env python3
"""sg_tightener.py — Evidence-based security group CIDR tightening.

Replaces broad RFC 1918 ingress rules on AWS security groups with the
tightest covering CIDR blocks empirically observed in VPC flow logs.

Modes:
  analyse  Read flow logs (CloudWatch Logs or S3) and emit an
           approved-IPs JSON list. Before reading, the flow logs
           feeding the destination are checked with
           ec2:DescribeFlowLogs: the parse layout is derived from
           the configured log format, and a warning is raised when
           the format lacks pkt-srcaddr — without it, traffic that
           arrives through a transit gateway or NAT gateway is
           recorded under the intermediate interface's IP (the next
           hop), not the true source.
  plan     Read the approved IPs and the current SG inventory and
           emit a plan.json describing rules to revoke and rules
           to authorise. Plans are signed with a state hash so
           apply refuses to run against a stale snapshot.
  apply    Execute a plan. Halts immediately on any single-group
           failure and prints the revert command.
  revert   Restore the exact pre-apply state from the manifest
           written by the most recent apply.

This module also exposes a pure-Python CIDR collapse function
(``collapse_ips_to_cidrs``) used by the test suite. It is part of
the CloudToRepo project: https://cloudtorepo.com

Usage:
  sg_tightener.py analyse  --region <r> [--days 90] [--out approved.json]
                           [--log-group <name> | --s3-bucket <b> --s3-prefix <p>]
  sg_tightener.py plan     --region <r> --approved approved.json
                           [--max-rules 60] [--tolerance 0.30]
                           [--prefix-threshold 24] [--out plan.json]
  sg_tightener.py apply    --plan plan.json [--yes]
  sg_tightener.py revert   --manifest manifest-<ts>.json [--yes]
"""

from __future__ import annotations

import argparse
import dataclasses
import datetime as dt
import gzip
import hashlib
import ipaddress
import json
import logging
import os
import re
import sys
from typing import Iterable, Sequence

try:
    import boto3
    import botocore
    from botocore.config import Config as BotoConfig
except ImportError:
    boto3 = None
    botocore = None
    BotoConfig = None

LOG = logging.getLogger("sg_tightener")

RFC1918_BLOCKS = [
    ipaddress.ip_network("10.0.0.0/8"),
    ipaddress.ip_network("172.16.0.0/12"),
    ipaddress.ip_network("192.168.0.0/16"),
]

DEFAULT_PREFIX_THRESHOLD = 24
DEFAULT_TOLERANCE = 0.30
DEFAULT_MAX_RULES = 60
DEFAULT_DAYS = 90


# --------------------------------------------------------------------------- #
# CIDR collapsing
# --------------------------------------------------------------------------- #

def _is_strict_rfc1918(net: ipaddress.IPv4Network) -> bool:
    return any(net.subnet_of(b) for b in RFC1918_BLOCKS)


def _normalise_ips(ips: Iterable[str]) -> list[ipaddress.IPv4Address]:
    out: list[ipaddress.IPv4Address] = []
    seen: set[ipaddress.IPv4Address] = set()
    for ip in ips:
        try:
            addr = ipaddress.ip_address(ip.strip())
        except (ValueError, AttributeError):
            continue
        if not isinstance(addr, ipaddress.IPv4Address):
            continue
        if addr not in seen:
            seen.add(addr)
            out.append(addr)
    return out


def _widest_block_for(
    addr: ipaddress.IPv4Address,
    observed: set[ipaddress.IPv4Address],
    tolerance: float,
) -> ipaddress.IPv4Network:
    """Widest containing CIDR where (block_size - observed_in_block)/block_size <= tolerance.

    Always returns at least the /32 host route, and never widens past the
    RFC 1918 block the address belongs to.
    """
    home_block = next((b for b in RFC1918_BLOCKS if addr in b), None)
    if home_block is None:
        return ipaddress.ip_network(f"{addr}/32")
    best = ipaddress.ip_network(f"{addr}/32")
    for prefix in range(31, home_block.prefixlen - 1, -1):
        candidate = ipaddress.ip_network(f"{addr}/{prefix}", strict=False)
        if not candidate.subnet_of(home_block):
            break
        size = candidate.num_addresses
        in_block = sum(1 for o in observed if o in candidate)
        gap = (size - in_block) / size
        if gap <= tolerance:
            best = candidate
        else:
            break
    return best


def _force_fit(
    nets: list[ipaddress.IPv4Network],
    max_rules: int,
) -> list[ipaddress.IPv4Network]:
    """Merge the closest pairs of CIDR blocks until count <= max_rules.

    Operates per-RFC-1918 home block — merges never cross a boundary
    (e.g. a 10/8 block is never merged with a 172.16/12 block).
    """
    if len(nets) <= max_rules:
        return nets

    def home(net: ipaddress.IPv4Network) -> int:
        for i, b in enumerate(RFC1918_BLOCKS):
            if net.subnet_of(b):
                return i
        return -1

    groups: dict[int, list[ipaddress.IPv4Network]] = {}
    for n in nets:
        groups.setdefault(home(n), []).append(n)

    while sum(len(g) for g in groups.values()) > max_rules:
        biggest_key = max(groups, key=lambda k: len(groups[k]))
        if len(groups[biggest_key]) <= 1:
            break
        items = sorted(groups[biggest_key], key=lambda n: int(n.network_address))
        best_pair: tuple[int, int] | None = None
        best_cost = None
        for i in range(len(items) - 1):
            a, b = items[i], items[i + 1]
            super_net = _smallest_covering(a, b)
            if super_net is None:
                continue
            cost = super_net.num_addresses - (a.num_addresses + b.num_addresses)
            if best_cost is None or cost < best_cost:
                best_cost = cost
                best_pair = (i, i + 1)
        if best_pair is None:
            break
        i, j = best_pair
        merged = _smallest_covering(items[i], items[j])
        new_items = items[:i] + [merged] + items[j + 1:]
        groups[biggest_key] = new_items

    return [n for g in groups.values() for n in g]


def _smallest_covering(
    a: ipaddress.IPv4Network,
    b: ipaddress.IPv4Network,
) -> ipaddress.IPv4Network | None:
    home = next((blk for blk in RFC1918_BLOCKS if a.subnet_of(blk) and b.subnet_of(blk)), None)
    if home is None:
        return None
    lo = min(int(a.network_address), int(b.network_address))
    hi = max(int(a.broadcast_address), int(b.broadcast_address))
    for prefix in range(32, home.prefixlen - 1, -1):
        size = 1 << (32 - prefix)
        base = (lo // size) * size
        if base + size - 1 >= hi:
            candidate = ipaddress.ip_network((base, prefix))
            if candidate.subnet_of(home):
                return candidate
    return home


def collapse_ips_to_cidrs(
    ips: Sequence[str],
    max_rules: int = DEFAULT_MAX_RULES,
    tolerance: float = DEFAULT_TOLERANCE,
) -> list[str]:
    """Collapse observed IPs into a CIDR list <= max_rules in size.

    Layer 1: widen each IP to the widest block respecting ``tolerance``.
    Layer 2: deduplicate, widen tolerance in 5% steps if still over budget.
    Layer 3: force-fit merge nearest pairs while respecting RFC 1918 home block.

    Returns sorted ``"a.b.c.d/p"`` strings.
    """
    addrs = _normalise_ips(ips)
    if not addrs:
        return []
    observed = set(addrs)

    def _collapse_at(t: float) -> list[ipaddress.IPv4Network]:
        blocks: set[ipaddress.IPv4Network] = set()
        for a in addrs:
            blocks.add(_widest_block_for(a, observed, t))
        # ipaddress.collapse_addresses merges contiguous & adjacent nets.
        return list(ipaddress.collapse_addresses(blocks))

    t = max(0.0, min(1.0, tolerance))
    nets = _collapse_at(t)
    while len(nets) > max_rules and t < 0.95:
        t = round(min(0.95, t + 0.05), 2)
        LOG.warning("widening tolerance to %.2f to fit %d rule budget", t, max_rules)
        nets = _collapse_at(t)

    if len(nets) > max_rules:
        LOG.warning(
            "tolerance widening exhausted; force-fitting %d blocks into %d rules — "
            "request a quota increase from AWS Support to keep precision",
            len(nets), max_rules,
        )
        nets = _force_fit(nets, max_rules)

    nets_sorted = sorted(nets, key=lambda n: (int(n.network_address), n.prefixlen))
    return [str(n) for n in nets_sorted]


# --------------------------------------------------------------------------- #
# Eligibility
# --------------------------------------------------------------------------- #

def rule_is_eligible(
    cidr: str | None,
    prefix_threshold: int = DEFAULT_PREFIX_THRESHOLD,
) -> bool:
    """A rule is in-scope iff it is a strict RFC 1918 subset and shorter
    than the configured prefix threshold. Anything else — including
    0.0.0.0/0, overlapping non-private ranges, security-group references,
    IPv6, and already-tight CIDRs — is left untouched."""
    if not cidr:
        return False
    try:
        net = ipaddress.ip_network(cidr, strict=False)
    except ValueError:
        return False
    if not isinstance(net, ipaddress.IPv4Network):
        return False
    if not _is_strict_rfc1918(net):
        return False
    return net.prefixlen < prefix_threshold


# --------------------------------------------------------------------------- #
# Port range merging
# --------------------------------------------------------------------------- #

def merge_port_ranges(
    ranges: Iterable[tuple[int, int]],
) -> list[tuple[int, int]]:
    """Merge adjacent or overlapping (from, to) ranges into smallest spanning ranges."""
    items = sorted((min(a, b), max(a, b)) for a, b in ranges)
    if not items:
        return []
    merged: list[tuple[int, int]] = [items[0]]
    for lo, hi in items[1:]:
        last_lo, last_hi = merged[-1]
        if lo <= last_hi + 1:
            merged[-1] = (last_lo, max(last_hi, hi))
        else:
            merged.append((lo, hi))
    return merged


# --------------------------------------------------------------------------- #
# Plan signing
# --------------------------------------------------------------------------- #

def state_hash(payload: object) -> str:
    blob = json.dumps(payload, sort_keys=True, default=str).encode("utf-8")
    return hashlib.sha256(blob).hexdigest()


# --------------------------------------------------------------------------- #
# AWS helpers (only used by analyse/plan/apply/revert main entry points)
# --------------------------------------------------------------------------- #

def _require_boto3() -> None:
    if boto3 is None:
        sys.stderr.write(
            "boto3 is required. Activate the venv created by ./install.sh\n"
        )
        sys.exit(2)


def _client(service: str, region: str | None = None):
    _require_boto3()
    cfg = BotoConfig(retries={"max_attempts": 10, "mode": "adaptive"})
    return boto3.client(service, region_name=region, config=cfg)


def _list_security_groups(region: str) -> list[dict]:
    ec2 = _client("ec2", region)
    out: list[dict] = []
    paginator = ec2.get_paginator("describe_security_groups")
    for page in paginator.paginate():
        out.extend(page.get("SecurityGroups", []))
    return out


# --------------------------------------------------------------------------- #
# Flow-log configuration preflight
# --------------------------------------------------------------------------- #
# VPC flow logs only record the TRUE origin of traffic that reaches an
# interface through an intermediate hop — a transit gateway attachment ENI,
# a NAT gateway ENI, an EKS pod behind a node ENI — in the version-3
# ``pkt-srcaddr`` field. The DEFAULT log format stops at version 2: for such
# flows its ``srcaddr`` contains the private IP of the INTERMEDIATE interface
# (the next hop), not the client. An approved list built from default-format
# logs in a transit-gateway estate therefore contains TGW/NAT infrastructure
# addresses and misses the real client CIDRs. These checks verify the flow
# logs feeding the analysis before any list is written.

DEFAULT_LOG_FORMAT_FIELDS = [
    "version", "account-id", "interface-id", "srcaddr", "dstaddr",
    "srcport", "dstport", "protocol", "packets", "bytes",
    "start", "end", "action", "log-status",
]

# Custom format we recommend when warning: original addresses, direction,
# and everything the default format already provided.
RECOMMENDED_LOG_FORMAT = (
    "${version} ${account-id} ${interface-id} ${srcaddr} ${dstaddr} "
    "${srcport} ${dstport} ${protocol} ${packets} ${bytes} ${start} ${end} "
    "${action} ${log-status} ${pkt-srcaddr} ${pkt-dstaddr} ${flow-direction}"
)


def parse_log_format(log_format: str) -> list[str]:
    """Ordered field names from a flow-log format string (``${field} ...``)."""
    return re.findall(r"\$\{([a-z0-9-]+)\}", log_format or "")


@dataclasses.dataclass
class FlowLogCheck:
    fields: list[str]        # ordered fields the parsers should use
    warnings: list[str]
    errors: list[str]        # fatal: the analysis output would be garbage
    verified: bool           # True when a matching flow-log config was found


def check_flow_log_config(flow_logs: list[dict], accepted_only: bool = True) -> FlowLogCheck:
    """Evaluates the describe_flow_logs entries that feed the analysis
    destination and returns the parse field order plus warnings/errors."""
    warnings: list[str] = []
    errors: list[str] = []

    if not flow_logs:
        return FlowLogCheck(
            fields=list(DEFAULT_LOG_FORMAT_FIELDS),
            warnings=[
                "no flow log delivering to this destination was found in this "
                "account/region, so the log format cannot be verified (the logs "
                "may be delivered from another account). Analysis will assume "
                "the DEFAULT format — if these logs use a custom format the "
                "parsed columns WILL be wrong. Note the default format has no "
                "pkt-srcaddr field: traffic arriving through a transit gateway "
                "or NAT gateway is recorded with the intermediate interface's "
                "IP (the next hop), not the true source."
            ],
            errors=[],
            verified=False,
        )

    for fl in flow_logs:
        flid = fl.get("FlowLogId", "?")
        status = fl.get("FlowLogStatus", "")
        if status != "ACTIVE":
            warnings.append(f"flow log {flid} status is {status or 'unknown'}, not ACTIVE — its data may be stale or absent")
        if fl.get("DeliverLogsErrorMessage"):
            warnings.append(f"flow log {flid} reports a delivery error: {fl['DeliverLogsErrorMessage']}")
        ttype = fl.get("TrafficType", "")
        if accepted_only and ttype == "REJECT":
            errors.append(f"flow log {flid} captures REJECT traffic only — an accepted-traffic analysis would observe nothing")
        if not accepted_only and ttype == "ACCEPT":
            errors.append(f"flow log {flid} captures ACCEPT traffic only — a rejected-traffic analysis would observe nothing")

    formats = {fl.get("LogFormat") or "" for fl in flow_logs}
    if len(formats) > 1:
        errors.append(
            "the flow logs feeding this destination use DIFFERENT log formats; "
            "records in one destination cannot be parsed positionally when the "
            "column order varies per record. Align the formats or split the "
            "destinations."
        )
        return FlowLogCheck(list(DEFAULT_LOG_FORMAT_FIELDS), warnings, errors, verified=True)

    fields = parse_log_format(next(iter(formats)))
    if not fields:
        fields = list(DEFAULT_LOG_FORMAT_FIELDS)

    if "action" not in fields:
        errors.append("log format has no ${action} field — accepted traffic cannot be distinguished from rejected traffic")
    if "srcaddr" not in fields and "pkt-srcaddr" not in fields:
        errors.append("log format has neither ${srcaddr} nor ${pkt-srcaddr} — there is no source address to analyse")

    if "pkt-srcaddr" not in fields:
        warnings.append(
            "log format has no ${pkt-srcaddr} (v3) field. For traffic that "
            "reaches an interface through an intermediate hop — a transit "
            "gateway attachment ENI or a NAT gateway ENI — ${srcaddr} records "
            "the intermediate interface's private IP (the NEXT HOP), not the "
            "original client. Approved lists built from these logs can contain "
            "TGW/NAT infrastructure addresses and miss the real client CIDRs. "
            "Flow logs cannot be edited in place: create a replacement flow "
            f"log with a custom format such as: {RECOMMENDED_LOG_FORMAT}"
        )
    if "flow-direction" not in fields:
        warnings.append(
            "log format has no ${flow-direction} (v5) field — ingress and "
            "egress records cannot be separated, so the destinations of "
            "OUTBOUND connections also appear as observed sources and inflate "
            "the approved list."
        )

    return FlowLogCheck(fields, warnings, errors, verified=True)


def _describe_matching_flow_logs(region: str, log_group: str | None, s3_bucket: str | None):
    """Fetches flow-log configs that deliver to the analysis destination.
    Returns None when the API call itself fails (missing ec2:DescribeFlowLogs
    permission, endpoint issues) so the caller can degrade to a warning."""
    try:
        ec2 = _client("ec2", region)
        all_logs: list[dict] = []
        paginator = ec2.get_paginator("describe_flow_logs")
        for page in paginator.paginate():
            all_logs.extend(page.get("FlowLogs", []))
    except Exception as exc:  # noqa: BLE001 — any API failure degrades to "unverified"
        LOG.warning("could not verify flow-log configuration (ec2:DescribeFlowLogs failed: %s)", exc)
        return None

    matched = []
    for fl in all_logs:
        dest_type = fl.get("LogDestinationType", "cloud-watch-logs")
        if log_group and dest_type == "cloud-watch-logs" and fl.get("LogGroupName") == log_group:
            matched.append(fl)
        elif s3_bucket and dest_type == "s3":
            # LogDestination is arn:aws:s3:::bucket or arn:aws:s3:::bucket/prefix
            dest = fl.get("LogDestination", "")
            bucket = dest.split(":::", 1)[-1].split("/", 1)[0]
            if bucket == s3_bucket:
                matched.append(fl)
    return matched


# --------------------------------------------------------------------------- #
# Analyse
# --------------------------------------------------------------------------- #

@dataclasses.dataclass
class AnalyseConfig:
    region: str
    days: int
    log_group: str | None
    s3_bucket: str | None
    s3_prefix: str | None
    out_path: str
    accepted_only: bool = True


def build_cloudwatch_query(fields: list[str], accepted_only: bool = True) -> tuple[str, str]:
    """Builds the Logs Insights query for the given log format and returns
    (query, result_field_name).

    CloudWatch auto-discovers named fields (srcAddr, action, ...) ONLY for
    default-format VPC flow logs. Custom-format records must be split
    positionally out of @message, otherwise the query silently returns
    nothing — so the query is derived from the actual configured format."""
    wanted_action = "ACCEPT" if accepted_only else "REJECT"
    if fields == DEFAULT_LOG_FORMAT_FIELDS:
        query = (
            "fields srcAddr, action | "
            f"filter action = \"{wanted_action}\" | "
            "stats count() by srcAddr | "
            "limit 10000"
        )
        return query, "srcAddr"

    idx = {f: i for i, f in enumerate(fields)}
    pattern = " ".join("*" for _ in fields)
    aliases = ", ".join(f"f{i}" for i in range(len(fields)))
    src = f"f{idx['pkt-srcaddr']}" if "pkt-srcaddr" in idx else f"f{idx['srcaddr']}"
    query = (
        f"fields @message | parse @message \"{pattern}\" as {aliases} | "
        f"filter f{idx['action']} = \"{wanted_action}\" | "
    )
    if "flow-direction" in idx:
        query += f"filter f{idx['flow-direction']} = \"ingress\" | "
    query += f"stats count() by {src} | limit 10000"
    return query, src


def _analyse_from_cloudwatch(cfg: AnalyseConfig, fields: list[str]) -> list[str]:
    logs = _client("logs", cfg.region)
    end = dt.datetime.now(dt.timezone.utc)
    start = end - dt.timedelta(days=cfg.days)
    query, src_field = build_cloudwatch_query(fields, cfg.accepted_only)
    start_resp = logs.start_query(
        logGroupName=cfg.log_group,
        startTime=int(start.timestamp()),
        endTime=int(end.timestamp()),
        queryString=query,
    )
    qid = start_resp["queryId"]
    while True:
        result = logs.get_query_results(queryId=qid)
        if result["status"] in ("Complete", "Failed", "Cancelled", "Timeout"):
            break
    rows = result.get("results", []) if result["status"] == "Complete" else []
    # '-' is the flow-log placeholder for "not applicable" (e.g. pkt-srcaddr
    # on records where it could not be computed) — never a real source.
    return [
        c["value"]
        for row in rows
        for c in row
        if c["field"] == src_field and c["value"] != "-"
    ]


def ips_from_flow_log_lines(lines: Iterable[str], fields: list[str], accepted_only: bool = True) -> set[str]:
    """Extracts observed source addresses from space-separated flow-log
    records laid out per ``fields``. Prefers pkt-srcaddr (the ORIGINAL
    source) over srcaddr, which for traffic through a transit gateway or
    NAT gateway interface contains the intermediate hop's address."""
    idx = {f: i for i, f in enumerate(fields)}
    src_i = idx.get("pkt-srcaddr", idx.get("srcaddr"))
    fallback_i = idx.get("srcaddr")
    action_i = idx.get("action")
    dir_i = idx.get("flow-direction")
    if src_i is None or action_i is None:
        return set()
    wanted_action = "ACCEPT" if accepted_only else "REJECT"
    n = len(fields)
    ips: set[str] = set()
    for line in lines:
        parts = line.split()
        # Also skips each file's header row: its 'action' column holds the
        # literal field name, which never equals the wanted action.
        if len(parts) < n:
            continue
        if parts[action_i] != wanted_action:
            continue
        if dir_i is not None and parts[dir_i] == "egress":
            continue
        src = parts[src_i]
        if src == "-" and fallback_i is not None:
            src = parts[fallback_i]
        if src != "-":
            ips.add(src)
    return ips


def _analyse_from_s3(cfg: AnalyseConfig, fields: list[str]) -> list[str]:
    if not cfg.s3_bucket:
        return []
    s3 = _client("s3")
    end = dt.datetime.now(dt.timezone.utc)
    start = end - dt.timedelta(days=cfg.days)
    prefix = (cfg.s3_prefix or "").rstrip("/")
    ips: set[str] = set()
    total = 0
    failed = 0
    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=cfg.s3_bucket, Prefix=prefix):
        for obj in page.get("Contents", []):
            if obj["LastModified"] < start or obj["LastModified"] > end:
                continue
            total += 1
            try:
                body = s3.get_object(Bucket=cfg.s3_bucket, Key=obj["Key"])["Body"].read()
                if obj["Key"].endswith(".gz"):
                    body = gzip.decompress(body)
                lines = body.decode("utf-8", errors="ignore").splitlines()
                ips |= ips_from_flow_log_lines(lines, fields, cfg.accepted_only)
            except Exception as exc:  # noqa: BLE001 — broad on purpose, see below
                failed += 1
                LOG.warning("failed to read s3://%s/%s: %s", cfg.s3_bucket, obj["Key"], exc)
    if total and failed / total > 0.10:
        raise RuntimeError(
            f"S3 flow-log read failure ratio {failed}/{total} exceeds 10% — refusing "
            "to emit a partial approved list. Check IAM and bucket policies."
        )
    return list(ips)


def run_analyse(cfg: AnalyseConfig) -> dict:
    if not cfg.log_group and not cfg.s3_bucket:
        raise ValueError("either --log-group or --s3-bucket is required")

    # Preflight: verify the flow logs feeding this destination can actually
    # answer "who talks to these instances" before writing any approved list.
    matched = _describe_matching_flow_logs(cfg.region, cfg.log_group, cfg.s3_bucket)
    if matched is None:
        check = FlowLogCheck(
            fields=list(DEFAULT_LOG_FORMAT_FIELDS),
            warnings=[
                "flow-log configuration could not be verified (add "
                "ec2:DescribeFlowLogs to the analysis role to enable this "
                "check) — assuming the DEFAULT log format. If these logs use "
                "a custom format the parsed columns WILL be wrong, and the "
                "default format records only the next-hop address (not the "
                "true source) for traffic through a transit gateway or NAT "
                "gateway."
            ],
            errors=[],
            verified=False,
        )
    else:
        check = check_flow_log_config(matched, cfg.accepted_only)

    for warning in check.warnings:
        LOG.warning("flow-log config: %s", warning)
    if check.errors:
        for error in check.errors:
            LOG.error("flow-log config: %s", error)
        raise RuntimeError(
            "flow-log configuration cannot support this analysis: "
            + "; ".join(check.errors)
        )

    if cfg.log_group:
        ips = _analyse_from_cloudwatch(cfg, check.fields)
    else:
        ips = _analyse_from_s3(cfg, check.fields)

    if not ips:
        raise RuntimeError(
            "no source IPs observed — refusing to write an empty approved list. "
            "Verify that flow logs are enabled and the analysis window contains traffic."
        )

    payload = {
        "schema": "sg-tightener.approved/v1",
        "region": cfg.region,
        "days": cfg.days,
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "source": "cloudwatch" if cfg.log_group else "s3",
        "flow_log_check": {
            "verified": check.verified,
            "fields": check.fields,
            "warnings": check.warnings,
        },
        "ips": sorted(set(ips)),
    }
    with open(cfg.out_path, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, indent=2)
    LOG.info("wrote %d observed IPs to %s", len(payload["ips"]), cfg.out_path)
    return payload


# --------------------------------------------------------------------------- #
# Plan
# --------------------------------------------------------------------------- #

def _eligible_rules(sg: dict, prefix_threshold: int) -> list[dict]:
    out = []
    for perm in sg.get("IpPermissions", []):
        proto = perm.get("IpProtocol")
        from_p = perm.get("FromPort")
        to_p = perm.get("ToPort")
        for ip in perm.get("IpRanges", []):
            if rule_is_eligible(ip.get("CidrIp"), prefix_threshold):
                out.append({
                    "cidr": ip["CidrIp"],
                    "protocol": proto,
                    "from_port": from_p,
                    "to_port": to_p,
                    "description": ip.get("Description"),
                })
    return out


def _all_rule_count(sg: dict) -> int:
    n = 0
    for perm in sg.get("IpPermissions", []):
        n += len(perm.get("IpRanges", []))
        n += len(perm.get("Ipv6Ranges", []))
        n += len(perm.get("UserIdGroupPairs", []))
        n += len(perm.get("PrefixListIds", []))
    return n


def build_plan(
    sgs: list[dict],
    approved_ips: list[str],
    *,
    max_rules: int = DEFAULT_MAX_RULES,
    tolerance: float = DEFAULT_TOLERANCE,
    prefix_threshold: int = DEFAULT_PREFIX_THRESHOLD,
) -> dict:
    plan_groups = []
    for sg in sgs:
        eligible = _eligible_rules(sg, prefix_threshold)
        if not eligible:
            continue
        revokes_per_proto_port: dict[tuple, list[dict]] = {}
        for r in eligible:
            key = (r["protocol"], r["from_port"], r["to_port"])
            revokes_per_proto_port.setdefault(key, []).append(r)

        # Per-group budget = max_rules - (rules NOT being touched).
        existing_total = _all_rule_count(sg)
        untouched = existing_total - len(eligible)
        budget = max(1, max_rules - untouched)

        # Compute replacement CIDRs once across every observed IP that
        # would be covered by *any* eligible rule on this SG.
        replacement_cidrs = collapse_ips_to_cidrs(
            approved_ips,
            max_rules=budget,
            tolerance=tolerance,
        )

        authorise_perms: list[dict] = []
        port_merge_flagged = False
        for (proto, from_p, to_p), _rules in revokes_per_proto_port.items():
            authorise_perms.append({
                "IpProtocol": proto,
                "FromPort": from_p,
                "ToPort": to_p,
                "IpRanges": [
                    {"CidrIp": c, "Description": "sg-tightener evidence-based"}
                    for c in replacement_cidrs
                ],
            })

        # If multiple eligible rules share a CIDR set but differ on ports,
        # the operator can ask to merge. We surface that here.
        port_ranges_by_proto: dict[str, list[tuple[int, int]]] = {}
        for k in revokes_per_proto_port:
            proto, fp, tp = k
            if fp is None or tp is None:
                continue
            port_ranges_by_proto.setdefault(str(proto), []).append((int(fp), int(tp)))
        for proto, ranges in port_ranges_by_proto.items():
            merged = merge_port_ranges(ranges)
            if len(merged) < len(ranges):
                port_merge_flagged = True

        revoke_perms = []
        for (proto, from_p, to_p), rules in revokes_per_proto_port.items():
            revoke_perms.append({
                "IpProtocol": proto,
                "FromPort": from_p,
                "ToPort": to_p,
                "IpRanges": [{"CidrIp": r["cidr"]} for r in rules],
            })

        plan_groups.append({
            "group_id": sg["GroupId"],
            "group_name": sg.get("GroupName"),
            "vpc_id": sg.get("VpcId"),
            "revoke": revoke_perms,
            "authorise": authorise_perms,
            "port_merge_flagged": port_merge_flagged,
            "budget": budget,
            "current_rule_count": existing_total,
        })

    snapshot = [{
        "group_id": sg["GroupId"],
        "rules": sg.get("IpPermissions", []),
    } for sg in sgs]

    plan = {
        "schema": "sg-tightener.plan/v1",
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "max_rules": max_rules,
        "tolerance": tolerance,
        "prefix_threshold": prefix_threshold,
        "groups": plan_groups,
        "snapshot_hash": state_hash(snapshot),
    }
    return plan


# --------------------------------------------------------------------------- #
# Apply / revert
# --------------------------------------------------------------------------- #

def _current_snapshot_hash(region: str) -> str:
    sgs = _list_security_groups(region)
    snapshot = [{"group_id": sg["GroupId"], "rules": sg.get("IpPermissions", [])} for sg in sgs]
    return state_hash(snapshot)


def apply_plan(plan: dict, region: str, *, manifest_path: str) -> None:
    current = _current_snapshot_hash(region)
    if current != plan["snapshot_hash"]:
        raise RuntimeError(
            "plan is stale — security group state changed since it was generated. "
            "Re-run plan and review again."
        )

    ec2 = _client("ec2", region)
    manifest = {
        "schema": "sg-tightener.manifest/v1",
        "applied_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "region": region,
        "groups": [],
    }
    for grp in plan["groups"]:
        gid = grp["group_id"]
        # Revoke first — but record the original perms so revert can replay them.
        manifest_grp = {
            "group_id": gid,
            "revoked": grp["revoke"],
            "authorised": grp["authorise"],
        }
        try:
            if grp["revoke"]:
                ec2.revoke_security_group_ingress(
                    GroupId=gid, IpPermissions=grp["revoke"]
                )
            if grp["authorise"]:
                ec2.authorize_security_group_ingress(
                    GroupId=gid, IpPermissions=grp["authorise"]
                )
        except botocore.exceptions.ClientError as exc:
            # Save what we did so far and bail loudly. No partial silent state.
            manifest["groups"].append(manifest_grp)
            with open(manifest_path, "w", encoding="utf-8") as fh:
                json.dump(manifest, fh, indent=2)
            raise SystemExit(
                f"apply HALTED on {gid}: {exc}\n"
                f"Partial manifest written to {manifest_path}\n"
                f"Revert: sg_tightener.py revert --manifest {manifest_path}"
            )
        manifest["groups"].append(manifest_grp)

    with open(manifest_path, "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=2)
    LOG.info("apply complete; manifest written to %s", manifest_path)


def revert_from_manifest(manifest_path: str) -> None:
    with open(manifest_path, "r", encoding="utf-8") as fh:
        manifest = json.load(fh)
    ec2 = _client("ec2", manifest["region"])
    for grp in reversed(manifest["groups"]):
        gid = grp["group_id"]
        if grp.get("authorised"):
            try:
                ec2.revoke_security_group_ingress(GroupId=gid, IpPermissions=grp["authorised"])
            except botocore.exceptions.ClientError as exc:
                LOG.warning("revert: could not revoke restored rules on %s: %s", gid, exc)
        if grp.get("revoked"):
            try:
                ec2.authorize_security_group_ingress(GroupId=gid, IpPermissions=grp["revoked"])
            except botocore.exceptions.ClientError as exc:
                LOG.warning("revert: could not re-authorise original rules on %s: %s", gid, exc)
    LOG.info("revert complete")


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #

def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="sg_tightener.py", description=__doc__.splitlines()[0])
    sub = p.add_subparsers(dest="mode", required=True)

    a = sub.add_parser("analyse", help="read flow logs and write approved IP list")
    a.add_argument("--region", required=True)
    a.add_argument("--days", type=int, default=DEFAULT_DAYS)
    a.add_argument("--log-group", help="CloudWatch Logs group containing VPC flow logs")
    a.add_argument("--s3-bucket", help="S3 bucket containing VPC flow logs")
    a.add_argument("--s3-prefix", help="S3 prefix under --s3-bucket")
    a.add_argument("--out", default="approved.json")

    pl = sub.add_parser("plan", help="emit a plan.json")
    pl.add_argument("--region", required=True)
    pl.add_argument("--approved", required=True)
    pl.add_argument("--max-rules", type=int, default=DEFAULT_MAX_RULES)
    pl.add_argument("--tolerance", type=float, default=DEFAULT_TOLERANCE)
    pl.add_argument("--prefix-threshold", type=int, default=DEFAULT_PREFIX_THRESHOLD)
    pl.add_argument("--out", default="plan.json")

    ap = sub.add_parser("apply", help="execute a plan")
    ap.add_argument("--plan", required=True)
    ap.add_argument("--yes", action="store_true")

    rv = sub.add_parser("revert", help="restore pre-apply state from a manifest")
    rv.add_argument("--manifest", required=True)
    rv.add_argument("--yes", action="store_true")

    return p


def _confirm(action: str) -> None:
    answer = input(f"Type 'yes' to {action}: ").strip().lower()
    if answer != "yes":
        sys.exit("aborted")


def main(argv: Sequence[str] | None = None) -> int:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    args = _build_parser().parse_args(argv)

    if args.mode == "analyse":
        cfg = AnalyseConfig(
            region=args.region,
            days=args.days,
            log_group=args.log_group,
            s3_bucket=args.s3_bucket,
            s3_prefix=args.s3_prefix,
            out_path=args.out,
        )
        run_analyse(cfg)
        return 0

    if args.mode == "plan":
        with open(args.approved, "r", encoding="utf-8") as fh:
            approved = json.load(fh)
        sgs = _list_security_groups(args.region)
        plan = build_plan(
            sgs,
            approved["ips"],
            max_rules=args.max_rules,
            tolerance=args.tolerance,
            prefix_threshold=args.prefix_threshold,
        )
        with open(args.out, "w", encoding="utf-8") as fh:
            json.dump(plan, fh, indent=2)
        LOG.info(
            "wrote plan covering %d groups to %s",
            len(plan["groups"]), args.out,
        )
        return 0

    if args.mode == "apply":
        with open(args.plan, "r", encoding="utf-8") as fh:
            plan = json.load(fh)
        if not args.yes:
            _confirm("apply this plan")
        ts = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        manifest_path = f"manifest-{ts}.json"
        # Region is inferred from the snapshot — but apply needs an explicit region.
        # We piggyback on AWS_DEFAULT_REGION / boto3 session region for now.
        region = os.environ.get("AWS_REGION") or os.environ.get("AWS_DEFAULT_REGION")
        if not region:
            sys.exit("AWS_REGION must be set for apply")
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
