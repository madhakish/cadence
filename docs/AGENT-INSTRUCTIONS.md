# Maintaining agent instructions

Keep one canonical repository contract in [AGENTS.md](../AGENTS.md) and one
coordination protocol in [AGENT-COORDINATION.md](../AGENT-COORDINATION.md).
Tool entry points load those files instead of maintaining competing copies.
The [Torvalds doctrine](../.agents/torvalds-doctrine.md) applies to implementation
and code review; do not paste another copy into each entry point.

## Loading and precedence

- Codex discovers `AGENTS.md` along its instruction chain. The root guide
  explicitly requires reading coordination and relevant detailed guidance.
- Claude's `CLAUDE.md` imports `@AGENTS.md` and
  `@AGENT-COORDINATION.md` as plain lines. Keep imports acyclic. Other tools
  are not assumed to expand Claude's import syntax.
- Copilot's `.github/copilot-instructions.md` has short read instructions and
  essential review constraints. Feature/IDE support differs; references alone
  do not prove a tool fetched their targets.
- Chat/mobile sessions without a checkout must fetch these same files through
  GitHub. Global personalization is environment-specific and is not shipped
  by this repository.
- User/runtime policy retains its normal precedence. Nested guidance applies
  to its subtree; do not silently weaken repository safety or compatibility.
  Do not create `AGENTD.md`, case variants, or override files to bypass loading.
- Restart an existing session after changing startup instructions, or explicitly
  reload the changed files. Do not assume a running agent received the update.

## Context budgets

These are repository maintenance budgets, not universal model context limits:

| Content | Budget |
| --- | --- |
| Root `AGENTS.md` | At most 200 lines and 8 KiB |
| `CLAUDE.md` loader | At most 20 lines and 1 KiB |
| `.github/copilot-instructions.md` | At most 40 lines and 2 KiB |
| `AGENT-COORDINATION.md` | At most 120 lines and 6 KiB |
| The above plus doctrine and automatic imports, counted once each | At most 20 KiB |

Keep durable instructions about triggers, actions, evidence, and stopping rules.
Put current run IDs, claims, status, and results in issues/PRs. Put detailed
task procedures behind explicit reading triggers; do not import every document
at startup. When a required procedure is long, read the relevant complete
section rather than silently truncating its safety rules.

Codex's documented default instruction-discovery cap is 32 KiB across its
`AGENTS.md` chain; a user's global/nested files and configuration also consume
that allowance. Claude recommends keeping a `CLAUDE.md` under 200 lines.
Imports and files read later still consume model context. Our budgets leave
headroom but cannot guarantee an arbitrary user's remaining context.

Measure after changes from the repository root:

```sh
wc -lc AGENTS.md CLAUDE.md AGENT-COORDINATION.md \
  .github/copilot-instructions.md .agents/torvalds-doctrine.md
git diff --check
```

Also resolve local Markdown links/imports, check for import cycles, and review
that moved rules remain reachable. No extra app test suite is needed solely
to count documentation bytes; existing required CI still applies.

## Loading and coordination experiment

1. Start a fresh session in each actual tool → verify: it reports the loaded
   instruction files and current coordination protocol, not just file names.
2. Give agent A a bounded task → verify: its issue/PR has a scoped claim.
3. Give agent B that task reference → verify: it sees A's claim and reviews or
   takes agreed disjoint work instead of duplicating the implementation.
4. Have B post one finding → verify: A fetches it at a checkpoint without the
   owner forwarding it. A posted message alone is not proof of consumption.
5. Resume in a fresh session → verify: it can recover branch/SHA, evidence,
   remaining work, and ownership from the thread.

Count missed findings, duplicate implementations, conflicting edits, useful
comments, and coordination overhead. This convention does not implement
atomic locking, scheduling, or guaranteed delivery. Add enforcement only in
response to an observed need and an authorized change.

## Official references

Checked September 19, 2026:

- [Codex instruction discovery](https://learn.chatgpt.com/docs/agent-configuration/agents-md)
- [Claude instruction files and imports](https://code.claude.com/docs/en/memory)
- [Copilot instruction support by feature](https://docs.github.com/en/copilot/reference/custom-instructions-support)

## Automated hygiene

[Repository hygiene](REPOSITORY-HYGIENE.md) documents the PR contract, automated
instruction checks, labels, and proposed merge settings. Run the local commands
there when changing instructions or workflows. The gate checks structure and
budgets; reviewers still verify preserved meaning and actual evidence.
