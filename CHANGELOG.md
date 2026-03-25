# Changelog

All notable changes to Terraclaim are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [1.7.2] — 2026-03-25

### Added
- `.github/workflows/import.yml` — `workflow_dispatch` CI job that runs
  `import.sh` against the output directory. Inputs: `regions`, `services`,
  `accounts`, `parallel`, `dry_run` (default `true`). Uploads per-directory
  `.import*.log` files as artifacts. Uses OIDC for AWS authentication.
- `tests/import.bats` +1 — `--parallel` test: verifies that all three service
  directories are processed and all resources imported when `--parallel 3` is set.
- `index.html`: Reconcile section added to Deep Dive tab — shows full
  `reconcile.sh` output example, `--local` output example, and
  `--services list` demo with sample output.

### Changed
- README: `import.bats` row updated to 13 tests; suite total updated to 112.

---

## [1.7.1] — 2026-03-25

### Added
- `tests/import.bats` (12 tests) — full BATS suite for `import.sh` using a
  mock terraform binary (no real state or credentials needed). Covers flags,
  `--dry-run`, `--services`/`--regions`/`--accounts` filters, import call
  verification, and state-skipping behaviour.

### Changed
- `index.html`: test count updated to 111 (7 suites); `import.sh` section
  added to Deep Dive tab; `import.sh` added to `chmod +x` quickstart line.
- README: test table updated to 111 tests / 7 suites; `import.bats` row added.

---

## [1.7.0] — 2026-03-25

### Added
- `import.sh` — runs `terraform import` for every resource block in an output
  directory. Reads `imports.tf` files, checks `terraform state list` to skip
  already-managed resources, and calls `terraform import <address> <id>`.
  Supports `--parallel`, `--services`, `--regions`, `--accounts`, `--init`,
  `--dry-run`, and `--debug` flags.
- `reconcile.sh --local` — bypass AWS Resource Explorer entirely; prints a
  per-account / per-region / per-service import block count table directly
  from the output directory. Useful when Resource Explorer is not enabled.
  Auto-fallback: if no aggregator index is found, `--local` behaviour triggers
  automatically with a hint to enable Resource Explorer.
- `report.sh` cross-account summary — when the output directory contains more
  than one account, two additional sections are now emitted: an **Account
  Totals** table and a **Cross-Account Service Totals** table sorted by import
  block count descending.
- `--since` date filter broadened to cover **7 services**: EC2 instances
  (`LaunchTime`), EBS volumes (`CreateTime`), EKS clusters (`createdAt`),
  Lambda functions (`LastModified`), ECR repositories (`createdAt`), RDS
  instances (`InstanceCreateTime`), and Secrets Manager secrets (`CreatedDate`).
- `--services list` flag in both `terraclaim.sh` and `drift.sh` — prints all
  supported service names (one per line, sorted) and exits 0. Useful for
  scripting and tab-completion.

### Added (services)
- **v1.5.0 services** (6 new): `emr`, `sagemaker`, `organizations`, `xray`,
  `appconfig`, `bedrock` — exporters in `terraclaim.sh`, scan functions in
  `drift.sh`, registered in `lib/common.sh` default services list.
- **v1.6.0 services** (3 new): `connect`, `ram`, `servicequotas` — same
  pattern; total supported services now **65+**.

### Tests
- 44 new BATS tests (99 total across 6 suites, all passing):
  - `tests/drift.bats` +19 — `--dry-run` flag, `--services list`, and 13 new
    service scan detection tests (`scan_s3`, `scan_lambda`, `scan_rds`,
    `scan_eks`, `scan_emr`, `scan_sagemaker`, `scan_organizations`, `scan_xray`,
    `scan_appconfig`, `scan_bedrock`, `scan_connect`, `scan_ram`,
    `scan_servicequotas`)
  - `tests/reconcile.bats` +1 — `--local` flag: verifies per-service summary
    without querying Resource Explorer
  - `tests/report.bats` (13) — new suite covering `--title`, summary table,
    per-service counts, sort order, `--out` file writing, drift section, no-drift
    message, and next steps
  - `tests/run.bats` (11) — new suite covering `terraform plan` runner: flags,
    `--services`/`--regions`/`--accounts` filters, `--dry-run`, `--init-only`,
    no-match exit
  - `tests/terraclaim.bats` +3 — `export_connect`, `export_ram`,
    `--services list` includes new services

---

## [1.4.0] — 2026-03-25

### Added
- `report.sh` — generates a Markdown summary report from any `terraclaim.sh`
  output directory. Produces an executive summary table, per-region/service
  import block counts sorted by size, and an optional drift section when a
  `drift.sh --report` file is supplied. Flags: `--output`, `--drift`, `--title`,
  `--out`.
- `lib/common.sh` — shared helper library sourced by both `terraclaim.sh` and
  `drift.sh`. Single source of truth for: `slugify()`, the AWS CLI retry wrapper
  (exponential back-off + jitter), `flush_aws_warnings()`, `load_tag_filter()`,
  `tag_match()`, `assume_role()`, `restore_credentials()`, logging helpers
  (`log`, `debug`, `err`, `die`), and `_TERRACLAIM_DEFAULT_SERVICES`.
- `--profile` flag added to `reconcile.sh` — all three scripts now accept a
  named AWS profile consistently.
- `scripts/hooks/pre-commit` — git pre-commit hook that runs ShellCheck
  (`--severity=warning`) on all shell files and the full BATS test suite before
  every commit. Install with `./scripts/install-hooks.sh`.
- `scripts/install-hooks.sh` — one-shot installer that copies hooks from
  `scripts/hooks/` into `.git/hooks/`.

### Fixed
- `tag_match` calls were missing from 11 `drift.sh` scan functions (`scan_ec2`,
  `scan_ebs`, `scan_eks`, `scan_ecs`, `scan_lambda`, `scan_rds` ×2,
  `scan_dynamodb`, `scan_elb`, `scan_secretsmanager`, `scan_cloudwatch`) —
  resources were not being filtered by `--tags` during drift scans.
- `reconcile.sh` used `grep -r` without `-h`, causing macOS to prepend
  `filename:` to every matched line; the import ID regex never matched and
  coverage was always reported as 0%.
- `reconcile.sh` coverage matching now also walks all slash-segments of each
  ARN resource path, enabling composite import IDs (e.g. EKS nodegroup
  `cluster:nodegroup`) to match against ARNs like
  `arn:aws:eks:.../nodegroup/cluster/ng/uuid`.
- `aws()` wrapper used `printf '%s'` which silently dropped the trailing newline
  stripped by command substitution; the last line of multi-line AWS CLI output
  was never processed by callers using `while read`.
- Three `local` declarations in the `drift.sh` main loop body (outside any
  function) caused a syntax error in strict shells; changed to plain assignments.

### Changed
- `drift.sh` `scan_s3` parallelised to match `terraclaim.sh` `export_s3` —
  bucket-location lookups now run concurrently (throttled to `--parallel N`)
  instead of serially.
- ShellCheck CI workflow updated to use `check_together: yes` so cross-file
  variable references (e.g. `TAGS` / `DEBUG` set in the main script and
  consumed inside `lib/common.sh`) resolve correctly.
- `index.html` split into **Overview** and **Deep Dive** tabs to reduce page
  length. Added `report.sh` section with live example output. Added Quality
  section (55 tests, 4 suites, mock AWS CLI). Updated step labels.

### Tests
- 40 new BATS tests across four suites (55 total, all passing):
  - `tests/common.bats` (15) — `slugify`, `tag_match`, `log`/`debug`/`die`
  - `tests/reconcile.bats` (7) — coverage calculation, composite IDs, ARN matching
  - `tests/drift.bats` +5 — `--apply` mutations (append new, comment stale,
    preserve unchanged)
  - `tests/terraclaim.bats` +10 — `export_s3`, `export_lambda`, `export_kms`,
    `--output-format json`, `--since` validation, `--exclude-services`,
    `--resume` checkpoint, `summary.txt` count

---

## [1.3.0] — 2026-03-24

### Added
- `--account-parallel N` flag — scan multiple accounts concurrently. The outer
  account loop is now extracted into `_run_account()` and can be backgrounded;
  default is 1 (sequential) to preserve existing behaviour.
- `--output-format json` flag — after a run, writes `summary.json` alongside
  `summary.txt` with a structured breakdown of import counts by account, region,
  and service (populated by scanning the output tree via `jq`).
- `--since YYYY-MM-DD` flag — best-effort date filter applied to Lambda
  (`LastModified`), ECR (`createdAt`), and RDS instances (`InstanceCreateTime`);
  resources older than the cutoff are skipped.
- `tag_match()` is now wired into all 12 major exporters: `ec2`, `ebs`, `s3`,
  `lambda`, `rds` (instances + Aurora clusters), `dynamodb`, `elb`, `ecr`,
  `cloudwatch`, `secretsmanager`, `eks` (cluster), `ecs` (cluster). Previously
  only the newer service exporters (`apprunner`, `memorydb`, `lightsail`) used it.
- `.github/workflows/drift-check.yml` — GitHub Actions workflow that runs
  `drift.sh` on a nightly schedule (06:00 UTC) and on `workflow_dispatch`. Opens
  a GitHub issue when new or removed resources are detected; uploads the drift
  report as an artifact.
- `index.html` terminal demo box now lifts on hover (matching the service card
  and step card hover animations).

---

## [1.2.0] — 2026-03-24

### Added
- `--profile` flag in `terraclaim.sh` and `drift.sh` — pass a named AWS profile
  (exported as `AWS_PROFILE`; takes effect before any cross-account role assumption).
- Pagination for Cognito exports — `cognito-idp list-user-pools` and
  `cognito-identity list-identity-pools` now follow `NextToken` until all
  pools are returned (previously hard-capped at 60 per run).
- VPC exporter now captures security groups (non-default), non-main route tables,
  internet gateways, and NAT gateways.
- IAM exporter now captures instance profiles (`aws_iam_instance_profile`) and
  OIDC providers (`aws_iam_openid_connect_provider`).
- EKS exporter now captures Fargate profiles (`aws_eks_fargate_profile`).
- S3 bucket-location parallel scan is throttled to `--parallel N` concurrent jobs
  (previously unbounded, which could hit EC2 API rate limits on large accounts).
- `tests/` — bats-core test suite with mock AWS CLI; covers flag parsing, dry-run
  behaviour, service exporter output structure, slug collision, and `--resume`.

---

## [1.0.0] — 2026-03-24

### Added
- `run.sh` — automates `terraform init` + `terraform plan -generate-config-out=generated.tf`
  across every service directory in the output tree. Supports `--parallel`, `--services`,
  `--regions`, `--accounts`, `--init-only`, and `--dry-run` flags.
- `drift.sh` — drift detection without AWS Resource Explorer; diffs live AWS against
  existing `imports.tf` files; `--apply` patches files in place automatically.
- `--parallel N` flag in `terraclaim.sh` and `drift.sh` (default: 5) — scans up to N services
  concurrently within each account/region using bash job control.
- `--exclude-services` flag in `terraclaim.sh` and `drift.sh` — skip services managed separately.
- `--version` flag in `terraclaim.sh`.
- Automatic AWS API throttle retry with exponential back-off and jitter in both
  `terraclaim.sh` and `drift.sh`. Up to 5 retries on `ThrottlingException`,
  `RequestLimitExceeded`, `SlowDown`, and related errors.
- 13 new services: `kinesis`, `cognito`, `cloudtrail`, `guardduty`, `backup`, `redshift`,
  `glue`, `ses`, `codepipeline`, `codebuild`, `documentdb`, `fsx`, `transfer`.
- `sync.sh` — deploys `index.html` to S3 + invalidates CloudFront for terraclaim.org.
- `CONTRIBUTING.md` — contributing guide with service addition checklist.
- `index.html` — terraclaim.org homepage (single-page, no framework).
- `favicon.svg` — purple `tc` favicon.

### Changed
- Renamed from `aws-tf-reverse` to **Terraclaim**; script renamed to `terraclaim.sh`.
- Total service coverage: **45+ services** across 10 categories.
- `reconcile.sh` updated to remove all `aws-tf-reverse` references.

### Added
- Initial release as **Terraclaim** (renamed from `aws-tf-reverse`).
- `terraclaim.sh` — main exporter; scans AWS and generates `import {}` blocks,
  `backend.tf`, and `resources.tf` per account/region/service.
- `drift.sh` — drift detection without AWS Resource Explorer; diffs live AWS against
  existing `imports.tf` files; `--apply` patches files in place.
- `reconcile.sh` — coverage check via AWS Resource Explorer aggregator index.
- `sync.sh` — deploys `index.html` to S3 and invalidates CloudFront for terraclaim.org.
- 45+ supported services across Compute, Networking, Data, Streaming, Integration,
  Security, Platform, Auth, ETL, and Storage categories.
- Multi-account support via cross-account IAM role assumption (`--role`).
- S3 remote state backend generation (`--state-bucket`, `--state-region`).
- `--dry-run` mode — prints resource counts without writing files.
- Service coverage: `ec2`, `ebs`, `ecs`, `eks`, `lambda`, `vpc`, `elb`, `cloudfront`,
  `route53`, `acm`, `transitgateway`, `vpcendpoints`, `rds`, `dynamodb`, `elasticache`,
  `msk`, `s3`, `efs`, `opensearch`, `redshift`, `documentdb`, `kinesis`, `sqs`, `sns`,
  `apigateway`, `eventbridge`, `stepfunctions`, `ses`, `iam`, `kms`, `secretsmanager`,
  `wafv2`, `config`, `cloudtrail`, `guardduty`, `ecr`, `ssm`, `cloudwatch`, `backup`,
  `codepipeline`, `codebuild`, `cognito`, `glue`, `fsx`, `transfer`.
