# sg-tightener

Evidence-based security group CIDR tightening for AWS, as an extension of
[CloudtoRepo](https://cloudtorepo.com).

Most enterprise AWS estates trust broad RFC 1918 CIDR blocks for inbound
traffic — `10.0.0.0/16`, `10.4.0.0/16`, and so on — because that is what the
corporate network was once assumed to need. `sg-tightener` reads VPC flow
logs, observes which source IPs have actually connected, and replaces those
broad rules with the tightest set of CIDRs that covers the observed
addresses without exceeding the per-group rule limit.

The tool **only** touches rules whose source CIDR is a strict subset of
RFC 1918 and shorter than `/24` (configurable). Rules with `0.0.0.0/0`,
security group references, IPv6, NACLs, and already-tight CIDRs are left
untouched.

---

## Tools in this directory

| Script | Purpose |
|---|---|
| `sg_tightener.py` | Main tool — modes `analyse`, `plan`, `apply`, `revert` |
| `sg_diagnose.py` | Post-deploy diagnostic — find IPs being REJECTED and not covered |
| `sg_ou_report.py` | Organisation-wide permissive-rule risk report (SG + NACL) |
| `sg_extend.py` | Strictly-additive break-glass extender for live incidents |
| `sg_tightener_test.py` | Regression suite — 44 tests, no AWS credentials required |
| `iam-policy.json` | Minimum IAM permissions |
| `install.sh` | Create the Python venv |
| `requirements.txt` | Python dependencies |

---

## Install

```bash
./install.sh
source .venv/bin/activate
python sg_tightener_test.py        # 44 tests should pass
```

Requires Python 3.9 or later.

---

## Standard workflow

```bash
# 1. Read 90 days of flow logs and write approved.json
python sg_tightener.py analyse \
  --region us-east-1 \
  --log-group /aws/vpc/flowlogs \
  --days 90 \
  --out approved.json

# 2. Build a plan (no AWS writes)
python sg_tightener.py plan \
  --region us-east-1 \
  --approved approved.json \
  --max-rules 60 \
  --out plan.json

# 3. Review plan.json by hand. Apply when satisfied.
python sg_tightener.py apply --plan plan.json

# 4. If apply succeeded but something is now being blocked:
python sg_diagnose.py \
  --region us-east-1 \
  --log-group /aws/vpc/flowlogs \
  --hours 24

# 5. If anything goes seriously wrong:
python sg_tightener.py revert --manifest manifest-<ts>.json
```

---

## Break-glass: sg_extend.py

When a DR failover, supplier IP cutover, or any other unanticipated event
brings traffic from an IP range nothing has seen before, the standard
plan/apply loop is too slow. `sg_extend.py` adds rules immediately and
strictly additively — nothing is ever removed.

```bash
python sg_extend.py \
  --groups sg-aaaa,sg-bbbb \
  --cidrs 10.1.2.0/24 \
  --ports 443,5432 \
  --description "DR failover 2026-05-28"
```

The script writes a timestamped manifest of exactly what it added so the
next tightening cycle can fold the changes back into the evidence base.

---

## OU-wide risk report

```bash
python sg_ou_report.py \
  --regions us-east-1,eu-west-1 \
  --ou-id ou-root-xxxxxxxx \
  --role-name OrganizationAccountAccessRole \
  --out report.xlsx --json report.json
```

Severity-weighted ranking — a single CRITICAL outranks any number of
LOW findings, so the report points you at the right accounts first.
Exits with code 1 if any CRITICAL findings are present, making it
usable as a pipeline gate.

---

## Operational caveats

`sg_tightener` is a forensic analysis framework, not a fire-and-forget
tool. The default 90-day flow log window will not capture quarterly DR
tests, month-end batch jobs, or paths used by blue-green deployments
where the dormant environment was inactive during analysis. Extend the
window with `--days 180` (or longer) for any account where you know
seasonal or infrequent traffic patterns exist, schedule applies for
periods when an on-call engineer is watching, and keep `sg_diagnose.py`
and `sg_extend.py` ready in case something legitimate gets caught.

---

## Related

* [CloudtoRepo](https://cloudtorepo.com) — reverse-engineer your AWS
  estate into Terraform.
* Blog post: "sg-tightener — evidence-based CIDR reduction for hybrid
  cloud security groups" — Andrew Baker, Group CIO, Capitec Bank.
