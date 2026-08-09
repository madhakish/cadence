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

require_success() {
  local label="$1"
  local result="$2"

  if [[ "$result" != "success" ]]; then
    echo "$label must succeed, got '$result'" >&2
    return 1
  fi
}

require_success "preflight + classify" "${CHANGES_RESULT:-unset}"
require_success "CadenceCore tests (Linux)" "${CORE_RESULT:-unset}"
require_success "Web tests (parity + smoke)" "${WEB_RESULT:-unset}"

require_job_result "unsigned device build" "${DEVICE_REQUIRED:-}" "${DEVICE_RESULT:-}"
require_job_result "iOS Simulator build" "${SIMULATOR_REQUIRED:-}" "${SIMULATOR_RESULT:-}"
require_job_result "signed release artifact" "${STORE_REQUIRED:-}" "${STORE_RESULT:-}"
require_job_result "shipped-store migration tests" "${MIGRATIONS_REQUIRED:-}" "${MIGRATION_RESULT:-}"

echo "Required CI jobs passed"
