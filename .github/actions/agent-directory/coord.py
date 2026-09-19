#!/usr/bin/env python3
"""Bounded GitHub Discussion coordination. No scheduler or ownership authority."""

from __future__ import annotations

import argparse
import hashlib
import html
import json
import os
import re
import secrets
import sys
import urllib.error
import urllib.request
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, cast

Record = dict[str, Any]
EVENTS = {"CLAIM", "UPDATE", "BLOCKED", "HANDOFF", "DONE"}
STATES = {"active", "paused", "finished"}
TOKEN = re.compile(r"[A-Za-z0-9][A-Za-z0-9._/-]{0,199}\Z")
REPO = re.compile(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\Z")
HEADER = re.compile(r"\[coord/v1\] run=([\w./-]+) event=(\w+)\Z", re.ASCII)
FIELDS = {
    "kind": "Kind",
    "agent": "Agent",
    "role": "Role",
    "message": "Message",
    "to": "To",
    "parent": "Parent",
    "resumed_from": "Resumed-from",
    "state": "State",
    "scope": "Scope",
    "ref": "Ref",
}
NODE_FIELDS = "id body url createdAt updatedAt author { login }"
PAGE = "pageInfo { hasNextPage endCursor }"
DISCUSSIONS = f"""query($owner:String!,$name:String!,$after:String) {{
 repository(owner:$owner,name:$name) {{ items:discussions(first:100,after:$after,
 orderBy:{{field:CREATED_AT,direction:ASC}}) {{
 nodes {{ {NODE_FIELDS} title number category {{ id name }} }} {PAGE} }} }}
}}"""
COMMENTS = f"""query($id:ID!,$after:String) {{ node(id:$id) {{ ... on Discussion {{
 items:comments(first:100,after:$after) {{
 nodes {{ {NODE_FIELDS} replies(first:1) {{ totalCount }} }} {PAGE} }} }} }} }}"""
REPLIES = f"""query($id:ID!,$after:String) {{ node(id:$id) {{ ... on DiscussionComment {{
 items:replies(first:100,after:$after) {{ nodes {{ {NODE_FIELDS} }} {PAGE} }} }} }} }}"""


class CoordError(Exception):
    """A bounded failure safe to show without request bodies or credentials."""


class GitHub:
    def __init__(self, token: str, max_requests: int = 100, limit: int = 1000):
        if not token:
            raise CoordError("Set GH_TOKEN or GITHUB_TOKEN with repository Discussions access")
        if not 1 <= max_requests <= 1000 or not 1 <= limit <= 10000:
            raise CoordError("Bounds must be 1..1000 requests and 1..10000 records")
        self.token = token
        self.remaining = max_requests
        self.limit = limit
        self.count = 0

    def call(self, query: str, variables: Record) -> Record:
        if self.remaining <= 0:
            raise CoordError("Request bound reached; scan incomplete, no write is safe")
        self.remaining -= 1
        request = urllib.request.Request(
            "https://api.github.com/graphql",
            data=json.dumps({"query": query, "variables": variables}).encode(),
            headers={
                "Authorization": f"Bearer {self.token}",
                "Content-Type": "application/json",
                "User-Agent": "pantheon-github-coordination/1",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                payload: object = json.load(response)
        except urllib.error.HTTPError as exc:
            raise CoordError(f"GitHub HTTP {exc.code}; reconcile before retrying any write") from None
        except (OSError, ValueError):
            raise CoordError("GitHub request failed; write outcome may be unknown; reconcile on retry") from None
        if not isinstance(payload, dict):
            raise CoordError("Unexpected GitHub response; reconcile before retrying any write")
        data = cast("Record", payload)
        if data.get("errors") or not isinstance(data.get("data"), dict):
            raise CoordError("GraphQL failed; check access/schema; reconcile before retrying a write")
        return data["data"]

    def pages(self, query: str, variables: Record, root: str) -> list[Record]:
        nodes: list[Record] = []
        cursor = None
        seen_cursors: set[str] = set()
        while True:
            data = self.call(query, {**variables, "after": cursor}).get(root)
            if not isinstance(data, dict) or "items" not in data:
                raise CoordError("Repository or Discussion is inaccessible; scan incomplete")
            raw_page = cast("Record", data)["items"]
            if not isinstance(raw_page, dict):
                raise CoordError("Unexpected GitHub page; scan incomplete")
            page = cast("Record", raw_page)
            raw_batch, raw_info = page.get("nodes"), page.get("pageInfo")
            if not isinstance(raw_batch, list) or not isinstance(raw_info, dict):
                raise CoordError("Unexpected GitHub page fields; scan incomplete")
            values = cast("list[object]", raw_batch)
            info = cast("Record", raw_info)
            if any(not isinstance(node, dict) for node in values) or type(info.get("hasNextPage")) is not bool:
                raise CoordError("Inaccessible record or invalid pagination; scan incomplete")
            batch = cast("list[Record]", values)
            self.count += len(batch)
            if self.count > self.limit:
                raise CoordError("Record bound reached; narrow scope or explicitly raise the limit")
            nodes.extend(batch)
            if not info["hasNextPage"]:
                return nodes
            cursor = info.get("endCursor")
            if not isinstance(cursor, str) or not cursor or cursor in seen_cursors:
                raise CoordError("Pagination made no progress; scan incomplete")
            seen_cursors.add(cursor)


def repository(value: str) -> Record:
    if not REPO.fullmatch(value):
        raise CoordError("Repository must be owner/name")
    owner, name = value.split("/")
    return {"owner": owner, "name": name}


def metadata(api: GitHub, repo: str) -> Record:
    data = api.call(
        """query($owner:String!,$name:String!) {
      repository(owner:$owner,name:$name) { id hasDiscussionsEnabled
        discussionCategories(first:100) { nodes { id name } pageInfo { hasNextPage } } }
    }""",
        repository(repo),
    ).get("repository")
    if not data:
        raise CoordError("Repository is inaccessible")
    if not data["hasDiscussionsEnabled"]:
        raise CoordError("Enable Discussions in repository settings before using coordination")
    if data["discussionCategories"]["pageInfo"]["hasNextPage"]:
        raise CoordError("Category scan incomplete")
    return data


def category_id(meta: Record, name: str) -> str:
    matches = [c["id"] for c in meta["discussionCategories"]["nodes"] if c["name"] == name]
    if len(matches) != 1:
        raise CoordError(f"Create or select the exact Discussion category: {name}")
    return matches[0]


def envelope(payload: object) -> str:
    if not isinstance(payload, dict):
        raise CoordError("Expected a JSON object")
    request = cast("Record", payload)
    allowed = {"schema", "run", "event", "text", "title", "category", *FIELDS}
    if set(request) - allowed or type(request.get("schema")) is not int or request["schema"] != 1:
        raise CoordError("Expected schema 1 request; unknown fields are rejected")
    for key, value in request.items():
        if key != "schema" and not isinstance(value, str):
            raise CoordError(f"Expected string for {key}")
    for key in ("run", "agent", "message"):
        if not isinstance(request.get(key), str) or not TOKEN.fullmatch(request[key]):
            raise CoordError(f"Invalid or missing {key}")
    if not request["message"].startswith(request["run"] + "/"):
        raise CoordError("Message ID must begin with the full run ID and a slash")
    if request.get("event") not in EVENTS or request.get("kind") not in {"session", "topic", "message"}:
        raise CoordError("Invalid event or kind")
    if "state" in request and request["state"] not in STATES:
        raise CoordError("Invalid session state")
    for key in ("to", "parent", "resumed_from"):
        if key in request and not TOKEN.fullmatch(request[key]):
            raise CoordError(f"Invalid {key} run ID")
    text = request.get("text")
    if not isinstance(text, str) or not text.strip():
        raise CoordError("Provide nonempty text")
    lines = [f"[coord/v1] run={request['run']} event={request['event']}"]
    for key, label in FIELDS.items():
        if key not in request:
            continue
        value = request[key]
        if not isinstance(value, str) or not value or len(value) > 500 or any(ord(c) < 32 for c in value):
            raise CoordError(f"Invalid single-line {key}")
        lines.append(f"{label}: {value}")
    body = "\n".join(lines) + "\n\n" + text.strip() + "\n"
    if len(body.encode()) > 50000:
        raise CoordError("Message exceeds 50,000 bytes; link evidence instead")
    return body


def parse(body: str) -> Record:
    """Read only the leading envelope, never examples in the message body."""
    body = body.replace("\r\n", "\n").removeprefix("### Coordination record\n\n")
    header, separator, _ = body.partition("\n\n")
    lines = header.splitlines()
    match = HEADER.fullmatch(lines[0]) if lines and separator else None
    if not match or match[2] not in EVENTS:
        return {}
    result: Record = {"run": match[1], "event": match[2]}
    labels = {label: key for key, label in FIELDS.items()}
    for line in lines[1:]:
        label, sep, value = line.partition(": ")
        if not sep or label not in labels or labels[label] in result:
            return {}
        result[labels[label]] = value
    if not all(TOKEN.fullmatch(result.get(k, "")) for k in ("run", "agent", "message")):
        return {}
    if not result["message"].startswith(result["run"] + "/"):
        return {}
    return result


def roots(api: GitHub, repo: str) -> list[Record]:
    return api.pages(DISCUSSIONS, repository(repo), "repository")


def thread(api: GitHub, repo: str, number: int) -> list[Record]:
    root = api.call(
        f"""query($owner:String!,$name:String!,$number:Int!) {{
      repository(owner:$owner,name:$name) {{ discussion(number:$number) {{ {NODE_FIELDS} title number }} }}
    }}""",
        {**repository(repo), "number": number},
    ).get("repository")
    if not root or not root.get("discussion"):
        raise CoordError("Discussion is inaccessible")
    api.count += 1
    if api.count > api.limit:
        raise CoordError("Record bound reached; narrow scope or explicitly raise the limit")
    discussion = root["discussion"]
    result = [{**discussion, "parent_id": None}]
    for comment in api.pages(COMMENTS, {"id": discussion["id"]}, "node"):
        result.append({**comment, "parent_id": discussion["id"]})
        if not comment["replies"]["totalCount"]:
            continue
        replies = api.pages(REPLIES, {"id": comment["id"]}, "node")
        result.extend({**reply, "parent_id": comment["id"]} for reply in replies)
    return result


def existing(records: list[Record], body: str, message: str) -> Record | None:
    matches = [r for r in records if parse(r["body"]).get("message") == message]
    if len(matches) > 1:
        raise CoordError("Duplicate message ID exists; reconcile manually")
    if matches and matches[0]["body"].replace("\r\n", "\n") != body:
        raise CoordError("Message ID already exists with different content; append a new message")
    return matches[0] if matches else None


def create(api: GitHub, repo: str, request: Record) -> Record:
    body = envelope(request)
    if request["kind"] not in {"session", "topic"}:
        raise CoordError("Create requires session or topic kind")
    if request["kind"] == "session" and request["message"] != request["run"] + "/register":
        raise CoordError("Session registration must use <run>/register")
    title = request.get("title")
    if not isinstance(title, str) or not 1 <= len(title) <= 200 or any(ord(c) < 32 for c in title):
        raise CoordError("Provide a single-line title of 1..200 characters")
    allowed_categories = (
        {"Agent Sessions"} if request["kind"] == "session" else {"Design and Coordination", "Questions"}
    )
    category_name = request.get("category", "Agent Sessions" if request["kind"] == "session" else "")
    if category_name not in allowed_categories:
        raise CoordError("Discussion category must match the session/topic kind")
    meta = metadata(api, repo)
    category = category_id(meta, category_name)
    records = roots(api, repo)
    prior = existing(records, body, request["message"])
    if prior:
        if prior["title"] != title or prior["category"]["id"] != category:
            raise CoordError("Existing message title/category differs; use its original request")
        return {"reused": True, "id": prior["id"], "url": prior["url"]}
    result = api.call(
        """mutation($input:CreateDiscussionInput!) {
      createDiscussion(input:$input) { discussion { id url } }
    }""",
        {"input": {"repositoryId": meta["id"], "categoryId": category, "title": title, "body": body}},
    )
    return {"reused": False, **result["createDiscussion"]["discussion"]}


def comment(api: GitHub, repo: str, number: int, request: Record, reply_to: str | None) -> Record:
    body = envelope(request)
    if request["kind"] != "message" or "title" in request or "category" in request:
        raise CoordError("Comment requires message kind without title/category")
    records = thread(api, repo, number)
    discussion_id = records[0]["id"]
    # GitHub replies are attached to a top-level comment; retain the exact parent.
    target = next((r for r in records[1:] if r["id"] == reply_to), None)
    if reply_to and (not target or target["parent_id"] != discussion_id):
        raise CoordError("Reply target must be a top-level comment in this Discussion")
    parent = reply_to or discussion_id
    prior = existing(records, body, request["message"])
    if prior:
        if prior["parent_id"] != parent:
            raise CoordError("Existing message has a different reply target")
        return {"reused": True, "id": prior["id"], "url": prior["url"]}
    inputs = {"discussionId": discussion_id, "body": body}
    if reply_to:
        inputs["replyToId"] = reply_to
    result = api.call(
        """mutation($input:AddDiscussionCommentInput!) {
      addDiscussionComment(input:$input) { comment { id url } }
    }""",
        {"input": inputs},
    )
    return {"reused": False, **result["addDiscussionComment"]["comment"]}


def inbox(api: GitHub, repo: str, numbers: list[int], payload: object) -> Record:
    scope: Record = {"repository": repo, "discussions": sorted(set(numbers))}
    if not isinstance(payload, dict):
        raise CoordError("Cursor must be a JSON object")
    previous = cast("Record", payload)
    if previous and (
        set(previous) != {"schema", "scope", "seen"}
        or type(previous.get("schema")) is not int
        or previous["schema"] != 1
        or previous.get("scope") != scope
    ):
        raise CoordError("Cursor belongs to another inbox scope or schema")
    raw_seen = previous.get("seen", {})
    if not isinstance(raw_seen, dict):
        raise CoordError("Cursor seen must be an object of node IDs and fingerprints")
    seen = cast("Record", raw_seen)
    if any(not isinstance(value, str) or not re.fullmatch(r"[0-9a-f]{64}", value) for value in seen.values()):
        raise CoordError("Invalid cursor fingerprint")
    messages: list[Record] = []
    current: dict[str, str] = {}
    for number in scope["discussions"]:
        for record in thread(api, repo, number):
            fingerprint = hashlib.sha256((record["updatedAt"] + record["body"]).encode()).hexdigest()
            current[record["id"]] = fingerprint
            if seen.get(record["id"]) != fingerprint:
                messages.append({**record, "discussion": number, "attribution": parse(record["body"])})
    return {"messages": messages, "cursor": {"schema": 1, "scope": scope, "seen": current}}


def directory(api: GitHub, repo: str) -> str:
    meta = metadata(api, repo)
    category = category_id(meta, "Agent Sessions")
    lines = [
        "# Agent session directory",
        "",
        "Self-reported attribution; status does not establish ownership or liveness.",
        "",
        "| Agent | Run | State | Last self-report | Session |",
        "| --- | --- | --- | --- | --- |",
    ]
    for root in roots(api, repo):
        identity = parse(root["body"])
        if root["category"]["id"] != category or identity.get("kind") != "session":
            continue
        records = thread(api, repo, root["number"])
        reports = [
            r
            for r in records
            if parse(r["body"]).get("run") == identity["run"]
            and r["parent_id"] in {None, root["id"]}
            and parse(r["body"]).get("state") in STATES
        ]
        last = max(enumerate(reports), key=lambda item: (item[1]["createdAt"], item[0]))[1] if reports else root
        state = parse(last["body"]).get("state", "unknown")
        values = [identity["agent"], identity["run"], state, last["createdAt"]]
        cells = [html.escape(v).replace("|", "&#124;").replace("@", "&#64;") for v in values]
        # Construct links from validated repository and numeric identifiers, not post content.
        cells.append(f"[#{root['number']}](https://github.com/{repo}/discussions/{int(root['number'])})")
        lines.append("| " + " | ".join(cells) + " |")
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", help="Explicit owner/name, including for cross-repo work")
    parser.add_argument("--limit", type=int, default=1000)
    parser.add_argument("--max-requests", type=int, default=100)
    sub = parser.add_subparsers(dest="command", required=True)
    init = sub.add_parser("init", help="Generate a request locally; save it outside tracked files")
    init.add_argument("--tool", required=True)
    init.add_argument("--name", required=True)
    init.add_argument("--role", required=True)
    sub.add_parser("doctor", help="Read Discussion/category availability")
    sub.add_parser("directory", help="Render the derived session directory as Markdown")
    new = sub.add_parser("create", help="Register a session or initiate a topic")
    new.add_argument("--request", type=Path, required=True)
    post = sub.add_parser("comment", help="Post or reply, reconciling uncertain earlier attempts")
    post.add_argument("--request", type=Path, required=True)
    post.add_argument("--discussion", type=int, required=True)
    post.add_argument("--reply-to", help="Top-level comment GraphQL node ID from inbox")
    read = sub.add_parser("inbox", help="Read explicit threads; save returned cursor AFTER consumption")
    read.add_argument("--discussion", type=int, action="append", required=True)
    read.add_argument("--cursor", type=Path, help="Previous cursor object, not the whole inbox output")
    args = parser.parse_args()
    try:
        if args.command == "init":
            stamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")
            suffix = secrets.token_hex(4)
            run = f"{args.tool}/{stamp}/{suffix}"
            result = {
                "schema": 1,
                "kind": "session",
                "run": run,
                "agent": f"{args.name}-{suffix}",
                "role": args.role,
                "message": run + "/register",
                "event": "UPDATE",
                "state": "active",
                "category": "Agent Sessions",
                "title": f"Session {args.name}-{suffix}",
                "scope": "Replace with the authorized scope",
                "ref": "Replace with the task issue URL",
                "text": "Replace with the next action and actual evidence before posting.",
            }
            envelope(result)
        else:
            if not args.repo:
                raise CoordError("--repo is required")
            repository(args.repo)
            api = GitHub(
                os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN", ""), args.max_requests, args.limit
            )
            if args.command == "doctor":
                result = metadata(api, args.repo)
            elif args.command == "directory":
                print(directory(api, args.repo), end="")
                return 0
            elif args.command == "inbox":
                previous: Record = json.loads(args.cursor.read_text()) if args.cursor else {}
                result = inbox(api, args.repo, args.discussion, previous)
            else:
                request = json.loads(args.request.read_text())
                result = (
                    create(api, args.repo, request)
                    if args.command == "create"
                    else comment(api, args.repo, args.discussion, request, args.reply_to)
                )
        print(json.dumps(result, indent=2))
        return 0
    except (CoordError, OSError, ValueError) as exc:
        print(f"coord: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
