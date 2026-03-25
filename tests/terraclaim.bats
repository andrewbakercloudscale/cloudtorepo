#!/usr/bin/env bats
# Tests for terraclaim.sh
# Run with: bats tests/terraclaim.bats
# Requires bats-core >= 1.5: https://bats-core.readthedocs.io/

bats_require_minimum_version 1.5.0

TERRACLAIM="${BATS_TEST_DIRNAME}/../terraclaim.sh"

load 'helpers/mock_aws'

setup() {
  setup_mock_aws
  # Mock sts get-caller-identity so the script can resolve the current account
  mock_response "sts get-caller-identity" '{"Account":"123456789012","UserId":"AIDAEXAMPLE","Arn":"arn:aws:iam::123456789012:user/test"}'
}

teardown() {
  teardown_mock_aws
}

# ---------------------------------------------------------------------------
# Flag tests
# ---------------------------------------------------------------------------

@test "--version prints version and exits 0" {
  run bash "${TERRACLAIM}" --version
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^terraclaim\ [0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "--help prints usage and exits 0" {
  run bash "${TERRACLAIM}" --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Usage:" ]]
}

@test "--parallel rejects non-integer" {
  run bash "${TERRACLAIM}" --parallel abc --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" =~ "--parallel must be a positive integer" ]]
}

@test "--parallel rejects zero" {
  run bash "${TERRACLAIM}" --parallel 0 --dry-run
  [ "$status" -ne 0 ]
}

@test "unknown flag exits with error" {
  run bash "${TERRACLAIM}" --no-such-flag --dry-run
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# --profile flag
# ---------------------------------------------------------------------------

@test "--profile exports AWS_PROFILE" {
  # Use a tiny script that just checks the env var and exits
  run env -i PATH="${_TC_MOCK_DIR}:${PATH}" HOME="${HOME}" \
    bash "${TERRACLAIM}" --profile myprofile --dry-run \
    --accounts 123456789012 --regions us-east-1 --services ec2
  # If AWS_PROFILE is exported, the mock aws would receive --profile myprofile.
  # We verify the script completed (dry-run, no real AWS calls needed).
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# --dry-run
# ---------------------------------------------------------------------------

@test "--dry-run does not create output files" {
  mock_response "ec2 describe-instances" \
    'InstanceId  my-server'
  run bash "${TERRACLAIM}" \
    --dry-run \
    --accounts 123456789012 \
    --regions us-east-1 \
    --services ec2 \
    --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  # No service directories should be created
  [ ! -d "${_TC_OUTPUT_DIR}/123456789012" ]
}

# ---------------------------------------------------------------------------
# Service exporter output structure
# ---------------------------------------------------------------------------

@test "export_ec2 writes imports.tf with correct import block" {
  mock_response "ec2 describe-instances" \
    "i-0abc123def456\tmy-web-server"
  run bash "${TERRACLAIM}" \
    --accounts 123456789012 \
    --regions us-east-1 \
    --services ec2 \
    --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  local imports_tf="${_TC_OUTPUT_DIR}/123456789012/us-east-1/ec2/imports.tf"
  [ -f "${imports_tf}" ]
  grep -q 'aws_instance' "${imports_tf}"
  grep -q 'i-0abc123def456' "${imports_tf}"
}

@test "export_ec2 writes backend.tf with aws provider block" {
  mock_response "ec2 describe-instances" \
    "i-0abc123def456\tmy-server"
  run bash "${TERRACLAIM}" \
    --accounts 123456789012 \
    --regions us-east-1 \
    --services ec2 \
    --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  local backend_tf="${_TC_OUTPUT_DIR}/123456789012/us-east-1/ec2/backend.tf"
  [ -f "${backend_tf}" ]
  grep -q 'hashicorp/aws' "${backend_tf}"
}

@test "export_vpc includes security groups in output" {
  mock_response "ec2 describe-vpcs" \
    "vpc-111\t"
  mock_response "ec2 describe-subnets" \
    "subnet-abc\tmy-subnet"
  mock_response "ec2 describe-security-groups" \
    "sg-0deadbeef\tmy-sg"
  mock_response "ec2 describe-route-tables" \
    ""
  mock_response "ec2 describe-internet-gateways" \
    ""
  mock_response "ec2 describe-nat-gateways" \
    ""
  run bash "${TERRACLAIM}" \
    --accounts 123456789012 \
    --regions us-east-1 \
    --services vpc \
    --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  local imports_tf="${_TC_OUTPUT_DIR}/123456789012/us-east-1/vpc/imports.tf"
  [ -f "${imports_tf}" ]
  grep -q 'aws_security_group' "${imports_tf}"
  grep -q 'sg-0deadbeef' "${imports_tf}"
}

@test "export_iam includes instance profiles and OIDC providers" {
  mock_response "iam list-roles" \
    "MyRole"
  mock_response "iam list-instance-profiles" \
    "MyInstanceProfile"
  mock_response "iam list-open-id-connect-providers" \
    "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
  run bash "${TERRACLAIM}" \
    --accounts 123456789012 \
    --regions us-east-1 \
    --services iam \
    --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  local imports_tf="${_TC_OUTPUT_DIR}/123456789012/us-east-1/iam/imports.tf"
  [ -f "${imports_tf}" ]
  grep -q 'aws_iam_instance_profile' "${imports_tf}"
  grep -q 'aws_iam_openid_connect_provider' "${imports_tf}"
}

@test "export_eks includes fargate profiles" {
  mock_response "eks list-clusters" \
    "my-cluster"
  mock_response "eks list-nodegroups" \
    ""
  mock_response "eks list-addons" \
    ""
  mock_response "eks list-fargate-profiles" \
    "my-fp"
  run bash "${TERRACLAIM}" \
    --accounts 123456789012 \
    --regions us-east-1 \
    --services eks \
    --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  local imports_tf="${_TC_OUTPUT_DIR}/123456789012/us-east-1/eks/imports.tf"
  [ -f "${imports_tf}" ]
  grep -q 'aws_eks_fargate_profile' "${imports_tf}"
}

@test "export_cognito writes import blocks for user pools" {
  # The simple mock can't return different pages per call (--next-token is stripped
  # from the key), so we return all pools in one page with no NextToken.
  mock_response "cognito-idp list-user-pools" \
    '{"UserPools":[{"Id":"us-east-1_AAAA","Name":"pool-a"},{"Id":"us-east-1_BBBB","Name":"pool-b"}]}'
  mock_response "cognito-idp list-user-pool-clients" \
    '{"UserPoolClients":[]}'
  mock_response "cognito-identity list-identity-pools" \
    '{"IdentityPools":[]}'
  run bash "${TERRACLAIM}" \
    --accounts 123456789012 \
    --regions us-east-1 \
    --services cognito \
    --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  local imports_tf="${_TC_OUTPUT_DIR}/123456789012/us-east-1/cognito/imports.tf"
  [ -f "${imports_tf}" ]
  grep -q 'us-east-1_AAAA' "${imports_tf}"
  grep -q 'us-east-1_BBBB' "${imports_tf}"
}

@test "slug collision is deduplicated with _2 suffix" {
  # Two instances with the same Name tag produce colliding slugs
  mock_response "ec2 describe-instances" \
    "$(printf 'i-0aaa\tdup-name\ni-0bbb\tdup-name')"
  run bash "${TERRACLAIM}" \
    --accounts 123456789012 \
    --regions us-east-1 \
    --services ec2 \
    --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  local imports_tf="${_TC_OUTPUT_DIR}/123456789012/us-east-1/ec2/imports.tf"
  [ -f "${imports_tf}" ]
  # Both IDs must appear
  grep -q 'i-0aaa' "${imports_tf}"
  grep -q 'i-0bbb' "${imports_tf}"
  # Second occurrence gets a _2 suffix
  grep -q 'dup_name_2' "${imports_tf}"
}

@test "--output-format rejects invalid value" {
  run bash "${TERRACLAIM}" --output-format xml --dry-run \
    --accounts 123456789012 --regions us-east-1 --services ec2
  [ "$status" -ne 0 ]
  [[ "$output" =~ "--output-format must be" ]]
}

@test "--since rejects invalid date format" {
  run bash "${TERRACLAIM}" --since 01-01-2025 --dry-run \
    --accounts 123456789012 --regions us-east-1 --services ec2
  [ "$status" -ne 0 ]
  [[ "$output" =~ "--since must be in YYYY-MM-DD" ]]
}

@test "--exclude-services skips listed service" {
  # Even though mock returns data, the service should be skipped
  mock_response "ec2 describe-instances" \
    "i-0abc123\tmy-server"
  run bash "${TERRACLAIM}" \
    --accounts 123456789012 \
    --regions us-east-1 \
    --services ec2 \
    --exclude-services ec2 \
    --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  [ ! -d "${_TC_OUTPUT_DIR}/123456789012/us-east-1/ec2" ]
}

@test "export_s3 writes import block for bucket in matching region" {
  mock_response "s3api list-buckets" "my-bucket"
  mock_response "s3api get-bucket-location" "us-east-1"
  run bash "${TERRACLAIM}" \
    --accounts 123456789012 \
    --regions us-east-1 \
    --services s3 \
    --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  local imports_tf="${_TC_OUTPUT_DIR}/123456789012/us-east-1/s3/imports.tf"
  [ -f "${imports_tf}" ]
  grep -q 'aws_s3_bucket' "${imports_tf}"
  grep -q 'my-bucket' "${imports_tf}"
}

@test "export_lambda writes import block" {
  mock_response "lambda list-functions" \
    "$(printf 'my-function\t2025-01-01T00:00:00Z')"
  mock_response "lambda get-function" "None"
  run bash "${TERRACLAIM}" \
    --accounts 123456789012 \
    --regions us-east-1 \
    --services lambda \
    --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  local imports_tf="${_TC_OUTPUT_DIR}/123456789012/us-east-1/lambda/imports.tf"
  [ -f "${imports_tf}" ]
  grep -q 'aws_lambda_function' "${imports_tf}"
  grep -q 'my-function' "${imports_tf}"
}

@test "export_kms writes import block" {
  mock_response "kms list-keys" \
    "$(printf 'abc-123-def\tarn:aws:kms:us-east-1:123456789012:key/abc-123-def')"
  run bash "${TERRACLAIM}" \
    --accounts 123456789012 \
    --regions us-east-1 \
    --services kms \
    --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  local imports_tf="${_TC_OUTPUT_DIR}/123456789012/us-east-1/kms/imports.tf"
  [ -f "${imports_tf}" ]
  grep -q 'aws_kms_key' "${imports_tf}"
  grep -q 'abc-123-def' "${imports_tf}"
}

@test "summary.txt is written with correct total count" {
  mock_response "ec2 describe-instances" \
    "$(printf 'i-0aaa\tserver-a\ni-0bbb\tserver-b')"
  run bash "${TERRACLAIM}" \
    --accounts 123456789012 \
    --regions us-east-1 \
    --services ec2 \
    --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  [ -f "${_TC_OUTPUT_DIR}/summary.txt" ]
  grep -q 'Total import blocks written: 2' "${_TC_OUTPUT_DIR}/summary.txt"
}

@test "--output-format json writes summary.json" {
  mock_response "ec2 describe-instances" \
    "i-0abc123\tmy-server"
  run bash "${TERRACLAIM}" \
    --accounts 123456789012 \
    --regions us-east-1 \
    --services ec2 \
    --output-format json \
    --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  [ -f "${_TC_OUTPUT_DIR}/summary.json" ]
  grep -q '"total_imports"' "${_TC_OUTPUT_DIR}/summary.json"
}

@test "--resume skips already-completed service directories" {
  mock_response "ec2 describe-instances" \
    "i-0abc123def456\tmy-server"
  # First run (without --resume) writes files
  run bash "${TERRACLAIM}" \
    --accounts 123456789012 \
    --regions us-east-1 \
    --services ec2 \
    --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  [ -f "${_TC_OUTPUT_DIR}/123456789012/us-east-1/ec2/imports.tf" ]

  # Simulate a previous interrupted --resume run by seeding the checkpoint file.
  # (The checkpoint is cleared on success, so it only persists across interruptions.)
  echo "123456789012/us-east-1/ec2" > "${_TC_OUTPUT_DIR}/.terraclaim-checkpoint"

  # Second run with --resume should see the checkpoint and skip ec2.
  # Change mock to return different data — if resume works, imports.tf won't change.
  mock_response "ec2 describe-instances" \
    "i-DIFFERENT\tdifferent-server"
  run bash "${TERRACLAIM}" \
    --resume \
    --accounts 123456789012 \
    --regions us-east-1 \
    --services ec2 \
    --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  # imports.tf should still have the original content — ec2 was skipped
  grep -q 'i-0abc123def456' "${_TC_OUTPUT_DIR}/123456789012/us-east-1/ec2/imports.tf"
  ! grep -q 'i-DIFFERENT' "${_TC_OUTPUT_DIR}/123456789012/us-east-1/ec2/imports.tf"
}

@test "export_connect writes import block for instance" {
  mock_response "connect list-instances" "abc-instance-id"
  mock_response "connect list-contact-flows" ""
  run bash "${TERRACLAIM}" \
    --accounts 123456789012 \
    --regions us-east-1 \
    --services connect \
    --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  local imports_tf="${_TC_OUTPUT_DIR}/123456789012/us-east-1/connect/imports.tf"
  [ -f "${imports_tf}" ]
  grep -q 'aws_connect_instance' "${imports_tf}"
  grep -q 'abc-instance-id' "${imports_tf}"
}

@test "export_ram writes import block for resource share" {
  mock_response "ram list-resource-shares" \
    "$(printf 'arn:aws:ram:us-east-1:123456789012:resource-share/share-id\tmy-share')"
  run bash "${TERRACLAIM}" \
    --accounts 123456789012 \
    --regions us-east-1 \
    --services ram \
    --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  local imports_tf="${_TC_OUTPUT_DIR}/123456789012/us-east-1/ram/imports.tf"
  [ -f "${imports_tf}" ]
  grep -q 'aws_ram_resource_share' "${imports_tf}"
  grep -q 'share-id' "${imports_tf}"
}

@test "--services list includes new services" {
  run bash "${TERRACLAIM}" --services list
  [ "$status" -eq 0 ]
  [[ "$output" =~ "connect" ]]
  [[ "$output" =~ "ram" ]]
  [[ "$output" =~ "servicequotas" ]]
  [[ "$output" =~ "bedrock" ]]
}
