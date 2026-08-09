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

assert_workflow_contains() {
  local expected="$1"
  if ! grep -Fq "$expected" "$workflow"; then
    echo "workflow must contain: $expected" >&2
    exit 1
  fi
}

# Preflight is the only entry to the portable suites, which are the only entry
# to expensive Darwin work.
assert_job_contains core-tests "needs: changes"
assert_job_contains web-tests "needs: changes"
assert_job_contains simulator-build "needs: [changes, core-tests, web-tests]"
assert_job_contains store-build "needs: [changes, core-tests, web-tests]"
assert_job_contains migration-tests "needs: [changes, core-tests, web-tests]"
assert_job_contains changes "bash .github/scripts/cancel-stale-pr-runs.sh"
assert_job_contains changes "bash .github/scripts/test-cancel-stale-pr-runs.sh"
assert_job_contains changes "bash .github/scripts/test-ci-topology.sh"
assert_job_contains changes "bash .github/scripts/test-fastlane-phases.sh"
assert_job_contains changes "bash .github/scripts/test-verify-native-jobs.sh"
assert_job_contains changes "force_testflight and verify_signed_artifact are mutually exclusive"
assert_job_contains web-tests 'simulator-build-required: ${{ steps.release-plan.outputs.simulator-build-required }}'
assert_job_contains web-tests 'store-build-required: ${{ steps.release-plan.outputs.store-build-required }}'
assert_job_contains web-tests 'release-artifact-source: ${{ steps.release-plan.outputs.artifact-source }}'
assert_job_contains web-tests 'release-version: ${{ steps.release-plan.outputs.version }}'
assert_job_contains web-tests "node .github/scripts/test-plan-release.mjs"
assert_job_contains web-tests "run: node .github/scripts/plan-release.mjs"

# A new PR head starts immediately and cancels older whole-workflow runs through
# the API. Production retains GitHub's multi-run serialized queue. GitHub
# rejects queue:max combined with any cancel-in-progress expression that can be
# true, so keep that key out of the top-level concurrency block.
assert_workflow_contains "group: \${{ github.event_name == 'pull_request' && format('ci-pr-{0}-{1}', github.event.pull_request.number, github.run_id) || 'cadence-production-release' }}"
assert_workflow_contains "queue: max"
top_level_concurrency="$(awk '
  $0 == "concurrency:" { found = 1; next }
  found && /^[^[:space:]]/ { exit }
  found { print }
' "$workflow")"
if [[ "$top_level_concurrency" == *"cancel-in-progress:"* ]]; then
  echo "top-level queue:max must not be combined with cancel-in-progress" >&2
  exit 1
fi
assert_job_contains changes "actions: write"
assert_job_contains changes "github.event.pull_request.head.repo.full_name == github.repository"

# PR validation compiles the unsigned production target. A pending release
# builds one signed IPA and the simulator download; tagged retries build none.
assert_job_contains simulator-build "if: needs.web-tests.outputs.simulator-build-required == 'true'"
assert_job_contains device-build "if: github.event_name == 'pull_request' && needs.changes.outputs.native == 'true'"
assert_job_contains store-build "if: needs.web-tests.outputs.store-build-required == 'true'"
assert_job_contains device-build "Run unit tests (Darwin)"
assert_job_not_contains simulator-build "Run unit tests (Darwin)"
assert_job_contains store-build "Run unit tests (Darwin)"
assert_job_contains store-build "bundle exec fastlane build_beta"
assert_job_contains store-build "bash .github/scripts/verify-release-artifact.sh"
assert_job_contains store-build "name: Cadence-store"
assert_job_not_contains device-build "concurrency:"
assert_job_not_contains migration-tests "concurrency:"
assert_job_contains device-build "needs: [changes, core-tests, web-tests]"
assert_job_contains simulator-build "timeout-minutes: 20"
assert_job_contains device-build "timeout-minutes: 20"
assert_job_contains store-build "timeout-minutes: 45"
assert_job_contains migration-tests "timeout-minutes: 45"

# Preserve the stable aggregate check and route its policy through the
# scenario-tested executable gate. The portable suites are direct dependencies
# so their failures cannot disappear when every conditional native job skips.
assert_job_contains app-build "needs: [changes, core-tests, web-tests, simulator-build, device-build, store-build, migration-tests]"
assert_job_contains app-build "if: always()"
assert_job_contains app-build 'CORE_RESULT: ${{ needs.core-tests.result }}'
assert_job_contains app-build 'WEB_RESULT: ${{ needs.web-tests.result }}'
assert_job_contains app-build "DEVICE_REQUIRED: \${{ github.event_name == 'pull_request' && needs.changes.outputs.native == 'true' }}"
assert_job_contains app-build "SIMULATOR_REQUIRED: \${{ needs.web-tests.outputs.simulator-build-required == 'true' }}"
assert_job_contains app-build "STORE_REQUIRED: \${{ needs.web-tests.outputs.store-build-required == 'true' }}"
assert_job_contains app-build 'STORE_RESULT: ${{ needs.store-build.result }}'
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
