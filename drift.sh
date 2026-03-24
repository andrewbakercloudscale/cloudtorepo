#!/usr/bin/env bash
# drift.sh — Detect drift between live AWS resources and a terraclaim output directory.
#
# Re-scans AWS using the same discovery logic as terraclaim.sh and compares the
# results against the import blocks already written in your tf-output directory.
# Reports NEW resources (exist in AWS, missing from imports.tf) and REMOVED
# resources (in imports.tf but no longer present in AWS).
#
# With --apply, drift.sh updates imports.tf and resources.tf in place:
#   - Appends new import {} blocks for discovered resources
#   - Comments out stale blocks for resources that no longer exist
#
# Requirements: aws-cli >= 2, jq >= 1.6, Bash 4+
#
# Usage:
#   ./drift.sh [OPTIONS]
#
# Options:
#   --output    "./tf-output"           Output directory from terraclaim.sh
#   --accounts  "id1,id2"              Comma-separated account IDs (default: current)
#   --regions   "r1,r2"                Comma-separated regions (default: us-east-1)
#   --services  "svc1,svc2"            Comma-separated services (default: all)
#   --role      "RoleName"             IAM role to assume in each account
#   --apply                            Update imports.tf in place (add new, mark removed)
#   --report    "./drift-report.txt"   Write report to file in addition to stdout
#   --parallel  5                      Max concurrent service scans (default: 5, set to 1 to disable)
#   --exclude-services "svc1,svc2"     Comma-separated services to skip
#   --debug                            Verbose logging
#   --help                             Show this help

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
OUTPUT_DIR="./tf-output"
ACCOUNTS=""
REGIONS="us-east-1"
SERVICES="ec2,ebs,ecs,eks,lambda,vpc,elb,cloudfront,route53,acm,rds,dynamodb,elasticache,msk,s3,sqs,sns,apigateway,iam,kms,secretsmanager,ssm,cloudwatch,eventbridge,ecr,stepfunctions,wafv2,transitgateway,vpcendpoints,config,efs,opensearch,kinesis,cognito,cloudtrail,guardduty,backup,redshift,glue,ses,codepipeline,codebuild,documentdb,fsx,transfer,elasticbeanstalk,apprunner,memorydb,athena,lakeformation,servicecatalog,lightsail"
EXCLUDE_SERVICES=""
TAGS=""
ROLE_NAME=""
APPLY=false
REPORT_FILE=""
PARALLEL=5
DEBUG=false

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { echo "[INFO]  $*" >&2; }
debug(){ [[ "${DEBUG}" == "true" ]] && echo "[DEBUG] $*" >&2 || true; }
err()  { echo "[ERROR] $*" >&2; }
die()  { err "$*"; exit 1; }

slugify() {
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
    --output)   OUTPUT_DIR="$2";  shift 2 ;;
    --accounts) ACCOUNTS="$2";    shift 2 ;;
    --regions)  REGIONS="$2";     shift 2 ;;
    --services) SERVICES="$2";    shift 2 ;;
    --role)     ROLE_NAME="$2";   shift 2 ;;
    --apply)            APPLY=true;             shift ;;
    --report)           REPORT_FILE="$2";       shift 2 ;;
    --parallel)         PARALLEL="$2";          shift 2 ;;
    --exclude-services) EXCLUDE_SERVICES="$2";  shift 2 ;;
    --tags)             TAGS="$2";              shift 2 ;;
    --debug)            DEBUG=true;             shift ;;
    --help|-h)          usage ;;
    *) die "Unknown option: $1 — run with --help for usage." ;;
  esac
done

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------
[[ "${PARALLEL}" =~ ^[1-9][0-9]*$ ]] || die "--parallel must be a positive integer (got: '${PARALLEL}')"

# ---------------------------------------------------------------------------
# Dependency checks
# ---------------------------------------------------------------------------
for cmd in aws jq; do
  command -v "$cmd" &>/dev/null || die "Required command not found: $cmd"
done

[[ -d "${OUTPUT_DIR}" ]] || die "Output directory not found: ${OUTPUT_DIR}. Run terraclaim.sh first."

IFS=',' read -ra ACCOUNT_LIST <<< "${ACCOUNTS}"
IFS=',' read -ra REGION_LIST  <<< "${REGIONS}"
IFS=',' read -ra SERVICE_LIST <<< "${SERVICES}"

# Apply --exclude-services filter
if [[ -n "${EXCLUDE_SERVICES}" ]]; then
  IFS=',' read -ra _EXCL <<< "${EXCLUDE_SERVICES}"
  _FILTERED=()
  for _svc in "${SERVICE_LIST[@]}"; do
    _svc="${_svc// /}"
    _skip=false
    for _ex in "${_EXCL[@]}"; do
      [[ "${_svc}" == "${_ex// /}" ]] && { _skip=true; break; }
    done
    "${_skip}" || _FILTERED+=("${_svc}")
  done
  SERVICE_LIST=("${_FILTERED[@]}")
  debug "Service list after exclusions: ${SERVICE_LIST[*]}"
fi

# ---------------------------------------------------------------------------
# AWS CLI wrapper — retries on throttling with exponential back-off + jitter
# ---------------------------------------------------------------------------
aws() {
  local attempt=1 delay=1 max=5 out ec
  while true; do
    out=$(command aws "$@" 2>&1); ec=$?
    if [[ $ec -eq 0 ]]; then
      printf '%s' "${out}"
      return 0
    fi
    if [[ $attempt -lt $max ]] && \
       echo "${out}" | grep -qiE 'ThrottlingException|RequestLimitExceeded|Rate exceeded|Throttling|SlowDown|TooManyRequestsException'; then
      local jitter; jitter=$(awk "BEGIN{srand(${RANDOM}); printf \"%.2f\", rand()}")
      local sleep_time; sleep_time=$(awk "BEGIN{printf \"%.2f\", ${delay} + ${jitter}}")
      debug "  [backoff] throttled — attempt ${attempt}/${max}, retrying in ${sleep_time}s"
      sleep "${sleep_time}"
      delay=$(( delay * 2 ))
      attempt=$(( attempt + 1 ))
    else
      # Surface auth/credential errors via a temp file so they are never
      # silently swallowed by 2>/dev/null at call sites
      if echo "${out}" | grep -qiE 'AccessDeniedException|UnauthorizedOperation|AuthFailure|ExpiredTokenException|InvalidClientTokenId|NoCredentialProviders|AccessDenied'; then
        echo "[WARN] AWS auth/permission error — aws ${*:1:2}: ${out}" >> "${_AWS_WARN_FILE:-/dev/stderr}"
      fi
      printf '%s\n' "${out}" >&2
      return $ec
    fi
  done
}

# Print any queued auth warnings and clear the file
flush_aws_warnings() {
  [[ -z "${_AWS_WARN_FILE:-}" || ! -s "${_AWS_WARN_FILE}" ]] && return
  while IFS= read -r _warn_line; do
    err "${_warn_line}"
  done < "${_AWS_WARN_FILE}"
  > "${_AWS_WARN_FILE}"
}

# ---------------------------------------------------------------------------
# Tag filter
# ---------------------------------------------------------------------------
declare -A TAG_IDS=()

load_tag_filter() {
  local region="$1"
  [[ -z "${TAGS}" ]] && return
  TAG_IDS=()
  local filter_args=()
  IFS=',' read -ra _pairs <<< "${TAGS}"
  for _pair in "${_pairs[@]}"; do
    local _key="${_pair%%=*}"
    local _val="${_pair#*=}"
    filter_args+=("Key=${_key// /},Values=${_val// /}")
  done
  log "  [tags] loading tag filter for region ${region}..."
  local _arn
  while IFS= read -r _arn; do
    [[ -z "${_arn}" ]] && continue
    TAG_IDS["${_arn}"]="1"
    local _id="${_arn##*/}"; [[ "${_id}" == "${_arn}" ]] && _id="${_arn##*:}"
    TAG_IDS["${_id}"]="1"
  done < <(aws resourcegroupstaggingapi get-resources \
    --region "${region}" \
    --tag-filters "${filter_args[@]}" \
    --query 'ResourceTagMappingList[].ResourceARN' \
    --output text 2>/dev/null || true)
  debug "  [tags] ${#TAG_IDS[@]} tagged resource IDs loaded for ${region}"
  if [[ ${#TAG_IDS[@]} -eq 0 ]]; then
    err "[WARN] --tags filter returned 0 matching resources in ${region}. Verify:"
    err "  - IAM permission resourcegroupstaggingapi:GetResources is granted"
    err "  - Tags are specified exactly as they appear in AWS: ${TAGS}"
  fi
}

tag_match() {
  [[ -z "${TAGS}" ]] && return 0
  [[ -n "${TAG_IDS[$1]+_}" ]] && return 0
  return 1
}

# ---------------------------------------------------------------------------
# Cross-account role assumption
# ---------------------------------------------------------------------------
assume_role() {
  local account_id="$1" role="$2"
  local arn="arn:aws:iam::${account_id}:role/${role}"
  debug "Assuming role: ${arn}"
  local creds
  creds=$(aws sts assume-role \
    --role-arn "${arn}" \
    --role-session-name "terraclaim-drift-$$" \
    --query 'Credentials' \
    --output json) || die "Failed to assume role ${arn}"
  export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
  AWS_ACCESS_KEY_ID=$(echo "${creds}"     | jq -r '.AccessKeyId')
  AWS_SECRET_ACCESS_KEY=$(echo "${creds}" | jq -r '.SecretAccessKey')
  AWS_SESSION_TOKEN=$(echo "${creds}"     | jq -r '.SessionToken')
  [[ "${AWS_ACCESS_KEY_ID}" == "null" || -z "${AWS_ACCESS_KEY_ID}" ]] && \
    die "assume_role: invalid credentials returned for ${arn} — verify the role exists and its trust policy allows this principal"
}

restore_credentials() {
  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
}

# ---------------------------------------------------------------------------
# Parse known import IDs from an existing imports.tf
# Populates associative array: KNOWN_IDS[id]=address
# ---------------------------------------------------------------------------
parse_known_ids() {
  local imports_file="$1"
  unset KNOWN_IDS; declare -gA KNOWN_IDS
  unset KNOWN_ADDRS; declare -gA KNOWN_ADDRS

  [[ -f "${imports_file}" ]] || return

  local current_addr=""
  while IFS= read -r line; do
    if [[ "${line}" =~ ^[[:space:]]*to[[:space:]]*=[[:space:]]*(.+)[[:space:]]*$ ]]; then
      current_addr="${BASH_REMATCH[1]// /}"
    fi
    if [[ "${line}" =~ ^[[:space:]]*id[[:space:]]*=[[:space:]]*\"(.+)\"[[:space:]]*$ ]]; then
      local id="${BASH_REMATCH[1]}"
      KNOWN_IDS["${id}"]="${current_addr}"
      KNOWN_ADDRS["${current_addr}"]="${id}"
      current_addr=""
    fi
  done < "${imports_file}"
  debug "    parsed ${#KNOWN_IDS[@]} known IDs from ${imports_file}"
}

# ---------------------------------------------------------------------------
# Apply changes: append new import blocks, comment out stale ones
# ---------------------------------------------------------------------------
apply_new_imports() {
  local imports_file="$1" resources_file="$2"
  shift 2
  local new_pairs=("$@")  # alternating addr id

  [[ ${#new_pairs[@]} -eq 0 ]] && return

  {
    echo ""
    echo "# --- drift.sh additions: $(date -u '+%Y-%m-%dT%H:%M:%SZ') ---"
    local i=0
    while [[ $i -lt ${#new_pairs[@]} ]]; do
      local addr="${new_pairs[$i]}"
      local id="${new_pairs[$((i+1))]}"
      printf 'import {\n  to = %s\n  id = "%s"\n}\n\n' "${addr}" "${id}"
      i=$((i+2))
    done
  } >> "${imports_file}"

  {
    echo ""
    echo "# --- drift.sh additions ---"
    local i=0
    while [[ $i -lt ${#new_pairs[@]} ]]; do
      local addr="${new_pairs[$i]}"
      printf 'resource "%s" "%s" {}\n\n' \
        "$(echo "${addr}" | cut -d. -f1)" \
        "$(echo "${addr}" | cut -d. -f2)"
      i=$((i+2))
    done
  } >> "${resources_file}"

  debug "    appended $((${#new_pairs[@]}/2)) new import blocks to ${imports_file}"
}

apply_remove_stale() {
  local imports_file="$1"
  shift
  local stale_addrs=("$@")

  [[ ${#stale_addrs[@]} -eq 0 ]] && return
  [[ ! -f "${imports_file}" ]] && return

  local tmp; tmp=$(mktemp) || { err "Failed to create temp file for ${imports_file} — skipping"; return 1; }
  local in_block=false
  local skip_block=false
  local block_lines=()
  local block_addr=""

  while IFS= read -r line; do
    if [[ "${line}" =~ ^import[[:space:]]*\{ ]]; then
      in_block=true
      skip_block=false
      block_lines=("${line}")
      block_addr=""
      continue
    fi

    if "${in_block}"; then
      block_lines+=("${line}")

      if [[ "${line}" =~ ^[[:space:]]*to[[:space:]]*=[[:space:]]*(.+)[[:space:]]*$ ]]; then
        block_addr="${BASH_REMATCH[1]// /}"
        for stale in "${stale_addrs[@]}"; do
          if [[ "${block_addr}" == "${stale}" ]]; then
            skip_block=true
            break
          fi
        done
      fi

      if [[ "${line}" =~ ^\} ]]; then
        in_block=false
        if "${skip_block}"; then
          # Write as a commented-out block with a drift note
          echo "# [drift.sh] resource no longer found in AWS — $(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "${tmp}"
          for bl in "${block_lines[@]}"; do
            echo "# ${bl}" >> "${tmp}"
          done
          echo "" >> "${tmp}"
        else
          for bl in "${block_lines[@]}"; do
            echo "${bl}" >> "${tmp}"
          done
        fi
        block_lines=()
        block_addr=""
        skip_block=false
        continue
      fi
      continue
    fi

    echo "${line}" >> "${tmp}"
  done < "${imports_file}"

  mv "${tmp}" "${imports_file}" || { err "Failed to update ${imports_file} — original preserved at ${tmp}"; return 1; }
  debug "    commented out ${#stale_addrs[@]} stale blocks in ${imports_file}"
}

# ---------------------------------------------------------------------------
# Report output (stdout + optional file)
# ---------------------------------------------------------------------------
REPORT_LINES=()
report() {
  echo "$*"
  REPORT_LINES+=("$*")
}

flush_report() {
  [[ -z "${REPORT_FILE}" ]] && return
  printf '%s\n' "${REPORT_LINES[@]}" > "${REPORT_FILE}"
  log "Report written to ${REPORT_FILE}"
}

# ---------------------------------------------------------------------------
# Per-service live scanners
# Each populates LIVE_PAIRS array: alternating addr id (same format as terraclaim.sh)
# ---------------------------------------------------------------------------

scan_ec2() {
  local region="$1"; LIVE_PAIRS=()
  while IFS=$'\t' read -r instance_id name_tag; do
    [[ -z "${instance_id}" ]] && continue
    local slug; slug=$(slugify "${name_tag:-${instance_id}}")
    LIVE_PAIRS+=("aws_instance.${slug}" "${instance_id}")
  done < <(aws ec2 describe-instances \
    --region "${region}" \
    --filters "Name=instance-state-name,Values=running,stopped" \
    --query 'Reservations[].Instances[].[InstanceId, Tags[?Key==`Name`].Value|[0]]' \
    --output text 2>/dev/null || true)
}

scan_ebs() {
  local region="$1"; LIVE_PAIRS=()
  while IFS=$'\t' read -r vol_id name_tag; do
    [[ -z "${vol_id}" ]] && continue
    local slug; slug=$(slugify "${name_tag:-${vol_id}}")
    LIVE_PAIRS+=("aws_ebs_volume.${slug}" "${vol_id}")
  done < <(aws ec2 describe-volumes \
    --region "${region}" \
    --query 'Volumes[].[VolumeId, Tags[?Key==`Name`].Value|[0]]' \
    --output text 2>/dev/null || true)
}

scan_s3() {
  local region="$1"; LIVE_PAIRS=()
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
    LIVE_PAIRS+=("aws_s3_bucket.${slug}" "${bucket}")
  done < <(aws s3api list-buckets \
    --query 'Buckets[].Name' \
    --output text 2>/dev/null | tr '\t' '\n' || true)
}

scan_vpc() {
  local region="$1"; LIVE_PAIRS=()
  while IFS=$'\t' read -r vpc_id name_tag; do
    [[ -z "${vpc_id}" ]] && continue
    local slug; slug=$(slugify "${name_tag:-${vpc_id}}")
    LIVE_PAIRS+=("aws_vpc.${slug}" "${vpc_id}")
  done < <(aws ec2 describe-vpcs \
    --region "${region}" \
    --query 'Vpcs[].[VpcId, Tags[?Key==`Name`].Value|[0]]' \
    --output text 2>/dev/null || true)
}

scan_eks() {
  local region="$1"; LIVE_PAIRS=()
  local clusters
  clusters=$(aws eks list-clusters \
    --region "${region}" \
    --query 'clusters[]' \
    --output text 2>/dev/null || true)
  for cluster in ${clusters}; do
    local slug; slug=$(slugify "${cluster}")
    LIVE_PAIRS+=("aws_eks_cluster.cluster_${slug}" "${cluster}")
    while read -r ng; do
      [[ -z "${ng}" ]] && continue
      local ng_slug; ng_slug=$(slugify "${ng}")
      LIVE_PAIRS+=("aws_eks_node_group.ng_${slug}_${ng_slug}" "${cluster}:${ng}")
    done < <(aws eks list-nodegroups \
      --cluster-name "${cluster}" \
      --region "${region}" \
      --query 'nodegroups[]' \
      --output text 2>/dev/null | tr '\t' '\n' || true)
    while read -r addon; do
      [[ -z "${addon}" ]] && continue
      local addon_slug; addon_slug=$(slugify "${addon}")
      LIVE_PAIRS+=("aws_eks_addon.addon_${slug}_${addon_slug}" "${cluster}:${addon}")
    done < <(aws eks list-addons \
      --cluster-name "${cluster}" \
      --region "${region}" \
      --query 'addons[]' \
      --output text 2>/dev/null | tr '\t' '\n' || true)
  done
}

scan_ecs() {
  local region="$1"; LIVE_PAIRS=()
  while read -r cluster_arn; do
    [[ -z "${cluster_arn}" ]] && continue
    local cluster_name; cluster_name=$(basename "${cluster_arn}")
    local slug; slug=$(slugify "${cluster_name}")
    LIVE_PAIRS+=("aws_ecs_cluster.${slug}" "${cluster_name}")
    while read -r svc_arn; do
      [[ -z "${svc_arn}" ]] && continue
      local svc_name; svc_name=$(basename "${svc_arn}")
      local svc_slug; svc_slug=$(slugify "${svc_name}")
      LIVE_PAIRS+=("aws_ecs_service.${svc_slug}" "${cluster_name}/${svc_name}")
    done < <(aws ecs list-services \
      --cluster "${cluster_name}" \
      --region "${region}" \
      --query 'serviceArns[]' \
      --output text 2>/dev/null | tr '\t' '\n' || true)
  done < <(aws ecs list-clusters \
    --region "${region}" \
    --query 'clusterArns[]' \
    --output text 2>/dev/null | tr '\t' '\n' || true)
}

scan_lambda() {
  local region="$1"; LIVE_PAIRS=()
  while read -r fn_name; do
    [[ -z "${fn_name}" ]] && continue
    local slug; slug=$(slugify "${fn_name}")
    LIVE_PAIRS+=("aws_lambda_function.${slug}" "${fn_name}")
  done < <(aws lambda list-functions \
    --region "${region}" \
    --query 'Functions[].FunctionName' \
    --output text 2>/dev/null | tr '\t' '\n' || true)
}

scan_rds() {
  local region="$1"; LIVE_PAIRS=()
  while read -r db_id; do
    [[ -z "${db_id}" ]] && continue
    local slug; slug=$(slugify "${db_id}")
    LIVE_PAIRS+=("aws_db_instance.${slug}" "${db_id}")
  done < <(aws rds describe-db-instances \
    --region "${region}" \
    --query 'DBInstances[].DBInstanceIdentifier' \
    --output text 2>/dev/null | tr '\t' '\n' || true)
  while read -r cluster_id; do
    [[ -z "${cluster_id}" ]] && continue
    local slug; slug=$(slugify "${cluster_id}")
    LIVE_PAIRS+=("aws_rds_cluster.${slug}" "${cluster_id}")
  done < <(aws rds describe-db-clusters \
    --region "${region}" \
    --query 'DBClusters[].DBClusterIdentifier' \
    --output text 2>/dev/null | tr '\t' '\n' || true)
}

scan_dynamodb() {
  local region="$1"; LIVE_PAIRS=()
  while read -r table; do
    [[ -z "${table}" ]] && continue
    local slug; slug=$(slugify "${table}")
    LIVE_PAIRS+=("aws_dynamodb_table.${slug}" "${table}")
  done < <(aws dynamodb list-tables \
    --region "${region}" \
    --query 'TableNames[]' \
    --output text 2>/dev/null | tr '\t' '\n' || true)
}

scan_elasticache() {
  local region="$1"; LIVE_PAIRS=()
  while read -r rg_id; do
    [[ -z "${rg_id}" ]] && continue
    local slug; slug=$(slugify "${rg_id}")
    LIVE_PAIRS+=("aws_elasticache_replication_group.${slug}" "${rg_id}")
  done < <(aws elasticache describe-replication-groups \
    --region "${region}" \
    --query 'ReplicationGroups[].ReplicationGroupId' \
    --output text 2>/dev/null | tr '\t' '\n' || true)
}

scan_msk() {
  local region="$1"; LIVE_PAIRS=()
  while IFS=$'\t' read -r cluster_arn cluster_name; do
    [[ -z "${cluster_arn}" ]] && continue
    local slug; slug=$(slugify "${cluster_name}")
    LIVE_PAIRS+=("aws_msk_cluster.${slug}" "${cluster_arn}")
  done < <(aws kafka list-clusters \
    --region "${region}" \
    --query 'ClusterInfoList[].[ClusterArn, ClusterName]' \
    --output text 2>/dev/null || true)
}

scan_sqs() {
  local region="$1"; LIVE_PAIRS=()
  while read -r url; do
    [[ -z "${url}" ]] && continue
    local qname; qname=$(basename "${url}")
    local slug; slug=$(slugify "${qname}")
    LIVE_PAIRS+=("aws_sqs_queue.${slug}" "${url}")
  done < <(aws sqs list-queues \
    --region "${region}" \
    --query 'QueueUrls[]' \
    --output text 2>/dev/null | tr '\t' '\n' || true)
}

scan_sns() {
  local region="$1"; LIVE_PAIRS=()
  while read -r arn; do
    [[ -z "${arn}" ]] && continue
    local tname; tname=$(basename "${arn}")
    local slug; slug=$(slugify "${tname}")
    LIVE_PAIRS+=("aws_sns_topic.${slug}" "${arn}")
  done < <(aws sns list-topics \
    --region "${region}" \
    --query 'Topics[].TopicArn' \
    --output text 2>/dev/null | tr '\t' '\n' || true)
}

scan_elb() {
  local region="$1"; LIVE_PAIRS=()
  while IFS=$'\t' read -r lb_arn lb_name; do
    [[ -z "${lb_arn}" ]] && continue
    local slug; slug=$(slugify "${lb_name}")
    LIVE_PAIRS+=("aws_lb.${slug}" "${lb_arn}")
  done < <(aws elbv2 describe-load-balancers \
    --region "${region}" \
    --query 'LoadBalancers[].[LoadBalancerArn, LoadBalancerName]' \
    --output text 2>/dev/null || true)
}

scan_cloudfront() {
  local region="$1"; LIVE_PAIRS=()
  [[ "${region}" != "us-east-1" ]] && return
  while IFS=$'\t' read -r dist_id _comment; do
    [[ -z "${dist_id}" ]] && continue
    local slug; slug=$(slugify "${dist_id}")
    LIVE_PAIRS+=("aws_cloudfront_distribution.${slug}" "${dist_id}")
  done < <(aws cloudfront list-distributions \
    --query 'DistributionList.Items[].[Id, Comment]' \
    --output text 2>/dev/null || true)
}

scan_route53() {
  local region="$1"; LIVE_PAIRS=()
  [[ "${region}" != "us-east-1" ]] && return
  while IFS=$'\t' read -r zone_id zone_name; do
    [[ -z "${zone_id}" ]] && continue
    zone_id="${zone_id##*/hostedzone/}"
    local slug; slug=$(slugify "${zone_name%.}")
    LIVE_PAIRS+=("aws_route53_zone.${slug}" "${zone_id}")
  done < <(aws route53 list-hosted-zones \
    --query 'HostedZones[].[Id, Name]' \
    --output text 2>/dev/null || true)
}

scan_acm() {
  local region="$1"; LIVE_PAIRS=()
  while read -r cert_arn; do
    [[ -z "${cert_arn}" ]] && continue
    local slug; slug=$(slugify "$(echo "${cert_arn}" | awk -F/ '{print $NF}')")
    LIVE_PAIRS+=("aws_acm_certificate.${slug}" "${cert_arn}")
  done < <(aws acm list-certificates \
    --region "${region}" \
    --query 'CertificateSummaryList[].CertificateArn' \
    --output text 2>/dev/null | tr '\t' '\n' || true)
}

scan_iam() {
  local region="$1"; LIVE_PAIRS=()
  [[ "${region}" != "us-east-1" ]] && return
  while read -r role_name; do
    [[ -z "${role_name}" ]] && continue
    local slug; slug=$(slugify "${role_name}")
    LIVE_PAIRS+=("aws_iam_role.${slug}" "${role_name}")
  done < <(aws iam list-roles \
    --query 'Roles[].RoleName' \
    --output text 2>/dev/null | tr '\t' '\n' || true)
}

scan_kms() {
  local region="$1"; LIVE_PAIRS=()
  while IFS=$'\t' read -r key_id _key_arn; do
    [[ -z "${key_id}" ]] && continue
    local slug; slug=$(slugify "${key_id}")
    LIVE_PAIRS+=("aws_kms_key.${slug}" "${key_id}")
  done < <(aws kms list-keys \
    --region "${region}" \
    --query 'Keys[].[KeyId, KeyArn]' \
    --output text 2>/dev/null || true)
}

scan_secretsmanager() {
  local region="$1"; LIVE_PAIRS=()
  while IFS=$'\t' read -r secret_arn secret_name; do
    [[ -z "${secret_arn}" ]] && continue
    local slug; slug=$(slugify "${secret_name}")
    LIVE_PAIRS+=("aws_secretsmanager_secret.${slug}" "${secret_arn}")
  done < <(aws secretsmanager list-secrets \
    --region "${region}" \
    --query 'SecretList[].[ARN, Name]' \
    --output text 2>/dev/null || true)
}

scan_ssm() {
  local region="$1"; LIVE_PAIRS=()
  while read -r param_name; do
    [[ -z "${param_name}" ]] && continue
    local slug; slug=$(slugify "${param_name}")
    LIVE_PAIRS+=("aws_ssm_parameter.${slug}" "${param_name}")
  done < <(aws ssm describe-parameters \
    --region "${region}" \
    --query 'Parameters[].Name' \
    --output text 2>/dev/null | tr '\t' '\n' || true)
}

scan_apigateway() {
  local region="$1"; LIVE_PAIRS=()
  while IFS=$'\t' read -r api_id api_name; do
    [[ -z "${api_id}" ]] && continue
    local slug; slug=$(slugify "${api_name:-${api_id}}")
    LIVE_PAIRS+=("aws_api_gateway_rest_api.${slug}" "${api_id}")
  done < <(aws apigateway get-rest-apis \
    --region "${region}" \
    --query 'items[].[id, name]' \
    --output text 2>/dev/null || true)
  while IFS=$'\t' read -r api_id api_name; do
    [[ -z "${api_id}" ]] && continue
    local slug; slug=$(slugify "${api_name:-${api_id}}")
    LIVE_PAIRS+=("aws_apigatewayv2_api.${slug}" "${api_id}")
  done < <(aws apigatewayv2 get-apis \
    --region "${region}" \
    --query 'Items[].[ApiId, Name]' \
    --output text 2>/dev/null || true)
}

scan_cloudwatch() {
  local region="$1"; LIVE_PAIRS=()
  while read -r lg_name; do
    [[ -z "${lg_name}" ]] && continue
    local slug; slug=$(slugify "${lg_name}")
    LIVE_PAIRS+=("aws_cloudwatch_log_group.${slug}" "${lg_name}")
  done < <(aws logs describe-log-groups \
    --region "${region}" \
    --query 'logGroups[].logGroupName' \
    --output text 2>/dev/null | tr '\t' '\n' || true)
}

scan_eventbridge() {
  local region="$1"; LIVE_PAIRS=()
  local all_buses=("default")
  while read -r bus_name; do
    [[ -z "${bus_name}" ]] && continue
    [[ "${bus_name}" == "default" ]] && continue
    local slug; slug=$(slugify "${bus_name}")
    LIVE_PAIRS+=("aws_cloudwatch_event_bus.${slug}" "${bus_name}")
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
      LIVE_PAIRS+=("aws_cloudwatch_event_rule.${slug}" "${import_id}")
    done < <(aws events list-rules \
      --event-bus-name "${bus}" \
      --region "${region}" \
      --query 'Rules[].Name' \
      --output text 2>/dev/null | tr '\t' '\n' || true)
  done
}

scan_ecr() {
  local region="$1"; LIVE_PAIRS=()
  local repo_names=()
  while read -r repo_name; do
    [[ -z "${repo_name}" ]] && continue
    local slug; slug=$(slugify "${repo_name}")
    LIVE_PAIRS+=("aws_ecr_repository.${slug}" "${repo_name}")
    repo_names+=("${repo_name}")
  done < <(aws ecr describe-repositories \
    --region "${region}" \
    --query 'repositories[].repositoryName' \
    --output text 2>/dev/null | tr '\t' '\n' || true)
  for repo_name in "${repo_names[@]}"; do
    local slug; slug=$(slugify "${repo_name}")
    local has_policy
    has_policy=$(aws ecr get-lifecycle-policy \
      --repository-name "${repo_name}" \
      --region "${region}" \
      --query 'repositoryName' \
      --output text 2>/dev/null || true)
    [[ -n "${has_policy}" ]] && LIVE_PAIRS+=("aws_ecr_lifecycle_policy.${slug}" "${repo_name}")
  done
}

scan_stepfunctions() {
  local region="$1"; LIVE_PAIRS=()
  while IFS=$'\t' read -r sm_arn sm_name; do
    [[ -z "${sm_arn}" ]] && continue
    local slug; slug=$(slugify "${sm_name}")
    LIVE_PAIRS+=("aws_sfn_state_machine.${slug}" "${sm_arn}")
  done < <(aws stepfunctions list-state-machines \
    --region "${region}" \
    --query 'stateMachines[].[stateMachineArn, name]' \
    --output text 2>/dev/null || true)
}

scan_wafv2() {
  local region="$1"; LIVE_PAIRS=()
  for scope in REGIONAL CLOUDFRONT; do
    [[ "${scope}" == "CLOUDFRONT" ]] && [[ "${region}" != "us-east-1" ]] && continue
    while IFS=$'\t' read -r acl_id acl_name; do
      [[ -z "${acl_id}" ]] && continue
      local slug; slug=$(slugify "${scope}_${acl_name}")
      LIVE_PAIRS+=("aws_wafv2_web_acl.${slug}" "${acl_name}/${acl_id}/${scope}")
    done < <(aws wafv2 list-web-acls \
      --scope "${scope}" --region "${region}" \
      --query 'WebACLs[].[Id, Name]' --output text 2>/dev/null || true)
    while IFS=$'\t' read -r ip_id ip_name; do
      [[ -z "${ip_id}" ]] && continue
      local slug; slug=$(slugify "${scope}_${ip_name}")
      LIVE_PAIRS+=("aws_wafv2_ip_set.${slug}" "${ip_name}/${ip_id}/${scope}")
    done < <(aws wafv2 list-ip-sets \
      --scope "${scope}" --region "${region}" \
      --query 'IPSets[].[Id, Name]' --output text 2>/dev/null || true)
    while IFS=$'\t' read -r rg_id rg_name; do
      [[ -z "${rg_id}" ]] && continue
      local slug; slug=$(slugify "${scope}_${rg_name}")
      LIVE_PAIRS+=("aws_wafv2_rule_group.${slug}" "${rg_name}/${rg_id}/${scope}")
    done < <(aws wafv2 list-rule-groups \
      --scope "${scope}" --region "${region}" \
      --query 'RuleGroups[].[Id, Name]' --output text 2>/dev/null || true)
  done
}

scan_transitgateway() {
  local region="$1"; LIVE_PAIRS=()
  while IFS=$'\t' read -r tgw_id name_tag; do
    [[ -z "${tgw_id}" ]] && continue
    local slug; slug=$(slugify "${name_tag:-${tgw_id}}")
    LIVE_PAIRS+=("aws_ec2_transit_gateway.${slug}" "${tgw_id}")
    while IFS=$'\t' read -r att_id att_name; do
      [[ -z "${att_id}" ]] && continue
      local att_slug; att_slug=$(slugify "${att_name:-${att_id}}")
      LIVE_PAIRS+=("aws_ec2_transit_gateway_vpc_attachment.${att_slug}" "${att_id}")
    done < <(aws ec2 describe-transit-gateway-vpc-attachments \
      --region "${region}" \
      --filters "Name=transit-gateway-id,Values=${tgw_id}" "Name=state,Values=available" \
      --query 'TransitGatewayVpcAttachments[].[TransitGatewayAttachmentId, Tags[?Key==`Name`].Value|[0]]' \
      --output text 2>/dev/null || true)
    while IFS=$'\t' read -r rt_id rt_name; do
      [[ -z "${rt_id}" ]] && continue
      local rt_slug; rt_slug=$(slugify "${rt_name:-${rt_id}}")
      LIVE_PAIRS+=("aws_ec2_transit_gateway_route_table.${rt_slug}" "${rt_id}")
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
}

scan_vpcendpoints() {
  local region="$1"; LIVE_PAIRS=()
  while IFS=$'\t' read -r ep_id service_name; do
    [[ -z "${ep_id}" ]] && continue
    local short; short=$(echo "${service_name}" | awk -F. '{print $NF}')
    local slug; slug=$(slugify "${ep_id}_${short}")
    LIVE_PAIRS+=("aws_vpc_endpoint.${slug}" "${ep_id}")
  done < <(aws ec2 describe-vpc-endpoints \
    --region "${region}" \
    --filters "Name=vpc-endpoint-state,Values=available,pending" \
    --query 'VpcEndpoints[].[VpcEndpointId, ServiceName]' \
    --output text 2>/dev/null || true)
}

scan_config() {
  local region="$1"; LIVE_PAIRS=()
  while read -r recorder_name; do
    [[ -z "${recorder_name}" ]] && continue
    local slug; slug=$(slugify "${recorder_name}")
    LIVE_PAIRS+=("aws_config_configuration_recorder.${slug}" "${recorder_name}")
    LIVE_PAIRS+=("aws_config_configuration_recorder_status.${slug}" "${recorder_name}")
  done < <(aws configservice describe-configuration-recorders \
    --region "${region}" \
    --query 'ConfigurationRecorders[].name' \
    --output text 2>/dev/null | tr '\t' '\n' || true)
  while read -r channel_name; do
    [[ -z "${channel_name}" ]] && continue
    local slug; slug=$(slugify "${channel_name}")
    LIVE_PAIRS+=("aws_config_delivery_channel.${slug}" "${channel_name}")
  done < <(aws configservice describe-delivery-channels \
    --region "${region}" \
    --query 'DeliveryChannels[].name' \
    --output text 2>/dev/null | tr '\t' '\n' || true)
  while read -r rule_name; do
    [[ -z "${rule_name}" ]] && continue
    local slug; slug=$(slugify "${rule_name}")
    LIVE_PAIRS+=("aws_config_config_rule.${slug}" "${rule_name}")
  done < <(aws configservice describe-config-rules \
    --region "${region}" \
    --query 'ConfigRules[].ConfigRuleName' \
    --output text 2>/dev/null | tr '\t' '\n' || true)
  while read -r pack_name; do
    [[ -z "${pack_name}" ]] && continue
    local slug; slug=$(slugify "${pack_name}")
    LIVE_PAIRS+=("aws_config_conformance_pack.${slug}" "${pack_name}")
  done < <(aws configservice describe-conformance-packs \
    --region "${region}" \
    --query 'ConformancePackDetails[].ConformancePackName' \
    --output text 2>/dev/null | tr '\t' '\n' || true)
}

scan_efs() {
  local region="$1"; LIVE_PAIRS=()
  while IFS=$'\t' read -r fs_id name_tag; do
    [[ -z "${fs_id}" ]] && continue
    local slug; slug=$(slugify "${name_tag:-${fs_id}}")
    LIVE_PAIRS+=("aws_efs_file_system.${slug}" "${fs_id}")
    while read -r mt_id; do
      [[ -z "${mt_id}" ]] && continue
      local mt_slug; mt_slug=$(slugify "${mt_id}")
      LIVE_PAIRS+=("aws_efs_mount_target.${mt_slug}" "${mt_id}")
    done < <(aws efs describe-mount-targets \
      --file-system-id "${fs_id}" --region "${region}" \
      --query 'MountTargets[].MountTargetId' \
      --output text 2>/dev/null | tr '\t' '\n' || true)
    while IFS=$'\t' read -r ap_id ap_name; do
      [[ -z "${ap_id}" ]] && continue
      local ap_slug; ap_slug=$(slugify "${ap_name:-${ap_id}}")
      LIVE_PAIRS+=("aws_efs_access_point.${ap_slug}" "${ap_id}")
    done < <(aws efs describe-access-points \
      --file-system-id "${fs_id}" --region "${region}" \
      --query 'AccessPoints[].[AccessPointId, Tags[?Key==`Name`].Value|[0]]' \
      --output text 2>/dev/null || true)
  done < <(aws efs describe-file-systems \
    --region "${region}" \
    --query 'FileSystems[].[FileSystemId, Tags[?Key==`Name`].Value|[0]]' \
    --output text 2>/dev/null || true)
}

scan_opensearch() {
  local account="$1" region="$2"; LIVE_PAIRS=()
  while read -r domain_name; do
    [[ -z "${domain_name}" ]] && continue
    local slug; slug=$(slugify "${domain_name}")
    LIVE_PAIRS+=("aws_opensearch_domain.${slug}" "${account}/${domain_name}")
  done < <(aws opensearch list-domain-names \
    --region "${region}" \
    --query 'DomainNames[].DomainName' \
    --output text 2>/dev/null | tr '\t' '\n' || true)
}

scan_kinesis() {
  local region="$1"; LIVE_PAIRS=()
  while read -r stream_name; do
    [[ -z "${stream_name}" ]] && continue
    local slug; slug=$(slugify "${stream_name}")
    LIVE_PAIRS+=("aws_kinesis_stream.${slug}" "${stream_name}")
  done < <(aws kinesis list-streams \
    --region "${region}" \
    --query 'StreamNames[]' \
    --output text 2>/dev/null | tr '\t' '\n' || true)
  while read -r ds_name; do
    [[ -z "${ds_name}" ]] && continue
    local slug; slug=$(slugify "${ds_name}")
    LIVE_PAIRS+=("aws_kinesis_firehose_delivery_stream.${slug}" "${ds_name}")
  done < <(aws firehose list-delivery-streams \
    --region "${region}" \
    --query 'DeliveryStreamNames[]' \
    --output text 2>/dev/null | tr '\t' '\n' || true)
}

scan_cognito() {
  local region="$1"; LIVE_PAIRS=()
  while IFS=$'\t' read -r pool_id pool_name; do
    [[ -z "${pool_id}" ]] && continue
    local slug; slug=$(slugify "${pool_name:-${pool_id}}")
    LIVE_PAIRS+=("aws_cognito_user_pool.${slug}" "${pool_id}")
    while IFS=$'\t' read -r client_id client_name; do
      [[ -z "${client_id}" ]] && continue
      local csluq; csluq=$(slugify "${client_name:-${client_id}}")
      LIVE_PAIRS+=("aws_cognito_user_pool_client.${csluq}" "${pool_id}/${client_id}")
    done < <(aws cognito-idp list-user-pool-clients \
      --user-pool-id "${pool_id}" --region "${region}" \
      --query 'UserPoolClients[].[ClientId, ClientName]' \
      --output text 2>/dev/null || true)
  done < <(aws cognito-idp list-user-pools \
    --max-results 60 --region "${region}" \
    --query 'UserPools[].[Id, Name]' \
    --output text 2>/dev/null || true)
  while IFS=$'\t' read -r identity_pool_id identity_pool_name; do
    [[ -z "${identity_pool_id}" ]] && continue
    local slug; slug=$(slugify "${identity_pool_name:-${identity_pool_id}}")
    LIVE_PAIRS+=("aws_cognito_identity_pool.${slug}" "${identity_pool_id}")
  done < <(aws cognito-identity list-identity-pools \
    --max-results 60 --region "${region}" \
    --query 'IdentityPools[].[IdentityPoolId, IdentityPoolName]' \
    --output text 2>/dev/null || true)
}

scan_cloudtrail() {
  local region="$1"; LIVE_PAIRS=()
  while IFS=$'\t' read -r trail_arn trail_name home_region; do
    [[ -z "${trail_arn}" ]] && continue
    [[ "${home_region}" != "${region}" ]] && continue
    local slug; slug=$(slugify "${trail_name}")
    LIVE_PAIRS+=("aws_cloudtrail.${slug}" "${trail_name}")
  done < <(aws cloudtrail describe-trails \
    --region "${region}" \
    --include-shadow-trails false \
    --query 'trailList[].[TrailARN, Name, HomeRegion]' \
    --output text 2>/dev/null || true)
}

scan_guardduty() {
  local region="$1"; LIVE_PAIRS=()
  while read -r detector_id; do
    [[ -z "${detector_id}" ]] && continue
    local slug; slug=$(slugify "${detector_id}")
    LIVE_PAIRS+=("aws_guardduty_detector.${slug}" "${detector_id}")
    while read -r ipset_id; do
      [[ -z "${ipset_id}" ]] && continue
      local is_slug; is_slug=$(slugify "${detector_id}_${ipset_id}")
      LIVE_PAIRS+=("aws_guardduty_ipset.${is_slug}" "${detector_id}:${ipset_id}")
    done < <(aws guardduty list-ip-sets \
      --detector-id "${detector_id}" --region "${region}" \
      --query 'IpSetIds[]' --output text 2>/dev/null | tr '\t' '\n' || true)
    while read -r tis_id; do
      [[ -z "${tis_id}" ]] && continue
      local ts_slug; ts_slug=$(slugify "${detector_id}_${tis_id}")
      LIVE_PAIRS+=("aws_guardduty_threatintelset.${ts_slug}" "${detector_id}:${tis_id}")
    done < <(aws guardduty list-threat-intel-sets \
      --detector-id "${detector_id}" --region "${region}" \
      --query 'ThreatIntelSetIds[]' --output text 2>/dev/null | tr '\t' '\n' || true)
  done < <(aws guardduty list-detectors \
    --region "${region}" \
    --query 'DetectorIds[]' --output text 2>/dev/null | tr '\t' '\n' || true)
}

scan_backup() {
  local region="$1"; LIVE_PAIRS=()
  while read -r vault_name; do
    [[ -z "${vault_name}" ]] && continue
    local slug; slug=$(slugify "${vault_name}")
    LIVE_PAIRS+=("aws_backup_vault.${slug}" "${vault_name}")
  done < <(aws backup list-backup-vaults \
    --region "${region}" \
    --query 'BackupVaultList[].BackupVaultName' \
    --output text 2>/dev/null | tr '\t' '\n' || true)
  while IFS=$'\t' read -r plan_id plan_name; do
    [[ -z "${plan_id}" ]] && continue
    local slug; slug=$(slugify "${plan_name:-${plan_id}}")
    LIVE_PAIRS+=("aws_backup_plan.${slug}" "${plan_id}")
    while IFS=$'\t' read -r sel_id sel_name; do
      [[ -z "${sel_id}" ]] && continue
      local ss_slug; ss_slug=$(slugify "${plan_id}_${sel_name:-${sel_id}}")
      LIVE_PAIRS+=("aws_backup_selection.${ss_slug}" "${plan_id}|${sel_id}")
    done < <(aws backup list-backup-selections \
      --backup-plan-id "${plan_id}" --region "${region}" \
      --query 'BackupSelectionsList[].[SelectionId, SelectionName]' \
      --output text 2>/dev/null || true)
  done < <(aws backup list-backup-plans \
    --region "${region}" \
    --query 'BackupPlansList[].[BackupPlanId, BackupPlanName]' \
    --output text 2>/dev/null || true)
}

scan_redshift() {
  local region="$1"; LIVE_PAIRS=()
  while read -r cluster_id; do
    [[ -z "${cluster_id}" ]] && continue
    local slug; slug=$(slugify "${cluster_id}")
    LIVE_PAIRS+=("aws_redshift_cluster.${slug}" "${cluster_id}")
  done < <(aws redshift describe-clusters \
    --region "${region}" \
    --query 'Clusters[].ClusterIdentifier' \
    --output text 2>/dev/null | tr '\t' '\n' || true)
  while read -r ns_name; do
    [[ -z "${ns_name}" ]] && continue
    local slug; slug=$(slugify "${ns_name}")
    LIVE_PAIRS+=("aws_redshiftserverless_namespace.${slug}" "${ns_name}")
  done < <(aws redshift-serverless list-namespaces \
    --region "${region}" \
    --query 'namespaces[].namespaceName' \
    --output text 2>/dev/null | tr '\t' '\n' || true)
  while read -r wg_name; do
    [[ -z "${wg_name}" ]] && continue
    local slug; slug=$(slugify "${wg_name}")
    LIVE_PAIRS+=("aws_redshiftserverless_workgroup.${slug}" "${wg_name}")
  done < <(aws redshift-serverless list-workgroups \
    --region "${region}" \
    --query 'workgroups[].workgroupName' \
    --output text 2>/dev/null | tr '\t' '\n' || true)
}

scan_glue() {
  local account="$1" region="$2"; LIVE_PAIRS=()
  while read -r job_name; do
    [[ -z "${job_name}" ]] && continue
    local slug; slug=$(slugify "${job_name}")
    LIVE_PAIRS+=("aws_glue_job.${slug}" "${job_name}")
  done < <(aws glue list-jobs --region "${region}" \
    --query 'JobNames[]' --output text 2>/dev/null | tr '\t' '\n' || true)
  while read -r crawler_name; do
    [[ -z "${crawler_name}" ]] && continue
    local slug; slug=$(slugify "${crawler_name}")
    LIVE_PAIRS+=("aws_glue_crawler.${slug}" "${crawler_name}")
  done < <(aws glue list-crawlers --region "${region}" \
    --query 'CrawlerNames[]' --output text 2>/dev/null | tr '\t' '\n' || true)
  while read -r db_name; do
    [[ -z "${db_name}" ]] && continue
    local slug; slug=$(slugify "${db_name}")
    LIVE_PAIRS+=("aws_glue_catalog_database.${slug}" "${account}:${db_name}")
  done < <(aws glue get-databases --region "${region}" \
    --query 'DatabaseList[].Name' --output text 2>/dev/null | tr '\t' '\n' || true)
  while read -r conn_name; do
    [[ -z "${conn_name}" ]] && continue
    local slug; slug=$(slugify "${conn_name}")
    LIVE_PAIRS+=("aws_glue_connection.${slug}" "${account}:${conn_name}")
  done < <(aws glue list-connections --region "${region}" \
    --query 'ConnectionList[].Name' --output text 2>/dev/null | tr '\t' '\n' || true)
}

scan_ses() {
  local region="$1"; LIVE_PAIRS=()
  while IFS=$'\t' read -r identity_name _identity_type; do
    [[ -z "${identity_name}" ]] && continue
    local slug; slug=$(slugify "${identity_name}")
    LIVE_PAIRS+=("aws_sesv2_email_identity.${slug}" "${identity_name}")
  done < <(aws sesv2 list-email-identities \
    --region "${region}" \
    --query 'EmailIdentities[].[IdentityName, IdentityType]' \
    --output text 2>/dev/null || true)
  while read -r cs_name; do
    [[ -z "${cs_name}" ]] && continue
    local slug; slug=$(slugify "${cs_name}")
    LIVE_PAIRS+=("aws_sesv2_configuration_set.${slug}" "${cs_name}")
  done < <(aws sesv2 list-configuration-sets \
    --region "${region}" \
    --query 'ConfigurationSets[]' \
    --output text 2>/dev/null | tr '\t' '\n' || true)
}

scan_codepipeline() {
  local region="$1"; LIVE_PAIRS=()
  while read -r pipeline_name; do
    [[ -z "${pipeline_name}" ]] && continue
    local slug; slug=$(slugify "${pipeline_name}")
    LIVE_PAIRS+=("aws_codepipeline.${slug}" "${pipeline_name}")
  done < <(aws codepipeline list-pipelines \
    --region "${region}" \
    --query 'pipelines[].name' \
    --output text 2>/dev/null | tr '\t' '\n' || true)
}

scan_codebuild() {
  local region="$1"; LIVE_PAIRS=()
  while read -r project_name; do
    [[ -z "${project_name}" ]] && continue
    local slug; slug=$(slugify "${project_name}")
    LIVE_PAIRS+=("aws_codebuild_project.${slug}" "${project_name}")
  done < <(aws codebuild list-projects \
    --region "${region}" \
    --query 'projects[]' \
    --output text 2>/dev/null | tr '\t' '\n' || true)
}

scan_documentdb() {
  local region="$1"; LIVE_PAIRS=()
  while read -r cluster_id; do
    [[ -z "${cluster_id}" ]] && continue
    local slug; slug=$(slugify "${cluster_id}")
    LIVE_PAIRS+=("aws_docdb_cluster.${slug}" "${cluster_id}")
  done < <(aws docdb describe-db-clusters \
    --region "${region}" \
    --filters "Name=engine,Values=docdb" \
    --query 'DBClusters[].DBClusterIdentifier' \
    --output text 2>/dev/null | tr '\t' '\n' || true)
  while read -r instance_id; do
    [[ -z "${instance_id}" ]] && continue
    local slug; slug=$(slugify "${instance_id}")
    LIVE_PAIRS+=("aws_docdb_cluster_instance.${slug}" "${instance_id}")
  done < <(aws docdb describe-db-instances \
    --region "${region}" \
    --filters "Name=engine,Values=docdb" \
    --query 'DBInstances[].DBInstanceIdentifier' \
    --output text 2>/dev/null | tr '\t' '\n' || true)
}

scan_fsx() {
  local region="$1"; LIVE_PAIRS=()
  while IFS=$'\t' read -r fs_id fs_type; do
    [[ -z "${fs_id}" ]] && continue
    local slug; slug=$(slugify "${fs_id}")
    case "${fs_type}" in
      WINDOWS) LIVE_PAIRS+=("aws_fsx_windows_file_system.${slug}" "${fs_id}") ;;
      LUSTRE)  LIVE_PAIRS+=("aws_fsx_lustre_file_system.${slug}"  "${fs_id}") ;;
      ONTAP)   LIVE_PAIRS+=("aws_fsx_ontap_file_system.${slug}"   "${fs_id}") ;;
      OPENZFS) LIVE_PAIRS+=("aws_fsx_openzfs_file_system.${slug}" "${fs_id}") ;;
      *)       LIVE_PAIRS+=("aws_fsx_lustre_file_system.${slug}"  "${fs_id}") ;;
    esac
  done < <(aws fsx describe-file-systems \
    --region "${region}" \
    --query 'FileSystems[].[FileSystemId, FileSystemType]' \
    --output text 2>/dev/null || true)
}

scan_transfer() {
  local region="$1"; LIVE_PAIRS=()
  while IFS=$'\t' read -r server_id _domain; do
    [[ -z "${server_id}" ]] && continue
    local slug; slug=$(slugify "${server_id}")
    LIVE_PAIRS+=("aws_transfer_server.${slug}" "${server_id}")
    while read -r username; do
      [[ -z "${username}" ]] && continue
      local u_slug; u_slug=$(slugify "${server_id}_${username}")
      LIVE_PAIRS+=("aws_transfer_user.${u_slug}" "${server_id}/${username}")
    done < <(aws transfer list-users \
      --server-id "${server_id}" --region "${region}" \
      --query 'Users[].UserName' --output text 2>/dev/null | tr '\t' '\n' || true)
  done < <(aws transfer list-servers \
    --region "${region}" \
    --query 'Servers[].[ServerId, Domain]' \
    --output text 2>/dev/null || true)
}

scan_elasticbeanstalk() {
  local region="$1"; LIVE_PAIRS=()
  while IFS=$'\t' read -r name; do
    [[ -z "${name}" ]] && continue
    LIVE_PAIRS+=("aws_elastic_beanstalk_application.$(slugify "${name}")" "${name}")
  done < <(aws elasticbeanstalk describe-applications \
    --region "${region}" --query 'Applications[].ApplicationName' \
    --output text 2>/dev/null | tr '\t' '\n' || true)
  while IFS=$'\t' read -r app env; do
    [[ -z "${env}" ]] && continue
    LIVE_PAIRS+=("aws_elastic_beanstalk_environment.$(slugify "${app}_${env}")" "${env}")
  done < <(aws elasticbeanstalk describe-environments \
    --region "${region}" --query 'Environments[].[ApplicationName,EnvironmentName]' \
    --output text 2>/dev/null || true)
}

scan_apprunner() {
  local region="$1"; LIVE_PAIRS=()
  while IFS=$'\t' read -r arn name; do
    [[ -z "${arn}" ]] && continue
    tag_match "${arn}" || continue
    LIVE_PAIRS+=("aws_apprunner_service.$(slugify "${name:-${arn##*/}}")" "${arn}")
  done < <(aws apprunner list-services \
    --region "${region}" --query 'ServiceSummaryList[].[ServiceArn,ServiceName]' \
    --output text 2>/dev/null || true)
}

scan_memorydb() {
  local region="$1"; LIVE_PAIRS=()
  while IFS=$'\t' read -r name arn; do
    [[ -z "${name}" ]] && continue
    tag_match "${arn}" || continue
    LIVE_PAIRS+=("aws_memorydb_cluster.$(slugify "${name}")" "${name}")
  done < <(aws memorydb describe-clusters \
    --region "${region}" --query 'Clusters[].[Name,ARN]' \
    --output text 2>/dev/null || true)
}

scan_athena() {
  local region="$1"; LIVE_PAIRS=()
  while IFS=$'\t' read -r name; do
    [[ -z "${name}" || "${name}" == "primary" ]] && continue
    LIVE_PAIRS+=("aws_athena_workgroup.$(slugify "${name}")" "${name}")
  done < <(aws athena list-work-groups \
    --region "${region}" --query 'WorkGroups[].Name' \
    --output text 2>/dev/null | tr '\t' '\n' || true)
  while IFS=$'\t' read -r name; do
    [[ -z "${name}" ]] && continue
    LIVE_PAIRS+=("aws_athena_data_catalog.$(slugify "${name}")" "${name}")
  done < <(aws athena list-data-catalogs \
    --region "${region}" --query 'DataCatalogsSummary[?Type!=`GLUE`].CatalogName' \
    --output text 2>/dev/null | tr '\t' '\n' || true)
}

scan_lakeformation() {
  local region="$1"; LIVE_PAIRS=()
  [[ "${region}" != "us-east-1" ]] && return
  while IFS=$'\t' read -r arn; do
    [[ -z "${arn}" ]] && continue
    LIVE_PAIRS+=("aws_lakeformation_resource.$(slugify "${arn##*/}")" "${arn}")
  done < <(aws lakeformation list-resources \
    --region "${region}" --query 'ResourceInfoList[].ResourceArn' \
    --output text 2>/dev/null | tr '\t' '\n' || true)
}

scan_servicecatalog() {
  local region="$1"; LIVE_PAIRS=()
  while IFS=$'\t' read -r id name; do
    [[ -z "${id}" ]] && continue
    LIVE_PAIRS+=("aws_servicecatalog_portfolio.$(slugify "${name:-${id}}")" "${id}")
  done < <(aws servicecatalog list-portfolios \
    --region "${region}" --query 'PortfolioDetails[].[Id,DisplayName]' \
    --output text 2>/dev/null || true)
  while IFS=$'\t' read -r id name; do
    [[ -z "${id}" ]] && continue
    LIVE_PAIRS+=("aws_servicecatalog_product.$(slugify "${name:-${id}}")" "${id}")
  done < <(aws servicecatalog search-products-as-admin \
    --region "${region}" --query 'ProductViewDetails[].ProductViewSummary.[ProductId,Name]' \
    --output text 2>/dev/null || true)
}

scan_lightsail() {
  local region="$1"; LIVE_PAIRS=()
  while IFS=$'\t' read -r name arn; do
    [[ -z "${name}" ]] && continue
    tag_match "${arn}" || continue
    LIVE_PAIRS+=("aws_lightsail_instance.$(slugify "${name}")" "${name}")
  done < <(aws lightsail get-instances \
    --region "${region}" --query 'instances[].[name,arn]' \
    --output text 2>/dev/null || true)
  while IFS=$'\t' read -r name arn; do
    [[ -z "${name}" ]] && continue
    tag_match "${arn}" || continue
    LIVE_PAIRS+=("aws_lightsail_database.$(slugify "${name}")" "${name}")
  done < <(aws lightsail get-relational-databases \
    --region "${region}" --query 'relationalDatabases[].[name,arn]' \
    --output text 2>/dev/null || true)
}

# ---------------------------------------------------------------------------
# Service dispatcher
# ---------------------------------------------------------------------------
scan_service() {
  local svc="$1" account="$2" region="$3"
  LIVE_PAIRS=()
  case "${svc}" in
    ec2)            scan_ec2            "${region}" ;;
    ebs)            scan_ebs            "${region}" ;;
    s3)             scan_s3             "${region}" ;;
    vpc)            scan_vpc            "${region}" ;;
    eks)            scan_eks            "${region}" ;;
    ecs)            scan_ecs            "${region}" ;;
    lambda)         scan_lambda         "${region}" ;;
    rds)            scan_rds            "${region}" ;;
    dynamodb)       scan_dynamodb       "${region}" ;;
    elasticache)    scan_elasticache    "${region}" ;;
    msk)            scan_msk            "${region}" ;;
    sqs)            scan_sqs            "${region}" ;;
    sns)            scan_sns            "${region}" ;;
    elb)            scan_elb            "${region}" ;;
    cloudfront)     scan_cloudfront     "${region}" ;;
    route53)        scan_route53        "${region}" ;;
    acm)            scan_acm            "${region}" ;;
    iam)            scan_iam            "${region}" ;;
    kms)            scan_kms            "${region}" ;;
    secretsmanager) scan_secretsmanager "${region}" ;;
    ssm)            scan_ssm            "${region}" ;;
    apigateway)     scan_apigateway     "${region}" ;;
    cloudwatch)     scan_cloudwatch     "${region}" ;;
    eventbridge)    scan_eventbridge    "${region}" ;;
    ecr)            scan_ecr            "${region}" ;;
    stepfunctions)  scan_stepfunctions  "${region}" ;;
    wafv2)          scan_wafv2          "${region}" ;;
    transitgateway) scan_transitgateway "${region}" ;;
    vpcendpoints)   scan_vpcendpoints   "${region}" ;;
    config)         scan_config         "${region}" ;;
    efs)            scan_efs            "${region}" ;;
    opensearch)     scan_opensearch     "${account}" "${region}" ;;
    kinesis)        scan_kinesis        "${region}" ;;
    cognito)        scan_cognito        "${region}" ;;
    cloudtrail)     scan_cloudtrail     "${region}" ;;
    guardduty)      scan_guardduty      "${region}" ;;
    backup)         scan_backup         "${region}" ;;
    redshift)       scan_redshift       "${region}" ;;
    glue)           scan_glue           "${account}" "${region}" ;;
    ses)            scan_ses            "${region}" ;;
    codepipeline)   scan_codepipeline   "${region}" ;;
    codebuild)      scan_codebuild      "${region}" ;;
    documentdb)     scan_documentdb     "${region}" ;;
    fsx)            scan_fsx            "${region}" ;;
    transfer)          scan_transfer          "${region}" ;;
    elasticbeanstalk)  scan_elasticbeanstalk  "${region}" ;;
    apprunner)         scan_apprunner         "${region}" ;;
    memorydb)          scan_memorydb          "${region}" ;;
    athena)            scan_athena            "${region}" ;;
    lakeformation)     scan_lakeformation     "${region}" ;;
    servicecatalog)    scan_servicecatalog    "${region}" ;;
    lightsail)         scan_lightsail         "${region}" ;;
    *) log "  [WARN] Unknown service '${svc}' — skipping" ;;
  esac
}

# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
# _scan_svc_to_tmp defined here (not inside the region loop) so it is only
# declared once regardless of how many regions are swept.
_scan_svc_to_tmp() {
  local _svc="$1" _account="$2" _region="$3" _tmp="$4"
  LIVE_PAIRS=()
  scan_service "${_svc}" "${_account}" "${_region}"
  printf '%s\n' "${LIVE_PAIRS[@]}" > "${_tmp}"
}

# Temp file receives auth/permission warnings from the aws() wrapper even
# when call sites use 2>/dev/null; flushed after each region sweep.
_AWS_WARN_FILE=$(mktemp)
trap 'rm -f "${_AWS_WARN_FILE}" 2>/dev/null' EXIT INT TERM

TOTAL_NEW=0
TOTAL_REMOVED=0
TOTAL_UNCHANGED=0

report ""
report "Terraclaim Drift Report"
report "Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
report "Output dir: ${OUTPUT_DIR}"
"${APPLY}" && report "Mode: apply (imports.tf will be updated)" || report "Mode: report-only (use --apply to update imports.tf)"
report "======================================================="

if [[ -z "${ACCOUNTS}" ]]; then
  CURRENT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) \
    || die "Unable to determine current AWS account. Check your credentials."
  ACCOUNTS="${CURRENT_ACCOUNT}"
  ACCOUNT_LIST=("${CURRENT_ACCOUNT}")
  log "No --accounts specified; using current account: ${ACCOUNTS}"
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

    # Load tag filter for this region (no-op if --tags not set)
    load_tag_filter "${region}"

    # -----------------------------------------------------------------------
    # Phase 1 — Parallel scan: each service writes LIVE_PAIRS to a temp file
    # -----------------------------------------------------------------------
    declare -A _SVC_TMPFILES=()

    for service in "${SERVICE_LIST[@]}"; do
      service="${service// /}"
      [[ -z "${service}" ]] && continue
      _tmp=$(mktemp)
      _SVC_TMPFILES["${service}"]="${_tmp}"
      log "  [${service}] scanning..."
      if [[ "${PARALLEL}" -gt 1 ]]; then
        while [[ $(jobs -rp | wc -l | tr -d ' ') -ge "${PARALLEL}" ]]; do
          wait -n 2>/dev/null || true
        done
        (
          _scan_svc_to_tmp "${service}" "${account}" "${region}" "${_tmp}" \
            || err "[FAIL] ${service} scan failed in ${region}"
        ) &
      else
        _scan_svc_to_tmp "${service}" "${account}" "${region}" "${_tmp}" \
          || err "[FAIL] ${service} scan failed in ${region}"
      fi
    done
    [[ "${PARALLEL}" -gt 1 ]] && wait

    # -----------------------------------------------------------------------
    # Phase 2 — Sequential diff + report + apply
    # -----------------------------------------------------------------------
    for service in "${SERVICE_LIST[@]}"; do
      service="${service// /}"
      [[ -z "${service}" ]] && continue

      local_imports_file="${OUTPUT_DIR}/${account}/${region}/${service}/imports.tf"
      local_resources_file="${OUTPUT_DIR}/${account}/${region}/${service}/resources.tf"

      # Read LIVE_PAIRS back from the temp file written by the scan phase
      LIVE_PAIRS=()
      _tmp="${_SVC_TMPFILES["${service}"]}"
      if [[ -f "${_tmp}" ]] && [[ -s "${_tmp}" ]]; then
        while IFS= read -r _line; do
          [[ -n "${_line}" ]] && LIVE_PAIRS+=("${_line}")
        done < "${_tmp}"
      fi
      rm -f "${_tmp}" 2>/dev/null || true

      # Build lookup of live IDs: id -> addr
      declare -A LIVE_IDS=()
      i=0
      while [[ $i -lt ${#LIVE_PAIRS[@]} ]]; do
        addr="${LIVE_PAIRS[$i]}"
        id="${LIVE_PAIRS[$((i+1))]}"
        LIVE_IDS["${id}"]="${addr}"
        i=$((i+2))
      done

      # Parse what we already have on disk
      parse_known_ids "${local_imports_file}"

      # Diff: NEW = in live but not in known
      new_pairs=()
      for id in "${!LIVE_IDS[@]}"; do
        if [[ -z "${KNOWN_IDS[${id}]+_}" ]]; then
          new_pairs+=("${LIVE_IDS[${id}]}" "${id}")
        fi
      done

      # Diff: REMOVED = in known but not in live
      removed_addrs=()
      for id in "${!KNOWN_IDS[@]}"; do
        if [[ -z "${LIVE_IDS[${id}]+_}" ]]; then
          removed_addrs+=("${KNOWN_IDS[${id}]}")
        fi
      done

      unchanged=$(( ${#LIVE_IDS[@]} - ${#new_pairs[@]} / 2 ))
      [[ $unchanged -lt 0 ]] && unchanged=0

      TOTAL_NEW=$(( TOTAL_NEW + ${#new_pairs[@]} / 2 ))
      TOTAL_REMOVED=$(( TOTAL_REMOVED + ${#removed_addrs[@]} ))
      TOTAL_UNCHANGED=$(( TOTAL_UNCHANGED + unchanged ))

      has_drift=false
      if [[ ${#new_pairs[@]} -gt 0 ]] || [[ ${#removed_addrs[@]} -gt 0 ]]; then
        has_drift=true
      fi

      if "${has_drift}"; then
        report ""
        report "  ${account} / ${region} / ${service}"
        report "  -------------------------------------------------------"

        if [[ ${#new_pairs[@]} -gt 0 ]]; then
          report "  NEW  ($((${#new_pairs[@]}/2)) resource(s) found in AWS, not in imports.tf)"
          j=0
          while [[ $j -lt ${#new_pairs[@]} ]]; do
            report "    + ${new_pairs[$j]}  (id: ${new_pairs[$((j+1))]})"
            j=$((j+2))
          done
        fi

        if [[ ${#removed_addrs[@]} -gt 0 ]]; then
          report "  REMOVED  (${#removed_addrs[@]} resource(s) in imports.tf, no longer in AWS)"
          for addr in "${removed_addrs[@]}"; do
            report "    - ${addr}  (id: ${KNOWN_ADDRS[${addr}]:-unknown})"
          done
        fi

        if "${APPLY}"; then
          if [[ ${#new_pairs[@]} -gt 0 ]]; then
            # Ensure the service directory exists (first run may not have written it)
            mkdir -p "${OUTPUT_DIR}/${account}/${region}/${service}"
            if [[ ! -f "${local_imports_file}" ]]; then
              printf '# Auto-generated import blocks — do not edit by hand.\n# Run: terraform plan -generate-config-out=generated.tf\n\n' \
                > "${local_imports_file}"
              printf '# Auto-generated resource skeletons.\n\n' \
                > "${local_resources_file}"
            fi
            apply_new_imports "${local_imports_file}" "${local_resources_file}" "${new_pairs[@]}"
          fi
          [[ ${#removed_addrs[@]} -gt 0 ]] && apply_remove_stale "${local_imports_file}" "${removed_addrs[@]}"
          report "  APPLIED"
        fi
      else
        debug "  [${service}] no drift in ${region} (${unchanged} resources unchanged)"
      fi

      unset LIVE_IDS LIVE_ADDRS
    done
    unset _SVC_TMPFILES
    # Surface any auth/permission errors collected during this region sweep
    flush_aws_warnings
  done

  if [[ -n "${ROLE_NAME}" ]]; then
    restore_credentials
  fi
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
report ""
report "======================================================="
report "Summary"
report "-------"
report "Unchanged:        ${TOTAL_UNCHANGED}"
report "New (not yet imported):  ${TOTAL_NEW}"
report "Removed (stale):  ${TOTAL_REMOVED}"
if [[ $(( TOTAL_NEW + TOTAL_REMOVED )) -eq 0 ]]; then
  report ""
  report "No drift detected. Your imports.tf files are up to date."
else
  report ""
  if ! "${APPLY}"; then
    report "Run with --apply to update imports.tf files automatically."
  else
    report "imports.tf files updated."
  fi
fi
report ""

flush_report
