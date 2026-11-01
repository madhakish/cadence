#!/usr/bin/env bash
# The signing-health tracking issue against a mock `gh`: one issue, opened on
# failure or an expiry warning, never duplicated, commented on only when the
# findings change, closed on a clean pass.
set -euo pipefail

cd "$(dirname "$0")/../.."
source .github/scripts/signing-health-issue.sh

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

# MOCK_ISSUES: what `gh issue list --json number,title` returns (open issues).
# MOCK_BODY: the body `gh issue view` returns. Writes are logged as
# "<verb> <issue-or-title>"; the last body sent is kept in $work/body.
gh() {
  [[ "$1" == issue ]] || fail "unexpected gh call: $*"
  local verb="$2" target="$3" jq="" body="" title="" args=" $* "
  shift 2
  while (($#)); do
    case "$1" in
      --jq) jq="$2"; shift ;;
      --body) body="$2"; shift ;;
      --title) title="$2"; shift ;;
      --comment) body="$2"; shift ;;
    esac
    shift
  done
  [[ "$args" == *" --repo example/cadence "* ]] || fail "gh $verb must name the repository"
  case "$verb" in
    list)
      [[ "$args" == *" --state open "* ]] || fail "only open issues may be reused"
      jq -r "$jq" <<<"$MOCK_ISSUES" ;;
    view) printf '%s\n' "$MOCK_BODY" ;;
    create) echo "create $title" >> "$work/log"; printf '%s' "$body" > "$work/body" ;;
    edit) echo "edit $target" >> "$work/log"; printf '%s' "$body" > "$work/body" ;;
    comment|close) echo "$verb $target" >> "$work/log"; printf '%s' "$body" > "$work/comment" ;;
    *) fail "unexpected gh issue $verb" ;;
  esac
}

export GH_REPO=example/cadence RUN_URL=https://github.com/example/cadence/actions/runs/7
unrelated='[{"number":12,"title":"Signing health: action needed (2025)"},{"number":13,"title":"ci: something else"}]'
tracking='[{"number":80,"title":"Signing health: action needed"},{"number":77,"title":"Signing health: action needed"},{"number":13,"title":"ci: something else"}]'

sync() { # outcome findings-text open-issues [previous-body]
  : > "$work/log"; rm -f "$work/body" "$work/comment"
  if [[ -n "$2" ]]; then printf '%s\n' "$2" > "$work/findings.md"; else : > "$work/findings.md"; fi
  PREFLIGHT_OUTCOME="$1" FINDINGS_FILE="$work/findings.md" MOCK_ISSUES="$3" MOCK_BODY="${4:-}" \
    sync_signing_health_issue > /dev/null
}
expect_log() { [[ "$(cat "$work/log")" == "$1" ]] || fail "$2: expected '$1', got '$(cat "$work/log")'"; }

expired="- **Error:** the active App Store profile for com.example.App expired on 2026-10-30."
expiring="- **Expiring:** the distribution certificate expires on 2026-11-21, in 20 days."

# A failure with no tracking issue open creates exactly one, with the findings.
sync failure "$expired" "$unrelated"
expect_log "create Signing health: action needed" "first failure"
[[ "$(cat "$work/body")" == *"$expired"* && "$(cat "$work/body")" == *"Latest run: $RUN_URL"* ]] \
  || fail "the new issue must list the findings and the run, got: $(cat "$work/body")"
first_body="$(cat "$work/body")"

# An expiry warning alone (the check passed) also needs action.
sync success "$expiring" "$unrelated"
expect_log "create Signing health: action needed" "expiry warning"

# The same findings again: refresh the oldest open tracking issue silently.
sync failure "$expired" "$tracking" "$first_body"
expect_log "edit 77" "unchanged findings"

# New findings: refresh and comment once, still no second issue.
sync failure "$expired"$'\n'"$expiring" "$tracking" "$first_body"
expect_log $'edit 77\ncomment 77' "changed findings"
[[ "$(cat "$work/body")" == *"$expiring"* ]] || fail "the refreshed body must list the new findings"

# A clean pass closes the tracking issue; with none open it writes nothing.
sync success "" "$tracking"
expect_log "close 77" "recovered"
[[ "$(cat "$work/comment")" == *"passed in $RUN_URL"* ]] || fail "the closing comment must link the run"
sync success "" "$unrelated"
expect_log "" "healthy"

# A crash before the findings were written still opens the issue.
sync failure "" "$unrelated"
expect_log "create Signing health: action needed" "failure without findings"
[[ "$(cat "$work/body")" == *"failed without reporting findings"* ]] || fail "an empty failure must say so"

echo "Signing health issue tests passed"
