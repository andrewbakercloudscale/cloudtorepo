#!/usr/bin/env bash
# Shared helpers for Terraclaim bats tests.
# Load with: load 'helpers/mock_aws'

# ---------------------------------------------------------------------------
# setup_mock_aws — installs a fake aws binary into a temp dir on PATH
# teardown_mock_aws — cleans up the temp dir
#
# The mock reads the commands it receives and returns canned JSON or text
# from the MOCK_AWS_RESPONSES associative array (set per-test).
# ---------------------------------------------------------------------------

setup_mock_aws() {
  export _TC_MOCK_DIR
  _TC_MOCK_DIR=$(mktemp -d)
  export _TC_OUTPUT_DIR
  _TC_OUTPUT_DIR=$(mktemp -d)

  # Write the mock aws script
  cat > "${_TC_MOCK_DIR}/aws" << 'MOCK_EOF'
#!/usr/bin/env bash
# Mock AWS CLI — returns fixture data based on the subcommand.
# Fixtures are looked up from files in _TC_MOCK_DIR/responses/.

# Strip global flags (--profile, --region, --output, --query, --no-paginate)
# to get a canonical key like "ec2 describe-instances"
_key=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile|--region|--output|--query|--no-paginate|--max-results|--next-token)
      shift 2 2>/dev/null || shift ;;
    --*)
      shift 2 2>/dev/null || shift ;;
    sts|ec2|ecs|eks|lambda|rds|s3|s3api|sqs|sns|iam|kms|secretsmanager|ssm|\
    elasticache|elb|elbv2|cloudfront|route53|acm|kafka|logs|events|wafv2|\
    cognito-idp|cognito-identity|kinesis|firehose|ecr|stepfunctions|configservice|\
    efs|opensearch|guardduty|backup|redshift|redshift-serverless|glue|sesv2|\
    codepipeline|codebuild|docdb|fsx|transfer|elasticbeanstalk|apprunner|\
    memorydb|athena|lakeformation|servicecatalog|lightsail|resourcegroupstaggingapi|\
    resource-explorer-2|emr|sagemaker|organizations|xray|appconfig|bedrock-agent)
      _svc="$1"; shift
      _cmd="$1"; shift 2>/dev/null || true
      _key="${_svc} ${_cmd}"
      break ;;
    *) shift ;;
  esac
done

_resp_file="${_TC_MOCK_DIR}/responses/${_key// /_}"
if [[ -f "${_resp_file}" ]]; then
  cat "${_resp_file}"
  exit 0
fi
# Default: return empty responses that won't crash the exporter
echo ""
exit 0
MOCK_EOF
  chmod +x "${_TC_MOCK_DIR}/aws"

  # Also mock terraform and jq so terraclaim.sh dependency checks pass
  cat > "${_TC_MOCK_DIR}/terraform" << 'EOF'
#!/usr/bin/env bash
if [[ "$1" == "version" ]]; then
  echo '{"terraform_version":"1.6.0"}'
fi
exit 0
EOF
  chmod +x "${_TC_MOCK_DIR}/terraform"

  # jq must be real — just make sure it's on PATH (it usually is)
  mkdir -p "${_TC_MOCK_DIR}/responses"
  export PATH="${_TC_MOCK_DIR}:${PATH}"
}

# Install a response fixture for a given service+command
# Usage: mock_response "ec2 describe-instances" '{"Reservations":[]}'
mock_response() {
  local key="${1// /_}"
  printf '%s\n' "$2" > "${_TC_MOCK_DIR}/responses/${key}"
}

teardown_mock_aws() {
  [[ -n "${_TC_MOCK_DIR:-}" ]] && rm -rf "${_TC_MOCK_DIR}"
  [[ -n "${_TC_OUTPUT_DIR:-}" ]] && rm -rf "${_TC_OUTPUT_DIR}"
}
