#!/usr/bin/env bash
# aws-tf-reverse.sh — Reverse-engineer an AWS estate into Terraform import blocks.
#
# Generates backend.tf, imports.tf, and resources.tf per account/region/service
# so you can run `terraform plan -generate-config-out=generated.tf` to capture
# live configuration without click-ops.
#
# Requirements: aws-cli >= 2, terraform >= 1.5, jq >= 1.6
#
# Usage:
#   ./aws-tf-reverse.sh [OPTIONS]
#
# Options:
#   --accounts  "id1,id2"           Comma-separated account IDs (default: current)
#   --regions   "r1,r2"             Comma-separated regions (default: us-east-1)
#   --services  "svc1,svc2"         Comma-separated services (default: all)
#   --role      "RoleName"          Cross-account IAM role to assume
#   --state-bucket "bucket"         S3 bucket for remote state backend
#   --state-region "region"         Region of the state S3 bucket
#   --output    "./tf-output"       Root output directory (default: ./tf-output)
#   --dry-run                       Print resource counts; do not write files
#   --debug                         Verbose logging
#   --help                          Show this help

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
ACCOUNTS=""
REGIONS="us-east-1"
SERVICES="ec2,ebs,ecs,eks,lambda,vpc,elb,cloudfront,route53,acm,rds,dynamodb,elasticache,msk,s3,sqs,sns,apigateway,iam,kms,secretsmanager,ssm,cloudwatch,eventbridge,ecr,stepfunctions,wafv2,transitgateway,vpcendpoints,config,efs,opensearch"
ROLE_NAME=""
STATE_BUCKET=""
STATE_REGION=""
OUTPUT_DIR="./tf-output"
DRY_RUN=false
DEBUG=false

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { echo "[INFO]  $*" >&2; }
debug(){ [[ "${DEBUG}" == "true" ]] && echo "[DEBUG] $*" >&2 || true; }
err()  { echo "[ERROR] $*" >&2; }
die()  { err "$*"; exit 1; }

slugify() {
  # Convert a string to a safe Terraform identifier
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/_/g' | sed 's/__*/_/g' | sed 's/^_//;s/_$//'
}

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --accounts)     ACCOUNTS="$2";     shift 2 ;;
    --regions)      REGIONS="$2";      shift 2 ;;
    --services)     SERVICES="$2";     shift 2 ;;
    --role)         ROLE_NAME="$2";    shift 2 ;;
    --state-bucket) STATE_BUCKET="$2"; shift 2 ;;
    --state-region) STATE_REGION="$2"; shift 2 ;;
    --output)       OUTPUT_DIR="$2";   shift 2 ;;
    --dry-run)      DRY_RUN=true;      shift ;;
    --debug)        DEBUG=true;        shift ;;
    --help|-h)      usage ;;
    *) die "Unknown option: $1 — run with --help for usage." ;;
  esac
done

# ---------------------------------------------------------------------------
# Dependency checks
# ---------------------------------------------------------------------------
for cmd in aws terraform jq; do
  command -v "$cmd" &>/dev/null || die "Required command not found: $cmd"
done

TF_VERSION=$(terraform version -json 2>/dev/null | jq -r '.terraform_version' 2>/dev/null || terraform version | head -1 | grep -oE '[0-9]+\.[0-9]+')
TF_MAJOR=$(echo "$TF_VERSION" | cut -d. -f1)
TF_MINOR=$(echo "$TF_VERSION" | cut -d. -f2)
if [[ "$TF_MAJOR" -lt 1 ]] || { [[ "$TF_MAJOR" -eq 1 ]] && [[ "$TF_MINOR" -lt 5 ]]; }; then
  die "Terraform >= 1.5 is required (found $TF_VERSION)"
fi

# ---------------------------------------------------------------------------
# Resolve accounts
# ---------------------------------------------------------------------------
if [[ -z "${ACCOUNTS}" ]]; then
  CURRENT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) \
    || die "Unable to determine current AWS account. Check your credentials."
  ACCOUNTS="${CURRENT_ACCOUNT}"
  log "No --accounts specified; using current account: ${ACCOUNTS}"
fi

IFS=',' read -ra ACCOUNT_LIST <<< "${ACCOUNTS}"
IFS=',' read -ra REGION_LIST  <<< "${REGIONS}"
IFS=',' read -ra SERVICE_LIST <<< "${SERVICES}"

# ---------------------------------------------------------------------------
# Cross-account role assumption
# ---------------------------------------------------------------------------
assume_role() {
  local account_id="$1"
  local role="$2"
  local arn="arn:aws:iam::${account_id}:role/${role}"
  debug "Assuming role: ${arn}"
  local creds
  creds=$(aws sts assume-role \
    --role-arn "${arn}" \
    --role-session-name "aws-tf-reverse-$$" \
    --query 'Credentials' \
    --output json) || die "Failed to assume role ${arn}"
  export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
  AWS_ACCESS_KEY_ID=$(echo "${creds}"    | jq -r '.AccessKeyId')
  AWS_SECRET_ACCESS_KEY=$(echo "${creds}" | jq -r '.SecretAccessKey')
  AWS_SESSION_TOKEN=$(echo "${creds}"    | jq -r '.SessionToken')
}

restore_credentials() {
  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
}

# ---------------------------------------------------------------------------
# File writers
# ---------------------------------------------------------------------------
write_backend_tf() {
  local path="$1" account="$2" region="$3" service="$4"
  cat > "${path}/backend.tf" <<HCL
terraform {
HCL

  if [[ -n "${STATE_BUCKET}" ]]; then
    local key="${account}/${region}/${service}/terraform.tfstate"
    local state_region="${STATE_REGION:-${region}}"
    cat >> "${path}/backend.tf" <<HCL
  backend "s3" {
    bucket         = "${STATE_BUCKET}"
    key            = "${key}"
    region         = "${state_region}"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }

HCL
  fi

  cat >> "${path}/backend.tf" <<HCL
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "${region}"
}
HCL
  debug "Wrote backend.tf -> ${path}/backend.tf"
}

write_imports_tf() {
  local path="$1"
  shift
  # Remaining args: pairs of "resource_address import_id"
  local imports=("$@")
  {
    echo "# Auto-generated import blocks — do not edit by hand."
    echo "# Run: terraform plan -generate-config-out=generated.tf"
    echo ""
    local i=0
    while [[ $i -lt ${#imports[@]} ]]; do
      local addr="${imports[$i]}"
      local id="${imports[$((i+1))]}"
      printf 'import {\n  to = %s\n  id = "%s"\n}\n\n' "${addr}" "${id}"
      i=$((i+2))
    done
  } > "${path}/imports.tf"
  debug "Wrote imports.tf -> ${path}/imports.tf"
}

write_resources_tf() {
  local path="$1"
  shift
  local resource_types=("$@")
  {
    echo "# Auto-generated resource skeletons."
    echo "# After running 'terraform plan -generate-config-out=generated.tf',"
    echo "# replace these stubs with the contents of generated.tf."
    echo ""
    for rt in "${resource_types[@]}"; do
      printf 'resource "%s" "%s" {}\n\n' "$(echo "${rt}" | cut -d. -f1)" "$(echo "${rt}" | cut -d. -f2)"
    done
  } > "${path}/resources.tf"
  debug "Wrote resources.tf -> ${path}/resources.tf"
}

# ---------------------------------------------------------------------------
# Per-service exporters
# Each function receives: account_id region output_path
# It populates arrays: IMPORT_PAIRS (addr id addr id ...) and RESOURCE_TYPES
# ---------------------------------------------------------------------------

export_ec2() {
  local account="$1" region="$2" path="$3"
  local imports=() types=()
  log "  [ec2] listing instances..."
  while IFS=$'\t' read -r instance_id name_tag; do
    [[ -z "${instance_id}" ]] && continue
    local slug; slug=$(slugify "${name_tag:-${instance_id}}")
    imports+=("aws_instance.${slug}" "${instance_id}")
    types+=("aws_instance.${slug}")
  done < <(aws ec2 describe-instances \
    --region "${region}" \
    --filters "Name=instance-state-name,Values=running,stopped" \
    --query 'Reservations[].Instances[].[InstanceId, Tags[?Key==`Name`].Value|[0]]' \
    --output text 2>/dev/null || true)

  [[ ${#imports[@]} -eq 0 ]] && { debug "  [ec2] no instances found"; return; }
  log "  [ec2] found $((${#imports[@]}/2)) instances"
  "${DRY_RUN}" && return
  mkdir -p "${path}"
  write_backend_tf "${path}" "${account}" "${region}" "ec2"
  write_imports_tf  "${path}" "${imports[@]}"
  write_resources_tf "${path}" "${types[@]}"
}

export_ebs() {
  local account="$1" region="$2" path="$3"
  local imports=() types=()
  log "  [ebs] listing volumes..."
  while IFS=$'\t' read -r vol_id name_tag; do
    [[ -z "${vol_id}" ]] && continue
    local slug; slug=$(slugify "${name_tag:-${vol_id}}")
    imports+=("aws_ebs_volume.${slug}" "${vol_id}")
    types+=("aws_ebs_volume.${slug}")
  done < <(aws ec2 describe-volumes \
    --region "${region}" \
    --query 'Volumes[].[VolumeId, Tags[?Key==`Name`].Value|[0]]' \
    --output text 2>/dev/null || true)

  [[ ${#imports[@]} -eq 0 ]] && { debug "  [ebs] no volumes found"; return; }
  log "  [ebs] found $((${#imports[@]}/2)) volumes"
  "${DRY_RUN}" && return
  mkdir -p "${path}"
  write_backend_tf  "${path}" "${account}" "${region}" "ebs"
  write_imports_tf  "${path}" "${imports[@]}"
  write_resources_tf "${path}" "${types[@]}"
}

export_s3() {
  local account="$1" region="$2" path="$3"
  # S3 is global but we scope by region via bucket location
  local imports=() types=()
  log "  [s3] listing buckets..."
  while read -r bucket; do
    [[ -z "${bucket}" ]] && continue
    local bucket_region
    bucket_region=$(aws s3api get-bucket-location \
      --bucket "${bucket}" \
      --query 'LocationConstraint' \
      --output text 2>/dev/null || echo "us-east-1")
    [[ "${bucket_region}" == "None" ]] && bucket_region="us-east-1"
    [[ "${bucket_region}" != "${region}" ]] && continue
    local slug; slug=$(slugify "${bucket}")
    imports+=("aws_s3_bucket.${slug}" "${bucket}")
    types+=("aws_s3_bucket.${slug}")
  done < <(aws s3api list-buckets \
    --query 'Buckets[].Name' \
    --output text 2>/dev/null | tr '\t' '\n' || true)

  [[ ${#imports[@]} -eq 0 ]] && { debug "  [s3] no buckets in ${region}"; return; }
  log "  [s3] found $((${#imports[@]}/2)) buckets in ${region}"
  "${DRY_RUN}" && return
  mkdir -p "${path}"
  write_backend_tf  "${path}" "${account}" "${region}" "s3"
  write_imports_tf  "${path}" "${imports[@]}"
  write_resources_tf "${path}" "${types[@]}"
}

export_vpc() {
  local account="$1" region="$2" path="$3"
  local imports=() types=()
  log "  [vpc] listing VPCs..."
  while IFS=$'\t' read -r vpc_id name_tag; do
    [[ -z "${vpc_id}" ]] && continue
    local slug; slug=$(slugify "${name_tag:-${vpc_id}}")
    imports+=("aws_vpc.${slug}" "${vpc_id}")
    types+=("aws_vpc.${slug}")
  done < <(aws ec2 describe-vpcs \
    --region "${region}" \
    --query 'Vpcs[].[VpcId, Tags[?Key==`Name`].Value|[0]]' \
    --output text 2>/dev/null || true)

  # Subnets
  while IFS=$'\t' read -r subnet_id name_tag; do
    [[ -z "${subnet_id}" ]] && continue
    local slug; slug=$(slugify "${name_tag:-${subnet_id}}")
    imports+=("aws_subnet.${slug}" "${subnet_id}")
    types+=("aws_subnet.${slug}")
  done < <(aws ec2 describe-subnets \
    --region "${region}" \
    --query 'Subnets[].[SubnetId, Tags[?Key==`Name`].Value|[0]]' \
    --output text 2>/dev/null || true)

  [[ ${#imports[@]} -eq 0 ]] && { debug "  [vpc] no VPC resources found"; return; }
  log "  [vpc] found $((${#imports[@]}/2)) VPC resources"
  "${DRY_RUN}" && return
  mkdir -p "${path}"
  write_backend_tf  "${path}" "${account}" "${region}" "vpc"
  write_imports_tf  "${path}" "${imports[@]}"
  write_resources_tf "${path}" "${types[@]}"
}

export_eks() {
  local account="$1" region="$2" path="$3"
  local imports=() types=()
  log "  [eks] listing clusters..."
  local clusters
  clusters=$(aws eks list-clusters \
    --region "${region}" \
    --query 'clusters[]' \
    --output text 2>/dev/null || true)

  for cluster in ${clusters}; do
    local slug; slug=$(slugify "${cluster}")
    imports+=("aws_eks_cluster.cluster_${slug}" "${cluster}")
    types+=("aws_eks_cluster.cluster_${slug}")

    # Node groups
    while read -r ng; do
      [[ -z "${ng}" ]] && continue
      local ng_slug; ng_slug=$(slugify "${ng}")
      imports+=("aws_eks_node_group.ng_${slug}_${ng_slug}" "${cluster}:${ng}")
      types+=("aws_eks_node_group.ng_${slug}_${ng_slug}")
    done < <(aws eks list-nodegroups \
      --cluster-name "${cluster}" \
      --region "${region}" \
      --query 'nodegroups[]' \
      --output text 2>/dev/null | tr '\t' '\n' || true)

    # Addons
    while read -r addon; do
      [[ -z "${addon}" ]] && continue
      local addon_slug; addon_slug=$(slugify "${addon}")
      imports+=("aws_eks_addon.addon_${slug}_${addon_slug}" "${cluster}:${addon}")
      types+=("aws_eks_addon.addon_${slug}_${addon_slug}")
    done < <(aws eks list-addons \
      --cluster-name "${cluster}" \
      --region "${region}" \
      --query 'addons[]' \
      --output text 2>/dev/null | tr '\t' '\n' || true)
  done

  [[ ${#imports[@]} -eq 0 ]] && { debug "  [eks] no clusters found"; return; }
  log "  [eks] found $((${#imports[@]}/2)) EKS resources"
  "${DRY_RUN}" && return
  mkdir -p "${path}"
  write_backend_tf  "${path}" "${account}" "${region}" "eks"
  write_imports_tf  "${path}" "${imports[@]}"
  write_resources_tf "${path}" "${types[@]}"
}

export_ecs() {
  local account="$1" region="$2" path="$3"
  local imports=() types=()
  log "  [ecs] listing clusters..."
  while read -r cluster_arn; do
    [[ -z "${cluster_arn}" ]] && continue
    local cluster_name; cluster_name=$(basename "${cluster_arn}")
    local slug; slug=$(slugify "${cluster_name}")
    imports+=("aws_ecs_cluster.${slug}" "${cluster_name}")
    types+=("aws_ecs_cluster.${slug}")

    # Services
    while read -r svc_arn; do
      [[ -z "${svc_arn}" ]] && continue
      local svc_name; svc_name=$(basename "${svc_arn}")
      local svc_slug; svc_slug=$(slugify "${svc_name}")
      imports+=("aws_ecs_service.${svc_slug}" "${cluster_name}/${svc_name}")
      types+=("aws_ecs_service.${svc_slug}")
    done < <(aws ecs list-services \
      --cluster "${cluster_name}" \
      --region "${region}" \
      --query 'serviceArns[]' \
      --output text 2>/dev/null | tr '\t' '\n' || true)
  done < <(aws ecs list-clusters \
    --region "${region}" \
    --query 'clusterArns[]' \
    --output text 2>/dev/null | tr '\t' '\n' || true)

  [[ ${#imports[@]} -eq 0 ]] && { debug "  [ecs] no clusters found"; return; }
  log "  [ecs] found $((${#imports[@]}/2)) ECS resources"
  "${DRY_RUN}" && return
  mkdir -p "${path}"
  write_backend_tf  "${path}" "${account}" "${region}" "ecs"
  write_imports_tf  "${path}" "${imports[@]}"
  write_resources_tf "${path}" "${types[@]}"
}

export_lambda() {
  local account="$1" region="$2" path="$3"
  local pkg_dir="${path}/_packages"
  local imports=() types=()
  log "  [lambda] listing functions..."
  while read -r fn_name; do
    [[ -z "${fn_name}" ]] && continue
    local slug; slug=$(slugify "${fn_name}")
    imports+=("aws_lambda_function.${slug}" "${fn_name}")
    types+=("aws_lambda_function.${slug}")

    if ! "${DRY_RUN}"; then
      mkdir -p "${pkg_dir}"
      debug "  [lambda] downloading code package for ${fn_name}"
      local url
      url=$(aws lambda get-function \
        --function-name "${fn_name}" \
        --region "${region}" \
        --query 'Code.Location' \
        --output text 2>/dev/null || true)
      if [[ -n "${url}" ]] && [[ "${url}" != "None" ]]; then
        curl -sSL -o "${pkg_dir}/${fn_name}.zip" "${url}" 2>/dev/null || \
          debug "  [lambda] could not download package for ${fn_name}"
      fi
    fi
  done < <(aws lambda list-functions \
    --region "${region}" \
    --query 'Functions[].FunctionName' \
    --output text 2>/dev/null | tr '\t' '\n' || true)

  [[ ${#imports[@]} -eq 0 ]] && { debug "  [lambda] no functions found"; return; }
  log "  [lambda] found $((${#imports[@]}/2)) functions"
  "${DRY_RUN}" && return
  mkdir -p "${path}"
  write_backend_tf  "${path}" "${account}" "${region}" "lambda"
  write_imports_tf  "${path}" "${imports[@]}"
  write_resources_tf "${path}" "${types[@]}"
}

export_rds() {
  local account="$1" region="$2" path="$3"
  local imports=() types=()
  log "  [rds] listing instances and clusters..."

  # RDS instances
  while read -r db_id; do
    [[ -z "${db_id}" ]] && continue
    local slug; slug=$(slugify "${db_id}")
    imports+=("aws_db_instance.${slug}" "${db_id}")
    types+=("aws_db_instance.${slug}")
  done < <(aws rds describe-db-instances \
    --region "${region}" \
    --query 'DBInstances[].DBInstanceIdentifier' \
    --output text 2>/dev/null | tr '\t' '\n' || true)

  # Aurora clusters
  while read -r cluster_id; do
    [[ -z "${cluster_id}" ]] && continue
    local slug; slug=$(slugify "${cluster_id}")
    imports+=("aws_rds_cluster.${slug}" "${cluster_id}")
    types+=("aws_rds_cluster.${slug}")
  done < <(aws rds describe-db-clusters \
    --region "${region}" \
    --query 'DBClusters[].DBClusterIdentifier' \
    --output text 2>/dev/null | tr '\t' '\n' || true)

  [[ ${#imports[@]} -eq 0 ]] && { debug "  [rds] no instances/clusters found"; return; }
  log "  [rds] found $((${#imports[@]}/2)) RDS resources"
  "${DRY_RUN}" && return
  mkdir -p "${path}"
  write_backend_tf  "${path}" "${account}" "${region}" "rds"
  write_imports_tf  "${path}" "${imports[@]}"
  write_resources_tf "${path}" "${types[@]}"
}

export_dynamodb() {
  local account="$1" region="$2" path="$3"
  local imports=() types=()
  log "  [dynamodb] listing tables..."
  while read -r table; do
    [[ -z "${table}" ]] && continue
    local slug; slug=$(slugify "${table}")
    imports+=("aws_dynamodb_table.${slug}" "${table}")
    types+=("aws_dynamodb_table.${slug}")
  done < <(aws dynamodb list-tables \
    --region "${region}" \
    --query 'TableNames[]' \
    --output text 2>/dev/null | tr '\t' '\n' || true)

  [[ ${#imports[@]} -eq 0 ]] && { debug "  [dynamodb] no tables found"; return; }
  log "  [dynamodb] found $((${#imports[@]}/2)) tables"
  "${DRY_RUN}" && return
  mkdir -p "${path}"
  write_backend_tf  "${path}" "${account}" "${region}" "dynamodb"
  write_imports_tf  "${path}" "${imports[@]}"
  write_resources_tf "${path}" "${types[@]}"
}

export_elasticache() {
  local account="$1" region="$2" path="$3"
  local imports=() types=()
  log "  [elasticache] listing replication groups..."
  while read -r rg_id; do
    [[ -z "${rg_id}" ]] && continue
    local slug; slug=$(slugify "${rg_id}")
    imports+=("aws_elasticache_replication_group.${slug}" "${rg_id}")
    types+=("aws_elasticache_replication_group.${slug}")
  done < <(aws elasticache describe-replication-groups \
    --region "${region}" \
    --query 'ReplicationGroups[].ReplicationGroupId' \
    --output text 2>/dev/null | tr '\t' '\n' || true)

  [[ ${#imports[@]} -eq 0 ]] && { debug "  [elasticache] no groups found"; return; }
  log "  [elasticache] found $((${#imports[@]}/2)) ElastiCache groups"
  "${DRY_RUN}" && return
  mkdir -p "${path}"
  write_backend_tf  "${path}" "${account}" "${region}" "elasticache"
  write_imports_tf  "${path}" "${imports[@]}"
  write_resources_tf "${path}" "${types[@]}"
}

export_msk() {
  local account="$1" region="$2" path="$3"
  local imports=() types=()
  log "  [msk] listing Kafka clusters..."
  while IFS=$'\t' read -r cluster_arn cluster_name; do
    [[ -z "${cluster_arn}" ]] && continue
    local slug; slug=$(slugify "${cluster_name}")
    imports+=("aws_msk_cluster.${slug}" "${cluster_arn}")
    types+=("aws_msk_cluster.${slug}")
  done < <(aws kafka list-clusters \
    --region "${region}" \
    --query 'ClusterInfoList[].[ClusterArn, ClusterName]' \
    --output text 2>/dev/null || true)

  [[ ${#imports[@]} -eq 0 ]] && { debug "  [msk] no clusters found"; return; }
  log "  [msk] found $((${#imports[@]}/2)) MSK clusters"
  "${DRY_RUN}" && return
  mkdir -p "${path}"
  write_backend_tf  "${path}" "${account}" "${region}" "msk"
  write_imports_tf  "${path}" "${imports[@]}"
  write_resources_tf "${path}" "${types[@]}"
}

export_sqs() {
  local account="$1" region="$2" path="$3"
  local imports=() types=()
  log "  [sqs] listing queues..."
  while read -r url; do
    [[ -z "${url}" ]] && continue
    local qname; qname=$(basename "${url}")
    local slug; slug=$(slugify "${qname}")
    imports+=("aws_sqs_queue.${slug}" "${url}")
    types+=("aws_sqs_queue.${slug}")
  done < <(aws sqs list-queues \
    --region "${region}" \
    --query 'QueueUrls[]' \
    --output text 2>/dev/null | tr '\t' '\n' || true)

  [[ ${#imports[@]} -eq 0 ]] && { debug "  [sqs] no queues found"; return; }
  log "  [sqs] found $((${#imports[@]}/2)) queues"
  "${DRY_RUN}" && return
  mkdir -p "${path}"
  write_backend_tf  "${path}" "${account}" "${region}" "sqs"
  write_imports_tf  "${path}" "${imports[@]}"
  write_resources_tf "${path}" "${types[@]}"
}

export_sns() {
  local account="$1" region="$2" path="$3"
  local imports=() types=()
  log "  [sns] listing topics..."
  while read -r arn; do
    [[ -z "${arn}" ]] && continue
    local tname; tname=$(basename "${arn}")
    local slug; slug=$(slugify "${tname}")
    imports+=("aws_sns_topic.${slug}" "${arn}")
    types+=("aws_sns_topic.${slug}")
  done < <(aws sns list-topics \
    --region "${region}" \
    --query 'Topics[].TopicArn' \
    --output text 2>/dev/null | tr '\t' '\n' || true)

  [[ ${#imports[@]} -eq 0 ]] && { debug "  [sns] no topics found"; return; }
  log "  [sns] found $((${#imports[@]}/2)) topics"
  "${DRY_RUN}" && return
  mkdir -p "${path}"
  write_backend_tf  "${path}" "${account}" "${region}" "sns"
  write_imports_tf  "${path}" "${imports[@]}"
  write_resources_tf "${path}" "${types[@]}"
}

export_elb() {
  local account="$1" region="$2" path="$3"
  local imports=() types=()
  log "  [elb] listing load balancers..."
  while IFS=$'\t' read -r lb_arn lb_name; do
    [[ -z "${lb_arn}" ]] && continue
    local slug; slug=$(slugify "${lb_name}")
    imports+=("aws_lb.${slug}" "${lb_arn}")
    types+=("aws_lb.${slug}")
  done < <(aws elbv2 describe-load-balancers \
    --region "${region}" \
    --query 'LoadBalancers[].[LoadBalancerArn, LoadBalancerName]' \
    --output text 2>/dev/null || true)

  [[ ${#imports[@]} -eq 0 ]] && { debug "  [elb] no load balancers found"; return; }
  log "  [elb] found $((${#imports[@]}/2)) load balancers"
  "${DRY_RUN}" && return
  mkdir -p "${path}"
  write_backend_tf  "${path}" "${account}" "${region}" "elb"
  write_imports_tf  "${path}" "${imports[@]}"
  write_resources_tf "${path}" "${types[@]}"
}

export_cloudfront() {
  local account="$1" region="$2" path="$3"
  # CloudFront is global; only export when region is us-east-1
  [[ "${region}" != "us-east-1" ]] && return
  local imports=() types=()
  log "  [cloudfront] listing distributions..."
  while IFS=$'\t' read -r dist_id _comment; do
    [[ -z "${dist_id}" ]] && continue
    local slug; slug=$(slugify "${dist_id}")
    imports+=("aws_cloudfront_distribution.${slug}" "${dist_id}")
    types+=("aws_cloudfront_distribution.${slug}")
  done < <(aws cloudfront list-distributions \
    --query 'DistributionList.Items[].[Id, Comment]' \
    --output text 2>/dev/null || true)

  [[ ${#imports[@]} -eq 0 ]] && { debug "  [cloudfront] no distributions found"; return; }
  log "  [cloudfront] found $((${#imports[@]}/2)) distributions"
  "${DRY_RUN}" && return
  mkdir -p "${path}"
  write_backend_tf  "${path}" "${account}" "${region}" "cloudfront"
  write_imports_tf  "${path}" "${imports[@]}"
  write_resources_tf "${path}" "${types[@]}"
}

export_route53() {
  local account="$1" region="$2" path="$3"
  # Route53 is global; only export once
  [[ "${region}" != "us-east-1" ]] && return
  local imports=() types=()
  log "  [route53] listing hosted zones..."
  while IFS=$'\t' read -r zone_id zone_name; do
    [[ -z "${zone_id}" ]] && continue
    # Strip /hostedzone/ prefix
    zone_id="${zone_id##*/hostedzone/}"
    local slug; slug=$(slugify "${zone_name%.}")
    imports+=("aws_route53_zone.${slug}" "${zone_id}")
    types+=("aws_route53_zone.${slug}")
  done < <(aws route53 list-hosted-zones \
    --query 'HostedZones[].[Id, Name]' \
    --output text 2>/dev/null || true)

  [[ ${#imports[@]} -eq 0 ]] && { debug "  [route53] no zones found"; return; }
  log "  [route53] found $((${#imports[@]}/2)) hosted zones"
  "${DRY_RUN}" && return
  mkdir -p "${path}"
  write_backend_tf  "${path}" "${account}" "${region}" "route53"
  write_imports_tf  "${path}" "${imports[@]}"
  write_resources_tf "${path}" "${types[@]}"
}

export_acm() {
  local account="$1" region="$2" path="$3"
  local imports=() types=()
  log "  [acm] listing certificates..."
  while read -r cert_arn; do
    [[ -z "${cert_arn}" ]] && continue
    local slug; slug=$(slugify "$(echo "${cert_arn}" | awk -F/ '{print $NF}')")
    imports+=("aws_acm_certificate.${slug}" "${cert_arn}")
    types+=("aws_acm_certificate.${slug}")
  done < <(aws acm list-certificates \
    --region "${region}" \
    --query 'CertificateSummaryList[].CertificateArn' \
    --output text 2>/dev/null | tr '\t' '\n' || true)

  [[ ${#imports[@]} -eq 0 ]] && { debug "  [acm] no certificates found"; return; }
  log "  [acm] found $((${#imports[@]}/2)) certificates"
  "${DRY_RUN}" && return
  mkdir -p "${path}"
  write_backend_tf  "${path}" "${account}" "${region}" "acm"
  write_imports_tf  "${path}" "${imports[@]}"
  write_resources_tf "${path}" "${types[@]}"
}

export_iam() {
  local account="$1" region="$2" path="$3"
  # IAM is global; only export once
  [[ "${region}" != "us-east-1" ]] && return
  local imports=() types=()
  log "  [iam] listing roles..."
  while read -r role_name; do
    [[ -z "${role_name}" ]] && continue
    local slug; slug=$(slugify "${role_name}")
    imports+=("aws_iam_role.${slug}" "${role_name}")
    types+=("aws_iam_role.${slug}")
  done < <(aws iam list-roles \
    --query 'Roles[].RoleName' \
    --output text 2>/dev/null | tr '\t' '\n' || true)

  [[ ${#imports[@]} -eq 0 ]] && { debug "  [iam] no roles found"; return; }
  log "  [iam] found $((${#imports[@]}/2)) IAM resources"
  "${DRY_RUN}" && return
  mkdir -p "${path}"
  write_backend_tf  "${path}" "${account}" "${region}" "iam"
  write_imports_tf  "${path}" "${imports[@]}"
  write_resources_tf "${path}" "${types[@]}"
}

export_kms() {
  local account="$1" region="$2" path="$3"
  local imports=() types=()
  log "  [kms] listing keys..."
  while IFS=$'\t' read -r key_id _key_arn; do
    [[ -z "${key_id}" ]] && continue
    local slug; slug=$(slugify "${key_id}")
    imports+=("aws_kms_key.${slug}" "${key_id}")
    types+=("aws_kms_key.${slug}")
  done < <(aws kms list-keys \
    --region "${region}" \
    --query 'Keys[].[KeyId, KeyArn]' \
    --output text 2>/dev/null || true)

  [[ ${#imports[@]} -eq 0 ]] && { debug "  [kms] no keys found"; return; }
  log "  [kms] found $((${#imports[@]}/2)) KMS keys"
  "${DRY_RUN}" && return
  mkdir -p "${path}"
  write_backend_tf  "${path}" "${account}" "${region}" "kms"
  write_imports_tf  "${path}" "${imports[@]}"
  write_resources_tf "${path}" "${types[@]}"
}

export_secretsmanager() {
  local account="$1" region="$2" path="$3"
  local imports=() types=()
  log "  [secretsmanager] listing secrets..."
  while IFS=$'\t' read -r secret_arn secret_name; do
    [[ -z "${secret_arn}" ]] && continue
    local slug; slug=$(slugify "${secret_name}")
    imports+=("aws_secretsmanager_secret.${slug}" "${secret_arn}")
    types+=("aws_secretsmanager_secret.${slug}")
  done < <(aws secretsmanager list-secrets \
    --region "${region}" \
    --query 'SecretList[].[ARN, Name]' \
    --output text 2>/dev/null || true)

  [[ ${#imports[@]} -eq 0 ]] && { debug "  [secretsmanager] no secrets found"; return; }
  log "  [secretsmanager] found $((${#imports[@]}/2)) secrets"
  "${DRY_RUN}" && return
  mkdir -p "${path}"
  write_backend_tf  "${path}" "${account}" "${region}" "secretsmanager"
  write_imports_tf  "${path}" "${imports[@]}"
  write_resources_tf "${path}" "${types[@]}"
}

export_ssm() {
  local account="$1" region="$2" path="$3"
  local imports=() types=()
  log "  [ssm] listing parameters..."
  while read -r param_name; do
    [[ -z "${param_name}" ]] && continue
    local slug; slug=$(slugify "${param_name}")
    imports+=("aws_ssm_parameter.${slug}" "${param_name}")
    types+=("aws_ssm_parameter.${slug}")
  done < <(aws ssm describe-parameters \
    --region "${region}" \
    --query 'Parameters[].Name' \
    --output text 2>/dev/null | tr '\t' '\n' || true)

  [[ ${#imports[@]} -eq 0 ]] && { debug "  [ssm] no parameters found"; return; }
  log "  [ssm] found $((${#imports[@]}/2)) SSM parameters"
  "${DRY_RUN}" && return
  mkdir -p "${path}"
  write_backend_tf  "${path}" "${account}" "${region}" "ssm"
  write_imports_tf  "${path}" "${imports[@]}"
  write_resources_tf "${path}" "${types[@]}"
}

export_apigateway() {
  local account="$1" region="$2" path="$3"
  local imports=() types=()
  log "  [apigateway] listing REST APIs..."
  while IFS=$'\t' read -r api_id api_name; do
    [[ -z "${api_id}" ]] && continue
    local slug; slug=$(slugify "${api_name:-${api_id}}")
    imports+=("aws_api_gateway_rest_api.${slug}" "${api_id}")
    types+=("aws_api_gateway_rest_api.${slug}")
  done < <(aws apigateway get-rest-apis \
    --region "${region}" \
    --query 'items[].[id, name]' \
    --output text 2>/dev/null || true)

  # HTTP APIs (v2)
  while IFS=$'\t' read -r api_id api_name; do
    [[ -z "${api_id}" ]] && continue
    local slug; slug=$(slugify "${api_name:-${api_id}}")
    imports+=("aws_apigatewayv2_api.${slug}" "${api_id}")
    types+=("aws_apigatewayv2_api.${slug}")
  done < <(aws apigatewayv2 get-apis \
    --region "${region}" \
    --query 'Items[].[ApiId, Name]' \
    --output text 2>/dev/null || true)

  [[ ${#imports[@]} -eq 0 ]] && { debug "  [apigateway] no APIs found"; return; }
  log "  [apigateway] found $((${#imports[@]}/2)) APIs"
  "${DRY_RUN}" && return
  mkdir -p "${path}"
  write_backend_tf  "${path}" "${account}" "${region}" "apigateway"
  write_imports_tf  "${path}" "${imports[@]}"
  write_resources_tf "${path}" "${types[@]}"
}

export_cloudwatch() {
  local account="$1" region="$2" path="$3"
  local imports=() types=()
  log "  [cloudwatch] listing log groups..."
  while read -r lg_name; do
    [[ -z "${lg_name}" ]] && continue
    local slug; slug=$(slugify "${lg_name}")
    imports+=("aws_cloudwatch_log_group.${slug}" "${lg_name}")
    types+=("aws_cloudwatch_log_group.${slug}")
  done < <(aws logs describe-log-groups \
    --region "${region}" \
    --query 'logGroups[].logGroupName' \
    --output text 2>/dev/null | tr '\t' '\n' || true)

  [[ ${#imports[@]} -eq 0 ]] && { debug "  [cloudwatch] no log groups found"; return; }
  log "  [cloudwatch] found $((${#imports[@]}/2)) CloudWatch log groups"
  "${DRY_RUN}" && return
  mkdir -p "${path}"
  write_backend_tf  "${path}" "${account}" "${region}" "cloudwatch"
  write_imports_tf  "${path}" "${imports[@]}"
  write_resources_tf "${path}" "${types[@]}"
}

export_eventbridge() {
  local account="$1" region="$2" path="$3"
  local imports=() types=()
  log "  [eventbridge] listing rules and event buses..."

  # Custom event buses (skip the default bus — it's not importable)
  while read -r bus_name; do
    [[ -z "${bus_name}" ]] && continue
    [[ "${bus_name}" == "default" ]] && continue
    local slug; slug=$(slugify "${bus_name}")
    imports+=("aws_cloudwatch_event_bus.${slug}" "${bus_name}")
    types+=("aws_cloudwatch_event_bus.${slug}")
  done < <(aws events list-event-buses \
    --region "${region}" \
    --query 'EventBuses[].Name' \
    --output text 2>/dev/null | tr '\t' '\n' || true)

  # Rules (on the default bus and any custom buses)
  local all_buses=("default")
  while read -r bus_name; do
    [[ -z "${bus_name}" ]] && continue
    [[ "${bus_name}" == "default" ]] && continue
    all_buses+=("${bus_name}")
  done < <(aws events list-event-buses \
    --region "${region}" \
    --query 'EventBuses[].Name' \
    --output text 2>/dev/null | tr '\t' '\n' || true)

  for bus in "${all_buses[@]}"; do
    while read -r rule_name; do
      [[ -z "${rule_name}" ]] && continue
      local slug; slug=$(slugify "${bus}_${rule_name}")
      local import_id="${rule_name}"
      [[ "${bus}" != "default" ]] && import_id="${bus}/${rule_name}"
      imports+=("aws_cloudwatch_event_rule.${slug}" "${import_id}")
      types+=("aws_cloudwatch_event_rule.${slug}")
    done < <(aws events list-rules \
      --event-bus-name "${bus}" \
      --region "${region}" \
      --query 'Rules[].Name' \
      --output text 2>/dev/null | tr '\t' '\n' || true)
  done

  [[ ${#imports[@]} -eq 0 ]] && { debug "  [eventbridge] no resources found"; return; }
  log "  [eventbridge] found $((${#imports[@]}/2)) EventBridge resources"
  "${DRY_RUN}" && return
  mkdir -p "${path}"
  write_backend_tf  "${path}" "${account}" "${region}" "eventbridge"
  write_imports_tf  "${path}" "${imports[@]}"
  write_resources_tf "${path}" "${types[@]}"
}

export_ecr() {
  local account="$1" region="$2" path="$3"
  local imports=() types=()
  log "  [ecr] listing repositories..."
  while read -r repo_name; do
    [[ -z "${repo_name}" ]] && continue
    local slug; slug=$(slugify "${repo_name}")
    imports+=("aws_ecr_repository.${slug}" "${repo_name}")
    types+=("aws_ecr_repository.${slug}")
  done < <(aws ecr describe-repositories \
    --region "${region}" \
    --query 'repositories[].repositoryName' \
    --output text 2>/dev/null | tr '\t' '\n' || true)

  # Lifecycle policies are separate resources
  for i in $(seq 0 2 $((${#imports[@]}-2))); do
    local repo_name="${imports[$((i+1))]}"
    local slug; slug=$(slugify "${repo_name}")
    local has_policy
    has_policy=$(aws ecr get-lifecycle-policy \
      --repository-name "${repo_name}" \
      --region "${region}" \
      --query 'repositoryName' \
      --output text 2>/dev/null || true)
    if [[ -n "${has_policy}" ]]; then
      imports+=("aws_ecr_lifecycle_policy.${slug}" "${repo_name}")
      types+=("aws_ecr_lifecycle_policy.${slug}")
    fi
  done

  [[ ${#imports[@]} -eq 0 ]] && { debug "  [ecr] no repositories found"; return; }
  log "  [ecr] found $((${#imports[@]}/2)) ECR resources"
  "${DRY_RUN}" && return
  mkdir -p "${path}"
  write_backend_tf  "${path}" "${account}" "${region}" "ecr"
  write_imports_tf  "${path}" "${imports[@]}"
  write_resources_tf "${path}" "${types[@]}"
}

export_stepfunctions() {
  local account="$1" region="$2" path="$3"
  local imports=() types=()
  log "  [stepfunctions] listing state machines..."
  while IFS=$'\t' read -r sm_arn sm_name; do
    [[ -z "${sm_arn}" ]] && continue
    local slug; slug=$(slugify "${sm_name}")
    imports+=("aws_sfn_state_machine.${slug}" "${sm_arn}")
    types+=("aws_sfn_state_machine.${slug}")
  done < <(aws stepfunctions list-state-machines \
    --region "${region}" \
    --query 'stateMachines[].[stateMachineArn, name]' \
    --output text 2>/dev/null || true)

  [[ ${#imports[@]} -eq 0 ]] && { debug "  [stepfunctions] no state machines found"; return; }
  log "  [stepfunctions] found $((${#imports[@]}/2)) state machines"
  "${DRY_RUN}" && return
  mkdir -p "${path}"
  write_backend_tf  "${path}" "${account}" "${region}" "stepfunctions"
  write_imports_tf  "${path}" "${imports[@]}"
  write_resources_tf "${path}" "${types[@]}"
}

export_wafv2() {
  local account="$1" region="$2" path="$3"
  local imports=() types=()
  log "  [wafv2] listing Web ACLs and IP sets..."

  for scope in REGIONAL CLOUDFRONT; do
    # CloudFront scope must be queried from us-east-1
    [[ "${scope}" == "CLOUDFRONT" ]] && [[ "${region}" != "us-east-1" ]] && continue

    # Web ACLs
    while IFS=$'\t' read -r acl_id acl_name; do
      [[ -z "${acl_id}" ]] && continue
      local slug; slug=$(slugify "${scope}_${acl_name}")
      # Import ID format: name/id/scope
      imports+=("aws_wafv2_web_acl.${slug}" "${acl_name}/${acl_id}/${scope}")
      types+=("aws_wafv2_web_acl.${slug}")
    done < <(aws wafv2 list-web-acls \
      --scope "${scope}" \
      --region "${region}" \
      --query 'WebACLs[].[Id, Name]' \
      --output text 2>/dev/null || true)

    # IP sets
    while IFS=$'\t' read -r ip_id ip_name; do
      [[ -z "${ip_id}" ]] && continue
      local slug; slug=$(slugify "${scope}_${ip_name}")
      imports+=("aws_wafv2_ip_set.${slug}" "${ip_name}/${ip_id}/${scope}")
      types+=("aws_wafv2_ip_set.${slug}")
    done < <(aws wafv2 list-ip-sets \
      --scope "${scope}" \
      --region "${region}" \
      --query 'IPSets[].[Id, Name]' \
      --output text 2>/dev/null || true)

    # Rule groups
    while IFS=$'\t' read -r rg_id rg_name; do
      [[ -z "${rg_id}" ]] && continue
      local slug; slug=$(slugify "${scope}_${rg_name}")
      imports+=("aws_wafv2_rule_group.${slug}" "${rg_name}/${rg_id}/${scope}")
      types+=("aws_wafv2_rule_group.${slug}")
    done < <(aws wafv2 list-rule-groups \
      --scope "${scope}" \
      --region "${region}" \
      --query 'RuleGroups[].[Id, Name]' \
      --output text 2>/dev/null || true)
  done

  [[ ${#imports[@]} -eq 0 ]] && { debug "  [wafv2] no resources found"; return; }
  log "  [wafv2] found $((${#imports[@]}/2)) WAFv2 resources"
  "${DRY_RUN}" && return
  mkdir -p "${path}"
  write_backend_tf  "${path}" "${account}" "${region}" "wafv2"
  write_imports_tf  "${path}" "${imports[@]}"
  write_resources_tf "${path}" "${types[@]}"
}

export_transitgateway() {
  local account="$1" region="$2" path="$3"
  local imports=() types=()
  log "  [transitgateway] listing Transit Gateways..."

  # Transit Gateways
  while IFS=$'\t' read -r tgw_id name_tag; do
    [[ -z "${tgw_id}" ]] && continue
    local slug; slug=$(slugify "${name_tag:-${tgw_id}}")
    imports+=("aws_ec2_transit_gateway.${slug}" "${tgw_id}")
    types+=("aws_ec2_transit_gateway.${slug}")

    # VPC attachments for this TGW
    while IFS=$'\t' read -r att_id att_name; do
      [[ -z "${att_id}" ]] && continue
      local att_slug; att_slug=$(slugify "${att_name:-${att_id}}")
      imports+=("aws_ec2_transit_gateway_vpc_attachment.${att_slug}" "${att_id}")
      types+=("aws_ec2_transit_gateway_vpc_attachment.${att_slug}")
    done < <(aws ec2 describe-transit-gateway-vpc-attachments \
      --region "${region}" \
      --filters "Name=transit-gateway-id,Values=${tgw_id}" "Name=state,Values=available" \
      --query 'TransitGatewayVpcAttachments[].[TransitGatewayAttachmentId, Tags[?Key==`Name`].Value|[0]]' \
      --output text 2>/dev/null || true)

    # Route tables
    while IFS=$'\t' read -r rt_id rt_name; do
      [[ -z "${rt_id}" ]] && continue
      local rt_slug; rt_slug=$(slugify "${rt_name:-${rt_id}}")
      imports+=("aws_ec2_transit_gateway_route_table.${rt_slug}" "${rt_id}")
      types+=("aws_ec2_transit_gateway_route_table.${rt_slug}")
    done < <(aws ec2 describe-transit-gateway-route-tables \
      --region "${region}" \
      --filters "Name=transit-gateway-id,Values=${tgw_id}" \
      --query 'TransitGatewayRouteTables[].[TransitGatewayRouteTableId, Tags[?Key==`Name`].Value|[0]]' \
      --output text 2>/dev/null || true)
  done < <(aws ec2 describe-transit-gateways \
    --region "${region}" \
    --filters "Name=state,Values=available" \
    --query 'TransitGateways[].[TransitGatewayId, Tags[?Key==`Name`].Value|[0]]' \
    --output text 2>/dev/null || true)

  [[ ${#imports[@]} -eq 0 ]] && { debug "  [transitgateway] no resources found"; return; }
  log "  [transitgateway] found $((${#imports[@]}/2)) Transit Gateway resources"
  "${DRY_RUN}" && return
  mkdir -p "${path}"
  write_backend_tf  "${path}" "${account}" "${region}" "transitgateway"
  write_imports_tf  "${path}" "${imports[@]}"
  write_resources_tf "${path}" "${types[@]}"
}

export_vpcendpoints() {
  local account="$1" region="$2" path="$3"
  local imports=() types=()
  log "  [vpcendpoints] listing VPC endpoints..."
  while IFS=$'\t' read -r ep_id service_name; do
    [[ -z "${ep_id}" ]] && continue
    # Use service short name for slug (e.g. com.amazonaws.us-east-1.s3 -> s3)
    local short; short=$(echo "${service_name}" | awk -F. '{print $NF}')
    local slug; slug=$(slugify "${ep_id}_${short}")
    imports+=("aws_vpc_endpoint.${slug}" "${ep_id}")
    types+=("aws_vpc_endpoint.${slug}")
  done < <(aws ec2 describe-vpc-endpoints \
    --region "${region}" \
    --filters "Name=vpc-endpoint-state,Values=available,pending" \
    --query 'VpcEndpoints[].[VpcEndpointId, ServiceName]' \
    --output text 2>/dev/null || true)

  [[ ${#imports[@]} -eq 0 ]] && { debug "  [vpcendpoints] no endpoints found"; return; }
  log "  [vpcendpoints] found $((${#imports[@]}/2)) VPC endpoints"
  "${DRY_RUN}" && return
  mkdir -p "${path}"
  write_backend_tf  "${path}" "${account}" "${region}" "vpcendpoints"
  write_imports_tf  "${path}" "${imports[@]}"
  write_resources_tf "${path}" "${types[@]}"
}

export_config() {
  local account="$1" region="$2" path="$3"
  local imports=() types=()
  log "  [config] listing Config rules and recorder..."

  # Configuration recorder
  while read -r recorder_name; do
    [[ -z "${recorder_name}" ]] && continue
    local slug; slug=$(slugify "${recorder_name}")
    imports+=("aws_config_configuration_recorder.${slug}" "${recorder_name}")
    types+=("aws_config_configuration_recorder.${slug}")
    # Recorder status is a separate resource, same import ID
    imports+=("aws_config_configuration_recorder_status.${slug}" "${recorder_name}")
    types+=("aws_config_configuration_recorder_status.${slug}")
  done < <(aws configservice describe-configuration-recorders \
    --region "${region}" \
    --query 'ConfigurationRecorders[].name' \
    --output text 2>/dev/null | tr '\t' '\n' || true)

  # Delivery channel
  while read -r channel_name; do
    [[ -z "${channel_name}" ]] && continue
    local slug; slug=$(slugify "${channel_name}")
    imports+=("aws_config_delivery_channel.${slug}" "${channel_name}")
    types+=("aws_config_delivery_channel.${slug}")
  done < <(aws configservice describe-delivery-channels \
    --region "${region}" \
    --query 'DeliveryChannels[].name' \
    --output text 2>/dev/null | tr '\t' '\n' || true)

  # Config rules
  while read -r rule_name; do
    [[ -z "${rule_name}" ]] && continue
    local slug; slug=$(slugify "${rule_name}")
    imports+=("aws_config_config_rule.${slug}" "${rule_name}")
    types+=("aws_config_config_rule.${slug}")
  done < <(aws configservice describe-config-rules \
    --region "${region}" \
    --query 'ConfigRules[].ConfigRuleName' \
    --output text 2>/dev/null | tr '\t' '\n' || true)

  # Conformance packs
  while read -r pack_name; do
    [[ -z "${pack_name}" ]] && continue
    local slug; slug=$(slugify "${pack_name}")
    imports+=("aws_config_conformance_pack.${slug}" "${pack_name}")
    types+=("aws_config_conformance_pack.${slug}")
  done < <(aws configservice describe-conformance-packs \
    --region "${region}" \
    --query 'ConformancePackDetails[].ConformancePackName' \
    --output text 2>/dev/null | tr '\t' '\n' || true)

  [[ ${#imports[@]} -eq 0 ]] && { debug "  [config] no resources found"; return; }
  log "  [config] found $((${#imports[@]}/2)) Config resources"
  "${DRY_RUN}" && return
  mkdir -p "${path}"
  write_backend_tf  "${path}" "${account}" "${region}" "config"
  write_imports_tf  "${path}" "${imports[@]}"
  write_resources_tf "${path}" "${types[@]}"
}

export_efs() {
  local account="$1" region="$2" path="$3"
  local imports=() types=()
  log "  [efs] listing file systems..."
  while IFS=$'\t' read -r fs_id name_tag; do
    [[ -z "${fs_id}" ]] && continue
    local slug; slug=$(slugify "${name_tag:-${fs_id}}")
    imports+=("aws_efs_file_system.${slug}" "${fs_id}")
    types+=("aws_efs_file_system.${slug}")

    # Mount targets for this file system
    while read -r mt_id; do
      [[ -z "${mt_id}" ]] && continue
      local mt_slug; mt_slug=$(slugify "${mt_id}")
      imports+=("aws_efs_mount_target.${mt_slug}" "${mt_id}")
      types+=("aws_efs_mount_target.${mt_slug}")
    done < <(aws efs describe-mount-targets \
      --file-system-id "${fs_id}" \
      --region "${region}" \
      --query 'MountTargets[].MountTargetId' \
      --output text 2>/dev/null | tr '\t' '\n' || true)

    # Access points
    while IFS=$'\t' read -r ap_id ap_name; do
      [[ -z "${ap_id}" ]] && continue
      local ap_slug; ap_slug=$(slugify "${ap_name:-${ap_id}}")
      imports+=("aws_efs_access_point.${ap_slug}" "${ap_id}")
      types+=("aws_efs_access_point.${ap_slug}")
    done < <(aws efs describe-access-points \
      --file-system-id "${fs_id}" \
      --region "${region}" \
      --query 'AccessPoints[].[AccessPointId, Tags[?Key==`Name`].Value|[0]]' \
      --output text 2>/dev/null || true)
  done < <(aws efs describe-file-systems \
    --region "${region}" \
    --query 'FileSystems[].[FileSystemId, Tags[?Key==`Name`].Value|[0]]' \
    --output text 2>/dev/null || true)

  [[ ${#imports[@]} -eq 0 ]] && { debug "  [efs] no file systems found"; return; }
  log "  [efs] found $((${#imports[@]}/2)) EFS resources"
  "${DRY_RUN}" && return
  mkdir -p "${path}"
  write_backend_tf  "${path}" "${account}" "${region}" "efs"
  write_imports_tf  "${path}" "${imports[@]}"
  write_resources_tf "${path}" "${types[@]}"
}

export_opensearch() {
  local account="$1" region="$2" path="$3"
  local imports=() types=()
  log "  [opensearch] listing domains..."
  while read -r domain_name; do
    [[ -z "${domain_name}" ]] && continue
    local slug; slug=$(slugify "${domain_name}")
    # Import ID format: account-id/domain-name
    imports+=("aws_opensearch_domain.${slug}" "${account}/${domain_name}")
    types+=("aws_opensearch_domain.${slug}")
  done < <(aws opensearch list-domain-names \
    --region "${region}" \
    --query 'DomainNames[].DomainName' \
    --output text 2>/dev/null | tr '\t' '\n' || true)

  [[ ${#imports[@]} -eq 0 ]] && { debug "  [opensearch] no domains found"; return; }
  log "  [opensearch] found $((${#imports[@]}/2)) OpenSearch domains"
  "${DRY_RUN}" && return
  mkdir -p "${path}"
  write_backend_tf  "${path}" "${account}" "${region}" "opensearch"
  write_imports_tf  "${path}" "${imports[@]}"
  write_resources_tf "${path}" "${types[@]}"
}

# ---------------------------------------------------------------------------
# Service dispatcher
# ---------------------------------------------------------------------------
dispatch_service() {
  local svc="$1" account="$2" region="$3" base_path="$4"
  local path="${base_path}/${region}/${svc}"
  case "${svc}" in
    ec2)            export_ec2            "${account}" "${region}" "${path}" ;;
    ebs)            export_ebs            "${account}" "${region}" "${path}" ;;
    s3)             export_s3             "${account}" "${region}" "${path}" ;;
    vpc)            export_vpc            "${account}" "${region}" "${path}" ;;
    eks)            export_eks            "${account}" "${region}" "${path}" ;;
    ecs)            export_ecs            "${account}" "${region}" "${path}" ;;
    lambda)         export_lambda         "${account}" "${region}" "${path}" ;;
    rds)            export_rds            "${account}" "${region}" "${path}" ;;
    dynamodb)       export_dynamodb       "${account}" "${region}" "${path}" ;;
    elasticache)    export_elasticache    "${account}" "${region}" "${path}" ;;
    msk)            export_msk            "${account}" "${region}" "${path}" ;;
    sqs)            export_sqs            "${account}" "${region}" "${path}" ;;
    sns)            export_sns            "${account}" "${region}" "${path}" ;;
    elb)            export_elb            "${account}" "${region}" "${path}" ;;
    cloudfront)     export_cloudfront     "${account}" "${region}" "${path}" ;;
    route53)        export_route53        "${account}" "${region}" "${path}" ;;
    acm)            export_acm            "${account}" "${region}" "${path}" ;;
    iam)            export_iam            "${account}" "${region}" "${path}" ;;
    kms)            export_kms            "${account}" "${region}" "${path}" ;;
    secretsmanager) export_secretsmanager "${account}" "${region}" "${path}" ;;
    ssm)            export_ssm            "${account}" "${region}" "${path}" ;;
    apigateway)     export_apigateway     "${account}" "${region}" "${path}" ;;
    cloudwatch)     export_cloudwatch     "${account}" "${region}" "${path}" ;;
    eventbridge)    export_eventbridge    "${account}" "${region}" "${path}" ;;
    ecr)            export_ecr            "${account}" "${region}" "${path}" ;;
    stepfunctions)  export_stepfunctions  "${account}" "${region}" "${path}" ;;
    wafv2)          export_wafv2          "${account}" "${region}" "${path}" ;;
    transitgateway) export_transitgateway "${account}" "${region}" "${path}" ;;
    vpcendpoints)   export_vpcendpoints   "${account}" "${region}" "${path}" ;;
    config)         export_config         "${account}" "${region}" "${path}" ;;
    efs)            export_efs            "${account}" "${region}" "${path}" ;;
    opensearch)     export_opensearch     "${account}" "${region}" "${path}" ;;
    *) log "  [WARN] Unknown service '${svc}' — skipping" ;;
  esac
}

# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
TOTAL_IMPORTS=0
SUMMARY_FILE="${OUTPUT_DIR}/summary.txt"

if ! "${DRY_RUN}"; then
  mkdir -p "${OUTPUT_DIR}"
  {
    echo "aws-tf-reverse summary"
    echo "Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "Accounts:  ${ACCOUNTS}"
    echo "Regions:   ${REGIONS}"
    echo "Services:  ${SERVICES}"
    echo "---"
  } > "${SUMMARY_FILE}"
fi

for account in "${ACCOUNT_LIST[@]}"; do
  account="${account// /}"
  [[ -z "${account}" ]] && continue
  log "Account: ${account}"

  if [[ -n "${ROLE_NAME}" ]]; then
    assume_role "${account}" "${ROLE_NAME}"
  fi

  for region in "${REGION_LIST[@]}"; do
    region="${region// /}"
    [[ -z "${region}" ]] && continue
    log " Region: ${region}"

    base_path="${OUTPUT_DIR}/${account}"

    for service in "${SERVICE_LIST[@]}"; do
      service="${service// /}"
      [[ -z "${service}" ]] && continue
      dispatch_service "${service}" "${account}" "${region}" "${base_path}"
    done
  done

  if [[ -n "${ROLE_NAME}" ]]; then
    restore_credentials
  fi
done

if ! "${DRY_RUN}"; then
  # Count total import blocks across all generated files
  TOTAL_IMPORTS=$(grep -r '^import {' "${OUTPUT_DIR}" 2>/dev/null | wc -l | tr -d ' ')
  echo "Total import blocks written: ${TOTAL_IMPORTS}" >> "${SUMMARY_FILE}"
  log "Done. Total import blocks: ${TOTAL_IMPORTS}"
  log "Output: ${OUTPUT_DIR}"
  log "Summary: ${SUMMARY_FILE}"
  log ""
  log "Next steps:"
  log "  1. For each service directory, run: terraform init"
  log "  2. Then: terraform plan -generate-config-out=generated.tf"
  log "  3. Review generated.tf; remove computed/read-only attributes"
  log "  4. Run reconcile.sh to check coverage"
else
  log "Dry run complete — no files written."
fi
