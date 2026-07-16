#!/usr/bin/env python3
"""sg_transfer_audit.py — list AWS Transfer Family servers open to the internet.

AWS Transfer Family servers (SFTP, FTPS, FTP, AS2) are not covered by
sg_tightener, sg_diagnose, or sg_extend, because those tools only act on
RFC 1918 security group rules and deliberately leave every 0.0.0.0/0 rule
untouched. A Transfer Family server is a distinct exposure category: it
can be internet reachable in three different ways depending on how it was
provisioned, and only one of those ways is controllable with a security
group at all.

EndpointType == PUBLIC
    The server has no security group. It is reachable from the entire
    internet on every enabled protocol port. There is no IP allowlist
    mechanism available at this endpoint type; the only remediation is
    migrating to EndpointType VPC.

EndpointType == VPC
    The server's network interface sits in your VPC and carries the
    security group(s) named in EndpointDetails.SecurityGroupIds. If an
    Elastic IP is attached (EndpointDetails.AddressAllocationIds), the
    server is internet reachable through that address and the security
    group is the only control available. This is the endpoint type that
    supports the "peer to specific partner IPs" pattern the operator
    wants: replace any 0.0.0.0/0 ingress rule with explicit partner CIDR
    blocks or /32 addresses.

EndpointType == VPC_ENDPOINT
    The legacy PrivateLink-based mode. The Transfer API does not expose
    security groups directly on the server; they belong to the VPC
    endpoint's own elastic network interfaces and are read with
    ec2:DescribeVpcEndpoints.

This script reports every server whose enabled protocol ports are exposed
to 0.0.0.0/0, whether that exposure comes from the endpoint type itself or
from a security group rule. It does not modify anything. Use sg_extend.py
or a direct security group edit to apply the partner CIDR allowlist once
you have decided what should be permitted.

Usage:
  sg_transfer_audit.py --regions af-south-1,eu-west-1
                        [--ou-id ou-xxxx-xxxxxxxx | --accounts 111111111111,222222222222]
                        [--role-name OrganizationAccountAccessRole]
                        [--out transfer_report.xlsx] [--json transfer_report.json]
                        [--max-workers 16]

Exit code 1 if any CRITICAL finding is present, so it can be used as a
pipeline gate alongside sg_ou_report.py.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import dataclasses
import datetime as dt
import ipaddress
import json
import logging
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

try:
    import pandas as pd
except ImportError:
    pd = None

from sg_ou_report import _assume, parse_partition_from_arn, _list_org_accounts

LOG = logging.getLogger("sg_transfer_audit")

PUBLIC_ANY = ipaddress.ip_network("0.0.0.0/0")

# Approximate default ports per protocol. FTPS passive ranges and custom
# AS2 listener ports are account specific and are not covered here; treat
# this as a floor, not an exhaustive port list.
PROTOCOL_PORTS: dict[str, list[tuple[int, int]]] = {
    "SFTP": [(22, 22)],
    "FTP": [(21, 21)],
    "FTPS": [(21, 21), (990, 990)],
    "AS2": [(443, 443)],
}


@dataclasses.dataclass
class Finding:
    account_id: str
    account_name: str
    region: str
    server_id: str
    arn: str
    domain: str
    endpoint_type: str
    protocols: list
    security_groups: list
    has_eip: bool
    severity: str
    reason: str
    recommendation: str


def _require_aws() -> None:
    if boto3 is None:
        sys.stderr.write("boto3 is required. Activate the sg-tightener venv.\n")
        sys.exit(2)


def _client(session, service: str, region: str):
    cfg = BotoConfig(retries={"max_attempts": 10, "mode": "adaptive"})
    return session.client(service, region_name=region, config=cfg)


def _list_transfer_servers(session, region: str) -> list[dict]:
    tf = _client(session, "transfer", region)
    out: list[dict] = []
    try:
        paginator = tf.get_paginator("list_servers")
        for page in paginator.paginate():
            for listed in page.get("Servers", []):
                try:
                    detail = tf.describe_server(ServerId=listed["ServerId"])["Server"]
                    out.append(detail)
                except botocore.exceptions.ClientError as exc:
                    LOG.warning(
                        "describe_server failed for %s in %s: %s",
                        listed.get("ServerId"), region, exc,
                    )
    except botocore.exceptions.ClientError as exc:
        LOG.warning("list_servers failed in %s: %s", region, exc)
    return out


def _security_groups_for_server(ec2, server: dict) -> list[str]:
    endpoint_type = server.get("EndpointType")
    endpoint_details = server.get("EndpointDetails") or {}

    if endpoint_type == "VPC":
        return list(endpoint_details.get("SecurityGroupIds") or [])

    if endpoint_type == "VPC_ENDPOINT":
        vpce_id = endpoint_details.get("VpcEndpointId")
        if not vpce_id:
            return []
        try:
            resp = ec2.describe_vpc_endpoints(VpcEndpointIds=[vpce_id])
        except botocore.exceptions.ClientError as exc:
            LOG.warning("describe_vpc_endpoints failed for %s: %s", vpce_id, exc)
            return []
        endpoints = resp.get("VpcEndpoints", [])
        if not endpoints:
            return []
        return [g["GroupId"] for g in endpoints[0].get("Groups", []) if g.get("GroupId")]

    return []  # PUBLIC has no security group at all


def _describe_security_groups(ec2, sg_ids: list[str]) -> list[dict]:
    if not sg_ids:
        return []
    try:
        resp = ec2.describe_security_groups(GroupIds=sg_ids)
        return resp.get("SecurityGroups", [])
    except botocore.exceptions.ClientError as exc:
        LOG.warning("describe_security_groups failed for %s: %s", sg_ids, exc)
        return []


def _ports_overlap(from_p, to_p, lo: int, hi: int) -> bool:
    if from_p is None or to_p is None:
        return True  # protocol "-1" / all ports
    return int(from_p) <= hi and int(to_p) >= lo


def _open_to_world_ports(sgs: list[dict], ports: set[tuple[int, int]]) -> list[tuple[int, int]]:
    """Return the subset of `ports` covered by a 0.0.0.0/0 ingress rule
    in any of `sgs`."""
    exposed: set[tuple[int, int]] = set()
    for sg in sgs:
        for perm in sg.get("IpPermissions", []):
            from_p, to_p = perm.get("FromPort"), perm.get("ToPort")
            for ip in perm.get("IpRanges", []):
                cidr = ip.get("CidrIp")
                if not cidr:
                    continue
                try:
                    net = ipaddress.ip_network(cidr, strict=False)
                except ValueError:
                    continue
                if net != PUBLIC_ANY:
                    continue
                for lo, hi in ports:
                    if _ports_overlap(from_p, to_p, lo, hi):
                        exposed.add((lo, hi))
    return sorted(exposed)


def classify_transfer_server(
    account_id: str, account_name: str, region: str, server: dict, ec2,
) -> Finding:
    endpoint_type = server.get("EndpointType", "UNKNOWN")
    protocols = server.get("Protocols", [])
    endpoint_details = server.get("EndpointDetails") or {}
    has_eip = bool(endpoint_details.get("AddressAllocationIds"))

    ports: set[tuple[int, int]] = set()
    for proto in protocols:
        for rng in PROTOCOL_PORTS.get(proto, []):
            ports.add(rng)

    base = dict(
        account_id=account_id,
        account_name=account_name,
        region=region,
        server_id=server.get("ServerId", ""),
        arn=server.get("Arn", ""),
        domain=server.get("Domain", ""),
        endpoint_type=endpoint_type,
        protocols=protocols,
        has_eip=has_eip,
    )

    if endpoint_type == "PUBLIC":
        return Finding(
            **base,
            security_groups=[],
            severity="CRITICAL",
            reason=(
                "EndpointType is PUBLIC. There is no security group on this "
                "server; it is reachable from the entire internet on every "
                "enabled protocol port."
            ),
            recommendation=(
                "Migrate to EndpointType VPC with an Elastic IP and a security "
                "group restricted to specific partner CIDR blocks or host "
                "addresses. PUBLIC endpoints cannot be restricted to an IP "
                "allowlist under any configuration."
            ),
        )

    sg_ids = _security_groups_for_server(ec2, server)
    sgs = _describe_security_groups(ec2, sg_ids)

    if sg_ids and not sgs:
        return Finding(
            **base,
            security_groups=sg_ids,
            severity="MEDIUM",
            reason="Security group ids were found but could not be described; verify access and re-run.",
            recommendation="Confirm read access to the referenced security groups and re-run the audit.",
        )

    if not sg_ids:
        return Finding(
            **base,
            security_groups=[],
            severity="MEDIUM",
            reason=(
                f"No security group could be resolved for this {endpoint_type} "
                "endpoint. This can happen if the VPC endpoint's network "
                "interfaces have not finished provisioning, or if permissions "
                "are missing."
            ),
            recommendation="Verify the endpoint's attached security groups manually.",
        )

    open_ports = _open_to_world_ports(sgs, ports) if ports else []

    if open_ports:
        severity = "CRITICAL" if has_eip else "HIGH"
        port_desc = ", ".join(f"{lo}" if lo == hi else f"{lo}-{hi}" for lo, hi in open_ports)
        return Finding(
            **base,
            security_groups=sg_ids,
            severity=severity,
            reason=(
                f"Security group(s) {', '.join(sg_ids)} permit 0.0.0.0/0 on "
                f"port(s) {port_desc}, which cover this server's enabled "
                f"protocols ({', '.join(protocols) or 'none listed'})."
            ),
            recommendation=(
                "Replace the 0.0.0.0/0 ingress rule with explicit partner CIDR "
                "blocks or /32 addresses for known partner source IPs. This is "
                "the mechanism that achieves IP-based peering for Transfer "
                "Family; there is no separate peering construct."
            ),
        )

    return Finding(
        **base,
        security_groups=sg_ids,
        severity="LOW",
        reason="No 0.0.0.0/0 ingress rule was found covering this server's enabled protocol ports.",
        recommendation="No action required. Confirm the currently permitted CIDRs still match your active partner list.",
    )


def _scan_region(session, account_id: str, account_name: str, region: str) -> list[Finding]:
    ec2 = _client(session, "ec2", region)
    servers = _list_transfer_servers(session, region)
    return [
        classify_transfer_server(account_id, account_name, region, server, ec2)
        for server in servers
    ]


SEVERITY_ORDER = {"CRITICAL": 0, "HIGH": 1, "MEDIUM": 2, "LOW": 3}


def _aggregate(findings: list[Finding]) -> list[dict]:
    by_account: dict[str, dict] = {}
    for f in findings:
        slot = by_account.setdefault(f.account_id, {
            "account_id": f.account_id,
            "account_name": f.account_name,
            "CRITICAL": 0, "HIGH": 0, "MEDIUM": 0, "LOW": 0,
        })
        slot[f.severity] += 1
    rows = list(by_account.values())
    rows.sort(key=lambda r: (r["CRITICAL"], r["HIGH"], r["MEDIUM"], r["LOW"]), reverse=True)
    return rows


def main(argv: Sequence[str] | None = None) -> int:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    p = argparse.ArgumentParser(prog="sg_transfer_audit.py")
    p.add_argument("--regions", required=True, help="comma-separated AWS regions")
    p.add_argument("--ou-id", help="root OU or sub-OU id; default = list all org accounts")
    p.add_argument("--accounts", help="comma-separated explicit account ids")
    p.add_argument("--role-name", default="OrganizationAccountAccessRole")
    p.add_argument("--out", default="transfer_report.xlsx")
    p.add_argument("--json", default="transfer_report.json")
    p.add_argument("--max-workers", type=int, default=16)
    args = p.parse_args(argv)

    _require_aws()
    regions = [r.strip() for r in args.regions.split(",") if r.strip()]

    sts_caller = boto3.client("sts").get_caller_identity()
    partition = parse_partition_from_arn(sts_caller.get("Arn"))

    if args.accounts:
        accounts = [{"Id": a.strip(), "Name": a.strip()} for a in args.accounts.split(",")]
    else:
        accounts = _list_org_accounts(args.ou_id)
    LOG.info("scanning %d account(s) across %d region(s) for Transfer Family exposure",
              len(accounts), len(regions))

    jobs: list[tuple[str, str, str]] = []
    sessions: dict[str, "boto3.Session"] = {}
    for acct in accounts:
        role_arn = f"arn:{partition}:iam::{acct['Id']}:role/{args.role_name}"
        try:
            sessions[acct["Id"]] = _assume(role_arn, "sg-transfer-audit")
        except Exception as exc:  # noqa: BLE001
            LOG.warning("could not assume role into %s: %s", acct["Id"], exc)
            continue
        for region in regions:
            jobs.append((acct["Id"], acct.get("Name", acct["Id"]), region))

    findings: list[Finding] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.max_workers) as pool:
        futs = {
            pool.submit(_scan_region, sessions[aid], aid, aname, region): (aid, region)
            for aid, aname, region in jobs
        }
        for fut in concurrent.futures.as_completed(futs):
            aid, region = futs[fut]
            try:
                findings.extend(fut.result())
            except Exception as exc:  # noqa: BLE001
                LOG.warning("scan failed in %s/%s: %s", aid, region, exc)

    findings.sort(key=lambda f: SEVERITY_ORDER.get(f.severity, 9))
    summary = _aggregate(findings)

    report = {
        "schema": "sg-transfer-audit.report/v1",
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "regions": regions,
        "findings": [dataclasses.asdict(f) for f in findings],
        "summary": summary,
    }
    with open(args.json, "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2, default=str)

    if pd is not None:
        findings_rows = [dataclasses.asdict(f) for f in findings]
        for row in findings_rows:
            row["protocols"] = ", ".join(row["protocols"])
            row["security_groups"] = ", ".join(row["security_groups"])
        with pd.ExcelWriter(args.out, engine="openpyxl") as writer:
            pd.DataFrame(summary).to_excel(writer, sheet_name="summary", index=False)
            pd.DataFrame(findings_rows).to_excel(writer, sheet_name="findings", index=False)
        LOG.info("wrote %s and %s", args.out, args.json)
    else:
        LOG.info("pandas not installed; wrote JSON only at %s", args.json)

    for f in findings:
        if f.severity in ("CRITICAL", "HIGH"):
            print(f"[{f.severity}] {f.account_id}/{f.region} {f.server_id} "
                  f"({f.endpoint_type}, {', '.join(f.protocols)}): {f.reason}")

    total_critical = sum(r["CRITICAL"] for r in summary)
    if total_critical:
        LOG.error("%d CRITICAL Transfer Family finding(s) across estate", total_critical)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
