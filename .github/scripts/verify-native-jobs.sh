#!/usr/bin/env bash
set -euo pipefail

require_job_result() {
  local label="$1"
  local required="$2"
  local result="$3"

  case "$required" in
    true)
      if [[ "$result" != "success" ]]; then
        echo "$label was required but finished with result '$result'" >&2
        return 1
      fi
      ;;
    false)
      if [[ "$result" != "skipped" ]]; then
        echo "$label was not required but finished with result '$result' instead of 'skipped'" >&2
        return 1
      fi
      ;;
    *)
      echo "$label requirement must be 'true' or 'false', got '$required'" >&2
      return 1
      ;;
  esac
}

if [[ "${CHANGES_RESULT:-}" != "success" ]]; then
  echo "preflight + classify must succeed, got '${CHANGES_RESULT:-unset}'" >&2
  exit 1
fi

require_job_result "unsigned device build" "${DEVICE_REQUIRED:-}" "${DEVICE_RESULT:-}"
require_job_result "iOS Simulator build" "${SIMULATOR_REQUIRED:-}" "${SIMULATOR_RESULT:-}"
require_job_result "shipped-store migration tests" "${MIGRATIONS_REQUIRED:-}" "${MIGRATION_RESULT:-}"

echo "Required native jobs passed"
