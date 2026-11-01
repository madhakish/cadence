# Repository hygiene

These checks enforce the few mechanical contracts in [AGENTS.md](../AGENTS.md)
and [coordination](../AGENT-COORDINATION.md). They catch mistakes; they do
not prove that work is complete.

## Pull request contract

The squash commit takes the PR title as its subject and the PR body as its
message, and semantic-release reads the subject to choose the release. The
required `PR contract` check therefore validates one thing: the title is a
Conventional Commit (`fix(watch): ...`, `feat!: ...`, `ci: ...`). It reruns
when the title is edited, without rerunning the app pipeline. The body is
free prose; the [template](../.github/pull_request_template.md) suggests
"what and why" and "checks".

Link an issue with `Closes #123` only when the PR satisfies all of its
acceptance criteria, and `Refs #123` otherwise. An issue is not required.

## Local checks and CI

From the repository root with Node 22 or newer:

```sh
make check   # the CI preflight, including the checks below
make who     # open PRs, their files, and overlap with this branch
```

`make check` runs the script tests, the instruction check and
`git diff --check` before any expensive suite. CI's preflight job runs the
same script, so a local pass means the CI preflight passes too.

These checks run candidate code under `pull_request`. A PR can change its own
workflow or validator, so they are not tamper-proof; review changes to them.
Never give this path write credentials or repository secrets.

The instruction check keeps the always-loaded files within their budgets
(listed in [maintaining agent instructions](AGENT-INSTRUCTIONS.md)), requires
the Claude imports and entry-point links, and resolves local links, heading
anchors and import cycles. It ignores fenced examples and HTML comments and
does not fetch external links.

## Area labels

`Area labels` reads its configuration from the trusted base branch using
`pull_request_target` and never checks out or runs PR code. Labels are for
navigation only; they grant no ownership and choose no tests. The CI path
classifier remains authoritative.

## Merge settings in force

Classic protection on `main` requires a PR with zero approving reviews and
these checks: `CadenceCore tests (Linux)`, `Web tests (parity + smoke)`,
`App build (macOS)` and `PR contract`. The `CadenceCore tests (Linux)` name is
kept for compatibility although it runs on macOS; renaming it needs a
coordinated protection change. Repository auto-merge is enabled. See
[CI acceptance](CI-ACCEPTANCE.md#verified-merge-policy-2026-10-02) for the
verified details.

## References

- [Issue linking](https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/linking-a-pull-request-to-an-issue)
- [Labeler configuration and permissions](https://github.com/actions/labeler)
- [Actions security](https://docs.github.com/en/actions/reference/security/secure-use)
