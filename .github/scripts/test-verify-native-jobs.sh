#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
gate="$script_dir/verify-native-jobs.sh"
scenarios=0

run_gate() {
  env \
    CHANGES_RESULT="$1" \
    CORE_RESULT="$2" \
    WEB_RESULT="$3" \
    DEVICE_REQUIRED="$4" \
    DEVICE_RESULT="$5" \
    SIMULATOR_REQUIRED="$6" \
    SIMULATOR_RESULT="$7" \
    STORE_REQUIRED="$8" \
    STORE_RESULT="$9" \
    MIGRATIONS_REQUIRED="${10}" \
    MIGRATION_RESULT="${11}" \
    bash "$gate"
}

expect_pass() {
  local description="$1"
  shift
  scenarios=$((scenarios + 1))
  if ! run_gate "$@" >/dev/null; then
    echo "$description: expected aggregate gate to pass" >&2
    exit 1
  fi
}

expect_fail() {
  local description="$1"
  shift
  scenarios=$((scenarios + 1))
  if run_gate "$@" >/dev/null 2>&1; then
    echo "$description: expected aggregate gate to fail" >&2
    exit 1
  fi
}

expect_pass "documentation PR" \
  success success success false skipped false skipped false skipped false skipped
expect_pass "native PR" \
  success success success true success false skipped false skipped false skipped
expect_pass "persistence PR" \
  success success success true success false skipped false skipped true success
expect_pass "non-release main push" \
  success success success false skipped false skipped false skipped false skipped
expect_pass "release-producing main push" \
  success success success false skipped true success true success false skipped
expect_pass "full-migration non-release dispatch" \
  success success success false skipped false skipped false skipped true success
expect_pass "full-migration release dispatch" \
  success success success false skipped true success true success true success

expect_fail "failed preflight" \
  failure success success false skipped false skipped false skipped false skipped
expect_fail "failed core suite with no native work" \
  success failure success false skipped false skipped false skipped false skipped
expect_fail "failed web suite with no native work" \
  success success failure false skipped false skipped false skipped false skipped
expect_fail "required device build failed" \
  success success success true failure false skipped false skipped false skipped
expect_fail "required device build skipped" \
  success success success true skipped false skipped false skipped false skipped
expect_fail "unexpected device build ran" \
  success success success false success false skipped false skipped false skipped
expect_fail "required simulator build failed" \
  success success success false skipped true failure true success false skipped
expect_fail "required signed artifact skipped" \
  success success success false skipped true success true skipped false skipped
expect_fail "required migration tests skipped" \
  success success success false skipped false skipped false skipped true skipped
expect_fail "invalid requirement value" \
  success success success required success false skipped false skipped false skipped

echo "CI job aggregate contract tests passed ($scenarios scenarios)"
