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
# to expensive app builds.
assert_job_contains core-tests "needs: changes"
assert_job_contains core-tests "runs-on: macos-latest"
assert_job_contains core-tests "name: CadenceCore tests (Linux)"
assert_job_not_contains core-tests "container:"
assert_job_contains core-tests "xcrun swiftc -parse"
assert_job_contains core-tests "run: xcrun swift test"
assert_job_contains web-tests "needs: changes"
for job in core-tests web-tests simulator-build device-build store-build migration-tests native-smoke testflight deploy-web; do
  assert_job_contains "$job" "runs-on: macos-latest"
  assert_job_not_contains "$job" "container:"
done
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
assert_job_contains app-build "needs: [changes, core-tests, web-tests, simulator-build, device-build, store-build, migration-tests, native-smoke]"
assert_job_contains app-build "if: always()"
assert_job_contains native-smoke "needs: [changes, core-tests, web-tests]"
assert_job_contains native-smoke "if: needs.changes.outputs.native == 'true'"
assert_job_contains native-smoke "test07FinalSetAdvancesToNextAuthoredExercise"
assert_job_contains native-smoke "test10PlankCountdownAndLog"
assert_job_contains native-smoke "test13SetCompletionKeepsDominantBlockStill"
assert_job_contains native-smoke "test14CalculatorTargetAtAccessibilityTextSize"
assert_job_contains native-smoke "node .github/scripts/verify-native-smoke.mjs"
assert_job_contains native-smoke $'- name: Require all four interaction tests to execute\n        if: always()'
assert_job_contains app-build 'NATIVE_SMOKE_RESULT: ${{ needs.native-smoke.result }}'
assert_job_contains deploy-web "needs: [changes, web-tests, app-build]"
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

# Browser tests run before the web gate can release app builds or Pages.
assert_job_contains web-tests 'run: npx --no-install playwright install chromium webkit'
assert_job_contains web-tests 'run: npm run test:browser'
assert_job_contains web-tests 'path: web/test-results/'
browser_command="$(node -p "JSON.parse(require('fs').readFileSync('web/package.json', 'utf8')).scripts['test:browser']")"
if [[ "$browser_command" != 'playwright test && node tools/verify-feature-coverage.mjs' ]]; then
  echo 'browser acceptance must validate the executed requirement report' >&2
  exit 1
fi

# Build-capable recovery and visual workflows use the same hosted tier.
workflow=".github/workflows/pages.yml"
assert_job_contains test "runs-on: macos-latest"
assert_job_contains test "if: github.ref == 'refs/heads/main'"
assert_job_contains test "run: npm test"
assert_job_contains test 'run: npx --no-install playwright install chromium webkit'
assert_job_contains test 'run: npm run test:browser'
assert_job_contains test 'path: web/test-results/'
assert_job_contains test "run: node .github/scripts/verify-pages-recovery.mjs"
assert_job_contains deploy "runs-on: macos-latest"
workflow=".github/workflows/visual-proof.yml"
assert_job_contains capture "runs-on: macos-latest"

# Reject self-hosted selectors and expressions that could route work to them.
for workflow in .github/workflows/*.yml; do
  if grep '^[[:space:]]*runs-on:' "$workflow" | grep -Ev '^[[:space:]]*runs-on: (ubuntu-latest|macos-latest)$'; then
    echo "$workflow must use explicit GitHub-hosted runners" >&2
    exit 1
  fi
done

echo "CI topology contract tests passed"
node .github/scripts/test-visual-ci.mjs
