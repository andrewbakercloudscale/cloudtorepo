#!/usr/bin/env python3
"""sg_ou_report.py — OU-wide permissive rule scan and risk ranking.

Walks an AWS Organisation (or a fixed account list), assumes a cross-account
role in each active account, scans every requested region in parallel, and
emits a risk-ranked report sorted from most-permissive account to least.
Severity-weighted ranking is used so a single CRITICAL outranks many LOWs.

Network ACLs are scanned and labelled in the report alongside security
groups, but only security groups are tightened by the rest of the suite.

Exits with code 1 if any CRITICAL findings are present, making the script
usable as a pipeline gate.

Usage:
  sg_ou_report.py --regions us-east-1,eu-west-1
                  [--ou-id ou-xxxx | --accounts 111,222,333]
                  [--role-name OrganizationAccountAccessRole]
                  [--out report.xlsx] [--json report.json]
                  [--max-workers 16]
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
    from botocore.config import Config as BotoConfig
except ImportError:
    boto3 = None

try:
    import pandas as pd
except ImportError:
    pd = None

LOG = logging.getLogger("sg_ou_report")

# Severity weights — must satisfy:
#   1 CRITICAL > unbounded LOWs;  1 HIGH > unbounded MEDs;  1 MED > unbounded LOWs.
# Geometric weighting with a large base does that cleanly. Keep the base
# wide enough that even pathological account counts can't promote a lower
# severity past a higher one.
W_CRITICAL = 1_000_000
W_HIGH = 10_000
W_MEDIUM = 100
W_LOW = 1


def compute_risk_score(critical: int, high: int, medium: int, low: int) -> int:
    return (
        critical * W_CRITICAL
        + high * W_HIGH
        + medium * W_MEDIUM
        + low * W_LOW
    )


def parse_partition_from_arn(arn: str | None) -> str:
    """Return the AWS partition from an ARN (aws, aws-cn, aws-us-gov).

    Defaults to ``"aws"`` for unknown, malformed, or missing inputs."""
    if not arn or not isinstance(arn, str):
        return "aws"
    parts = arn.split(":")
    if len(parts) < 2:
        return "aws"
    candidate = parts[1]
    if candidate in ("aws", "aws-cn", "aws-us-gov"):
        return candidate
    return "aws"


# --------------------------------------------------------------------------- #
# Severity classification
# --------------------------------------------------------------------------- #

PUBLIC_ANY = ipaddress.ip_network("0.0.0.0/0")
RFC1918_BLOCKS = [
    ipaddress.ip_network("10.0.0.0/8"),
    ipaddress.ip_network("172.16.0.0/12"),
    ipaddress.ip_network("192.168.0.0/16"),
]

CRITICAL_PUBLIC_PORTS = {22, 3389, 3306, 5432, 1433, 27017, 6379, 9200, 9300, 11211}


def _ports_in_range(from_p: int | None, to_p: int | None) -> set[int]:
    if from_p is None or to_p is None:
        return set(range(0, 65536))
    return set(range(int(from_p), int(to_p) + 1))


def classify_sg_rule(cidr: str, from_p: int | None, to_p: int | None) -> str | None:
    """Return one of CRITICAL/HIGH/MEDIUM/LOW or None for in-scope rules."""
    try:
        net = ipaddress.ip_network(cidr, strict=False)
    except ValueError:
        return None
    ports = _ports_in_range(from_p, to_p)
    if net == PUBLIC_ANY:
        if ports & CRITICAL_PUBLIC_PORTS:
            return "CRITICAL"
        return "HIGH"
    if isinstance(net, ipaddress.IPv4Network) and any(net.subnet_of(b) for b in RFC1918_BLOCKS):
        if net.prefixlen <= 16:
            return "HIGH"
        if net.prefixlen <= 20:
            return "MEDIUM"
        if net.prefixlen <= 23:
            return "LOW"
        return None
    return None


def classify_nacl_rule(cidr: str, port_range: dict | None) -> str | None:
    try:
        net = ipaddress.ip_network(cidr, strict=False)
    except ValueError:
        return None
    if net == PUBLIC_ANY:
        return "HIGH"
    if isinstance(net, ipaddress.IPv4Network) and any(net.subnet_of(b) for b in RFC1918_BLOCKS):
        if net.prefixlen <= 16:
            return "MEDIUM"
        if net.prefixlen <= 20:
            return "LOW"
    return None


# --------------------------------------------------------------------------- #
# Scanning
# --------------------------------------------------------------------------- #

@dataclasses.dataclass
class Finding:
    account_id: str
    account_name: str
    region: str
    resource_type: str  # "SG" or "NACL"
    resource_id: str
    cidr: str
    port_range: str
    severity: str


def _require_aws():
    if boto3 is None:
        sys.stderr.write("boto3 is required. Activate the venv from ./install.sh\n")
        sys.exit(2)


def _assume(role_arn: str, session_name: str) -> "boto3.Session":
    sts = boto3.client("sts")
    creds = sts.assume_role(RoleArn=role_arn, RoleSessionName=session_name)["Credentials"]
    return boto3.Session(
        aws_access_key_id=creds["AccessKeyId"],
        aws_secret_access_key=creds["SecretAccessKey"],
        aws_session_token=creds["SessionToken"],
    )


def _scan_region(session, account_id: str, account_name: str, region: str) -> list[Finding]:
    cfg = BotoConfig(retries={"max_attempts": 10, "mode": "adaptive"})
    ec2 = session.client("ec2", region_name=region, config=cfg)
    out: list[Finding] = []

    try:
        for page in ec2.get_paginator("describe_security_groups").paginate():
            for sg in page.get("SecurityGroups", []):
                for perm in sg.get("IpPermissions", []):
                    for ip in perm.get("IpRanges", []):
                        cidr = ip.get("CidrIp")
                        if not cidr:
                            continue
                        sev = classify_sg_rule(cidr, perm.get("FromPort"), perm.get("ToPort"))
                        if not sev:
                            continue
                        port = (
                            "all" if perm.get("FromPort") is None
                            else f"{perm.get('FromPort')}-{perm.get('ToPort')}"
                        )
                        out.append(Finding(
                            account_id, account_name, region, "SG",
                            sg["GroupId"], cidr, port, sev,
                        ))
    except Exception as exc:  # noqa: BLE001
        LOG.warning("SG scan failed in %s/%s: %s", account_id, region, exc)

    try:
        for page in ec2.get_paginator("describe_network_acls").paginate():
            for nacl in page.get("NetworkAcls", []):
                for entry in nacl.get("Entries", []):
                    if entry.get("Egress"):
                        continue
                    if entry.get("RuleAction") != "allow":
                        continue
                    cidr = entry.get("CidrBlock")
                    if not cidr:
                        continue
                    sev = classify_nacl_rule(cidr, entry.get("PortRange"))
                    if not sev:
                        continue
                    pr = entry.get("PortRange") or {}
                    port = (
                        "all" if not pr
                        else f"{pr.get('From', '?')}-{pr.get('To', '?')}"
                    )
                    out.append(Finding(
                        account_id, account_name, region, "NACL",
                        nacl["NetworkAclId"], cidr, port, sev,
                    ))
    except Exception as exc:  # noqa: BLE001
        LOG.warning("NACL scan failed in %s/%s: %s", account_id, region, exc)

    return out


def _list_org_accounts(ou_id: str | None) -> list[dict]:
    org = boto3.client("organizations")
    if not ou_id:
        accounts = []
        for page in org.get_paginator("list_accounts").paginate():
            accounts.extend(page.get("Accounts", []))
        return [a for a in accounts if a.get("Status") == "ACTIVE"]
    out = []
    queue = [ou_id]
    while queue:
        cur = queue.pop()
        for page in org.get_paginator("list_accounts_for_parent").paginate(ParentId=cur):
            out.extend(page.get("Accounts", []))
        for page in org.get_paginator("list_organizational_units_for_parent").paginate(ParentId=cur):
            queue.extend(o["Id"] for o in page.get("OrganizationalUnits", []))
    return [a for a in out if a.get("Status") == "ACTIVE"]


# --------------------------------------------------------------------------- #
# Aggregation
# --------------------------------------------------------------------------- #

def _aggregate_by_account(findings: list[Finding]) -> list[dict]:
    by_account: dict[str, dict] = {}
    for f in findings:
        slot = by_account.setdefault(f.account_id, {
            "account_id": f.account_id,
            "account_name": f.account_name,
            "CRITICAL": 0, "HIGH": 0, "MEDIUM": 0, "LOW": 0,
        })
        slot[f.severity] += 1
    rows = list(by_account.values())
    for r in rows:
        r["risk_score"] = compute_risk_score(r["CRITICAL"], r["HIGH"], r["MEDIUM"], r["LOW"])
    rows.sort(key=lambda r: r["risk_score"], reverse=True)
    return rows


def main(argv: Sequence[str] | None = None) -> int:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    p = argparse.ArgumentParser(prog="sg_ou_report.py")
    p.add_argument("--regions", required=True, help="comma-separated AWS regions")
    p.add_argument("--ou-id", help="root OU or sub-OU id; default = list all org accounts")
    p.add_argument("--accounts", help="comma-separated explicit account ids")
    p.add_argument("--role-name", default="OrganizationAccountAccessRole")
    p.add_argument("--out", default="report.xlsx")
    p.add_argument("--json", default="report.json")
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
    LOG.info("scanning %d accounts across %d regions", len(accounts), len(regions))

    jobs: list[tuple[str, str, str, str]] = []
    sessions: dict[str, "boto3.Session"] = {}
    for acct in accounts:
        role_arn = f"arn:{partition}:iam::{acct['Id']}:role/{args.role_name}"
        try:
            sessions[acct["Id"]] = _assume(role_arn, "sg-tightener-ou-report")
        except Exception as exc:  # noqa: BLE001
            LOG.warning("could not assume role into %s: %s", acct["Id"], exc)
            continue
        for region in regions:
            jobs.append((acct["Id"], acct.get("Name", acct["Id"]), region, role_arn))

    findings: list[Finding] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.max_workers) as pool:
        futs = {
            pool.submit(_scan_region, sessions[aid], aid, aname, region): (aid, region)
            for aid, aname, region, _ in jobs
        }
        for fut in concurrent.futures.as_completed(futs):
            aid, region = futs[fut]
            try:
                findings.extend(fut.result())
            except Exception as exc:  # noqa: BLE001
                LOG.warning("scan failed in %s/%s: %s", aid, region, exc)

    summary = _aggregate_by_account(findings)
    report = {
        "schema": "sg-tightener.report/v1",
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "regions": regions,
        "findings": [dataclasses.asdict(f) for f in findings],
        "summary": summary,
    }
    with open(args.json, "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2, default=str)

    if pd is not None:
        with pd.ExcelWriter(args.out, engine="openpyxl") as writer:
            pd.DataFrame(summary).to_excel(writer, sheet_name="summary", index=False)
            pd.DataFrame([dataclasses.asdict(f) for f in findings]).to_excel(
                writer, sheet_name="findings", index=False
            )
        LOG.info("wrote %s and %s", args.out, args.json)
    else:
        LOG.info("pandas not installed; wrote JSON only at %s", args.json)

    total_critical = sum(r["CRITICAL"] for r in summary)
    if total_critical:
        LOG.error("%d CRITICAL findings across estate", total_critical)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
