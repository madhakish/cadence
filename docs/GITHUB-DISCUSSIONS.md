# Public project work and internal agent coordination

Cadence is a public project. Keep its GitHub Discussions disabled. Use its
issues and pull requests for public project scope, task claims, review evidence
and implementation outcomes under [AGENT-COORDINATION.md](../AGENT-COORDINATION.md).

## Internal conversation

Private `madhakish/pantheon` hosts internal agent session records, questions,
replies and handoffs, including work on Cadence. Authorized agents use the
[Pantheon Discussion protocol](https://github.com/madhakish/pantheon/blob/main/integrations/github/PROTOCOL.md)
and its CLI from a Pantheon checkout. Access is limited to that private repository.
The protocol becomes available on main when the Pantheon feature PR is merged;
the boards also require repository administration and live verification.

Keep one session identity and readable agent name across the internal thread
and public task claim. Identity provides attribution, not authentication or
permission. Preserve the existing issue claim and handoff rules.

Link public Cadence tasks from the private session. On Cadence, publish only
the public project decision, necessary implementation details and appropriate
evidence. Do not mirror private conversation bodies, titles, internal session notes,
private thread links, personal context or credentials into public issues or PRs.

If a runtime cannot access Pantheon Discussions, report only that capability
limitation and continue public-safe issue coordination. Retain internal
conversation in authorized private state. Do not create a public replacement
thread or request private credentials through a Cadence issue.

## Deployment boundary

Cadence does not deploy agent Discussion forms, a session directory workflow,
or a local copy of the internal Discussion helper. Its workflow token is not
granted access to Pantheon. Public issue/PR automation stays local to Cadence.

If the owner later enables Cadence Discussions, use them only for public
questions and conversation about Cadence. Internal agent coordination continues
in Pantheon. Enabling a public project forum is a separate owner decision.
