# CLAUDE.md — Terraclaim Project Context

This file is the authoritative briefing for any Claude instance working on this repo.
Read it fully before making any changes.

---

## What is Terraclaim?

Terraclaim scans AWS accounts and generates ready-to-use Terraform `import {}` blocks
(Terraform >= 1.5), resource skeletons, and S3 remote-state backends. The goal is to
bring an existing AWS estate under Terraform control without click-ops or paid tooling.

**Repository:** https://github.com/andrewbakercloudscale/terraclaim
**Website:** https://terraclaim.org (hosted on S3 + CloudFront — see deployment below)
**Lead developer:** Andrew Baker — https://andrewbaker.ninja
**Blog post (needs updating):** https://andrewbaker.ninja/2026/03/21/reverse-engineering-your-aws-estate-into-terraform-using-terraclaim-org/

The blog post documents the original `aws-tf-reverse.sh` approach. It needs to be
updated to reflect the rename to Terraclaim, the new `drift.sh` feature, and the
expanded service coverage (now 45+ services).

---

## Repository structure

```
terraclaim/
├── terraclaim.sh       # Main script — scans AWS, writes import blocks
├── drift.sh            # Drift detection — diffs live AWS vs existing imports.tf
├── reconcile.sh        # Coverage check via AWS Resource Explorer
├── run.sh              # Auto terraform init+plan across all output directories
├── sync.sh             # Deploy index.html to S3 + invalidate CloudFront
├── index.html          # terraclaim.org homepage (single-page, no framework)
├── examples/
│   ├── single-account.sh
│   ├── org-sweep.sh
│   └── reconcile-example.sh
├── .github/
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug_report.md
│   │   └── new_service.md
│   └── workflows/
├── README.md
├── CONTRIBUTING.md
└── CLAUDE.md           # this file
```

---

## Scripts

### terraclaim.sh

The main exporter. Accepts:

```bash
./terraclaim.sh \
  --accounts  "123456789012,234567890123" \
  --regions   "us-east-1,eu-west-1" \
  --services  "ec2,eks,rds,s3" \
  --role      OrganizationAccountAccessRole \
  --state-bucket my-tf-state \
  --state-region us-east-1 \
  --output    ./tf-output \
  --parallel  5 \
  --exclude-services "iam,cloudtrail" \
  --dry-run \
  --debug \
  --version
```

Outputs per `account/region/service/`:
- `backend.tf` — S3 remote state + provider
- `imports.tf` — one `import {}` block per resource
- `resources.tf` — empty resource skeletons

After running: `terraform init && terraform plan -generate-config-out=generated.tf`

### drift.sh

Detects drift between live AWS and existing `imports.tf` files. Does NOT require
AWS Resource Explorer. Same flags as `terraclaim.sh` plus:

- `--apply` — patches `imports.tf` in place (appends new blocks, comments out stale ones)
- `--report ./drift-report.txt` — writes report to file as well as stdout
- `--parallel N` — concurrent service scans (default 5); same as terraclaim.sh
- `--exclude-services "svc1,svc2"` — skip specified services

New resources get appended with a timestamp comment. Removed resources are commented
out with a `# [drift.sh] resource no longer found in AWS` note.

### reconcile.sh

Compares output against AWS Resource Explorer. Requires Resource Explorer to be
enabled with an aggregator index. Use `drift.sh` if Resource Explorer is not available.

### run.sh

Automates the post-export terraform step. Finds every directory with an `imports.tf`
under the output tree and runs `terraform init -upgrade` + `terraform plan -generate-config-out=generated.tf`.
Writes a `.run.log` per directory and prints a pass/fail summary.

```bash
./run.sh --output ./tf-output --parallel 3
./run.sh --output ./tf-output --regions us-east-1 --services ec2,eks --dry-run
```

Flags: `--output`, `--services`, `--regions`, `--accounts`, `--parallel`, `--init-only`, `--dry-run`, `--debug`.

### sync.sh

Deploys the website. Uploads `index.html` to the `terraclaim` S3 bucket and creates
a CloudFront invalidation. Uses the `personal` AWS CLI profile.

```bash
./sync.sh
```

---

## AWS infrastructure for terraclaim.org

| Resource | Detail |
|---|---|
| S3 bucket | `terraclaim` (us-east-1, private, OAC-only) |
| CloudFront distribution | `E93UZDMC0QFS1` → `d3jo7iei4mg88l.cloudfront.net` |
| ACM certificate | `arn:aws:acm:us-east-1:987267051295:certificate/3b63fe8b-6510-4794-ab74-6648c2c4d922` |
| Route 53 hosted zone | `Z01548089M4TN3PCUAPT` (terraclaim.org) |
| AWS profile | `personal` |

To deploy website changes:

```bash
./sync.sh
# or manually:
aws s3 cp index.html s3://terraclaim/index.html --profile personal
aws cloudfront create-invalidation --distribution-id E93UZDMC0QFS1 --paths "/*" --profile personal
```

---

## Supported services (45+)

| Category | Services |
|---|---|
| Compute | `ec2`, `ebs`, `ecs`, `eks`, `lambda` |
| Networking | `vpc`, `elb`, `cloudfront`, `route53`, `acm`, `transitgateway`, `vpcendpoints` |
| Data | `rds`, `dynamodb`, `elasticache`, `msk`, `s3`, `efs`, `opensearch`, `redshift`, `documentdb` |
| Streaming | `kinesis` (Data Streams + Firehose) |
| Integration | `sqs`, `sns`, `apigateway`, `eventbridge`, `stepfunctions`, `ses` |
| Security & Compliance | `iam`, `kms`, `secretsmanager`, `wafv2`, `config`, `cloudtrail`, `guardduty` |
| Platform & CI/CD | `ecr`, `ssm`, `cloudwatch`, `backup`, `codepipeline`, `codebuild` |
| Auth | `cognito` (user pools + identity pools + clients) |
| ETL | `glue` (jobs, crawlers, databases, connections) |
| Storage & Transfer | `fsx` (Windows/Lustre/ONTAP/OpenZFS), `transfer` (SFTP/FTPS servers + users) |

---

## Adding a new service

Every service needs changes in **three places**:

1. **`terraclaim.sh`**
   - Add `export_<service>()` function before the dispatcher
   - Add to `dispatch_service` case statement
   - Add to the `SERVICES` default string at the top

2. **`drift.sh`**
   - Add matching `scan_<service>()` function (same AWS CLI calls, no file writing)
   - Add to `scan_service` case statement
   - Add to the `SERVICES` default string at the top

3. **Docs**
   - Add to the supported services table in `README.md`
   - Add to the services grid in `index.html`, then run `./sync.sh`

### Function patterns

`export_*` functions receive `(account region path)` and populate `imports` and `types`
arrays (alternating `resource_address id` pairs), then call `write_backend_tf`,
`write_imports_tf`, `write_resources_tf`.

`scan_*` functions receive `(region)` or `(account region)` for account-scoped services
(e.g. opensearch, glue). They populate the `LIVE_PAIRS` array only — no file I/O.

Global services (IAM, CloudFront, Route53) guard with:
```bash
[[ "${region}" != "us-east-1" ]] && return
```

### Code style rules
- `set -euo pipefail` at the top of every script
- Quote all variable expansions
- `[[ ]]` not `[ ]`
- `local` for all function-scoped variables
- Suppress expected errors with `2>/dev/null || true`
- `slugify()` for all Terraform identifiers
- `bash -n` must pass on all scripts before committing

---

## Website (index.html)

Single HTML file, no framework, no build step. Inline CSS and a small vanilla JS
snippet at the bottom for copy-to-clipboard buttons on all `<pre>` blocks.

Design tokens (CSS variables):
- `--bg: #0a0d14` — page background
- `--surface: #111622` — card background
- `--surface2: #161d2e` — hover card background / secondary surface
- `--border: #1e2a42` — borders
- `--accent: #7c6af7` — purple (step cards, primary buttons)
- `--accent2: #5eead4` — teal (service cards, links)
- `--text: #e2e8f0` — primary text
- `--muted: #c8d3e0` — body / secondary text
- `--code-bg: #0d1117` — code block background

Card hover pattern (used on `.step` and `.service-card` and `.output-card`):
```css
transform: translateY(-6px) scale(1.02);
box-shadow: 0 20px 40px rgba(0,0,0,0.5), 0 0 0 1px var(--accent), 0 8px 32px rgba(124,106,247,0.2);
```

Step card headings (`h3` inside `.step`) use electric yellow `#d4f700`.

After editing `index.html`, always run `./sync.sh` to deploy.

---

## Blog post update needed

URL: https://andrewbaker.ninja/2026/03/21/reverse-engineering-your-aws-estate-into-terraform-using-terraclaim-org/

The post was written for the original `aws-tf-reverse.sh` script. It needs updating to cover:

1. **Rename** — the project is now called Terraclaim, script is `terraclaim.sh`
2. **Website** — link to https://terraclaim.org
3. **GitHub** — link to https://github.com/andrewbakercloudscale/terraclaim
4. **drift.sh** — new drift detection feature, no Resource Explorer required
5. **Service coverage** — now 45+ services (was ~30), including kinesis, cognito,
   cloudtrail, guardduty, backup, redshift, glue, ses, codepipeline, codebuild,
   documentdb, fsx, transfer

---

## History / key decisions

- Originally named `aws-tf-reverse` — renamed to Terraclaim in March 2026
- `drift.sh` was added to complete the governance lifecycle: import → baseline → detect drift → re-import
- `reconcile.sh` requires AWS Resource Explorer; `drift.sh` does not (AWS CLI only)
- Website is a static single HTML file intentionally — no build tooling, easy to edit
- CloudFront uses OAC (Origin Access Control) — S3 bucket is fully private
- AWS profile for all infra operations is `personal`
