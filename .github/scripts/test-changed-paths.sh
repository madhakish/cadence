#!/usr/bin/env bash
set -euo pipefail

# Regression tests for changed-paths.sh against a throwaway repository whose
# main branch keeps moving after a pull request forks from it (#362).

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
changed_paths="$script_dir/changed-paths.sh"
classifier="$script_dir/classify-ci-paths.sh"

# A git hook (pre-commit runs `make check`) exports variables such as
# GIT_INDEX_FILE that would point the fixture at the real repository.
while IFS= read -r var; do unset "$var"; done < <(git rev-parse --local-env-vars)

repo="$(mktemp -d)"
trap 'rm -rf "$repo"' EXIT

git -C "$repo" init -q --initial-branch=main
git -C "$repo" config user.name "Cadence CI"
git -C "$repo" config user.email "ci@cadence.invalid"
git -C "$repo" config commit.gpgsign false
git -C "$repo" config core.hooksPath /dev/null

# Commit one change to each path on the current branch and print the commit.
commit() {
  local path
  for path in "$@"; do
    mkdir -p "$repo/$(dirname "$path")"
    printf '%s\n' "$path" >> "$repo/$path"
    git -C "$repo" add -- "$path"
  done
  git -C "$repo" commit -qm "change $*"
  git -C "$repo" rev-parse HEAD
}

changed() {
  (cd "$repo" && env EVENT_NAME="$1" BASE_SHA="$2" HEAD_SHA="$3" bash "$changed_paths")
}

scenarios=0
assert_lines() {
  local description="$1"
  local expected="$2"
  local actual="$3"
  scenarios=$((scenarios + 1))
  if [[ "$actual" != "$expected" ]]; then
    echo "$description: unexpected output" >&2
    echo "expected:" >&2
    echo "$expected" >&2
    echo "actual:" >&2
    echo "$actual" >&2
    exit 1
  fi
}

# main: a native app and a web app.
fork="$(commit Cadence/App.swift web/app/js/app.js)"

# A web-only pull request forks here.
git -C "$repo" checkout -q -b pr
pr_head="$(commit web/tests/browser/spec.mjs)"

# main moves on with native and shared-core work the PR never touched.
git -C "$repo" checkout -q main
main_tip="$(commit Cadence/Views/HomeView.swift CadenceCore/Sources/CadenceCore/Progression.swift)"

assert_lines "PR behind main lists only its own files" \
  'web/tests/browser/spec.mjs' \
  "$(changed pull_request "$main_tip" "$pr_head")"
assert_lines "PR behind main classifies as web-only" \
  $'native=false\nmigrations=false\nweb=true' \
  "$(changed pull_request "$main_tip" "$pr_head" | bash "$classifier")"

# The PR merges main in ("Update branch"), adds a commit, and main moves again.
git -C "$repo" checkout -q pr
git -C "$repo" merge -q --no-edit main
pr_updated="$(commit web/tests/browser/other.spec.mjs)"
git -C "$repo" checkout -q main
main_later="$(commit Cadence/Models/SessionModels.swift)"

assert_lines "PR that merged main lists only its own files after main moves again" \
  $'web/tests/browser/other.spec.mjs\nweb/tests/browser/spec.mjs' \
  "$(changed pull_request "$main_later" "$pr_updated")"

# Pushes compare against the commit they replaced, not a merge base.
assert_lines "push with a real before lists that diff" \
  $'Cadence/Models/SessionModels.swift\nCadence/Views/HomeView.swift\nCadenceCore/Sources/CadenceCore/Progression.swift' \
  "$(changed push "$fork" "$main_later")"
# A force-push whose before is not an ancestor: the two trees are compared
# directly (a merge base would hide the PR files the push removed).
assert_lines "push replacing a diverged tip compares the two trees directly" \
  $'Cadence/Models/SessionModels.swift\nweb/tests/browser/other.spec.mjs\nweb/tests/browser/spec.mjs' \
  "$(changed push "$pr_updated" "$main_later")"

full_tree=$'Cadence/App.swift\nCadence/Models/SessionModels.swift\nCadence/Views/HomeView.swift\nCadenceCore/Sources/CadenceCore/Progression.swift\nweb/app/js/app.js'
assert_lines "push with an all-zero before lists the full tree" \
  "$full_tree" \
  "$(changed push 0000000000000000000000000000000000000000 "$main_later")"
assert_lines "push with an empty before lists the full tree" \
  "$full_tree" \
  "$(changed push "" "$main_later")"

# A move out of a migration-bearing path lists both sides, so the migration
# suite still runs. With rename detection only the new path appears.
git -C "$repo" checkout -q -b move "$main_later"
mkdir -p "$repo/Cadence/Archive"
git -C "$repo" mv Cadence/Models/SessionModels.swift Cadence/Archive/SessionModels.swift
git -C "$repo" commit -qm "move the session model"
move_head="$(git -C "$repo" rev-parse HEAD)"
git -C "$repo" checkout -q main
assert_lines "a moved model lists both its old and new paths" \
  $'Cadence/Archive/SessionModels.swift\nCadence/Models/SessionModels.swift' \
  "$(changed pull_request "$main_later" "$move_head")"
assert_lines "a moved model still runs the migration suite" \
  $'native=true\nmigrations=true\nweb=false' \
  "$(changed pull_request "$main_later" "$move_head" | bash "$classifier")"

# Unrelated histories must fail loudly, not classify an empty diff.
orphan="$(git -C "$repo" commit-tree "$(git -C "$repo" mktree < /dev/null)" -m orphan)"
scenarios=$((scenarios + 1))
if changed pull_request "$orphan" "$pr_head" >/dev/null 2>&1; then
  echo "PR with no merge base: expected changed-paths.sh to fail" >&2
  exit 1
fi

echo "Changed-path tests passed ($scenarios scenarios)"
