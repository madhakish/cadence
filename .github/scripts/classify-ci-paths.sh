#!/usr/bin/env bash
set -euo pipefail

# Convert a newline-delimited list of changed repository paths into the coarse
# validation domains used by ci.yml. Keep this deliberately conservative:
# false positives cost a build; false negatives can ship an uncompiled app or
# an untested persistence migration.
native=false
migrations=false
web=false

while IFS= read -r path; do
  [[ -z "$path" ]] && continue

  case "$path" in
    Cadence/*|CadenceWidgets/*|CadenceCore/*|CadenceMigrationTests/*|fastlane/*|Gemfile|Gemfile.lock|project.yml|.github/workflows/ci.yml|.github/scripts/classify-ci-paths.sh|.github/scripts/test-classify-ci-paths.sh|.github/scripts/plan-release.mjs|.github/scripts/verify-native-jobs.sh|.github/scripts/verify-release-artifact.sh)
      native=true
      ;;
  esac

  case "$path" in
    # Every source compiled into the hostless CadenceMigrationTests target
    # (see project.yml) is compatibility-bearing: the backup and program-file
    # codecs plus the template/seed catalogs are proven only by that suite,
    # so a change to any of them must run it.
    Cadence/Models/*|Cadence/Seed/Seeder.swift|Cadence/Seed/ProgramTemplates.swift|Cadence/Services/ExportService.swift|Cadence/Services/ImportService.swift|Cadence/Services/ProgramExportService.swift|Cadence/Services/ProgramImportService.swift|Cadence/Services/SessionCorrectionService.swift|Cadence/Services/ActivitySession.swift|Cadence/Services/ProgramActivationService.swift|Cadence/Services/MilestoneProjection.swift|CadenceMigrationTests/*|project.yml|.github/scripts/generate-shipped-stores.sh)
      migrations=true
      ;;
  esac

  case "$path" in
    web/*|CadenceCore/*|.github/workflows/pages.yml)
      web=true
      ;;
  esac
done

printf 'native=%s\n' "$native"
printf 'migrations=%s\n' "$migrations"
printf 'web=%s\n' "$web"
