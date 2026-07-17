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
| `sg_tightener_test.py` | Regression suite — 80 tests, no AWS credentials required |
| `iam-policy.json` | Minimum IAM permissions |
| `install.sh` | Create the Python venv |
| `requirements.txt` | Python dependencies |

---

## Install

```bash
./install.sh
source .venv/bin/activate
python sg_tightener_test.py        # 101 tests should pass
```

Requires Python 3.9 or later.

### Flow-log format requirements

`analyse` now verifies the flow logs feeding your `--log-group` / `--s3-bucket`
with `ec2:DescribeFlowLogs` before writing an approved list, and derives its
record parsing from the configured log format. Two things to know:

- **The default flow-log format only shows the next hop.** It has no
  `pkt-srcaddr` field, so traffic that reaches an interface through an
  intermediate hop — a **transit gateway attachment ENI** or a **NAT gateway
  ENI** — is recorded with the intermediate interface's private IP as
  `srcaddr`, not the true client. In a TGW estate that puts infrastructure
  addresses into `approved.json` and misses the real client CIDRs. `analyse`
  warns loudly when the format lacks `pkt-srcaddr`. Flow logs cannot be edited
  in place; create a replacement flow log with a custom format such as:

  ```
  ${version} ${account-id} ${interface-id} ${srcaddr} ${dstaddr} ${srcport} ${dstport} ${protocol} ${packets} ${bytes} ${start} ${end} ${action} ${log-status} ${pkt-srcaddr} ${pkt-dstaddr} ${flow-direction}
  ```

- **Fatal misconfigurations abort the run** rather than producing a misleading
  list: flow logs that capture `REJECT` traffic only, formats with no
  `${action}` or no source-address field at all, and destinations fed by a mix
  of different formats (positional parsing is impossible when the column order
  varies per record). Inactive flow logs and delivery errors produce warnings.

The check degrades gracefully: without the `ec2:DescribeFlowLogs` permission
(now included in `iam-policy.json`), or for logs delivered from another
account, `analyse` proceeds assuming the default format and says so.

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
# Auto-discovery (recommended for live incidents): omit --groups and the
# tool derives them from the destination ENIs of the REJECTed flows. The
# operator only needs to know "things are broken in this region".
python sg_extend.py \
  --region us-east-1 \
  --log-group /aws/vpc/flowlogs \
  --hours 24

# Same, but scoped to specific groups when you already know which to fix.
python sg_extend.py \
  --region us-east-1 \
  --groups sg-aaaa,sg-bbbb \
  --log-group /aws/vpc/flowlogs \
  --hours 24 \
  --tolerance 0.5 \
  --ports 443,5432 \
  --description "DR failover 2026-05-29"

# S3 source
python sg_extend.py \
  --region us-east-1 \
  --s3-bucket my-flow-logs --s3-prefix AWSLogs/123456789012/vpcflowlogs \
  --hours 24
```

Behaviour and safety:

* **Auto-group-discovery.** When `--groups` is omitted, `sg_extend` looks
  up the destination ENI of each REJECTed flow via
  `DescribeNetworkInterfaces` and derives the set of attached security
  groups. Each group only receives rules for the flows that hit its own
  ENIs, so a typo in one operator's head doesn't spray rules across the
  estate. A hard `--max-groups` cap (default 20) refuses to act on more
  than that many groups in one run; widen the cap or tighten `--ports`
  / `--hours` if a real incident exceeds it.
* **AWS service summarisation.** When `--include-public` is on, public
  source IPs that fall inside an AWS-published service prefix (Lambda
  Hyperplane ENI traffic appearing under EC2, Route53 health-check
  pingers, etc.) are collapsed into the service's summary CIDR rather
  than enumerating `/32` host routes that go stale as soon as AWS
  rotates the IP. The rule description carries the AWS service / region
  label so the rule's origin is visible at audit time. The catch-all
  `AMAZON` class is deliberately ignored — it covers essentially all of
  AWS and is too broad to be a trust source. Pass `--no-aws-summarise`
  to revert to per-IP host routes.
* The rejected source IPs are **grouped into the smallest CIDR blocks
  allowed by `--tolerance`** — the fraction of unused (never-observed)
  addresses tolerated inside a grouping block. `--tolerance 0.5` lets a CIDR
  cover a set of sources even when half of that block's addresses were never
  seen. Raising the tolerance packs more sources into fewer rules, which is
  how you stay under the per-group rule limit during a noisy incident.
  Grouping is per protocol/port, so a rule only opens the port that was
  actually rejected.
* **Private by default.** Only RFC 1918 source IPs are added; internet
  REJECT noise is ignored unless `--include-public` is passed.
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
