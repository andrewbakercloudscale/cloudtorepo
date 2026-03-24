# aws-tf-reverse

Reverse-engineer your AWS estate into Terraform import blocks — using scripts, not click-ops.

`aws-tf-reverse` scans your AWS account(s) and generates ready-to-use Terraform
`import {}` blocks (Terraform >= 1.5) together with resource skeletons and S3
remote-state backends.  After running the script you can execute
`terraform plan -generate-config-out=generated.tf` in any service directory to
capture the full live configuration automatically.

Explained in detail on the blog:
<https://andrewbaker.ninja/2026/03/21/reverse-engineering-your-aws-estate-into-terraform-using-scripts-not-click-ops/>

---

## Requirements

| Tool | Minimum version |
|------|----------------|
| AWS CLI | 2.x |
| Terraform | 1.5 |
| jq | 1.6 |
| Bash | 4.x |

```bash
aws sts get-caller-identity   # verify credentials
terraform version             # must be >= 1.5
jq --version
```

---

## Quick start

```bash
git clone https://github.com/YOUR_USERNAME/aws-tf-reverse.git
cd aws-tf-reverse
chmod +x aws-tf-reverse.sh reconcile.sh examples/*.sh
```

### 1. Dry-run — preview resource counts without writing files

```bash
./aws-tf-reverse.sh \
  --regions "us-east-1" \
  --services "ec2,vpc,rds" \
  --dry-run
```

### 2. Single account with S3 remote state

```bash
./aws-tf-reverse.sh \
  --regions "us-east-1,eu-west-1" \
  --services "ec2,eks,rds,s3,vpc" \
  --state-bucket my-tf-state-prod \
  --state-region us-east-1 \
  --output ./tf-output
```

### 3. Multi-account organisation sweep

```bash
./aws-tf-reverse.sh \
  --accounts "123456789012,234567890123,345678901234" \
  --role OrganizationAccountAccessRole \
  --regions "us-east-1,eu-west-1,ap-southeast-2" \
  --state-bucket my-tf-state-org \
  --output ./tf-output \
  --debug
```

---

## Options

| Flag | Description | Default |
|------|-------------|---------|
| `--accounts` | Comma-separated account IDs | Current account |
| `--regions` | Comma-separated regions | `us-east-1` |
| `--services` | Comma-separated services (see below) | All supported services |
| `--role` | IAM role name to assume in each account | — |
| `--state-bucket` | S3 bucket for remote state `backend "s3"` | — (local state) |
| `--state-region` | Region of the state S3 bucket | Same as resource region |
| `--output` | Root output directory | `./tf-output` |
| `--dry-run` | Print resource counts; do not write files | `false` |
| `--debug` | Verbose logging | `false` |

---

## Supported services

| Category | Services |
|----------|---------|
| Compute | `ec2`, `ebs`, `ecs`, `eks`, `lambda` |
| Networking | `vpc`, `elb`, `cloudfront`, `route53`, `acm` |
| Data | `rds`, `dynamodb`, `elasticache`, `msk`, `s3` |
| Integration | `sqs`, `sns`, `apigateway` |
| Platform | `iam`, `kms`, `secretsmanager`, `ssm`, `cloudwatch` |

---

## Output structure

```
tf-output/
├── summary.txt
└── 123456789012/
    ├── us-east-1/
    │   ├── ec2/
    │   │   ├── backend.tf
    │   │   ├── imports.tf
    │   │   └── resources.tf
    │   ├── eks/
    │   ├── lambda/
    │   │   └── _packages/
    │   └── rds/
    └── eu-west-1/
```

### Generated files

**`backend.tf`** — S3 remote state configuration + provider block.

**`imports.tf`** — One `import {}` block per discovered resource, e.g.:

```hcl
import {
  to = aws_eks_cluster.cluster_production
  id = "production"
}
```

**`resources.tf`** — Empty resource skeletons matching the import blocks.

---

## Populating configuration from live state

For each service directory:

```bash
cd tf-output/123456789012/us-east-1/eks
terraform init
terraform plan -generate-config-out=generated.tf
```

Terraform reads live state and writes a fully-populated `generated.tf`.
Review it, remove any computed / read-only attributes that would cause a diff,
then commit as your Terraform baseline.

---

## Checking coverage with reconcile.sh

After exporting, verify you haven't missed any resources by comparing the output
against AWS Resource Explorer:

```bash
# Dry run — preview without querying Resource Explorer
./reconcile.sh --output ./tf-output --dry-run

# Full reconciliation
./reconcile.sh --output ./tf-output --index-region us-east-1
```

Sample output:

```
Summary
-------
Total resources (Resource Explorer):  847
Matched to exported import blocks:    801
Potentially missed:                    46
Coverage:                              94%
```

Resource Explorer must be enabled with an **aggregator index** in `--index-region`.

---

## Recommended workflow

1. Run with `--dry-run` to verify resource counts and permissions.
2. Export a single region with your highest-priority services.
3. For each service: `terraform init` → `terraform plan -generate-config-out=generated.tf`.
4. Review generated configuration; remove computed attributes.
5. Run `reconcile.sh` to identify gaps.
6. Commit the baseline on a `baseline-import` branch.
7. Refactor incrementally via pull requests.

---

## IAM permissions

The principal running the script needs read-only access to each service.
A minimum policy should include actions such as:

- `ec2:Describe*`, `eks:List*`, `eks:Describe*`, `rds:Describe*`
- `s3:ListAllMyBuckets`, `s3:GetBucketLocation`
- `lambda:ListFunctions`, `lambda:GetFunction`
- `iam:ListRoles`, `iam:ListUsers`
- `resource-explorer-2:Search`, `resource-explorer-2:GetIndex` (for `reconcile.sh`)
- `sts:AssumeRole` (for multi-account sweeps)

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)
