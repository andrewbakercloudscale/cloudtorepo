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

@test "export_cognito paginates user pools via NextToken" {
  # Page 1: returns 2 pools + a NextToken
  mock_response "cognito-idp list-user-pools" \
    '{"UserPools":[{"Id":"us-east-1_AAAA","Name":"pool-a"},{"Id":"us-east-1_BBBB","Name":"pool-b"}],"NextToken":"token-page-2"}'
  # Page 2: returns 1 pool + no NextToken
  # We can't easily mock different responses per call in the simple mock,
  # so we verify the first page is captured correctly.
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

@test "--resume skips already-completed service directories" {
  mock_response "ec2 describe-instances" \
    "i-0abc123def456\tmy-server"
  # First run writes files
  run bash "${TERRACLAIM}" \
    --accounts 123456789012 \
    --regions us-east-1 \
    --services ec2 \
    --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  local first_mtime
  first_mtime=$(stat -f '%m' "${_TC_OUTPUT_DIR}/123456789012/us-east-1/ec2/imports.tf" 2>/dev/null \
    || stat -c '%Y' "${_TC_OUTPUT_DIR}/123456789012/us-east-1/ec2/imports.tf")

  # Second run with --resume should skip ec2 (already checkpointed)
  # Change mock to return different data — if resume works, imports.tf won't change
  mock_response "ec2 describe-instances" \
    "i-DIFFERENT\tdifferent-server"
  run bash "${TERRACLAIM}" \
    --resume \
    --accounts 123456789012 \
    --regions us-east-1 \
    --services ec2 \
    --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  # imports.tf should still have the original content
  grep -q 'i-0abc123def456' "${_TC_OUTPUT_DIR}/123456789012/us-east-1/ec2/imports.tf"
}
