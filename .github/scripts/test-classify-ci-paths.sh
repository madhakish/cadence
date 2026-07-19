#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
classifier="$script_dir/classify-ci-paths.sh"

assert_classification() {
  local description="$1"
  local expected="$2"
  local paths="$3"
  local actual
  actual="$(printf '%s\n' "$paths" | bash "$classifier")"

  if [[ "$actual" != "$expected" ]]; then
    echo "$description: unexpected classification" >&2
    echo "expected:" >&2
    echo "$expected" >&2
    echo "actual:" >&2
    echo "$actual" >&2
    exit 1
  fi
}

assert_classification \
  "documentation-only changes" \
  $'native=false\nmigrations=false\nweb=false' \
  'docs/TESTFLIGHT.md'

assert_classification \
  "native view changes" \
  $'native=true\nmigrations=false\nweb=false' \
  'Cadence/Views/HomeView.swift'

assert_classification \
  "persistence changes" \
  $'native=true\nmigrations=true\nweb=false' \
  $'Cadence/Models/SessionModels.swift\nCadenceMigrationTests/PersistenceMigrationTests.swift'

assert_classification \
  "shared core changes" \
  $'native=true\nmigrations=false\nweb=true' \
  'CadenceCore/Sources/CadenceCore/Progression.swift'

assert_classification \
  "web-only changes" \
  $'native=false\nmigrations=false\nweb=true' \
  'web/js/app.js'

assert_classification \
  "CI workflow changes compile the current app without rebuilding historical stores" \
  $'native=true\nmigrations=false\nweb=false' \
  '.github/workflows/ci.yml'

echo "CI path classifier tests passed"
