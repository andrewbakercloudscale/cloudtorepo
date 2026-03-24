# Changelog

All notable changes to Terraclaim are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
