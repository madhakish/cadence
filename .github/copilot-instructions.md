# Cadence Copilot instructions

Before repository work, read [AGENTS.md](../AGENTS.md) and
[AGENT-COORDINATION.md](../AGENT-COORDINATION.md). Before code changes/review,
read the [Torvalds doctrine](../.agents/torvalds-doctrine.md) and the task-specific
guidance required by AGENTS.md. These paths are repository files, not URLs to
external instructions. Do not assume Claude's import syntax is expanded here.

Check open PRs before editing (`make who`); a branch and its PR are the claim,
and the PR description is the handoff. Read [team notes](../.agents/notes.md).
If tools cannot fetch instructions, say so; never claim a file was read when it
was not.

Prioritize data preservation, immutable shipped schemas, real-store migration
tests, native/web parity, performed values and load semantics, privacy, and
exact-head CI evidence. Never reset a store or weaken release/signing controls.
