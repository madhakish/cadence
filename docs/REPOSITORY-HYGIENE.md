# Repository hygiene

These workflows enforce mechanical contracts from [AGENTS.md](../AGENTS.md)
and [coordination](../AGENT-COORDINATION.md). They do not prove task completion,
authenticate run IDs, or start agent sessions.

## Pull request contract

Use a Conventional Commit title and fill these three lines outside comments or
code fences. The template includes them:

```text
Task: #123
Scope: What this PR changes and why.
Verification: Actual checks and results, or the specific pending reason.
```

Task accepts a same-repository issue number, `owner/repo#123`, or a GitHub issue
URL. CI verifies it exists and is an issue, not a PR. Cross-repository private
issues need token access; use an accessible local task with a cross-link when
the repository token cannot read the other repository.

For minor maintenance or a scoped review fix whose existing PR is the task
record, use `Task: none — <specific reason>`. Avoid duplicate bookkeeping.
Authenticated Dependabot PRs are exempt from these fields; their Conventional
Commit titles and all code checks still apply. No arbitrary bot exemption exists.

The check validates structure and issue existence. It cannot certify a claim
that tests passed. Review evidence for the current commit. A pending reason
makes metadata complete, not the work merge-ready.

Use `Closes #123` separately only when the issue's entire acceptance criteria
are satisfied. Partial work should reference the issue without closing it.
GitHub handles closure on qualifying merges to the default branch.

## Local checks and CI

From the repository root with Node 22 or newer:

```sh
node --test .github/scripts/test-repository-hygiene.mjs
node .github/scripts/check-agent-instructions.mjs
git diff --check
```

`Repository hygiene` runs on PR changes, including title/body edits, and main
pushes. It has a five-minute timeout, a read-only token, no secrets, and no npm
install. It cancels superseded runs of this workflow only.

The instruction check validates entry-point budgets, the aggregate 20 KiB
budget including doctrine and automatic imports, required entry-point links,
local inline/reference-definition links, ATX heading
anchors, required Claude imports, import cycles, and paths outside the checkout.
Fenced examples and HTML comments are ignored. It scans instruction/maintenance
guides and explicitly imported files, without crawling every document or
fetching external links. Keep instruction Markdown simple. Backtick command
paths and semantic policy preservation still need review. The documented
limits are maintenance budgets, not model context promises.

## Area labels

`Area labels` reads configuration from the PR's trusted main base using
`pull_request_target`. It never checks out or runs PR code. Its pinned labeler
may create missing labels and synchronizes only the configured `area:*` labels;
other labels remain human-owned. Configuration changes take effect after merge.
An existing PR needs a later push or reopening to refresh labels.

Labels identify source areas for navigation. They never grant ownership or
permissions, establish migration requirements, or select which tests can skip.
The actual diff and existing CI classifier remain authoritative for validation.

## Merge settings to apply after adoption

Workflow files do not activate branch protection. After the new check passes
and becomes selectable, configure a main-branch ruleset with these values:

| Setting | Value |
| --- | --- |
| Target | Default branch |
| Require pull requests | Enabled |
| Required approving reviews | 0 for the current single-maintainer setup |
| Require conversation resolution | Enabled |
| Required checks | `CadenceCore tests (Linux)`, `Web tests (parity + smoke)`, `App build (macOS)`, `Repository hygiene` |
| Require branch up to date | Enabled |
| Block force pushes and deletions | Enabled |

Do not require an optional reviewer job that can skip for missing credentials.
When independent authorized reviewers are available, choose an approval count
and dismiss stale approvals. Agents sharing an account are not independent
GitHub approvers. Preserve narrowly scoped release-identity exceptions needed
by the existing release pipeline. These settings require administration access;
this file is a proposal, not evidence of enforcement.

## Next experiments

- A consolidated review summary should distinguish current/older commit SHAs,
  actual completed/skipped/failed execution, and unresolved threads. Verify
  review delivery separately from a green action wrapper.
- Start inactivity reminders with needs-information issues and automatic
  closure disabled. Accepted backlog and blocked work remain open.
- Agent wake-up requires authorized dispatch, bounded execution, and duplicate
  suppression. Ordinary comments remain durable records.

## References

- [Issue linking](https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/linking-a-pull-request-to-an-issue)
- [Ruleset controls](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets)
- [Labeler configuration and permissions](https://github.com/actions/labeler)
- [Actions security](https://docs.github.com/en/actions/reference/security/secure-use)
