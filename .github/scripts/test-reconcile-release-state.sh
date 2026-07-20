#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
reconciler="$script_dir/reconcile-release-state.sh"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

git -C "$fixture" init -q
git -C "$fixture" config user.name "Cadence CI"
git -C "$fixture" config user.email "ci@cadence.invalid"
git -C "$fixture" commit --allow-empty -qm "feat: fixture"
released_sha="$(git -C "$fixture" rev-parse HEAD)"
git -C "$fixture" tag v3.0.2

run_reconciler() {
  local sha="$1"
  local outcome="$2"
  local output="$3"
  (
    cd "$fixture"
    GITHUB_SHA="$sha" \
      GITHUB_OUTPUT="$output" \
      SEMANTIC_RELEASE_OUTCOME="$outcome" \
      bash "$reconciler"
  )
}

output="$fixture/released.out"
run_reconciler "$released_sha" failure "$output"
grep -qx 'published=true' "$output"
grep -qx 'version=3.0.2' "$output"

git -C "$fixture" commit --allow-empty -qm "docs: no release"
unreleased_sha="$(git -C "$fixture" rev-parse HEAD)"
output="$fixture/unreleased.out"
run_reconciler "$unreleased_sha" success "$output"
grep -qx 'published=false' "$output"

output="$fixture/failed.out"
if run_reconciler "$unreleased_sha" failure "$output"; then
  echo "A failed release without an exact tag must remain failed" >&2
  exit 1
fi
grep -qx 'published=false' "$output"

echo "Release-state reconciliation tests passed"
