#!/usr/bin/env bash
# sync.sh — Deploy index.html to S3 and invalidate CloudFront.
#
# Uploads the cloudtorepo.com homepage to the S3 bucket and creates a
# CloudFront invalidation so changes are live within ~30 seconds.
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
INDEX="${SCRIPT_DIR}/index.html"

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

  [[ -f "${INDEX}" ]] || { echo "[ERROR] index.html not found at ${INDEX}" >&2; exit 1; }

  echo "[INFO]  Uploading index.html to s3://${BUCKET}/ ..."
  aws s3 cp "${INDEX}" "s3://${BUCKET}/index.html" --profile "${PROFILE}"

  echo "[INFO]  Uploading image assets to s3://${BUCKET}/ ..."
  aws s3 sync "${SCRIPT_DIR}" "s3://${BUCKET}/" \
    --profile "${PROFILE}" \
    --exclude "*" \
    --include "*.png" \
    --include "*.jpg" \
    --include "*.jpeg" \
    --include "*.svg" \
    --include "*.webp" \
    --include "*.ico"

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
