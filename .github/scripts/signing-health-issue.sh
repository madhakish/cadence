#!/usr/bin/env bash
# Keep one tracking issue in step with the daily signing health check
# (signing-health.yml). A failure or an expiry warning opens it; while the
# findings stand it is refreshed silently, a change in findings adds one
# comment, and a clean pass closes it. The exact title is the key: the open
# issues are listed directly (the search index lags), never searched.
#
#   GH_REPO            owner/repo
#   PREFLIGHT_OUTCOME  the check step's outcome (success, failure, ...)
#   FINDINGS_FILE      the list check-signing-material.rb wrote (SIGNING_FINDINGS)
#   RUN_URL            this workflow run
set -euo pipefail

SIGNING_HEALTH_TITLE="Signing health: action needed"

sync_signing_health_issue() {
  : "${GH_REPO:?GH_REPO is required}"
  : "${PREFLIGHT_OUTCOME:?PREFLIGHT_OUTCOME is required}"
  : "${RUN_URL:?RUN_URL is required}"

  local findings=""
  if [[ -s "${FINDINGS_FILE:-}" ]]; then
    findings="$(cat "$FINDINGS_FILE")"
  fi
  if [[ "$PREFLIGHT_OUTCOME" != "success" && -z "$findings" ]]; then
    findings="- **Error:** the signing health check failed without reporting findings; see the run log."
  fi

  local number
  number="$(gh issue list --repo "$GH_REPO" --state open --limit 500 --json number,title \
    --jq "[.[] | select(.title == \"$SIGNING_HEALTH_TITLE\") | .number] | min // empty")"

  if [[ -z "$findings" ]]; then
    if [[ -n "$number" ]]; then
      gh issue close "$number" --repo "$GH_REPO" --comment "The signing health check passed in $RUN_URL."
      echo "Signing health passed; closed #$number"
    else
      echo "Signing health passed"
    fi
    return 0
  fi

  local digest body
  digest="$(printf '%s\n' "$findings" | git hash-object --stdin)"
  body="The daily signing health check (\`.github/workflows/signing-health.yml\`) needs action:

$findings

Latest run: $RUN_URL

This issue closes itself when the check passes. What each finding means and how to fix it: \`docs/TESTFLIGHT.md\`, Signing health.
<!-- signing-health findings $digest -->"

  if [[ -z "$number" ]]; then
    gh issue create --repo "$GH_REPO" --title "$SIGNING_HEALTH_TITLE" --body "$body"
    return 0
  fi
  local previous
  previous="$(gh issue view "$number" --repo "$GH_REPO" --json body --jq .body)"
  gh issue edit "$number" --repo "$GH_REPO" --body "$body" >/dev/null
  if [[ "$previous" == *"<!-- signing-health findings $digest -->"* ]]; then
    echo "Signing health findings unchanged; refreshed #$number"
  else
    gh issue comment "$number" --repo "$GH_REPO" --body "The signing health findings changed in $RUN_URL; the issue body lists them."
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  sync_signing_health_issue
fi
