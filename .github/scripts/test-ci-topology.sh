#!/usr/bin/env bash
set -euo pipefail

workflow=".github/workflows/ci.yml"

job_block() {
  local job="$1"
  awk -v job="$job" '
    $0 == "  " job ":" { found = 1; print; next }
    found && $0 ~ /^  [[:alnum:]_-]+:$/ { exit }
    found { print }
    END { if (!found) exit 2 }
  ' "$workflow"
}

assert_job_contains() {
  local job="$1"
  local expected="$2"
  if ! job_block "$job" | grep -Fq -- "$expected"; then
    echo "$job must contain: $expected" >&2
    exit 1
  fi
}

# Preflight is the only entry to the portable suites, which are the only entry
# to expensive Darwin work.
assert_job_contains core-tests "needs: changes"
assert_job_contains web-tests "needs: changes"
assert_job_contains simulator-build "needs: [changes, core-tests, web-tests]"
assert_job_contains migration-tests "needs: [changes, core-tests, web-tests]"

# PR validation compiles one iOS target. The device package is a main-branch
# release artifact, and stale PR-native jobs must stop burning macOS minutes.
assert_job_contains simulator-build 'cancel-in-progress: ${{ github.event_name == '\''pull_request'\'' }}'
assert_job_contains migration-tests 'cancel-in-progress: ${{ github.event_name == '\''pull_request'\'' }}'
assert_job_contains device-build "needs: [changes, core-tests, web-tests]"
assert_job_contains device-build "if: github.ref == 'refs/heads/main'"

# Preserve the stable aggregate check while making its device requirement
# match the job's main-only scope.
assert_job_contains app-build "needs: [changes, simulator-build, device-build, migration-tests]"
assert_job_contains app-build 'DEVICE_REQUIRED: ${{ github.ref == '\''refs/heads/main'\'' }}'

# npm test owns the invariant checker and runs it first. Running it directly in
# the workflow and again through npm is duplicate work disguised as coverage.
if grep -Fq "run: node ../.github/scripts/check-invariants.mjs" "$workflow"; then
  echo "ci.yml must not run the invariant checker twice" >&2
  exit 1
fi

echo "CI topology contract tests passed"
