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

# ---------------------------------------------------------------------------
# --dry-run
# ---------------------------------------------------------------------------

@test "--dry-run exits 0 without requiring output dir" {
  run bash "${DRIFT}" \
    --dry-run \
    --accounts 123456789012 \
    --regions us-east-1 \
    --services ec2 \
    --output /nonexistent/path
  [ "$status" -eq 0 ]
}

@test "--dry-run does not write files even with --apply" {
  mock_response "ec2 describe-instances" "i-0new	new-server"
  run bash "${DRIFT}" \
    --dry-run \
    --apply \
    --accounts 123456789012 \
    --regions us-east-1 \
    --services ec2 \
    --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  # --apply should be suppressed: new resource should NOT appear in imports.tf
  local imports_tf="${_TC_OUTPUT_DIR}/123456789012/us-east-1/ec2/imports.tf"
  [ ! -f "${imports_tf}" ] || ! grep -q 'i-0new' "${imports_tf}"
}

# ---------------------------------------------------------------------------
# --services list
# ---------------------------------------------------------------------------

@test "--services list prints service names and exits 0" {
  run bash "${DRIFT}" --services list
  [ "$status" -eq 0 ]
  [[ "$output" =~ "ec2" ]]
  [[ "$output" =~ "s3" ]]
  [[ "$output" =~ "lambda" ]]
}

# ---------------------------------------------------------------------------
# scan_* function tests (via drift.sh wrapper)
# ---------------------------------------------------------------------------

@test "scan_s3 detects new bucket in AWS" {
  mkdir -p "${_TC_OUTPUT_DIR}/123456789012/us-east-1/s3"
  touch "${_TC_OUTPUT_DIR}/123456789012/us-east-1/s3/imports.tf"
  mock_response "s3api list-buckets" "my-new-bucket"
  mock_response "s3api get-bucket-location" "us-east-1"
  run bash "${DRIFT}" \
    --accounts 123456789012 \
    --regions us-east-1 \
    --services s3 \
    --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "NEW" ]] || [[ "$output" =~ "my-new-bucket" ]]
}

@test "scan_lambda detects new function in AWS" {
  mkdir -p "${_TC_OUTPUT_DIR}/123456789012/us-east-1/lambda"
  touch "${_TC_OUTPUT_DIR}/123456789012/us-east-1/lambda/imports.tf"
  mock_response "lambda list-functions" "$(printf 'my-fn\t2025-01-01T00:00:00.000+0000')"
  run bash "${DRIFT}" \
    --accounts 123456789012 \
    --regions us-east-1 \
    --services lambda \
    --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "NEW" ]] || [[ "$output" =~ "my-fn" ]]
}

@test "scan_rds detects new instance in AWS" {
  mkdir -p "${_TC_OUTPUT_DIR}/123456789012/us-east-1/rds"
  touch "${_TC_OUTPUT_DIR}/123456789012/us-east-1/rds/imports.tf"
  mock_response "rds describe-db-instances" "$(printf 'mydb\t2025-01-01')"
  mock_response "rds describe-db-clusters" ""
  run bash "${DRIFT}" \
    --accounts 123456789012 \
    --regions us-east-1 \
    --services rds \
    --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "NEW" ]] || [[ "$output" =~ "mydb" ]]
}

@test "scan_eks detects new cluster in AWS" {
  mkdir -p "${_TC_OUTPUT_DIR}/123456789012/us-east-1/eks"
  touch "${_TC_OUTPUT_DIR}/123456789012/us-east-1/eks/imports.tf"
  mock_response "eks list-clusters" "my-cluster"
  mock_response "eks list-nodegroups" ""
  mock_response "eks list-addons" ""
  mock_response "eks list-fargate-profiles" ""
  run bash "${DRIFT}" \
    --accounts 123456789012 \
    --regions us-east-1 \
    --services eks \
    --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "NEW" ]] || [[ "$output" =~ "my-cluster" ]]
}

@test "scan_emr detects new cluster in AWS" {
  mkdir -p "${_TC_OUTPUT_DIR}/123456789012/us-east-1/emr"
  touch "${_TC_OUTPUT_DIR}/123456789012/us-east-1/emr/imports.tf"
  mock_response "emr list-clusters" "$(printf 'j-ABC123\tMyCluster')"
  run bash "${DRIFT}" \
    --accounts 123456789012 --regions us-east-1 --services emr \
    --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "NEW" ]] || [[ "$output" =~ "j-ABC123" ]]
}

@test "scan_sagemaker detects new endpoint in AWS" {
  mkdir -p "${_TC_OUTPUT_DIR}/123456789012/us-east-1/sagemaker"
  touch "${_TC_OUTPUT_DIR}/123456789012/us-east-1/sagemaker/imports.tf"
  mock_response "sagemaker list-domains" ""
  mock_response "sagemaker list-endpoints" "my-endpoint"
  run bash "${DRIFT}" \
    --accounts 123456789012 --regions us-east-1 --services sagemaker \
    --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "NEW" ]] || [[ "$output" =~ "my-endpoint" ]]
}

@test "scan_organizations detects new account" {
  mkdir -p "${_TC_OUTPUT_DIR}/123456789012/us-east-1/organizations"
  touch "${_TC_OUTPUT_DIR}/123456789012/us-east-1/organizations/imports.tf"
  mock_response "organizations list-accounts" "$(printf '111111111111\tChildAccount')"
  run bash "${DRIFT}" \
    --accounts 123456789012 --regions us-east-1 --services organizations \
    --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "NEW" ]] || [[ "$output" =~ "111111111111" ]]
}

@test "scan_xray detects new group in AWS" {
  mkdir -p "${_TC_OUTPUT_DIR}/123456789012/us-east-1/xray"
  touch "${_TC_OUTPUT_DIR}/123456789012/us-east-1/xray/imports.tf"
  mock_response "xray get-groups" "$(printf 'MyGroup\tarn:aws:xray:us-east-1:123456789012:group/MyGroup')"
  mock_response "xray get-sampling-rules" ""
  run bash "${DRIFT}" \
    --accounts 123456789012 --regions us-east-1 --services xray \
    --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "NEW" ]] || [[ "$output" =~ "MyGroup" ]]
}

@test "scan_appconfig detects new application in AWS" {
  mkdir -p "${_TC_OUTPUT_DIR}/123456789012/us-east-1/appconfig"
  touch "${_TC_OUTPUT_DIR}/123456789012/us-east-1/appconfig/imports.tf"
  mock_response "appconfig list-applications" "$(printf 'app-abc\tMyApp')"
  mock_response "appconfig list-environments" ""
  run bash "${DRIFT}" \
    --accounts 123456789012 --regions us-east-1 --services appconfig \
    --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "NEW" ]] || [[ "$output" =~ "app-abc" ]]
}

@test "scan_bedrock detects new knowledge base in AWS" {
  mkdir -p "${_TC_OUTPUT_DIR}/123456789012/us-east-1/bedrock"
  touch "${_TC_OUTPUT_DIR}/123456789012/us-east-1/bedrock/imports.tf"
  mock_response "bedrock-agent list-knowledge-bases" "$(printf 'kb-12345\tMyKB')"
  mock_response "bedrock-agent list-agents" ""
  run bash "${DRIFT}" \
    --accounts 123456789012 --regions us-east-1 --services bedrock \
    --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "NEW" ]] || [[ "$output" =~ "kb-12345" ]]
}

@test "scan_connect detects new instance in AWS" {
  mkdir -p "${_TC_OUTPUT_DIR}/123456789012/us-east-1/connect"
  touch "${_TC_OUTPUT_DIR}/123456789012/us-east-1/connect/imports.tf"
  mock_response "connect list-instances" "inst-abc123"
  mock_response "connect list-contact-flows" ""
  run bash "${DRIFT}" \
    --accounts 123456789012 --regions us-east-1 --services connect \
    --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "NEW" ]] || [[ "$output" =~ "inst-abc123" ]]
}

@test "scan_ram detects new resource share in AWS" {
  mkdir -p "${_TC_OUTPUT_DIR}/123456789012/us-east-1/ram"
  touch "${_TC_OUTPUT_DIR}/123456789012/us-east-1/ram/imports.tf"
  mock_response "ram list-resource-shares" \
    "$(printf 'arn:aws:ram:us-east-1:123456789012:resource-share/share-xyz\tMyShare')"
  run bash "${DRIFT}" \
    --accounts 123456789012 --regions us-east-1 --services ram \
    --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "NEW" ]] || [[ "$output" =~ "share-xyz" ]]
}

@test "scan_servicequotas detects new quota override in AWS" {
  mkdir -p "${_TC_OUTPUT_DIR}/123456789012/us-east-1/servicequotas"
  touch "${_TC_OUTPUT_DIR}/123456789012/us-east-1/servicequotas/imports.tf"
  mock_response "service-quotas list-requested-services-by-requester" \
    "$(printf 'arn:aws:servicequotas:us-east-1:123456789012:ec2/L-1216C47A\tec2\tL-1216C47A')"
  run bash "${DRIFT}" \
    --accounts 123456789012 --regions us-east-1 --services servicequotas \
    --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "NEW" ]] || [[ "$output" =~ "ec2/L-1216C47A" ]]
}
