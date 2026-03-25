#!/usr/bin/env bash
# lib/common.sh — Shared helpers sourced by terraclaim.sh and drift.sh.
#
# Prerequisites (set these globals before sourcing):
#   DEBUG          — "true" | "false"
#   TAGS           — comma-separated Key=Value pairs, or ""
#   PARALLEL       — max concurrent jobs (integer)
#   _AWS_WARN_FILE — path to temp file that collects auth warnings
#   _TAG_IDS_FILE  — path to temp file used as the tag-filter set

# ---------------------------------------------------------------------------
# Default service list — single source of truth for both scripts
# ---------------------------------------------------------------------------
_TERRACLAIM_DEFAULT_SERVICES="ec2,ebs,ecs,eks,lambda,vpc,elb,cloudfront,route53,acm,rds,dynamodb,elasticache,msk,s3,sqs,sns,apigateway,iam,kms,secretsmanager,ssm,cloudwatch,eventbridge,ecr,stepfunctions,wafv2,transitgateway,vpcendpoints,config,efs,opensearch,kinesis,cognito,cloudtrail,guardduty,backup,redshift,glue,ses,codepipeline,codebuild,documentdb,fsx,transfer,elasticbeanstalk,apprunner,memorydb,athena,lakeformation,servicecatalog,lightsail,emr,sagemaker,organizations,xray,appconfig,bedrock"

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
log()   { echo "[INFO]  $*" >&2; }
debug() { [[ "${DEBUG}" == "true" ]] && echo "[DEBUG] $*" >&2 || true; }
err()   { echo "[ERROR] $*" >&2; }
die()   { err "$*"; exit 1; }

# ---------------------------------------------------------------------------
# Slugify — convert a string to a safe Terraform identifier
# ---------------------------------------------------------------------------
slugify() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/_/g' | sed 's/__*/_/g' | sed 's/^_//;s/_$//'
}

# ---------------------------------------------------------------------------
# AWS CLI wrapper — retries on throttling with exponential back-off + jitter
# ---------------------------------------------------------------------------
aws() {
  local attempt=1 delay=1 max=5 out ec
  while true; do
    out=$(command aws "$@" 2>&1); ec=$?
    if [[ $ec -eq 0 ]]; then
      # Command substitution strips trailing newlines; add one back so that
      # callers using `while read` correctly process the final output line.
      printf '%s\n' "${out}"
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
  true > "${_AWS_WARN_FILE}"
}

# ---------------------------------------------------------------------------
# Tag filter — populate _TAG_IDS_FILE lookup from Resource Groups Tagging API
# (Uses a temp file for Bash 3.2 compatibility — no associative arrays needed)
# ---------------------------------------------------------------------------
load_tag_filter() {
  local region="$1"
  [[ -z "${TAGS}" ]] && return 0
  true > "${_TAG_IDS_FILE}"   # clear previous region's entries
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
    echo "${_arn}" >> "${_TAG_IDS_FILE}"
    # Extract bare ID: last component after / or : (handles most ARN formats)
    local _id="${_arn##*/}"; [[ "${_id}" == "${_arn}" ]] && _id="${_arn##*:}"
    echo "${_id}" >> "${_TAG_IDS_FILE}"
  done < <(aws resourcegroupstaggingapi get-resources \
    --region "${region}" \
    --tag-filters "${filter_args[@]}" \
    --query 'ResourceTagMappingList[].ResourceARN' \
    --output text 2>/dev/null || true)
  local _count; _count=$(wc -l < "${_TAG_IDS_FILE}" | tr -d ' ') || true
  debug "  [tags] ${_count} tagged resource IDs loaded for ${region}"
  if [[ ! -s "${_TAG_IDS_FILE}" ]]; then
    err "[WARN] --tags filter returned 0 matching resources in ${region}. Verify:"
    err "  - IAM permission resourcegroupstaggingapi:GetResources is granted"
    err "  - Tags are specified exactly as they appear in AWS: ${TAGS}"
  fi
}

# Returns 0 if resource matches tag filter (or no filter set), 1 otherwise
tag_match() {
  [[ -z "${TAGS}" ]] && return 0
  grep -qxF "$1" "${_TAG_IDS_FILE}" 2>/dev/null
}

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
    --role-session-name "terraclaim-$$" \
    --query 'Credentials' \
    --output json) || die "Failed to assume role ${arn}"
  export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
  AWS_ACCESS_KEY_ID=$(echo "${creds}"    | jq -r '.AccessKeyId')
  AWS_SECRET_ACCESS_KEY=$(echo "${creds}" | jq -r '.SecretAccessKey')
  AWS_SESSION_TOKEN=$(echo "${creds}"    | jq -r '.SessionToken')
  [[ "${AWS_ACCESS_KEY_ID}" == "null" || -z "${AWS_ACCESS_KEY_ID}" ]] && \
    die "assume_role: invalid credentials returned for ${arn} — verify the role exists and its trust policy allows this principal"
}

restore_credentials() {
  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
}
