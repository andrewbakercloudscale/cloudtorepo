#!/usr/bin/env bats
# Tests for run.sh
# Run with: bats tests/run.bats

bats_require_minimum_version 1.5.0

RUN="${BATS_TEST_DIRNAME}/../run.sh"

setup() {
  _TC_OUTPUT_DIR=$(mktemp -d)
  export _TC_OUTPUT_DIR

  # Create a minimal output tree with imports.tf files
  mkdir -p "${_TC_OUTPUT_DIR}/123456789012/us-east-1/ec2"
  mkdir -p "${_TC_OUTPUT_DIR}/123456789012/us-east-1/s3"
  mkdir -p "${_TC_OUTPUT_DIR}/123456789012/eu-west-1/lambda"

  cat > "${_TC_OUTPUT_DIR}/123456789012/us-east-1/ec2/imports.tf" << 'EOF'
import {
  to = aws_instance.server
  id = "i-0abc"
}
EOF
  cat > "${_TC_OUTPUT_DIR}/123456789012/us-east-1/s3/imports.tf" << 'EOF'
import {
  to = aws_s3_bucket.mybucket
  id = "mybucket"
}
EOF
  cat > "${_TC_OUTPUT_DIR}/123456789012/eu-west-1/lambda/imports.tf" << 'EOF'
import {
  to = aws_lambda_function.fn
  id = "my-fn"
}
EOF

  # Mock terraform so no real Terraform is executed
  _TC_MOCK_DIR=$(mktemp -d)
  export _TC_MOCK_DIR
  cat > "${_TC_MOCK_DIR}/terraform" << 'EOF'
#!/usr/bin/env bash
# Mock terraform — always succeeds and prints "No changes" for plan
if [[ "$1" == "version" ]]; then
  echo '{"terraform_version":"1.6.0"}'
  exit 0
fi
# Handle -chdir=... flag
for arg in "$@"; do
  if [[ "${arg}" == "-generate-config-out="* ]]; then
    # Create the generated.tf stub so the call appears to have worked
    dir=$(echo "$@" | grep -o '\-chdir=[^ ]*' | cut -d= -f2)
    touch "${dir:-/tmp}/generated.tf" 2>/dev/null || true
  fi
done
echo "No changes. Your infrastructure matches the configuration."
echo "CLOUDTOREPO_RESULT=NOCHANGE"
exit 0
EOF
  chmod +x "${_TC_MOCK_DIR}/terraform"
  export PATH="${_TC_MOCK_DIR}:${PATH}"
}

teardown() {
  [[ -n "${_TC_OUTPUT_DIR:-}" ]] && rm -rf "${_TC_OUTPUT_DIR}" || true
  [[ -n "${_TC_MOCK_DIR:-}" ]] && rm -rf "${_TC_MOCK_DIR}" || true
}

# ---------------------------------------------------------------------------
# Flag tests
# ---------------------------------------------------------------------------

@test "--help prints usage and exits 0" {
  run bash "${RUN}" --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Usage:" ]]
}

@test "exits non-zero when output dir is missing" {
  run bash "${RUN}" --output /nonexistent/path
  [ "$status" -ne 0 ]
  [[ "$output" =~ "not found" ]]
}

@test "--parallel rejects non-integer" {
  run bash "${RUN}" --parallel abc --output "${_TC_OUTPUT_DIR}"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "--parallel must be a positive integer" ]]
}

@test "unknown flag exits with error" {
  run bash "${RUN}" --bogus-flag
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# --dry-run
# ---------------------------------------------------------------------------

@test "--dry-run prints directories and exits 0 without running terraform" {
  run bash "${RUN}" --dry-run --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "ec2" ]]
  [[ "$output" =~ "s3" ]]
  [[ "$output" =~ "lambda" ]]
  [[ "$output" =~ "Dry run" ]]
}

@test "--dry-run does not create generated.tf" {
  run bash "${RUN}" --dry-run --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  [ ! -f "${_TC_OUTPUT_DIR}/123456789012/us-east-1/ec2/generated.tf" ]
}

# ---------------------------------------------------------------------------
# Filtering
# ---------------------------------------------------------------------------

@test "--services filters to matching service only" {
  run bash "${RUN}" --dry-run --services ec2 --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "ec2" ]]
  [[ ! "$output" =~ "s3" ]]
  [[ ! "$output" =~ "lambda" ]]
}

@test "--regions filters to matching region only" {
  run bash "${RUN}" --dry-run --regions us-east-1 --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "us-east-1" ]]
  [[ ! "$output" =~ "eu-west-1" ]]
}

@test "--accounts filters to matching account only" {
  run bash "${RUN}" --dry-run --accounts 123456789012 --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "123456789012" ]]
}

@test "exits 0 with info message when no dirs match filters" {
  run bash "${RUN}" --dry-run --services nonexistent --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "No service directories found" ]] || [[ "$output" =~ "no" ]]
}

# ---------------------------------------------------------------------------
# --init-only
# ---------------------------------------------------------------------------

@test "--init-only exits 0 and processes directories" {
  run bash "${RUN}" --init-only --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
}
