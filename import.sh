#!/usr/bin/env bash
# import.sh — Run `terraform import` for every resource in a terraclaim output directory.
#
# Walks the tf-output tree, reads each imports.tf file, and runs
# `terraform import <address> <id>` for every resource not already present in
# terraform.tfstate. Skips directories that have not yet been initialised
# (no .terraform/ directory) unless --init is passed.
#
# Requirements: bash 3.2+, terraform >= 1.5
#
# Usage:
#   ./import.sh [OPTIONS]
#
# Options:
#   --output    "./tf-output"   Root output directory from terraclaim.sh (default: ./tf-output)
#   --services  "ec2,eks"       Limit to specific services (default: all)
#   --regions   "us-east-1"     Limit to specific regions (default: all)
#   --accounts  "123456789012"  Limit to specific accounts (default: all)
#   --parallel  3               Max concurrent terraform import runs (default: 1)
#   --init                      Run terraform init before importing (default: false)
#   --dry-run                   Print what would be imported; do not run terraform
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
PARALLEL=1
DO_INIT=false
DRY_RUN=false
DEBUG=false

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()   { echo "[INFO]  $*" >&2; }
debug() { [[ "${DEBUG}" == "true" ]] && echo "[DEBUG] $*" >&2 || true; }
err()   { echo "[ERROR] $*" >&2; }
die()   { err "$*"; exit 1; }

usage() {
  grep '^#' "$0" | grep -v '^#!' | sed 's/^# \{0,1\}//'
  exit 0
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)   OUTPUT_DIR="$2";        shift 2 ;;
    --services) FILTER_SERVICES="$2";   shift 2 ;;
    --regions)  FILTER_REGIONS="$2";    shift 2 ;;
    --accounts) FILTER_ACCOUNTS="$2";   shift 2 ;;
    --parallel) PARALLEL="$2";          shift 2 ;;
    --init)     DO_INIT=true;           shift ;;
    --dry-run)  DRY_RUN=true;           shift ;;
    --debug)    DEBUG=true;             shift ;;
    --help|-h)  usage ;;
    *) die "Unknown option: $1 — run with --help for usage." ;;
  esac
done

[[ "${PARALLEL}" =~ ^[1-9][0-9]*$ ]] || die "--parallel must be a positive integer (got: '${PARALLEL}')"

# ---------------------------------------------------------------------------
# Dependency checks
# ---------------------------------------------------------------------------
command -v terraform &>/dev/null || die "Required command not found: terraform"

[[ -d "${OUTPUT_DIR}" ]] || die "Output directory not found: ${OUTPUT_DIR}. Run terraclaim.sh first."

# ---------------------------------------------------------------------------
# Build list of directories to process (same filter logic as run.sh)
# ---------------------------------------------------------------------------
DIRS=()

while IFS= read -r imports_file; do
  dir=$(dirname "${imports_file}")
  rel="${dir#${OUTPUT_DIR}/}"
  IFS='/' read -r dir_account dir_region dir_service <<< "${rel}"

  if [[ -n "${FILTER_ACCOUNTS}" ]]; then
    IFS=',' read -ra _fa <<< "${FILTER_ACCOUNTS}"
    _match=false
    for _a in "${_fa[@]}"; do [[ "${dir_account}" == "${_a// /}" ]] && { _match=true; break; }; done
    "${_match}" || continue
  fi
  if [[ -n "${FILTER_REGIONS}" ]]; then
    IFS=',' read -ra _fr <<< "${FILTER_REGIONS}"
    _match=false
    for _r in "${_fr[@]}"; do [[ "${dir_region}" == "${_r// /}" ]] && { _match=true; break; }; done
    "${_match}" || continue
  fi
  if [[ -n "${FILTER_SERVICES}" ]]; then
    IFS=',' read -ra _fs <<< "${FILTER_SERVICES}"
    _match=false
    for _s in "${_fs[@]}"; do [[ "${dir_service}" == "${_s// /}" ]] && { _match=true; break; }; done
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

# ---------------------------------------------------------------------------
# Parse import blocks from an imports.tf file
# Output: lines of "address<TAB>id"
# ---------------------------------------------------------------------------
parse_imports_tf() {
  local file="$1"
  local addr="" id=""
  while IFS= read -r line; do
    if [[ "${line}" =~ ^[[:space:]]*to[[:space:]]*=[[:space:]]*(.+)[[:space:]]*$ ]]; then
      addr="${BASH_REMATCH[1]}"
    elif [[ "${line}" =~ ^[[:space:]]*id[[:space:]]*=[[:space:]]*\"(.+)\"[[:space:]]*$ ]]; then
      id="${BASH_REMATCH[1]}"
    fi
    if [[ -n "${addr}" && -n "${id}" ]]; then
      printf '%s\t%s\n' "${addr}" "${id}"
      addr=""; id=""
    fi
  done < "${file}"
}

# ---------------------------------------------------------------------------
# Check if an address is already in terraform state
# ---------------------------------------------------------------------------
in_state() {
  local dir="$1" addr="$2"
  terraform -chdir="${dir}" state list 2>/dev/null | grep -qxF "${addr}" || return 1
}

# ---------------------------------------------------------------------------
# Process a single service directory
# ---------------------------------------------------------------------------
_RESULTS_DIR=$(mktemp -d)
trap 'rm -rf "${_RESULTS_DIR}" 2>/dev/null' EXIT INT TERM

process_dir() {
  local dir="$1"
  local rel="${dir#${OUTPUT_DIR}/}"
  local imports_tf="${dir}/imports.tf"
  local imported=0 skipped=0 failed=0

  # Init if requested or if .terraform is missing
  if "${DO_INIT}" || [[ ! -d "${dir}/.terraform" ]]; then
    if ! "${DRY_RUN}"; then
      debug "  [${rel}] running terraform init..."
      if ! terraform -chdir="${dir}" init -upgrade -input=false -no-color \
            > "${dir}/.import-init.log" 2>&1; then
        err "  [${rel}] terraform init failed — see ${dir}/.import-init.log"
        printf 'FAIL\t%s\t0\t0\t1\n' "${rel}"
        return
      fi
    fi
  fi

  while IFS=$'\t' read -r addr id; do
    [[ -z "${addr}" || -z "${id}" ]] && continue

    # Skip commented-out blocks (addr starts with #)
    [[ "${addr}" =~ ^# ]] && continue

    if "${DRY_RUN}"; then
      echo "  would import: ${addr}  (id: ${id})"
      imported=$((imported + 1))
      continue
    fi

    # Skip if already in state
    if in_state "${dir}" "${addr}"; then
      debug "  [${rel}] already in state: ${addr}"
      skipped=$((skipped + 1))
      continue
    fi

    log "  [${rel}] importing ${addr} (id: ${id})..."
    if terraform -chdir="${dir}" import -input=false -no-color "${addr}" "${id}" \
         >> "${dir}/.import.log" 2>&1; then
      imported=$((imported + 1))
    else
      err "  [${rel}] FAILED: ${addr} (id: ${id}) — see ${dir}/.import.log"
      failed=$((failed + 1))
    fi
  done < <(parse_imports_tf "${imports_tf}")

  printf '%s\t%s\t%d\t%d\t%d\n' \
    "$([ "${failed}" -gt 0 ] && echo FAIL || echo PASS)" \
    "${rel}" "${imported}" "${skipped}" "${failed}"
}

# ---------------------------------------------------------------------------
# Dry run — just list what would happen
# ---------------------------------------------------------------------------
if "${DRY_RUN}"; then
  log "Dry run — no terraform commands will be executed."
  log ""
  _total=0
  for dir in "${DIRS[@]}"; do
    rel="${dir#${OUTPUT_DIR}/}"
    echo "${rel}:"
    process_dir "${dir}"
    echo ""
    _total=$((_total + 1))
  done
  log "Would process ${_total} director$([ "${_total}" -eq 1 ] && echo y || echo ies)."
  exit 0
fi

# ---------------------------------------------------------------------------
# Run — parallel or sequential
# ---------------------------------------------------------------------------
log "Importing resources (parallel=${PARALLEL})..."
log ""

run_dir() {
  local dir="$1"
  local rel="${dir#${OUTPUT_DIR}/}"
  local tmpresult
  tmpresult="${_RESULTS_DIR}/$(echo "${rel}" | tr '/' '_').result"
  process_dir "${dir}" > "${tmpresult}" 2>&1
}

for dir in "${DIRS[@]}"; do
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
_PASS=0
_FAIL=0
_TOTAL_IMPORTED=0
_TOTAL_SKIPPED=0
_TOTAL_FAILED=0
_FAILED_DIRS=()

log ""
log "Results:"
log "--------"

for dir in "${DIRS[@]}"; do
  rel="${dir#${OUTPUT_DIR}/}"
  local_key=$(echo "${rel}" | tr '/' '_')
  tmpresult="${_RESULTS_DIR}/${local_key}.result"
  if [[ ! -f "${tmpresult}" ]]; then
    log "  [FAIL] ${rel}  (no result file)"
    _FAIL=$((_FAIL + 1)); _FAILED_DIRS+=("${rel}"); continue
  fi
  while IFS=$'\t' read -r status _rel imported skipped failed; do
    case "${status}" in
      PASS)
        _PASS=$((_PASS + 1))
        log "  [OK]   ${_rel}  (imported: ${imported}, skipped: ${skipped})"
        ;;
      FAIL)
        _FAIL=$((_FAIL + 1))
        _FAILED_DIRS+=("${_rel}")
        log "  [FAIL] ${_rel}  (imported: ${imported}, skipped: ${skipped}, failed: ${failed})"
        ;;
    esac
    _TOTAL_IMPORTED=$((_TOTAL_IMPORTED + imported))
    _TOTAL_SKIPPED=$((_TOTAL_SKIPPED + skipped))
    _TOTAL_FAILED=$((_TOTAL_FAILED + failed))
  done < "${tmpresult}"
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
log ""
log "======================================================="
log "Summary"
log "-------"
log "Directories processed:  ${#DIRS[@]}"
log "Resources imported:     ${_TOTAL_IMPORTED}"
log "Resources skipped:      ${_TOTAL_SKIPPED}  (already in state)"
log "Resources failed:       ${_TOTAL_FAILED}"
log "Directories OK:         ${_PASS}"
log "Directories failed:     ${_FAIL}"
log "======================================================="

if [[ ${#_FAILED_DIRS[@]} -gt 0 ]]; then
  log ""
  log "Failed directories:"
  for d in "${_FAILED_DIRS[@]}"; do
    log "  ${d}  (see ${OUTPUT_DIR}/${d}/.import.log)"
  done
fi

log ""

if [[ "${_FAIL}" -gt 0 ]]; then
  exit 1
fi
