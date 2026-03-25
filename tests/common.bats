#!/usr/bin/env bats
# Tests for lib/common.sh shared helpers
# Run with: bats tests/common.bats
# Requires bats-core >= 1.5: https://bats-core.readthedocs.io/

bats_require_minimum_version 1.5.0

COMMON="${BATS_TEST_DIRNAME}/../lib/common.sh"

# Source common.sh with the minimum globals it expects
_load_common() {
  export DEBUG=false
  export TAGS=""
  export PARALLEL=5
  _AWS_WARN_FILE=$(mktemp)
  _TAG_IDS_FILE=$(mktemp)
  export _AWS_WARN_FILE _TAG_IDS_FILE
  # shellcheck source=../lib/common.sh
  source "${COMMON}"
}

setup() {
  _load_common
}

teardown() {
  rm -f "${_AWS_WARN_FILE}" "${_TAG_IDS_FILE}" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# slugify
# ---------------------------------------------------------------------------

@test "slugify lowercases input" {
  result=$(slugify "MyResource")
  [ "${result}" = "myresource" ]
}

@test "slugify replaces spaces with underscores" {
  result=$(slugify "my resource name")
  [ "${result}" = "my_resource_name" ]
}

@test "slugify replaces hyphens with underscores" {
  result=$(slugify "my-resource-name")
  [ "${result}" = "my_resource_name" ]
}

@test "slugify collapses consecutive non-alphanumeric chars" {
  result=$(slugify "foo--bar__baz")
  [ "${result}" = "foo_bar_baz" ]
}

@test "slugify strips leading and trailing underscores" {
  result=$(slugify "-leading-and-trailing-")
  [ "${result}" = "leading_and_trailing" ]
}

@test "slugify handles AWS resource IDs" {
  result=$(slugify "i-1234567890abcdef")
  [ "${result}" = "i_1234567890abcdef" ]
}

@test "slugify handles slashes (e.g. ARN suffix)" {
  result=$(slugify "my/nested/resource")
  [ "${result}" = "my_nested_resource" ]
}

# ---------------------------------------------------------------------------
# tag_match
# ---------------------------------------------------------------------------

@test "tag_match always returns 0 when TAGS is empty" {
  TAGS=""
  tag_match "anything"
}

@test "tag_match returns 0 for a resource in the tag IDs file" {
  export TAGS="Env=prod"
  echo "my-bucket" >> "${_TAG_IDS_FILE}"
  tag_match "my-bucket"
}

@test "tag_match returns 1 for a resource NOT in the tag IDs file" {
  export TAGS="Env=prod"
  echo "other-bucket" >> "${_TAG_IDS_FILE}"
  run tag_match "my-bucket"
  [ "${status}" -ne 0 ]
}

@test "tag_match uses exact-line matching (no substring matches)" {
  export TAGS="Env=prod"
  echo "my-bucket" >> "${_TAG_IDS_FILE}"
  # "my" alone should not match "my-bucket"
  run tag_match "my"
  [ "${status}" -ne 0 ]
}

# ---------------------------------------------------------------------------
# log / debug / err helpers
# ---------------------------------------------------------------------------

@test "log writes to stderr" {
  run bash -c "
    source '${COMMON}'
    DEBUG=false TAGS='' PARALLEL=5
    _AWS_WARN_FILE=/dev/null _TAG_IDS_FILE=/dev/null
    log 'hello world'
  "
  [[ "${output}" =~ \[INFO\] ]]
  [[ "${output}" =~ "hello world" ]]
}

@test "debug writes to stderr only when DEBUG=true" {
  run bash -c "
    source '${COMMON}'
    DEBUG=true TAGS='' PARALLEL=5
    _AWS_WARN_FILE=/dev/null _TAG_IDS_FILE=/dev/null
    debug 'debug msg'
  "
  [[ "${output}" =~ \[DEBUG\] ]]
}

@test "debug produces no output when DEBUG=false" {
  run bash -c "
    source '${COMMON}'
    DEBUG=false TAGS='' PARALLEL=5
    _AWS_WARN_FILE=/dev/null _TAG_IDS_FILE=/dev/null
    debug 'should be silent'
  "
  [ -z "${output}" ]
}

@test "die exits with non-zero status" {
  run bash -c "
    source '${COMMON}'
    DEBUG=false TAGS='' PARALLEL=5
    _AWS_WARN_FILE=/dev/null _TAG_IDS_FILE=/dev/null
    die 'fatal error'
  "
  [ "${status}" -ne 0 ]
  [[ "${output}" =~ "fatal error" ]]
}
