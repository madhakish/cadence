#!/usr/bin/env bash
set -euo pipefail

# Print the repository paths a CI run changed, one per line, for
# classify-ci-paths.sh. Needs full history (checkout fetch-depth: 0).
#
#   EVENT_NAME  github.event_name
#   BASE_SHA    pull_request.base.sha for a PR, event.before for a push
#   HEAD_SHA    the commit under test
#
# A pull request is compared from its merge base with the base branch, never
# from the base branch's tip: once main moves past the fork point, a diff
# against the tip counts everything main changed since as the PR's own work,
# and a web-only PR runs the whole native tier (#362). A push is compared from
# the commit it replaced; a new ref or an unknown `before` (empty or all
# zeros) classifies the whole tree.

: "${HEAD_SHA:?HEAD_SHA is required}"
base="${BASE_SHA:-}"

if [[ -z "$base" || "$base" =~ ^0+$ ]]; then
  exec git ls-tree -r --name-only "$HEAD_SHA"
fi

if [[ "${EVENT_NAME:-}" == "pull_request" ]]; then
  if ! base="$(git merge-base "$base" "$HEAD_SHA")"; then
    echo "no merge base between $BASE_SHA and $HEAD_SHA; is the history complete?" >&2
    exit 1
  fi
fi

# --no-renames lists both sides of a move: a model moved out of a
# migration-bearing path must still run the migration suite.
git diff --no-renames --name-only "$base" "$HEAD_SHA"
