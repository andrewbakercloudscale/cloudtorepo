#!/usr/bin/env bash
# sync.sh — Deploy site files to S3 and invalidate CloudFront.
#
# Uploads all HTML, CSS, and static assets for cloudtorepo.com to the S3
# bucket and creates a CloudFront invalidation so changes are live within
# ~30 seconds.
#
# Requirements: aws-cli >= 2, personal AWS CLI profile configured
#
# Usage:
#   ./sync.sh [-h|--help]

set -euo pipefail

BUCKET="cloudtorepo"
DISTRIBUTION_ID="ETOGUVSRE5GDD"
PROFILE="personal"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  grep '^#' "$0" | grep -v '^#!' | sed 's/^# \{0,1\}//'
  exit 0
}

function main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage ;;
      *) echo "[ERROR] Unknown option: $1" >&2; usage ;;
    esac
    shift
  done

  command -v aws &>/dev/null || { echo "[ERROR] aws-cli not found — install from https://aws.amazon.com/cli/" >&2; exit 1; }

  echo "[INFO]  Syncing HTML and CSS to s3://${BUCKET}/ ..."
  aws s3 sync "${SCRIPT_DIR}" "s3://${BUCKET}/" \
    --profile "${PROFILE}" \
    --exclude "*" \
    --include "*.html" \
    --include "*.css"

  echo "[INFO]  Syncing static assets to s3://${BUCKET}/ ..."
  aws s3 sync "${SCRIPT_DIR}" "s3://${BUCKET}/" \
    --profile "${PROFILE}" \
    --exclude "*" \
    --include "*.png" \
    --include "*.jpg" \
    --include "*.jpeg" \
    --include "*.svg" \
    --include "*.webp" \
    --include "*.ico" \
    --include "*.txt"

  echo "[INFO]  Creating CloudFront invalidation for distribution ${DISTRIBUTION_ID} ..."
  INVALIDATION_ID=$(aws cloudfront create-invalidation \
    --distribution-id "${DISTRIBUTION_ID}" \
    --paths "/*" \
    --profile "${PROFILE}" \
    --query 'Invalidation.Id' \
    --output text)

  echo "[INFO]  Invalidation ${INVALIDATION_ID} created."
  echo "[INFO]  cloudtorepo.com will be updated within ~30 seconds."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
  exit 0
fi
