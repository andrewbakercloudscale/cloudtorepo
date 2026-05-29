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
| `sg_extend.py` | Flow-log-driven, strictly-additive break-glass extender for live incidents |
| `sg_compact.py` | Widen RFC 1918 CIDRs to reclaim rule budget under the 60-rule SG limit |
| `sg_tightener_test.py` | Regression suite — 66 tests, no AWS credentials required |
| `iam-policy.json` | Minimum IAM permissions |
| `install.sh` | Create the Python venv |
| `requirements.txt` | Python dependencies |

---

## Install

```bash
./install.sh
source .venv/bin/activate
python sg_tightener_test.py        # 66 tests should pass
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
starts getting traffic blocked, the standard analyse/plan/apply loop is too
slow. `sg_extend.py` reads the VPC flow logs over a recent window (default:
the last 24 hours), finds the source IPs whose traffic was **REJECTED**, and
adds them to the named security groups immediately. It is strictly
additive — nothing is ever removed.

```bash
# CloudWatch Logs source
python sg_extend.py \
  --region us-east-1 \
  --groups sg-aaaa,sg-bbbb \
  --log-group /aws/vpc/flowlogs \
  --hours 24 \
  --tolerance 0.5 \
  --ports 443,5432 \
  --description "DR failover 2026-05-28"

# S3 source
python sg_extend.py \
  --region us-east-1 \
  --groups sg-aaaa,sg-bbbb \
  --s3-bucket my-flow-logs --s3-prefix AWSLogs/123456789012/vpcflowlogs \
  --hours 24
```

Behaviour and safety:

* The rejected source IPs are **grouped into the smallest CIDR blocks
  allowed by `--tolerance`** — the fraction of unused (never-observed)
  addresses tolerated inside a grouping block. `--tolerance 0.5` lets a CIDR
  cover a set of sources even when half of that block's addresses were never
  seen. Raising the tolerance packs more sources into fewer rules, which is
  how you stay under the per-group rule limit during a noisy incident.
  Grouping is per protocol/port, so a rule only opens the port that was
  actually rejected.
* **Private by default.** Only RFC 1918 source IPs are added; internet
  REJECT noise is ignored unless `--include-public` is passed. (Public IPs,
  when included, stay as `/32` host routes — they are never widened.)
* `--ports` restricts the rebuild to specific destination ports/ranges. Use
  it to scope a break-glass to just the service that is down.
* A per-group rule budget (`--max-rules`, default 60) is enforced. A group
  that would overflow is **skipped** with a warning — raise `--tolerance`,
  run `sg_compact` to reclaim budget, or raise the SG quota, then re-run.
* CIDRs already covered by an existing rule on the same protocol/port are
  dropped so the budget is honest and duplicate errors are avoided.
* It writes a timestamped manifest of exactly what it added so the next
  tightening cycle can fold the changes back into the evidence base.

Requires either `--log-group` or `--s3-bucket`.

---

## Compaction: sg_compact.py

AWS caps a security group at 60 rules. When a group nears that ceiling —
often after one or more `sg_extend` runs during an incident — `sg_compact`
reclaims budget by merging existing **RFC 1918** ingress CIDRs into fewer,
wider blocks. It reads no flow logs and never removes access: every widened
block is a superset of the blocks it replaces.

You supply a **compaction ratio** — the fraction of unused (never-covered)
addresses tolerated inside a widened CIDR. A ratio of `0.5` lets a block be
used to cover a set of CIDRs even when half of that block's addresses are
not currently allowed. Higher ratio → bigger gaps tolerated → harder
compaction. Public CIDRs, IPv6, `0.0.0.0/0`, SG references, and prefix lists
are never touched.

```bash
# 1. Plan mode with NO --ratio: just the stats. Shows which groups hold the
#    most rules and what each candidate ratio would achieve.
python sg_compact.py plan --region us-east-1

# 2. Pick a ratio from the sweep and write a concrete plan.
python sg_compact.py plan --region us-east-1 --ratio 0.5 --out plan.json

# 3. Review plan.json, then apply (revokes narrow CIDRs, authorises widened).
python sg_compact.py apply --plan plan.json

# 4. If anything looks wrong afterwards:
python sg_compact.py revert --manifest sg_compact-manifest-<ts>.json
```

Plan mode prints two things with no AWS writes:

* **A ranking** of groups by current rule count — where the rules are, and
  which groups are at or over the limit.
* **A ratio sweep** — for each candidate ratio, the projected total rule
  count, rules reclaimed, and how many groups would still exceed the limit.

The plan reuses the `sg-tightener.plan/v1` schema, so it carries a snapshot
hash (apply refuses to run against a changed estate) and is reverted by the
same manifest machinery as `sg_tightener`.

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
