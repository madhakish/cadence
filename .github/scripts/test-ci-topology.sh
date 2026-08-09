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
  local block
  if ! block="$(job_block "$job")"; then
    echo "missing workflow job: $job" >&2
    exit 1
  fi
  if [[ "$block" != *"$expected"* ]]; then
    echo "$job must contain: $expected" >&2
    exit 1
  fi
}

assert_job_not_contains() {
  local job="$1"
  local forbidden="$2"
  local block
  if ! block="$(job_block "$job")"; then
    echo "missing workflow job: $job" >&2
    exit 1
  fi
  if [[ "$block" == *"$forbidden"* ]]; then
    echo "$job must not contain: $forbidden" >&2
    exit 1
  fi
}

# Preflight is the only entry to the portable suites, which are the only entry
# to expensive Darwin work.
assert_job_contains core-tests "needs: changes"
assert_job_contains web-tests "needs: changes"
assert_job_contains simulator-build "needs: [changes, core-tests, web-tests]"
assert_job_contains migration-tests "needs: [changes, core-tests, web-tests]"
assert_job_contains changes "bash .github/scripts/test-ci-topology.sh"
assert_job_contains changes "bash .github/scripts/test-verify-native-jobs.sh"

# PR validation compiles the production device target; the simulator artifact
# is built on main. Scope cancellation per PR so unrelated branches cannot
# cancel one another's macOS proof.
assert_job_contains simulator-build "if: github.ref == 'refs/heads/main'"
assert_job_contains device-build "if: needs.changes.outputs.native == 'true' || github.ref == 'refs/heads/main'"
assert_job_contains device-build "group: \${{ github.event_name == 'pull_request' && format('device-pr-{0}', github.event.pull_request.number) || format('device-run-{0}', github.run_id) }}"
assert_job_contains device-build 'cancel-in-progress: ${{ github.event_name == '\''pull_request'\'' }}'
assert_job_contains device-build "Run unit tests (Darwin)"
assert_job_not_contains simulator-build "Run unit tests (Darwin)"
assert_job_contains migration-tests 'cancel-in-progress: ${{ github.event_name == '\''pull_request'\'' }}'
assert_job_contains migration-tests "group: \${{ github.event_name == 'pull_request' && format('migrations-pr-{0}', github.event.pull_request.number) || format('migrations-run-{0}', github.run_id) }}"
assert_job_contains device-build "needs: [changes, core-tests, web-tests]"

# Preserve the stable aggregate check and route its policy through the
# scenario-tested executable gate.
assert_job_contains app-build "needs: [changes, simulator-build, device-build, migration-tests]"
assert_job_contains app-build "if: always()"
assert_job_contains app-build "DEVICE_REQUIRED: \${{ needs.changes.outputs.native == 'true' || github.ref == 'refs/heads/main' }}"
assert_job_contains app-build "SIMULATOR_REQUIRED: \${{ github.ref == 'refs/heads/main' }}"
assert_job_contains app-build "MIGRATIONS_REQUIRED: \${{ needs.changes.outputs.migrations == 'true' }}"
assert_job_contains app-build "run: bash .github/scripts/verify-native-jobs.sh"

# npm test owns the invariant checker and runs it first. Running it directly in
# the workflow and again through npm is duplicate work disguised as coverage.
if grep -Fq "run: node ../.github/scripts/check-invariants.mjs" "$workflow"; then
  echo "ci.yml must not run the invariant checker twice" >&2
  exit 1
fi

test_command="$(node -p "JSON.parse(require('fs').readFileSync('web/package.json', 'utf8')).scripts.test")"
if [[ "${test_command%% && *}" != "node ../.github/scripts/check-invariants.mjs" ]]; then
  echo "npm test must run the invariant checker first" >&2
  exit 1
fi

echo "CI topology contract tests passed"
