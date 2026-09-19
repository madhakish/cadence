# Cadence Copilot instructions

Before repository work, read [AGENTS.md](../AGENTS.md) and
[AGENT-COORDINATION.md](../AGENT-COORDINATION.md). Before code changes/review,
read the [Torvalds doctrine](../.agents/torvalds-doctrine.md) and the task-specific
guidance required by AGENTS.md. These paths are repository files, not URLs to
external instructions. Do not assume Claude's import syntax is expanded here.

Check current task/PR discussion and ownership before editing; reuse that
thread, identify the run, and leave evidence and a resumable handoff.
A review-only agent can use its PR review surface without an exclusive claim.
If tools cannot fetch instructions or post updates, state the limitation;
never claim a file was read or coordination occurred when it did not.

Prioritize data preservation, immutable shipped schemas, real-store migration
tests, native/web parity, performed values and load semantics, privacy, and
exact-head CI evidence. Never reset a store or weaken release/signing controls.
