#!/usr/bin/env bats
# Tests for drift.sh
# Run with: bats tests/drift.bats
# Requires bats-core >= 1.5: https://bats-core.readthedocs.io/

bats_require_minimum_version 1.5.0

DRIFT="${BATS_TEST_DIRNAME}/../drift.sh"

load 'helpers/mock_aws'

setup() {
  setup_mock_aws
  mock_response "sts get-caller-identity" \
    '{"Account":"123456789012","UserId":"AIDAEXAMPLE","Arn":"arn:aws:iam::123456789012:user/test"}'

  # Seed a minimal tf-output tree so drift.sh has something to compare against
  mkdir -p "${_TC_OUTPUT_DIR}/123456789012/us-east-1/ec2"
  cat > "${_TC_OUTPUT_DIR}/123456789012/us-east-1/ec2/imports.tf" << 'EOF'
# Auto-generated import blocks — do not edit by hand.

import {
  to = aws_instance.my_server
  id = "i-0existing"
}
EOF
}

teardown() {
  teardown_mock_aws
}

# ---------------------------------------------------------------------------
# Flag tests
# ---------------------------------------------------------------------------

@test "--help prints usage and exits 0" {
  run bash "${DRIFT}" --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Usage:" ]]
}

@test "--parallel rejects non-integer" {
  run bash "${DRIFT}" --parallel abc --output "${_TC_OUTPUT_DIR}"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "--parallel must be a positive integer" ]]
}

@test "exits with error if output dir missing" {
  run bash "${DRIFT}" --output /nonexistent/path
  [ "$status" -ne 0 ]
  [[ "$output" =~ "not found" ]]
}

# ---------------------------------------------------------------------------
# --profile flag
# ---------------------------------------------------------------------------

@test "--profile is accepted without error" {
  mock_response "ec2 describe-instances" ""
  run bash "${DRIFT}" \
    --profile myprofile \
    --accounts 123456789012 \
    --regions us-east-1 \
    --services ec2 \
    --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Drift detection
# ---------------------------------------------------------------------------

@test "reports NEW resource when present in AWS but not in imports.tf" {
  # EC2 returns a new instance not in the existing imports.tf
  mock_response "ec2 describe-instances" \
    "i-0brandnew	new-server"
  run bash "${DRIFT}" \
    --accounts 123456789012 \
    --regions us-east-1 \
    --services ec2 \
    --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "NEW" ]] || [[ "$output" =~ "i-0brandnew" ]]
}

@test "reports REMOVED resource when in imports.tf but gone from AWS" {
  # EC2 returns empty — i-0existing is no longer in AWS
  mock_response "ec2 describe-instances" ""
  run bash "${DRIFT}" \
    --accounts 123456789012 \
    --regions us-east-1 \
    --services ec2 \
    --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "REMOVED" ]] || [[ "$output" =~ "i-0existing" ]]
}

@test "reports no drift when imports.tf matches live AWS" {
  # EC2 returns exactly what's in imports.tf
  mock_response "ec2 describe-instances" \
    "i-0existing	my-server"
  run bash "${DRIFT}" \
    --accounts 123456789012 \
    --regions us-east-1 \
    --services ec2 \
    --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  # Should not report NEW or REMOVED
  [[ ! "$output" =~ "NEW" ]] || true
}

# ---------------------------------------------------------------------------
# --apply: add new and comment out stale blocks
# ---------------------------------------------------------------------------

@test "--apply appends new import block to imports.tf" {
  mock_response "ec2 describe-instances" \
    "i-0brandnew	new-server"
  run bash "${DRIFT}" \
    --apply \
    --accounts 123456789012 \
    --regions us-east-1 \
    --services ec2 \
    --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  local imports_tf="${_TC_OUTPUT_DIR}/123456789012/us-east-1/ec2/imports.tf"
  # New resource should now be in imports.tf
  grep -q 'i-0brandnew' "${imports_tf}"
}

@test "--apply comments out stale import block" {
  # EC2 returns empty — i-0existing is no longer in AWS
  mock_response "ec2 describe-instances" ""
  run bash "${DRIFT}" \
    --apply \
    --accounts 123456789012 \
    --regions us-east-1 \
    --services ec2 \
    --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  local imports_tf="${_TC_OUTPUT_DIR}/123456789012/us-east-1/ec2/imports.tf"
  # Stale block should be commented out, not deleted
  grep -q '# \[drift\.sh\]' "${imports_tf}"
  grep -q 'i-0existing' "${imports_tf}"
  # The active (non-commented) import block should be gone
  ! grep -q '^import {' "${imports_tf}"
}

@test "--apply preserves existing unchanged blocks" {
  # EC2 returns the existing resource plus a new one
  mock_response "ec2 describe-instances" \
    "$(printf 'i-0existing\tmy-server\ni-0new\tnew-server')"
  run bash "${DRIFT}" \
    --apply \
    --accounts 123456789012 \
    --regions us-east-1 \
    --services ec2 \
    --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  local imports_tf="${_TC_OUTPUT_DIR}/123456789012/us-east-1/ec2/imports.tf"
  # Original block must still be present and uncommented
  grep -q '^import {' "${imports_tf}"
  grep -q 'i-0existing' "${imports_tf}"
  # New block also appended
  grep -q 'i-0new' "${imports_tf}"
}
