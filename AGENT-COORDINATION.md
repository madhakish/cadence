# Working alongside other agents

Several agents and the owner work here at once, usually through one GitHub
account. Coordinate through the work itself, meaning branches, pull requests
and a few words where they help, not through status posts.

## Before you start

- Run `make who`. It lists open pull requests with their branch, age and
  files, and flags any that touch files your branch already changes.
- If an open PR already covers your task and moved in the last day, pick other
  work, review it, or ask on that PR what is left. A PR idle for a day or more
  is fair to take over: say so in one comment, then continue from its branch
  or start fresh.
- Read the [team notes](.agents/notes.md), which hold what earlier agents
  learned the hard way.

## While you work

- Your branch and PR are your claim. Push early, and open the PR as a draft
  while the work is unfinished so others can see it. Link the issue with
  `Closes #N` when the PR finishes it or `Refs #N` otherwise; do not open an
  issue just to have one.
- Keep the PR description current: what changed and why, what you checked,
  what is left. It becomes the squash commit body and it is the handoff, so
  skip separate status comments.
- Comment when someone needs to know or decide something: a blocker, a
  question, a change of plan, or a finding on another agent's PR.
- Do not push to another agent's branch unless its PR says it was handed off.
  Never rewrite shared history. Subagents work under their parent's PR unless
  they open their own.

## When you stop

- Finished: mark the PR ready and run `gh pr merge <n> --squash --auto`. It
  merges when the required checks pass. The PR title is the squash subject and
  sets the release, so make it a correct Conventional Commit.
- Unfinished: leave the PR in draft with a description that says what is done,
  what is next and how to check it. Anyone can pick it up from there.
- If you hit something the next agent would trip over, such as a slow job, a
  flaky test, a tool quirk or a review finding that keeps coming back, add a
  line to the [team notes](.agents/notes.md) in the same PR. Delete lines that
  are no longer true.

Cadence is public: keep private paths, personal data and secrets out of
issues, PRs and notes.
