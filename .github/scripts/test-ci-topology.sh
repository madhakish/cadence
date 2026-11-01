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

assert_file_contains() {
  local file="$1"
  local expected="$2"
  if ! grep -Fq -- "$expected" "$file"; then
    echo "$file must contain: $expected" >&2
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
for job in core-tests web-tests simulator-build device-build watch-smoke store-build migration-tests native-smoke testflight deploy-web; do
  assert_job_contains "$job" "runs-on: macos-latest"
  assert_job_not_contains "$job" "container:"
done
assert_job_contains simulator-build "needs: [changes, core-tests, web-tests]"
assert_job_contains store-build "needs: [changes, core-tests, web-tests, signing-preflight]"
assert_job_contains migration-tests "needs: [changes, core-tests, web-tests]"
assert_job_contains changes "bash .github/scripts/cancel-stale-pr-runs.sh"
# CI, `make check` and pre-commit share one preflight script.
assert_job_contains changes "run: bash .github/scripts/preflight.sh"
assert_file_contains .github/scripts/preflight.sh "node --test .github/scripts/test-repository-hygiene.mjs"
assert_file_contains .github/scripts/preflight.sh "git diff --check"
assert_file_contains .github/scripts/preflight.sh 'git diff --check "$(git merge-base "$BASE_SHA" "$HEAD_SHA"'
assert_file_contains .github/scripts/changed-paths.sh "git diff --no-renames --name-only"
assert_file_contains .github/scripts/preflight.sh "bash .github/scripts/test-cancel-stale-pr-runs.sh"
# PR paths come from the merge base, not main's tip (#362), through one
# tested script.
assert_job_contains changes "fetch-depth: 0"
assert_job_contains changes "bash .github/scripts/changed-paths.sh > \"\$paths\""
assert_job_contains changes "bash .github/scripts/classify-ci-paths.sh < \"\$paths\""
assert_job_not_contains changes "git diff --name-only"
assert_file_contains .github/scripts/changed-paths.sh 'git merge-base "$base" "$HEAD_SHA"'
assert_file_contains .github/scripts/preflight.sh "bash .github/scripts/test-changed-paths.sh"
assert_file_contains .github/scripts/preflight.sh "bash .github/scripts/test-ci-topology.sh"
assert_file_contains .github/scripts/preflight.sh "bash .github/scripts/test-signing-preflight.sh"
# Signing material is proven on Ubuntu right after preflight, before any
# macOS minute is spent, and the signed build and the aggregate wait on it.
assert_job_contains signing-preflight "needs: changes"
assert_job_contains signing-preflight "runs-on: ubuntu-latest"
# Signing secrets never reach pull-request code (environment-ready).
assert_job_contains signing-preflight "if: github.event_name != 'pull_request'"
assert_job_contains signing-preflight "SIGNING_PREFLIGHT: required"
assert_job_contains signing-preflight 'ruby-version: "3.3"'
assert_job_contains changes 'ruby-version: "3.3"'
assert_job_contains signing-preflight "run: ruby .github/scripts/check-signing-material.rb"
assert_job_contains signing-preflight "MATCH_READONLY: \${{ vars.MATCH_READONLY }}"
assert_job_contains app-build "SIGNING_REQUIRED: \${{ github.event_name != 'pull_request' }}"
assert_job_contains app-build 'SIGNING_RESULT: ${{ needs.signing-preflight.result }}'
# While main's release path is red, release-producing PRs fail the aggregate
# (no new required check). The gate reads main with actions: read and no
# secrets, from the PR's merge-base paths, and its decision is unit-tested.
assert_job_contains main-health "name: Main release health"
assert_job_contains main-health "needs: changes"
assert_job_contains main-health "if: github.event_name == 'pull_request'"
assert_job_contains main-health "runs-on: ubuntu-latest"
assert_job_contains main-health "timeout-minutes: 5"
assert_job_contains main-health $'permissions:\n      actions: read\n      contents: read\n    steps:'
assert_job_not_contains main-health "secrets."
assert_job_contains main-health "fetch-depth: 0"
assert_job_contains main-health "filter: blob:none"
assert_job_contains main-health "persist-credentials: false"
assert_job_contains main-health "working-directory: .github/release"
assert_job_contains main-health 'bash .github/scripts/changed-paths.sh > "$paths"'
assert_job_contains main-health 'node .github/scripts/main-health-gate.mjs "$paths"'
assert_job_contains app-build "MAIN_HEALTH_REQUIRED: \${{ github.event_name == 'pull_request' }}"
assert_job_contains app-build 'MAIN_HEALTH_RESULT: ${{ needs.main-health.result }}'
assert_file_contains .github/scripts/verify-native-jobs.sh 'require_job_result "main release health" "${MAIN_HEALTH_REQUIRED:-}" "${MAIN_HEALTH_RESULT:-}"'
assert_file_contains .github/scripts/preflight.sh ".github/scripts/test-main-health-gate.mjs"
assert_file_contains .github/scripts/preflight.sh "bash .github/scripts/test-signing-health-issue.sh"
assert_file_contains .github/scripts/preflight.sh "bash .github/scripts/test-fastlane-phases.sh"
assert_file_contains .github/scripts/preflight.sh "bash .github/scripts/test-verify-native-jobs.sh"
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
# The watch build and UI smoke tests run in their own job beside the device
# build, on the same trigger; together they outgrew the device build's limit.
assert_job_contains watch-smoke "name: Watch simulator smoke tests"
assert_job_contains watch-smoke "needs: [changes, core-tests, web-tests]"
assert_job_contains watch-smoke "if: github.event_name == 'pull_request' && needs.changes.outputs.native == 'true'"
assert_job_contains watch-smoke "timeout-minutes: 30"
assert_job_contains watch-smoke "-scheme CadenceWatch"
assert_job_contains watch-smoke "-destination 'generic/platform=watchOS Simulator'"
assert_job_contains watch-smoke "xcodebuild test"
assert_job_contains watch-smoke "-resultBundlePath build/WatchSmoke.xcresult"
assert_job_contains watch-smoke $'- name: Retain watch smoke results\n        if: always()'
assert_job_contains watch-smoke "path: build/WatchSmoke.xcresult"
assert_job_contains watch-smoke "retention-days: 14"
assert_job_not_contains device-build "CadenceWatch"
assert_job_not_contains device-build "watchOS"
assert_job_not_contains device-build "xcodebuild test"
assert_job_contains device-build "-destination 'generic/platform=iOS'"
assert_job_contains store-build "timeout-minutes: 45"
assert_job_contains migration-tests "timeout-minutes: 75"
assert_job_contains migration-tests "ref: 20058600ec2947c1a4f13a855d3b922ae80e1709"
assert_job_contains migration-tests 'TEST_RUNNER_CADENCE_V14_STORE_DIR:'
assert_job_contains migration-tests "ref: 575ef369c9a44e52ec72c1f3d084f2a32e8cc469"
assert_job_contains migration-tests 'TEST_RUNNER_CADENCE_V15_STORE_DIR:'

# Preserve the stable aggregate check and route its policy through the
# scenario-tested executable gate. The portable suites are direct dependencies
# so their failures cannot disappear when every conditional native job skips.
assert_job_contains app-build "needs: [changes, core-tests, web-tests, signing-preflight, main-health, simulator-build, device-build, store-build, migration-tests, native-smoke, watch-smoke]"
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
assert_job_contains app-build "WATCH_SMOKE_REQUIRED: \${{ github.event_name == 'pull_request' && needs.changes.outputs.native == 'true' }}"
assert_job_contains app-build 'WATCH_SMOKE_RESULT: ${{ needs.watch-smoke.result }}'
assert_file_contains .github/scripts/verify-native-jobs.sh 'require_job_result "watch simulator smoke tests" "${WATCH_SMOKE_REQUIRED:-}" "${WATCH_SMOKE_RESULT:-}"'
assert_job_contains deploy-web "needs: [changes, web-tests, app-build]"
# Pages must evaluate its gate even when a PR-only app-build dependency was
# skipped on main; without always() the job is skipped on every main push.
assert_job_contains deploy-web $'if: >-\n      always() &&'
assert_job_contains deploy-web "needs.changes.result == 'success' &&"
assert_job_contains deploy-web "needs.web-tests.result == 'success' &&"
assert_job_contains deploy-web "needs.app-build.result == 'success' &&"
assert_job_contains deploy-web "github.event_name == 'push' &&"
assert_job_contains deploy-web "github.ref == 'refs/heads/main' &&"
assert_job_contains deploy-web "needs.changes.outputs.web == 'true'"
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

# The parity checker follows it, under the same single-owner rule.
if grep -Fq "run: node ../.github/scripts/check-parity.mjs" "$workflow"; then
  echo "ci.yml must not run the parity checker twice" >&2
  exit 1
fi
remaining_tests="${test_command#* && }"
if [[ "${remaining_tests%% && *}" != "node ../.github/scripts/check-parity.mjs" ]]; then
  echo "npm test must run the parity checker second" >&2
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
# Every capture boots through the script that verifies the device is usable.
assert_job_contains capture 'bash .github/visual-proof/boot-simulator.sh "$device_id"'
assert_job_contains edge-widths 'bash .github/visual-proof/boot-simulator.sh "$device_id"'
assert_job_contains baseline 'bash proof-source/.github/visual-proof/boot-simulator.sh "$device_id"'
assert_job_not_contains capture "simctl bootstatus"
assert_job_not_contains edge-widths "simctl bootstatus"
assert_job_not_contains baseline "simctl bootstatus"

# The daily signing health check: the Signing preflight's secrets, read-only,
# never on pull-request events, one tracking issue (signing-health-issue.sh).
ci_setup_ruby="$(grep -m1 -o 'ruby/setup-ruby@[0-9a-f]\{40\}' .github/workflows/ci.yml)"
workflow=".github/workflows/signing-health.yml"
assert_workflow_contains "schedule:"
assert_workflow_contains "workflow_dispatch:"
if grep -q "pull_request" "$workflow"; then
  echo "$workflow must never run on pull-request events" >&2
  exit 1
fi
if [[ "$(cat "$workflow")" != *$'\npermissions:\n  contents: read\n  issues: write\n\n'* ]]; then
  echo "$workflow must grant exactly contents: read and issues: write" >&2
  exit 1
fi
assert_job_contains check "runs-on: ubuntu-latest"
assert_job_contains check "uses: $ci_setup_ruby"
assert_job_contains check 'ruby-version: "3.3"'
assert_job_contains check "SIGNING_PREFLIGHT: required"
assert_job_contains check 'MATCH_READONLY: "true"'
assert_job_not_contains check "vars.MATCH_READONLY"
assert_job_contains check 'SIGNING_FINDINGS: ${{ runner.temp }}/signing-findings.md'
assert_job_contains check $'id: preflight\n        continue-on-error: true'
assert_job_contains check "run: ruby .github/scripts/check-signing-material.rb"
assert_job_contains check 'FINDINGS_FILE: ${{ runner.temp }}/signing-findings.md'
assert_job_contains check 'PREFLIGHT_OUTCOME: ${{ steps.preflight.outcome }}'
assert_job_contains check "run: bash .github/scripts/signing-health-issue.sh"
assert_job_contains check "if: steps.preflight.outcome != 'success'"

# A merge made with the workflow token starts no push run, so auto-merge must
# never be enabled with it (#299).
workflow=".github/workflows/auto-merge.yml"
assert_job_contains enable 'GH_TOKEN: ${{ env.AUTO_MERGE_TOKEN }}'
assert_job_not_contains enable 'github.token'
assert_workflow_contains "permissions: {}"

# Every job has a timeout, and every action is pinned to a full commit SHA
# with its version in a comment.
ruby -ryaml -e '
  ARGV.each do |path|
    jobs = YAML.load_file(path).fetch("jobs")
    bare = jobs.reject { |_, job| job["timeout-minutes"] || job["uses"] }.keys
    abort "#{path}: jobs without timeout-minutes: #{bare.join(", ")}" unless bare.empty?
  end' .github/workflows/*.yml
if grep -n "uses:" .github/workflows/*.yml | grep -vE "uses: [^@ ]+@[0-9a-f]{40} # v[0-9]"; then
  echo "pin every action to a full commit SHA with a version comment" >&2
  exit 1
fi

# Reject self-hosted selectors and expressions that could route work to them.
for workflow in .github/workflows/*.yml; do
  if grep '^[[:space:]]*runs-on:' "$workflow" | grep -Ev '^[[:space:]]*runs-on: (ubuntu-latest|macos-latest)$'; then
    echo "$workflow must use explicit GitHub-hosted runners" >&2
    exit 1
  fi
done

echo "CI topology contract tests passed"
node .github/scripts/test-visual-ci.mjs
