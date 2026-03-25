#!/usr/bin/env bats
# Tests for reconcile.sh coverage calculation
# Run with: bats tests/reconcile.bats
# Requires bats-core >= 1.5: https://bats-core.readthedocs.io/

bats_require_minimum_version 1.5.0

RECONCILE="${BATS_TEST_DIRNAME}/../reconcile.sh"

load 'helpers/mock_aws'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Create a minimal tf-output tree with given imports.tf content
_make_output() {
  local dir="${_TC_OUTPUT_DIR}/123456789012/us-east-1/ec2"
  mkdir -p "${dir}"
  printf '%s\n' "$1" > "${dir}/imports.tf"
}

setup() {
  setup_mock_aws
  # Resource Explorer index check
  mock_response "resource-explorer-2 get-index" "AGGREGATOR"
}

teardown() {
  teardown_mock_aws
}

# ---------------------------------------------------------------------------
# Flag tests
# ---------------------------------------------------------------------------

@test "--help prints usage and exits 0" {
  run bash "${RECONCILE}" --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Usage:" ]]
}

@test "exits with error if output dir missing" {
  run bash "${RECONCILE}" --output /nonexistent/path
  [ "$status" -ne 0 ]
  [[ "$output" =~ "not found" ]]
}

@test "--dry-run exits 0 without querying Resource Explorer" {
  _make_output '# empty'
  run bash "${RECONCILE}" \
    --output "${_TC_OUTPUT_DIR}" \
    --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Dry run" ]]
}

# ---------------------------------------------------------------------------
# Coverage: simple IDs
# ---------------------------------------------------------------------------

@test "simple resource ID matches ARN last-slash segment" {
  _make_output 'import {
  to = aws_s3_bucket.my_bucket
  id = "my-bucket"
}'
  # Resource Explorer returns an ARN whose last slash segment is "my-bucket"
  mock_response "resource-explorer-2 search" '{
    "Resources": [
      {
        "Arn": "arn:aws:s3:::my-bucket",
        "ResourceType": "AWS::S3::Bucket",
        "Region": "us-east-1"
      }
    ]
  }'
  run bash "${RECONCILE}" \
    --output "${_TC_OUTPUT_DIR}" \
    --index-region us-east-1
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Coverage:" ]]
  # Should report 100% coverage (1/1 matched)
  [[ "$output" =~ "Coverage:                              100%" ]]
}

@test "ARN-as-ID resource matches directly" {
  local lb_arn="arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/my-lb/abc123"
  _make_output "import {
  to = aws_lb.my_lb
  id = \"${lb_arn}\"
}"
  mock_response "resource-explorer-2 search" "{
    \"Resources\": [
      {
        \"Arn\": \"${lb_arn}\",
        \"ResourceType\": \"AWS::ElasticLoadBalancingV2::LoadBalancer\",
        \"Region\": \"us-east-1\"
      }
    ]
  }"
  run bash "${RECONCILE}" \
    --output "${_TC_OUTPUT_DIR}" \
    --index-region us-east-1
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Coverage:                              100%" ]]
}

# ---------------------------------------------------------------------------
# Coverage: composite IDs
# ---------------------------------------------------------------------------

@test "composite colon ID (cluster:nodegroup) matches via token" {
  # terraclaim uses "cluster-name:nodegroup-name" as the EKS nodegroup import ID
  _make_output 'import {
  to = aws_eks_node_group.ng_my_cluster_my_ng
  id = "my-cluster:my-ng"
}'
  # Resource Explorer returns the nodegroup ARN; last slash segment is the ng UUID
  mock_response "resource-explorer-2 search" '{
    "Resources": [
      {
        "Arn": "arn:aws:eks:us-east-1:123456789012:nodegroup/my-cluster/my-ng/abc123",
        "ResourceType": "AWS::EKS::Nodegroup",
        "Region": "us-east-1"
      }
    ]
  }'
  run bash "${RECONCILE}" \
    --output "${_TC_OUTPUT_DIR}" \
    --index-region us-east-1
  [ "$status" -eq 0 ]
  # Token "my-cluster" or "my-ng" from the composite ID should match ARN segments
  [[ "$output" =~ "Coverage:" ]]
  # Should NOT report the nodegroup as completely missed (coverage > 0)
  [[ ! "$output" =~ "Coverage:                              0%" ]]
}

@test "unrelated resource is reported as missed" {
  _make_output 'import {
  to = aws_s3_bucket.my_bucket
  id = "my-bucket"
}'
  # Resource Explorer returns a completely different resource
  mock_response "resource-explorer-2 search" '{
    "Resources": [
      {
        "Arn": "arn:aws:ec2:us-east-1:123456789012:instance/i-0abc123",
        "ResourceType": "AWS::EC2::Instance",
        "Region": "us-east-1"
      }
    ]
  }'
  run bash "${RECONCILE}" \
    --output "${_TC_OUTPUT_DIR}" \
    --index-region us-east-1
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Potentially missed" ]]
}

# ---------------------------------------------------------------------------
# --local flag (no Resource Explorer required)
# ---------------------------------------------------------------------------

@test "--local shows per-service summary without querying Resource Explorer" {
  _make_output 'import {
  to = aws_instance.web
  id = "i-0abc123"
}

import {
  to = aws_instance.app
  id = "i-0def456"
}'
  run bash "${RECONCILE}" \
    --output "${_TC_OUTPUT_DIR}" \
    --local
  [ "$status" -eq 0 ]
  # Should show account/region/service breakdown without Resource Explorer output
  [[ "$output" =~ "ec2" ]]
  [[ "$output" =~ "2" ]]
  # Should NOT attempt Resource Explorer queries
  [[ ! "$output" =~ "Coverage:" ]]
}
