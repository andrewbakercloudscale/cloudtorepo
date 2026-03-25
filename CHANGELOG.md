# Changelog

All notable changes to Terraclaim are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
