#!/usr/bin/env bash
# report.sh — Generate a Markdown summary report from a terraclaim output directory.
#
# Reads the directory structure produced by terraclaim.sh and optionally a drift
# report file produced by drift.sh --report, then writes a Markdown document.
#
# Requirements: bash 3.2+, awk, sort, grep
#
# Usage:
#   ./report.sh [OPTIONS]
#
# Options:
#   --output  "./tf-output"   Output directory from terraclaim.sh  (required)
#   --drift   "./drift.txt"   Drift report file from drift.sh --report (optional)
#   --title   "My Report"     Report title (default: "Terraclaim Infrastructure Report")
#   --out     "./report.md"   Write report to file instead of stdout
#   --help                    Show this help

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
OUTPUT_DIR="./tf-output"
DRIFT_FILE=""
TITLE="Terraclaim Infrastructure Report"
OUT_FILE=""

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
die() { echo "[ERROR] $*" >&2; exit 1; }

usage() {
  grep '^#' "$0" | grep -v '^#!' | sed 's/^# \{0,1\}//'
  exit 0
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) OUTPUT_DIR="$2"; shift 2 ;;
    --drift)  DRIFT_FILE="$2"; shift 2 ;;
    --title)  TITLE="$2";      shift 2 ;;
    --out)    OUT_FILE="$2";   shift 2 ;;
    --help|-h) usage ;;
    *) die "Unknown option: $1 — run with --help for usage." ;;
  esac
done

[[ -d "${OUTPUT_DIR}" ]] || die "Output directory not found: ${OUTPUT_DIR}"
[[ -n "${DRIFT_FILE}" && ! -f "${DRIFT_FILE}" ]] && die "Drift file not found: ${DRIFT_FILE}"

# ---------------------------------------------------------------------------
# Redirect stdout to file if --out specified
# ---------------------------------------------------------------------------
if [[ -n "${OUT_FILE}" ]]; then
  exec > "${OUT_FILE}"
fi

# ---------------------------------------------------------------------------
# Read terraclaim summary metadata
# ---------------------------------------------------------------------------
SUMMARY_FILE="${OUTPUT_DIR}/summary.txt"
GENERATED=""
ACCOUNTS=""
REGIONS=""
TOTAL_IMPORTS=0

if [[ -f "${SUMMARY_FILE}" ]]; then
  GENERATED=$(grep '^Generated:' "${SUMMARY_FILE}" | sed 's/^Generated:[[:space:]]*//' || true)
  ACCOUNTS=$(grep  '^Accounts:'  "${SUMMARY_FILE}" | sed 's/^Accounts:[[:space:]]*//'  || true)
  REGIONS=$(grep   '^Regions:'   "${SUMMARY_FILE}" | sed 's/^Regions:[[:space:]]*//'   || true)
  TOTAL_IMPORTS=$(grep '^Total import blocks' "${SUMMARY_FILE}" | grep -o '[0-9]*' || echo 0)
fi

[[ -z "${GENERATED}" ]] && GENERATED=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# ---------------------------------------------------------------------------
# Build per-account / per-region / per-service breakdown
# ---------------------------------------------------------------------------
# Collect: account region service count
rows=()
while IFS= read -r imports_tf; do
  count=$(grep -c '^import {' "${imports_tf}" 2>/dev/null || true)
  [[ "${count}" -eq 0 ]] && continue
  # Path: OUTPUT_DIR/{account}/{region}/{service}/imports.tf
  rel="${imports_tf#${OUTPUT_DIR}/}"
  account=$(echo "${rel}" | cut -d/ -f1)
  region=$(echo  "${rel}" | cut -d/ -f2)
  service=$(echo "${rel}" | cut -d/ -f3)
  rows+=("${account}	${region}	${service}	${count}")
done < <(find "${OUTPUT_DIR}" -name 'imports.tf' | sort)

# ---------------------------------------------------------------------------
# Emit Markdown
# ---------------------------------------------------------------------------
cat <<EOF
# ${TITLE}

**Generated:** ${GENERATED}
**Output directory:** \`${OUTPUT_DIR}\`

---

## Summary

| | |
|---|---|
| **Account(s)** | \`${ACCOUNTS}\` |
| **Region(s)** | ${REGIONS} |
| **Total import blocks** | **${TOTAL_IMPORTS}** |

EOF

# ---------------------------------------------------------------------------
# Per-account totals (only shown when more than one account present)
# ---------------------------------------------------------------------------
if [[ ${#rows[@]} -gt 0 ]]; then
  # Collect unique accounts
  unique_accounts=()
  while IFS=$'\t' read -r account _r _s _c; do
    _found=false
    for _a in "${unique_accounts[@]+"${unique_accounts[@]}"}"; do
      [[ "${_a}" == "${account}" ]] && { _found=true; break; }
    done
    "${_found}" || unique_accounts+=("${account}")
  done < <(printf '%s\n' "${rows[@]}" | sort -t$'\t' -k1,1)

  if [[ ${#unique_accounts[@]} -gt 1 ]]; then
    echo "## Account Totals"
    echo ""
    echo "| Account | Import blocks |"
    echo "|---------|--------------|"
    for _acct in "${unique_accounts[@]}"; do
      _acct_total=0
      while IFS=$'\t' read -r _a _r _s count; do
        [[ "${_a}" == "${_acct}" ]] && _acct_total=$((_acct_total + count))
      done < <(printf '%s\n' "${rows[@]}")
      printf "| \`%s\` | %d |\n" "${_acct}" "${_acct_total}"
    done
    echo ""
  fi
fi

# ---------------------------------------------------------------------------
# Per-region breakdown table
# ---------------------------------------------------------------------------
if [[ ${#rows[@]} -gt 0 ]]; then
  echo "## Resources by Service"
  echo ""

  current_region=""
  current_account=""

  # Sort rows: account, region, then by count descending
  while IFS=$'\t' read -r account region service count; do
    header="${account} / ${region}"
    if [[ "${header}" != "${current_account} / ${current_region}" ]]; then
      # Close previous table if open
      if [[ -n "${current_region}" ]]; then
        echo ""
      fi
      echo "### ${account} / ${region}"
      echo ""
      echo "| Service | Import blocks |"
      echo "|---------|--------------|"
      current_region="${region}"
      current_account="${account}"
    fi
    printf "| \`%s\` | %d |\n" "${service}" "${count}"
  done < <(printf '%s\n' "${rows[@]}" | sort -t$'\t' -k1,1 -k2,2 -k4,4rn)

  echo ""

  # Cross-account service totals (only when more than one account)
  if [[ ${#unique_accounts[@]} -gt 1 ]]; then
    echo "## Cross-Account Service Totals"
    echo ""
    echo "| Service | Import blocks |"
    echo "|---------|--------------|"
    # Aggregate by service across all accounts/regions
    declare -A _svc_totals 2>/dev/null || true
    while IFS=$'\t' read -r _a _r service count; do
      _svc_totals["${service}"]=$(( ${_svc_totals["${service}"]:-0} + count ))
    done < <(printf '%s\n' "${rows[@]}")
    # Sort by count descending
    for svc in "${!_svc_totals[@]}"; do
      printf '%d\t%s\n' "${_svc_totals[${svc}]}" "${svc}"
    done | sort -rn | while IFS=$'\t' read -r count svc; do
      printf "| \`%s\` | %d |\n" "${svc}" "${count}"
    done
    echo ""
    unset _svc_totals
  fi
fi

# ---------------------------------------------------------------------------
# Drift section
# ---------------------------------------------------------------------------
if [[ -n "${DRIFT_FILE}" ]]; then
  echo "---"
  echo ""
  echo "## Drift Report"
  echo ""

  # Parse counts from drift summary block
  drift_unchanged=$(grep  'Unchanged:'            "${DRIFT_FILE}" | grep -o '[0-9]*' | head -1 || echo 0)
  drift_new=$(grep        'New (not yet imported)' "${DRIFT_FILE}" | grep -o '[0-9]*' | head -1 || echo 0)
  drift_removed=$(grep    'Removed (stale):'      "${DRIFT_FILE}" | grep -o '[0-9]*' | head -1 || echo 0)

  echo "| Status | Count |"
  echo "|--------|-------|"
  printf "| Unchanged | %d |\n"              "${drift_unchanged}"
  printf "| New (not yet imported) | %d |\n" "${drift_new}"
  printf "| Removed (stale) | %d |\n"        "${drift_removed}"
  echo ""

  # Emit any NEW/REMOVED detail blocks
  in_detail=false
  while IFS= read -r line; do
    # Section headers: "  account / region / service"
    if [[ "${line}" =~ ^[[:space:]]{2}[0-9]+[[:space:]] ]]; then
      echo "### ${line## }"
      in_detail=true
      continue
    fi
    # Separator lines — must come before the +/- resource check
    [[ "${line}" =~ ^[[:space:]]*-{10,} ]] && continue
    [[ "${line}" =~ ^={10,} ]] && continue
    # NEW / REMOVED labels
    if [[ "${line}" =~ ^[[:space:]]*(NEW|REMOVED) ]]; then
      label="${line#"${line%%[![:space:]]*}"}"  # ltrim
      echo "**${label}**"
      echo ""
      continue
    fi
    # Resource lines starting with + or -
    if [[ "${line}" =~ ^[[:space:]]*[\+\-] ]]; then
      trimmed="${line#"${line%%[![:space:]]*}"}"
      echo "- \`${trimmed}\`"
      continue
    fi
  done < <(grep -v '^Summary' "${DRIFT_FILE}" | grep -v '^---' | grep -v '^Unchanged' | \
           grep -v 'New (not yet' | grep -v 'Removed (stale)' | grep -v '^Run with' | \
           grep -v '^Terraclaim Drift' | grep -v '^Generated:' | grep -v '^Output dir' | \
           grep -v '^Mode:')

  if [[ "${in_detail}" == "false" && "${drift_new}" -eq 0 && "${drift_removed}" -eq 0 ]]; then
    echo "> No drift detected — all resources match."
    echo ""
  fi
fi

# ---------------------------------------------------------------------------
# Next steps
# ---------------------------------------------------------------------------
cat <<'EOF'
---

## Next Steps

1. For each service directory, run `terraform init`
2. Then `terraform plan -generate-config-out=generated.tf`
3. Review `generated.tf` — remove computed / read-only attributes
4. Run `reconcile.sh` to check coverage against AWS Resource Explorer
5. Commit the baseline on a `baseline-import` branch
6. Run `drift.sh` regularly (or in CI) to catch out-of-band changes
EOF
