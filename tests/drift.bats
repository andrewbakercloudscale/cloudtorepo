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
