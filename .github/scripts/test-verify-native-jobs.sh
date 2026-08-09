#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
gate="$script_dir/verify-native-jobs.sh"
scenarios=0

run_gate() {
  env \
    CHANGES_RESULT="$1" \
    DEVICE_REQUIRED="$2" \
    DEVICE_RESULT="$3" \
    SIMULATOR_REQUIRED="$4" \
    SIMULATOR_RESULT="$5" \
    MIGRATIONS_REQUIRED="$6" \
    MIGRATION_RESULT="$7" \
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
  success false skipped false skipped false skipped
expect_pass "native PR" \
  success true success false skipped false skipped
expect_pass "persistence PR" \
  success true success false skipped true success
expect_pass "main push" \
  success true success true success false skipped
expect_pass "full-migration main run" \
  success true success true success true success

expect_fail "failed preflight" \
  failure false skipped false skipped false skipped
expect_fail "required device build failed" \
  success true failure false skipped false skipped
expect_fail "required device build skipped" \
  success true skipped false skipped false skipped
expect_fail "unexpected device build ran" \
  success false success false skipped false skipped
expect_fail "required simulator build failed" \
  success true success true failure false skipped
expect_fail "required migration tests skipped" \
  success true success false skipped true skipped
expect_fail "invalid requirement value" \
  success required success false skipped false skipped

echo "Native job aggregate contract tests passed ($scenarios scenarios)"
