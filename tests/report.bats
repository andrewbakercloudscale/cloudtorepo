#!/usr/bin/env bats
# Tests for report.sh
# Run with: bats tests/report.bats

bats_require_minimum_version 1.5.0

REPORT="${BATS_TEST_DIRNAME}/../report.sh"

setup() {
  _TC_OUTPUT_DIR=$(mktemp -d)
  export _TC_OUTPUT_DIR

  # Build a minimal tf-output tree
  mkdir -p "${_TC_OUTPUT_DIR}/123456789012/us-east-1/ec2"
  mkdir -p "${_TC_OUTPUT_DIR}/123456789012/us-east-1/s3"
  mkdir -p "${_TC_OUTPUT_DIR}/123456789012/us-east-1/lambda"

  cat > "${_TC_OUTPUT_DIR}/123456789012/us-east-1/ec2/imports.tf" << 'EOF'
import {
  to = aws_instance.server1
  id = "i-0aaa"
}
import {
  to = aws_instance.server2
  id = "i-0bbb"
}
import {
  to = aws_instance.server3
  id = "i-0ccc"
}
EOF

  cat > "${_TC_OUTPUT_DIR}/123456789012/us-east-1/s3/imports.tf" << 'EOF'
import {
  to = aws_s3_bucket.mybucket
  id = "mybucket"
}
EOF

  cat > "${_TC_OUTPUT_DIR}/123456789012/us-east-1/lambda/imports.tf" << 'EOF'
import {
  to = aws_lambda_function.fn1
  id = "fn1"
}
import {
  to = aws_lambda_function.fn2
  id = "fn2"
}
EOF

  cat > "${_TC_OUTPUT_DIR}/summary.txt" << 'EOF'
Generated: 2026-03-25T10:00:00Z
Accounts: 123456789012
Regions: us-east-1
Total import blocks: 6
EOF
}

teardown() {
  [[ -n "${_TC_OUTPUT_DIR:-}" ]] && rm -rf "${_TC_OUTPUT_DIR}" || true
  [[ -n "${_DRIFT_FILE:-}" ]] && rm -f "${_DRIFT_FILE}" || true
}

# ---------------------------------------------------------------------------
# Basic output
# ---------------------------------------------------------------------------

@test "--help prints usage and exits 0" {
  run bash "${REPORT}" --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Usage:" ]]
}

@test "exits non-zero when output dir is missing" {
  run bash "${REPORT}" --output /nonexistent/path
  [ "$status" -ne 0 ]
  [[ "$output" =~ "not found" ]]
}

@test "exits non-zero when drift file is specified but missing" {
  run bash "${REPORT}" --output "${_TC_OUTPUT_DIR}" --drift /nonexistent/drift.txt
  [ "$status" -ne 0 ]
  [[ "$output" =~ "not found" ]]
}

@test "generates Markdown title from summary.txt" {
  run bash "${REPORT}" --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "# Terraclaim Infrastructure Report" ]]
}

@test "--title overrides the default report title" {
  run bash "${REPORT}" --output "${_TC_OUTPUT_DIR}" --title "My Custom Report"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "# My Custom Report" ]]
}

@test "summary table includes account and total count" {
  run bash "${REPORT}" --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "123456789012" ]]
  [[ "$output" =~ "6" ]]
}

# ---------------------------------------------------------------------------
# Per-service table
# ---------------------------------------------------------------------------

@test "resources table lists all three services" {
  run bash "${REPORT}" --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "ec2" ]]
  [[ "$output" =~ "s3" ]]
  [[ "$output" =~ "lambda" ]]
}

@test "resources table sorted by count descending (ec2=3 first, s3=1 last)" {
  run bash "${REPORT}" --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  # ec2 (3) should appear before s3 (1) in output
  local ec2_pos s3_pos
  ec2_pos=$(echo "$output" | grep -n 'ec2' | head -1 | cut -d: -f1)
  s3_pos=$(echo  "$output" | grep -n 's3'  | head -1 | cut -d: -f1)
  [ "${ec2_pos}" -lt "${s3_pos}" ]
}

@test "resources table shows correct import block counts" {
  run bash "${REPORT}" --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  # ec2 has 3, lambda has 2, s3 has 1
  echo "$output" | grep 'ec2' | grep -q '3'
  echo "$output" | grep 'lambda' | grep -q '2'
  echo "$output" | grep 's3' | grep -q '1'
}

# ---------------------------------------------------------------------------
# --out flag
# ---------------------------------------------------------------------------

@test "--out writes report to file instead of stdout" {
  local out_file; out_file=$(mktemp)
  run bash "${REPORT}" --output "${_TC_OUTPUT_DIR}" --out "${out_file}"
  [ "$status" -eq 0 ]
  # stdout should be empty (redirected to file)
  [ -z "$output" ]
  # file should contain the report
  grep -q "Terraclaim Infrastructure Report" "${out_file}"
  rm -f "${out_file}"
}

# ---------------------------------------------------------------------------
# Drift section
# ---------------------------------------------------------------------------

@test "drift section appears when --drift is supplied" {
  _DRIFT_FILE=$(mktemp)
  cat > "${_DRIFT_FILE}" << 'EOF'
Terraclaim Drift Report
Generated: 2026-03-25T10:00:00Z
Output dir: ./tf-output
Mode: report-only
===============================================
Summary
-----------------------------------------------
Unchanged:                3
New (not yet imported):   1
Removed (stale):          0
-----------------------------------------------
  1 123456789012 / us-east-1 / ec2
  NEW
    + aws_instance.new_server  (id: i-0newone)
EOF
  run bash "${REPORT}" --output "${_TC_OUTPUT_DIR}" --drift "${_DRIFT_FILE}"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Drift Report" ]]
  [[ "$output" =~ "Unchanged" ]]
}

@test "no-drift message shown when drift file has 0 new and 0 removed" {
  _DRIFT_FILE=$(mktemp)
  cat > "${_DRIFT_FILE}" << 'EOF'
Terraclaim Drift Report
Generated: 2026-03-25T10:00:00Z
Summary
Unchanged:                5
New (not yet imported):   0
Removed (stale):          0
EOF
  run bash "${REPORT}" --output "${_TC_OUTPUT_DIR}" --drift "${_DRIFT_FILE}"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "No drift detected" ]]
}

@test "next steps section always present" {
  run bash "${REPORT}" --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Next Steps" ]]
}
