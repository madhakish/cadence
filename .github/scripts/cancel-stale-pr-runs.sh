#!/usr/bin/env bash
set -euo pipefail

cancel_stale_pr_runs() {
  : "${GH_REPO:?GH_REPO is required}"
  : "${WORKFLOW_FILE:?WORKFLOW_FILE is required}"
  : "${PR_HEAD_REF:?PR_HEAD_REF is required}"
  : "${CURRENT_RUN_ID:?CURRENT_RUN_ID is required}"
  : "${CURRENT_RUN_NUMBER:?CURRENT_RUN_NUMBER is required}"

  if ! [[ "$CURRENT_RUN_ID" =~ ^[0-9]+$ && "$CURRENT_RUN_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "current run identity must be numeric" >&2
    return 1
  fi

  local runs
  runs="$(
    gh api --method GET --paginate \
      "repos/$GH_REPO/actions/workflows/$WORKFLOW_FILE/runs" \
      -f event=pull_request \
      -f branch="$PR_HEAD_REF" \
      -f per_page=100 \
      --jq '.workflow_runs[] | [.id, .run_number, .status] | @tsv'
  )"

  local run_id run_number status response observed_status
  while IFS=$'\t' read -r run_id run_number status; do
    [[ -n "$run_id" ]] || continue
    if ! [[ "$run_id" =~ ^[0-9]+$ && "$run_number" =~ ^[0-9]+$ ]]; then
      echo "invalid workflow-run response: $run_id $run_number $status" >&2
      return 1
    fi
    [[ "$run_id" != "$CURRENT_RUN_ID" ]] || continue
    (( run_number < CURRENT_RUN_NUMBER )) || continue
    [[ "$status" != "completed" ]] || continue

    echo "Cancelling stale PR workflow run $run_id (run $run_number, $status)"
    if ! response="$(gh api --method POST "repos/$GH_REPO/actions/runs/$run_id/cancel" 2>&1)"; then
      # A run can finish between the list and cancel calls. Accept only that
      # narrow race; authentication and API failures must still fail preflight.
      observed_status="$(
        gh api --method GET "repos/$GH_REPO/actions/runs/$run_id" \
          --jq '.status' 2>/dev/null || true
      )"
      if [[ "$observed_status" == "completed" ]]; then
        echo "Run $run_id completed before cancellation"
      else
        echo "$response" >&2
        return 1
      fi
    fi
  done <<< "$runs"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  cancel_stale_pr_runs
fi
