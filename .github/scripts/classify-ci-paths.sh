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
    Cadence/*|CadenceWidgets/*|CadenceCore/*|CadenceMigrationTests/*|project.yml|.github/workflows/ci.yml)
      native=true
      ;;
  esac

  case "$path" in
    Cadence/Models/*|Cadence/Seed/Seeder.swift|CadenceMigrationTests/*|project.yml|.github/scripts/generate-shipped-stores.sh)
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
