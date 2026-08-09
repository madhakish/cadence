#!/usr/bin/env bash
set -euo pipefail

source .github/scripts/cancel-stale-pr-runs.sh

log_file="$(mktemp)"
trap 'rm -f "$log_file"' EXIT

gh() {
  local args=" $* "
  if [[ "$args" == *"/actions/workflows/ci.yml/runs "* ]]; then
    printf '%s\n' "$MOCK_RUNS"
    return 0
  fi
  if [[ "$args" == *"/actions/runs/101/cancel "* ]]; then
    echo 101 >> "$log_file"
    return 0
  fi
  if [[ "$args" == *"/actions/runs/102/cancel "* ]]; then
    echo 102 >> "$log_file"
    return 1
  fi
  if [[ "$args" == *"/actions/runs/102 "* ]]; then
    printf '%s\n' completed
    return 0
  fi
  if [[ "$args" == *"/actions/runs/105/cancel "* ]]; then
    echo 105 >> "$log_file"
    return 1
  fi
  if [[ "$args" == *"/actions/runs/105 "* ]]; then
    printf '%s\n' in_progress
    return 0
  fi
  echo "unexpected mock gh call:$args" >&2
  return 1
}

export GH_REPO=madhakish/cadence
export WORKFLOW_FILE=ci.yml
export PR_HEAD_REF=agent/ci-test-hardening
export CURRENT_RUN_ID=104
export CURRENT_RUN_NUMBER=20

# Cancel older active runs, tolerate a list/cancel completion race, and leave
# the current, newer, and already-completed runs untouched.
MOCK_RUNS=$'101\t17\tin_progress\n102\t18\tqueued\n103\t19\tcompleted\n104\t20\tin_progress\n106\t21\tqueued'
cancel_stale_pr_runs >/dev/null
if [[ "$(sort -n "$log_file" | tr '\n' ' ')" != "101 102 " ]]; then
  echo "stale-run cancellation selected the wrong runs" >&2
  exit 1
fi

# Do not hide a real cancellation/API failure behind best-effort behavior.
: > "$log_file"
MOCK_RUNS=$'105\t19\tin_progress'
if cancel_stale_pr_runs >/dev/null 2>&1; then
  echo "active-run cancellation failure must fail preflight" >&2
  exit 1
fi

# Reject malformed GitHub responses before acting on an ambiguous run.
MOCK_RUNS=$'not-an-id\t19\tin_progress'
if cancel_stale_pr_runs >/dev/null 2>&1; then
  echo "malformed run identity must fail preflight" >&2
  exit 1
fi

echo "Stale PR workflow cancellation tests passed"
