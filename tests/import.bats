#!/usr/bin/env bats
# Tests for import.sh
# Run with: bats tests/import.bats

bats_require_minimum_version 1.5.0

IMPORT="${BATS_TEST_DIRNAME}/../import.sh"

setup() {
  _TC_OUTPUT_DIR=$(mktemp -d)
  export _TC_OUTPUT_DIR

  # Minimal output tree
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

  # Mock terraform
  _TC_MOCK_DIR=$(mktemp -d)
  export _TC_MOCK_DIR
  cat > "${_TC_MOCK_DIR}/terraform" << 'EOF'
#!/usr/bin/env bash
# Parse -chdir=DIR from args
_chdir=""
_args=()
for arg in "$@"; do
  if [[ "${arg}" == -chdir=* ]]; then
    _chdir="${arg#-chdir=}"
  else
    _args+=("${arg}")
  fi
done

subcmd="${_args[0]:-}"

case "${subcmd}" in
  init)
    exit 0
    ;;
  state)
    # state list — check for a "in_state" marker file in the dir
    if [[ -n "${_chdir}" && -f "${_chdir}/.mock_in_state" ]]; then
      cat "${_chdir}/.mock_in_state"
    fi
    exit 0
    ;;
  import)
    # Record the import call
    echo "imported: ${_args[*]}" >> "${_TC_MOCK_DIR}/import_calls.log"
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
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
  run bash "${IMPORT}" --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Usage:" ]]
}

@test "exits non-zero when output dir is missing" {
  run bash "${IMPORT}" --output /nonexistent/path
  [ "$status" -ne 0 ]
  [[ "$output" =~ "not found" ]]
}

@test "--parallel rejects non-integer" {
  run bash "${IMPORT}" --parallel abc --output "${_TC_OUTPUT_DIR}"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "--parallel must be a positive integer" ]]
}

@test "unknown flag exits with error" {
  run bash "${IMPORT}" --bogus-flag
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# --dry-run
# ---------------------------------------------------------------------------

@test "--dry-run prints what would be imported without running terraform" {
  run bash "${IMPORT}" --dry-run --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Dry run" ]]
  [[ "$output" =~ aws_instance.server ]]
  [[ "$output" =~ aws_s3_bucket.mybucket ]]
}

@test "--dry-run does not call terraform import" {
  run bash "${IMPORT}" --dry-run --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  [ ! -f "${_TC_MOCK_DIR}/import_calls.log" ]
}

# ---------------------------------------------------------------------------
# Filtering
# ---------------------------------------------------------------------------

@test "--services filters to matching service only" {
  run bash "${IMPORT}" --dry-run --services ec2 --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" =~ aws_instance.server ]]
  [[ ! "$output" =~ aws_s3_bucket ]]
  [[ ! "$output" =~ aws_lambda_function ]]
}

@test "--regions filters to matching region only" {
  run bash "${IMPORT}" --dry-run --regions us-east-1 --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "us-east-1" ]]
  [[ ! "$output" =~ "eu-west-1" ]]
}

@test "--accounts filters to matching account only" {
  run bash "${IMPORT}" --dry-run --accounts 123456789012 --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "123456789012" ]]
}

@test "exits 0 with info when no dirs match filters" {
  run bash "${IMPORT}" --dry-run --services nonexistent --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "No service directories" ]] || [[ "$output" =~ "no " ]]
}

# ---------------------------------------------------------------------------
# Import behaviour
# ---------------------------------------------------------------------------

@test "calls terraform import for resources not in state" {
  run bash "${IMPORT}" \
    --services ec2 \
    --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  grep -q 'aws_instance.server' "${_TC_MOCK_DIR}/import_calls.log"
}

@test "skips resources already in terraform state" {
  local ec2_dir="${_TC_OUTPUT_DIR}/123456789012/us-east-1/ec2"
  # Mark aws_instance.server as already in state
  echo "aws_instance.server" > "${ec2_dir}/.mock_in_state"

  run bash "${IMPORT}" \
    --services ec2 \
    --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  # terraform import should NOT have been called for this resource
  [ ! -f "${_TC_MOCK_DIR}/import_calls.log" ] || \
    ! grep -q 'aws_instance.server' "${_TC_MOCK_DIR}/import_calls.log"
  [[ "$output" =~ "skipped" ]] || [[ "$output" =~ "already in state" ]]
}

@test "--parallel accepts a valid integer and processes all directories" {
  run bash "${IMPORT}" \
    --parallel 3 \
    --output "${_TC_OUTPUT_DIR}"
  [ "$status" -eq 0 ]
  # All three service directories should have been processed
  grep -q 'aws_instance.server'      "${_TC_MOCK_DIR}/import_calls.log"
  grep -q 'aws_s3_bucket.mybucket'   "${_TC_MOCK_DIR}/import_calls.log"
  grep -q 'aws_lambda_function.fn'   "${_TC_MOCK_DIR}/import_calls.log"
}
