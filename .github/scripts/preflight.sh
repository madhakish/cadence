#!/usr/bin/env bash
# Fast repository checks, about a minute, no Xcode or network. CI's
# "Preflight + classify" job, `make check` and the pre-commit hook all run
# exactly this file, so a local pass means the CI preflight passes too.
#
# BASE_SHA/HEAD_SHA (set by CI) select the whitespace-check range; locally the
# working tree is checked against HEAD.
set -euo pipefail
cd "$(dirname "$0")/../.."

node --test .github/scripts/test-repository-hygiene.mjs
node .github/scripts/check-agent-instructions.mjs
# The PR contract reads the pull request event; it exists only in CI.
if [[ -n "${GITHUB_EVENT_PATH:-}" ]]; then
  node .github/scripts/pr-contract.mjs --offline
fi

if [[ -n "${HEAD_SHA:-}" ]]; then
  if [[ -z "${BASE_SHA:-}" || "$BASE_SHA" =~ ^0+$ ]]; then
    git diff-tree --root --check "$HEAD_SHA"
  else
    git diff --check "$BASE_SHA" "$HEAD_SHA"
  fi
else
  git diff --check HEAD
fi

while IFS= read -r -d '' script; do
  bash -n "$script"
done < <(find .github/scripts -type f -name '*.sh' -print0)

while IFS= read -r -d '' script; do
  node --check "$script" >/dev/null
done < <(find .github/scripts web \
  -path web/node_modules -prune -o \
  -type f \( -name '*.js' -o -name '*.mjs' \) -print0)

while IFS= read -r -d '' script; do
  ruby -c "$script" >/dev/null
done < <(find .github/scripts fastlane -type f \( -name '*.rb' -o -name 'Fastfile' -o -name 'Matchfile' \) -print0)
ruby -e 'require "yaml"; ARGV.each { |path| YAML.parse_file(path) }' .github/workflows/*.yml

# Generated and local-only files must never be tracked.
tracked_generated="$(git ls-files -- Cadence.xcodeproj build '*.xcresult' 'Cadence/Info.plist' 'CadenceWatch/Info.plist' 'CadenceWidgets/Info.plist')"
if [[ -n "$tracked_generated" ]]; then
  echo "generated files are tracked; remove them from git:" >&2
  echo "$tracked_generated" >&2
  exit 1
fi

bash .github/scripts/test-cancel-stale-pr-runs.sh
bash .github/scripts/test-classify-ci-paths.sh
bash .github/scripts/test-ci-topology.sh
bash .github/scripts/test-signing-preflight.sh
node --test .github/scripts/test-verify-native-smoke.mjs .github/scripts/test-verify-pages-recovery.mjs .github/scripts/test-check-parity.mjs
bash .github/scripts/test-fastlane-phases.sh
bash .github/scripts/test-verify-native-jobs.sh

echo "Preflight passed"
