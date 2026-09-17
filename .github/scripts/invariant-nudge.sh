#!/usr/bin/env bash
# Post or refresh the advisory invariant-registry comment on a pull request
# (#95). Reads the PR's commits and changed files, asks invariant-nudge.mjs
# for the comment body, and keeps exactly one comment (marker-identified)
# up to date. Never fails the workflow over the outcome.
set -euo pipefail
: "${REPO:?set REPO=owner/name}" "${PR:?set PR=<number>}"
marker='<!-- invariant-nudge -->'

commits="$(gh api "repos/$REPO/pulls/$PR/commits" --paginate | jq -s 'add | [.[] | {sha: .sha, message: .commit.message}]')"
files="$(gh api "repos/$REPO/pulls/$PR/files" --paginate | jq -s 'add | [.[].filename]')"
body="$(jq -n --argjson commits "$commits" --argjson files "$files" '{commits: $commits, files: $files}' \
  | node .github/scripts/invariant-nudge.mjs)"
existing="$(gh api "repos/$REPO/issues/$PR/comments" --paginate \
  | jq -rs --arg marker "$marker" 'add | [.[] | select(.body | startswith($marker))] | (.[0].id // empty)')"

if [[ -z "$body" ]]; then
  if [[ -n "$existing" ]]; then
    gh api -X DELETE "repos/$REPO/issues/comments/$existing" >/dev/null
    echo "removed a nudge that no longer applies"
  else
    echo "no fix commits; nothing to say"
  fi
  exit 0
fi
if [[ -n "$existing" ]]; then
  gh api -X PATCH "repos/$REPO/issues/comments/$existing" -f body="$body" >/dev/null
  echo "updated nudge comment $existing"
else
  gh api -X POST "repos/$REPO/issues/$PR/comments" -f body="$body" >/dev/null
  echo "posted nudge comment"
fi
