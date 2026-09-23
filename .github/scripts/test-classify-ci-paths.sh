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
  "shared core dependency changes run native integration" \
  $'native=true\nmigrations=true\nweb=true' \
  'CadenceCore/Sources/CadenceCore/Progression.swift'

assert_classification \
  "backup and program-file codec changes run the migration suite" \
  $'native=true\nmigrations=true\nweb=false' \
  $'Cadence/Services/ExportService.swift\nCadence/Services/ProgramImportService.swift'

assert_classification \
  "models-only services compiled into the migration target run the migration suite" \
  $'native=true\nmigrations=true\nweb=false' \
  $'Cadence/Services/ActivitySession.swift\nCadence/Services/ProgramActivationService.swift'

assert_classification \
  "seed template catalog changes run the migration suite" \
  $'native=true\nmigrations=true\nweb=false' \
  'Cadence/Seed/ProgramTemplates.swift'

assert_classification \
  "web-only changes" \
  $'native=false\nmigrations=false\nweb=true' \
  'web/app/js/app.js'

assert_classification \
  "CI workflow changes compile the current app without rebuilding historical stores" \
  $'native=true\nmigrations=false\nweb=false' \
  '.github/workflows/ci.yml'

assert_classification \
  "release automation changes compile the current app without rebuilding historical stores" \
  $'native=true\nmigrations=false\nweb=false' \
  $'fastlane/Fastfile\n.github/scripts/plan-release.mjs\n.github/scripts/verify-release-artifact.sh'

assert_classification \
  "classifier changes cannot bypass native validation" \
  $'native=true\nmigrations=false\nweb=false' \
  '.github/scripts/classify-ci-paths.sh'

assert_classification \
  "native aggregate changes cannot bypass device validation" \
  $'native=true\nmigrations=false\nweb=false' \
  '.github/scripts/verify-native-jobs.sh'

assert_classification \
  "native UI regression changes cannot skip interaction tests" \
  $'native=true\nmigrations=false\nweb=false' \
  'CadenceVisualProofUITests/VisualProofUITests.swift'

for script in .github/scripts/verify-native-smoke.mjs .github/scripts/test-verify-native-smoke.mjs .github/scripts/native-smoke-summary.fixture.json; do
  assert_classification \
    "native result gate changes cannot skip interaction tests" \
    $'native=true\nmigrations=false\nweb=false' \
    "$script"
done

# Test each production source independently. A combined fixture can pass
# because one recognized path masks another missing classification.
sources="$(ruby -ryaml -e '
  spec = YAML.load_file("project.yml")
  spec.fetch("targets").fetch("CadenceMigrationTests").fetch("sources").each do |source|
    puts(source.is_a?(Hash) ? source.fetch("path") : source)
  end
')"
test -n "$sources"
while IFS= read -r source; do
  probe="$source"
  [[ "$source" == *.swift ]] || probe="$source/classifier-fixture.swift"
  assert_classification \
    "hostless target source $source" \
    $'native=true\nmigrations=true\nweb=false' \
    "$probe"
done <<< "$sources"

echo "CI path classifier tests passed"
