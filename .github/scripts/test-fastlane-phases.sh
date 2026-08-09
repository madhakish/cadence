#!/usr/bin/env bash
set -euo pipefail

fastfile="fastlane/Fastfile"
workflow=".github/workflows/ci.yml"

lane_block() {
  local lane="$1"
  awk -v lane="$lane" '
    $0 == "  lane :" lane " do" { found = 1; print; next }
    found && $0 ~ /^  (desc|lane) / { exit }
    found { print }
    END { if (!found) exit 2 }
  ' "$fastfile"
}

require_contains() {
  local label="$1"
  local text="$2"
  local expected="$3"
  [[ "$text" == *"$expected"* ]] || {
    echo "$label must contain: $expected" >&2
    exit 1
  }
}

require_not_contains() {
  local label="$1"
  local text="$2"
  local forbidden="$3"
  [[ "$text" != *"$forbidden"* ]] || {
    echo "$label must not contain: $forbidden" >&2
    exit 1
  }
}

build="$(lane_block build_beta)"
upload="$(lane_block upload_beta)"

require_contains "build_beta" "$build" "build_app("
require_not_contains "build_beta" "$build" "upload_to_testflight("
require_contains "upload_beta" "$upload" "upload_to_testflight("
require_contains "upload_beta" "$upload" "ipa: ipa_path"
require_not_contains "upload_beta" "$upload" "build_app("
require_not_contains "upload_beta" "$upload" "match("
require_not_contains "upload_beta" "$upload" "xcodegen"
require_not_contains "upload_beta" "$upload" "update_code_signing_settings("

workflow_text="$(<"$workflow")"
require_contains "CI workflow" "$workflow_text" "bundle exec fastlane build_beta"
require_contains "CI workflow" "$workflow_text" "name: Cadence-store"
require_contains "CI workflow" "$workflow_text" "bundle exec fastlane upload_beta"
require_not_contains "CI workflow" "$workflow_text" "bundle exec fastlane beta"

echo "Fastlane build/promote contract tests passed"
