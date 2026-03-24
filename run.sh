#!/usr/bin/env bash
# run.sh — Run `terraform init` + `terraform plan -generate-config-out=generated.tf`
# for every service directory produced by terraclaim.sh.
#
# Walks the tf-output tree looking for directories that contain an imports.tf
# file and runs Terraform in each one. A summary at the end shows which
# directories succeeded, which failed, and which had no changes.
#
# Usage:
#   ./run.sh [OPTIONS]
#
# Options:
#   --output    "./tf-output"   Root output directory from terraclaim.sh (default: ./tf-output)
#   --services  "ec2,eks"       Limit to specific services (default: all)
#   --regions   "us-east-1"     Limit to specific regions (default: all)
#   --accounts  "123456789012"  Limit to specific accounts (default: all)
#   --parallel  3               Max concurrent terraform runs (default: 3)
#   --dry-run                   Print directories that would be processed; do not run terraform
#   --init-only                 Only run terraform init, skip the plan step
#   --debug                     Verbose logging
#   --help                      Show this help

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
OUTPUT_DIR="./tf-output"
FILTER_SERVICES=""
FILTER_REGIONS=""
FILTER_ACCOUNTS=""
PARALLEL=3
DRY_RUN=false
INIT_ONLY=false
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
    --output)    OUTPUT_DIR="$2";         shift 2 ;;
    --services)  FILTER_SERVICES="$2";    shift 2 ;;
    --regions)   FILTER_REGIONS="$2";     shift 2 ;;
    --accounts)  FILTER_ACCOUNTS="$2";    shift 2 ;;
    --parallel)  PARALLEL="$2";           shift 2 ;;
    --dry-run)   DRY_RUN=true;            shift ;;
    --init-only) INIT_ONLY=true;          shift ;;
    --debug)     DEBUG=true;              shift ;;
    --help|-h)   usage ;;
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
command -v terraform &>/dev/null || die "Required command not found: terraform"

[[ -d "${OUTPUT_DIR}" ]] || die "Output directory not found: ${OUTPUT_DIR}. Run terraclaim.sh first."

# ---------------------------------------------------------------------------
# Build list of directories to process
# ---------------------------------------------------------------------------
# Expected layout: OUTPUT_DIR/ACCOUNT/REGION/SERVICE/imports.tf
DIRS=()

while IFS= read -r imports_file; do
  dir=$(dirname "${imports_file}")
  # Extract account, region, service from path
  # Strip OUTPUT_DIR prefix, then split remaining path
  rel="${dir#${OUTPUT_DIR}/}"
  IFS='/' read -r dir_account dir_region dir_service <<< "${rel}"

  # Apply filters
  if [[ -n "${FILTER_ACCOUNTS}" ]]; then
    IFS=',' read -ra _fa <<< "${FILTER_ACCOUNTS}"
    _match=false
    for _a in "${_fa[@]}"; do
      [[ "${dir_account}" == "${_a// /}" ]] && { _match=true; break; }
    done
    "${_match}" || continue
  fi

  if [[ -n "${FILTER_REGIONS}" ]]; then
    IFS=',' read -ra _fr <<< "${FILTER_REGIONS}"
    _match=false
    for _r in "${_fr[@]}"; do
      [[ "${dir_region}" == "${_r// /}" ]] && { _match=true; break; }
    done
    "${_match}" || continue
  fi

  if [[ -n "${FILTER_SERVICES}" ]]; then
    IFS=',' read -ra _fs <<< "${FILTER_SERVICES}"
    _match=false
    for _s in "${_fs[@]}"; do
      [[ "${dir_service}" == "${_s// /}" ]] && { _match=true; break; }
    done
    "${_match}" || continue
  fi

  DIRS+=("${dir}")
done < <(find "${OUTPUT_DIR}" -name "imports.tf" | sort)

if [[ ${#DIRS[@]} -eq 0 ]]; then
  log "No service directories found under ${OUTPUT_DIR}."
  log "Run terraclaim.sh first to generate import blocks."
  exit 0
fi

log "Found ${#DIRS[@]} service director$([ ${#DIRS[@]} -eq 1 ] && echo y || echo ies) to process."

if "${DRY_RUN}"; then
  for dir in "${DIRS[@]}"; do
    echo "  ${dir}"
  done
  log "Dry run — no terraform commands executed."
  exit 0
fi

# ---------------------------------------------------------------------------
# Counters and temp tracking
# ---------------------------------------------------------------------------
_PASS=0
_FAIL=0
_NOCHANGE=0
declare -a _FAILED_DIRS=()

# ---------------------------------------------------------------------------
# Process a single directory
# ---------------------------------------------------------------------------
process_dir() {
  local dir="$1"
  local rel="${dir#${OUTPUT_DIR}/}"
  local logfile; logfile="${dir}/.run.log"

  debug "Processing: ${dir}"

  {
    echo "=== terraform init ==="
    if ! terraform -chdir="${dir}" init -upgrade -input=false 2>&1; then
      echo "TERRACLAIM_RESULT=FAIL"
      return
    fi

    if "${INIT_ONLY}"; then
      echo "TERRACLAIM_RESULT=PASS"
      return
    fi

    echo ""
    echo "=== terraform plan ==="
    local plan_out
    plan_out=$(terraform -chdir="${dir}" plan \
      -generate-config-out=generated.tf \
      -input=false \
      -no-color 2>&1)
    local plan_ec=$?
    echo "${plan_out}"

    if [[ $plan_ec -ne 0 ]]; then
      echo "TERRACLAIM_RESULT=FAIL"
    elif echo "${plan_out}" | grep -q "No changes"; then
      echo "TERRACLAIM_RESULT=NOCHANGE"
    else
      echo "TERRACLAIM_RESULT=PASS"
    fi
  } > "${logfile}" 2>&1

  local result
  result=$(grep '^TERRACLAIM_RESULT=' "${logfile}" | tail -1 | cut -d= -f2)
  printf '%s\t%s\n' "${result:-FAIL}" "${rel}"
}

# ---------------------------------------------------------------------------
# Run — parallel or sequential
# ---------------------------------------------------------------------------
_RESULTS_DIR=$(mktemp -d)
trap 'rm -rf "${_RESULTS_DIR}" 2>/dev/null' EXIT INT TERM

run_dir() {
  local dir="$1"
  local rel="${dir#${OUTPUT_DIR}/}"
  local tmpresult
  tmpresult="${_RESULTS_DIR}/$(echo "${rel}" | tr '/' '_').result"
  process_dir "${dir}" > "${tmpresult}" 2>&1
}

log "Running terraform in up to ${PARALLEL} parallel job(s)..."
log ""

for dir in "${DIRS[@]}"; do
  rel="${dir#${OUTPUT_DIR}/}"
  log "  → ${rel}"
  if [[ "${PARALLEL}" -gt 1 ]]; then
    while [[ $(jobs -rp | wc -l | tr -d ' ') -ge "${PARALLEL}" ]]; do
      wait -n 2>/dev/null || true
    done
    run_dir "${dir}" &
  else
    run_dir "${dir}"
  fi
done
[[ "${PARALLEL}" -gt 1 ]] && wait

# ---------------------------------------------------------------------------
# Collect results
# ---------------------------------------------------------------------------
log ""
log "Results:"
log "--------"

for dir in "${DIRS[@]}"; do
  rel="${dir#${OUTPUT_DIR}/}"
  logfile="${dir}/.run.log"
  result=$(grep '^TERRACLAIM_RESULT=' "${logfile}" 2>/dev/null | tail -1 | cut -d= -f2 || echo "FAIL")

  case "${result}" in
    PASS)     _PASS=$((_PASS+1));     log "  [OK]        ${rel}" ;;
    NOCHANGE) _NOCHANGE=$((_NOCHANGE+1)); log "  [no-change] ${rel}" ;;
    FAIL)
      _FAIL=$((_FAIL+1))
      _FAILED_DIRS+=("${rel}")
      log "  [FAIL]      ${rel}  (see ${logfile})"
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
log ""
log "======================================================="
log "Summary"
log "-------"
log "  Succeeded (changes written): ${_PASS}"
log "  No changes:                  ${_NOCHANGE}"
log "  Failed:                      ${_FAIL}"
log ""

if [[ ${_FAIL} -gt 0 ]]; then
  log "Failed directories:"
  for _d in "${_FAILED_DIRS[@]}"; do
    log "  - ${_d}"
    log "    Log: ${OUTPUT_DIR}/${_d}/.run.log"
  done
  log ""
  log "Common causes:"
  log "  - 'generated.tf already exists' — delete it and re-run"
  log "  - Provider version conflict — check backend.tf"
  log "  - Missing AWS credentials or insufficient permissions"
  exit 1
fi

log "All directories processed successfully."
log ""
if ! "${INIT_ONLY}"; then
  log "Next steps:"
  log "  1. Review generated.tf in each service directory"
  log "  2. Remove any computed / read-only attributes that cause a diff"
  log "  3. Commit as your Terraform baseline on a 'baseline-import' branch"
fi
