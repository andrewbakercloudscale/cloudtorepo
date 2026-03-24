#!/usr/bin/env bash
# reconcile.sh — Compare a terraclaim output directory against AWS Resource Explorer.
#
# Queries Resource Explorer for all resources in the account/region and checks
# how many are already covered by an import block in the output directory.
# Reports coverage percentage and lists potentially missed resources.
#
# Requirements: aws-cli >= 2, jq >= 1.6
# Resource Explorer must be enabled and have an aggregator index configured.
#
# Usage:
#   ./reconcile.sh [OPTIONS]
#
# Options:
#   --output       "./tf-output"   Output directory from terraclaim.sh
#   --index-region "us-east-1"    Region containing the Resource Explorer aggregator index
#   --accounts     "id1,id2"      Comma-separated account IDs (default: all in index)
#   --dry-run                     Show what would be checked; do not query Resource Explorer
#   --debug                       Verbose logging
#   --help                        Show this help

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
OUTPUT_DIR="./tf-output"
INDEX_REGION="us-east-1"
ACCOUNTS=""
DRY_RUN=false
DEBUG=false

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { echo "[INFO]  $*" >&2; }
debug(){ [[ "${DEBUG}" == "true" ]] && echo "[DEBUG] $*" >&2 || true; }
err()  { echo "[ERROR] $*" >&2; }
die()  { err "$*"; exit 1; }

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)       OUTPUT_DIR="$2";    shift 2 ;;
    --index-region) INDEX_REGION="$2";  shift 2 ;;
    --accounts)     ACCOUNTS="$2";      shift 2 ;;
    --dry-run)      DRY_RUN=true;       shift ;;
    --debug)        DEBUG=true;         shift ;;
    --help|-h)      usage ;;
    *) die "Unknown option: $1 — run with --help for usage." ;;
  esac
done

# ---------------------------------------------------------------------------
# Dependency checks
# ---------------------------------------------------------------------------
for cmd in aws jq; do
  command -v "$cmd" &>/dev/null || die "Required command not found: $cmd"
done

[[ -d "${OUTPUT_DIR}" ]] || die "Output directory not found: ${OUTPUT_DIR}"

# ---------------------------------------------------------------------------
# Build a set of import IDs already covered by the output directory
# ---------------------------------------------------------------------------
log "Scanning import blocks in ${OUTPUT_DIR}..."
declare -A COVERED_IDS

while IFS= read -r line; do
  # Extract the id = "..." value from each import block
  if [[ "${line}" =~ ^[[:space:]]*id[[:space:]]*=[[:space:]]*\"(.+)\"[[:space:]]*$ ]]; then
    COVERED_IDS["${BASH_REMATCH[1]}"]="1"
  fi
done < <(grep -r 'id = "' "${OUTPUT_DIR}" --include='imports.tf' 2>/dev/null || true)

COVERED_COUNT=${#COVERED_IDS[@]}
log "Found ${COVERED_COUNT} covered import IDs."

if "${DRY_RUN}"; then
  log "Dry run — skipping Resource Explorer query."
  log "Would query Resource Explorer aggregator index in region: ${INDEX_REGION}"
  exit 0
fi

# ---------------------------------------------------------------------------
# Query Resource Explorer for all resources
# ---------------------------------------------------------------------------
log "Querying Resource Explorer (index region: ${INDEX_REGION})..."

# Verify Resource Explorer is available and has an index
INDEX_TYPE=$(aws resource-explorer-2 get-index \
  --region "${INDEX_REGION}" \
  --query 'Type' \
  --output text 2>/dev/null || echo "NONE")

if [[ "${INDEX_TYPE}" == "NONE" ]] || [[ "${INDEX_TYPE}" == "None" ]]; then
  die "No Resource Explorer index found in ${INDEX_REGION}. Enable Resource Explorer and create an aggregator index first."
fi

log "Index type: ${INDEX_TYPE}"

# Build query filter for accounts if specified
QUERY_STRING="region:* resourcetype:*"
if [[ -n "${ACCOUNTS}" ]]; then
  # Resource Explorer filter by account
  ACCOUNT_FILTER=$(echo "${ACCOUNTS}" | tr ',' '\n' | sed 's/^/accountid:/' | paste -sd ' OR ' -)
  QUERY_STRING="${ACCOUNT_FILTER}"
fi

# Paginate through all resources
ALL_RESOURCES=()
NEXT_TOKEN=""

log "Searching all resources (this may take a moment)..."
while true; do
  local_args=(
    --region "${INDEX_REGION}"
    --query-string "${QUERY_STRING}"
    --output json
  )
  [[ -n "${NEXT_TOKEN}" ]] && local_args+=(--next-token "${NEXT_TOKEN}")

  response=$(aws resource-explorer-2 search "${local_args[@]}" 2>/dev/null) || \
    die "Resource Explorer search failed. Check permissions: resource-explorer-2:Search"

  # Extract resources from this page
  while IFS= read -r resource_json; do
    ALL_RESOURCES+=("${resource_json}")
  done < <(echo "${response}" | jq -c '.Resources[]' 2>/dev/null || true)

  NEXT_TOKEN=$(echo "${response}" | jq -r '.NextToken // empty' 2>/dev/null || true)
  [[ -z "${NEXT_TOKEN}" ]] && break
  debug "Paginating... (${#ALL_RESOURCES[@]} resources so far)"
done

TOTAL=${#ALL_RESOURCES[@]}
log "Resource Explorer returned ${TOTAL} resources."

# ---------------------------------------------------------------------------
# Compare resources against covered import IDs
# ---------------------------------------------------------------------------
declare -A MISSED_BY_REGION_SERVICE
MATCHED=0
MISSED=0

for resource_json in "${ALL_RESOURCES[@]}"; do
  arn=$(echo "${resource_json}"     | jq -r '.Arn'          2>/dev/null || true)
  res_type=$(echo "${resource_json}" | jq -r '.ResourceType' 2>/dev/null || true)
  res_region=$(echo "${resource_json}" | jq -r '.Region'     2>/dev/null || true)

  # Extract the resource ID from the ARN (last path segment or resource portion)
  resource_id="${arn##*:}"
  resource_id="${resource_id##*/}"

  # Check if this ARN or resource ID is in covered set
  if [[ -n "${COVERED_IDS[${arn}]+_}" ]] || [[ -n "${COVERED_IDS[${resource_id}]+_}" ]]; then
    MATCHED=$((MATCHED + 1))
  else
    MISSED=$((MISSED + 1))
    key="${res_region}|${res_type}"
    if [[ -z "${MISSED_BY_REGION_SERVICE[${key}]+_}" ]]; then
      MISSED_BY_REGION_SERVICE["${key}"]=""
    fi
    MISSED_BY_REGION_SERVICE["${key}"]+="${arn}"$'\n'
  fi
done

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
if [[ "${TOTAL}" -gt 0 ]]; then
  COVERAGE=$(awk "BEGIN { printf \"%.0f\", (${MATCHED} / ${TOTAL}) * 100 }")
else
  COVERAGE=100
fi

echo ""
echo "Summary"
echo "-------"
printf "Total resources (Resource Explorer):  %d\n" "${TOTAL}"
printf "Matched to exported import blocks:    %d\n" "${MATCHED}"
printf "Potentially missed:                    %d\n" "${MISSED}"
printf "Coverage:                              %s%%\n" "${COVERAGE}"

if [[ "${MISSED}" -gt 0 ]]; then
  echo ""
  echo "Potentially Missed Resources (grouped by region, then service)"
  echo ""

  # Sort keys for consistent output
  sorted_keys=$(printf '%s\n' "${!MISSED_BY_REGION_SERVICE[@]}" | sort)

  current_region=""
  while IFS= read -r key; do
    region_part="${key%%|*}"
    service_part="${key##*|}"

    if [[ "${region_part}" != "${current_region}" ]]; then
      echo "Region: ${region_part}"
      echo "------------------------------------------------------------"
      current_region="${region_part}"
    fi

    echo ""
    echo "  Service: ${service_part%%/*}"
    echo "    Type: ${service_part}"
    while IFS= read -r arn_line; do
      [[ -z "${arn_line}" ]] && continue
      echo "    ARN:  ${arn_line}"
    done <<< "${MISSED_BY_REGION_SERVICE[${key}]}"
  done <<< "${sorted_keys}"

  echo ""
  echo "To add support for a missing service, open a GitHub issue using the"
  echo "'new_service' template, or submit a pull request — see CONTRIBUTING.md"
fi

echo ""
