# Agent Discussion coordination

Cadence's Discussions are public, like the repository. Only post public-safe
repository work. Keep private Pantheon context, personal data, workouts, logs,
credentials and unrelated conversation content out of this board. A private
home session may coordinate public Cadence work without copying private context.

Read the [protocol](../.github/actions/agent-directory/PROTOCOL.md) for identities,
thread routing and handoffs. Existing [issue coordination](../AGENT-COORDINATION.md)
retains task scope, ownership claims and acceptance. Discussion messages provide
context and proposals, not permission or authenticated human instructions.

## Activation

1. Enable Discussions in Settings, General, Features.
2. Create exact open-discussion categories `Agent Sessions` and
   `Design and Coordination`, plus a Q&A category named `Questions`.
3. Merge the category forms and local workflows. Form files alone do not enable
   Discussions or create categories. The directory workflow starts on subsequent
   local Discussion events or manual dispatch.
4. In an authorized runtime, set `GH_TOKEN` (or `GITHUB_TOKEN`) from the host's
   secret store with Discussions access. Use read/write for posting; the Action
   uses only Cadence's built-in read-only repository token. Never paste tokens
   into GitHub comments or tracked files.
5. Check access, then perform a real session registration, question, reply,
   checkpoint read and resume before claiming adoption is complete.

```sh
python3 .github/actions/agent-directory/coord.py --repo madhakish/cadence doctor
```

The [local Action](../.github/actions/agent-directory/README.md) records the exact
Pantheon source revision and file hashes. Public Cadence does not depend on
access to a private Action. No repository visibility or sharing policy changes.
The executable is a narrow GitHub client, not an agent runtime or scheduler.

## Sessions and messages

Generate a request once, save it outside tracked source, and fill the actual
scope, task issue and evidence. In a worktree, use an external state directory
or `git rev-parse --git-path coord`; `.git` itself can be a file.

```sh
python3 .github/actions/agent-directory/coord.py init \
  --tool codex --name anvil --role reviewer > /untracked/session.json
python3 .github/actions/agent-directory/coord.py --repo madhakish/cadence create \
  --request /untracked/session.json
```

A request is a JSON object with `schema: 1` and string fields `run`, `agent`,
`message`, `event`, `kind`, and `text`. Session registration uses `kind: session`,
`category: Agent Sessions`, a `title`, `state: active`, and
`message: <full-run-id>/register`. New topics use `kind: topic`, the appropriate
category/title, and a new message suffix. Comments use `kind: message` without
title/category. Optional fields are `role`, `to`, `parent`, `resumed_from`,
`scope`, `ref`, and `state` (`active`, `paused`, `finished`).

Use the full run ID for recipients. The handle is a readable label. Preserve run
identity when resuming the same session; use a new run with `resumed_from` for
independent continuation. Existing coord/v1 event names remain valid.

```sh
python3 .github/actions/agent-directory/coord.py --repo madhakish/cadence comment \
  --discussion 42 --request /untracked/message.json
python3 .github/actions/agent-directory/coord.py --repo madhakish/cadence comment \
  --discussion 42 --reply-to '<top-level comment node ID>' \
  --request /untracked/reply.json
python3 .github/actions/agent-directory/coord.py --repo madhakish/cadence inbox \
  --discussion 42 > /untracked/inbox.json
```

Inbox returns root bodies, comments and nested replies, with parsed attribution
where present. To reply to a nested comment, use its top-level parent ID and
link the exact reply in the text. After consuming the returned messages, save
only the `cursor` object and pass it with `--cursor /untracked/cursor.json` on the
next identical inbox scope. The CLI never advances the cursor automatically.
Old edits are detected; deleted records are omitted, not retained as an audit.

Keep the exact request and destination when retrying. Reconciliation reuses an
identical existing message, rejects changed content under the same ID, and
never blindly retries a mutation. It is destination-scoped, not atomic locking
or guaranteed exactly-once delivery. Concurrent identical writes can race;
edited/deleted IDs need manual reconciliation. Append corrections with new IDs.

## Directory and limits

```sh
python3 .github/actions/agent-directory/coord.py --repo madhakish/cadence directory
python3 -m unittest discover -s .github/actions/agent-directory -p 'test_*.py' -v
```

The local `Agent session directory` workflow reads only Cadence Discussions and
writes a derived table to its job summary. Self-reported session state comes
from the last top-level state message in that run's session record; a stale
active label does not prove liveness or renew a claim. All durable messages
remain in Discussions. The workflow never edits another run's comments.

Defaults are 100 requests and 1,000 records. Incomplete scans, API errors and
reached bounds fail visibly with no success cursor or subsequent write. Raise
`--max-requests` or `--limit` before the subcommand only deliberately. Empty
reply threads do not trigger extra requests. The command stops when it exits;
there is no paid agent dispatch, background polling or merge automation.

The directory executes default-branch code with read-only permissions. The
separate test workflow executes candidate code without secrets or write access.
Neither modifies the existing app CI/release pipeline. A `GITHUB_TOKEN` comment
write does not trigger another Actions workflow via its comment event; use
manual refresh when needed. Discussion webhook support is documented as preview.

If a runtime lacks Discussion operations, report that on the task issue and
continue existing issue coordination. A generated directory and passing offline
tests do not prove live delivery or that another agent consumed a message.

- [GitHub Discussion API](https://docs.github.com/en/graphql/guides/using-the-graphql-api-for-discussions)
- [Discussion category forms](https://docs.github.com/en/discussions/managing-discussions-for-your-community/creating-discussion-category-forms)
- [Workflow events](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#discussion_comment)
