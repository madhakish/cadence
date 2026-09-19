"""Synthetic contract tests; no token or live GitHub writes."""

import copy
import json
import tempfile
import unittest
from pathlib import Path
from typing import Any
from unittest.mock import patch

import coord


def request(kind: str = "session", **changes: Any) -> coord.Record:
    run = "codex/20260919T000000Z/abcd1234"
    result = {
        "schema": 1,
        "run": run,
        "kind": kind,
        "agent": "anvil-abcd1234",
        "role": "reviewer",
        "event": "UPDATE",
        "message": run + "/register",
        "state": "active",
        "text": "Evidence from a synthetic fixture.",
    }
    if kind != "message":
        result.update(
            title="Session anvil-abcd1234",
            category="Agent Sessions" if kind == "session" else "Design and Coordination",
        )
    result.update(changes)
    return result


def node(identifier: str, body: str, **extra: Any) -> coord.Record:
    return {
        "id": identifier,
        "body": body,
        "url": "https://github.com/owner/repo/discussions/1",
        "createdAt": "2026-09-19T00:00:00Z",
        "updatedAt": "2026-09-19T00:00:00Z",
        "author": {"login": "same-account"},
        **extra,
    }


def page(nodes: list[coord.Record], more: bool = False, cursor: str | None = None) -> coord.Record:
    return {"items": {"nodes": nodes, "pageInfo": {"hasNextPage": more, "endCursor": cursor}}}


class MemoryGitHub(coord.GitHub):
    """Small remote fixture that can commit a mutation then lose its response."""

    def __init__(self) -> None:
        super().__init__("fixture")
        self.discussions: list[coord.Record] = []
        self.comments: dict[str, list[coord.Record]] = {}
        self.replies: dict[str, list[coord.Record]] = {}
        self.calls: list[tuple[str, coord.Record]] = []
        self.fail_after_write = False
        self.writes = 0

    def call(self, query: str, variables: coord.Record) -> coord.Record:
        self.calls.append((query, copy.deepcopy(variables)))
        if "hasDiscussionsEnabled" in query:
            return {
                "repository": {
                    "id": "R",
                    "hasDiscussionsEnabled": True,
                    "discussionCategories": {
                        "nodes": [
                            {"id": "C", "name": "Agent Sessions"},
                            {"id": "C2", "name": "Design and Coordination"},
                            {"id": "C3", "name": "Questions"},
                        ],
                        "pageInfo": {"hasNextPage": False},
                    },
                }
            }
        if "items:discussions" in query:
            return {"repository": page(copy.deepcopy(self.discussions))}
        if "discussion(number" in query:
            root = next((d for d in self.discussions if d["number"] == variables["number"]), None)
            return {"repository": {"discussion": copy.deepcopy(root)}}
        if "items:comments" in query:
            comments = copy.deepcopy(self.comments.get(variables["id"], []))
            for entry in comments:
                entry["replies"] = {"totalCount": len(self.replies.get(entry["id"], []))}
            return {"node": page(comments)}
        if "items:replies" in query:
            return {"node": page(copy.deepcopy(self.replies.get(variables["id"], [])))}
        value = variables["input"]
        self.writes += 1
        identifier = f"N{self.writes}"
        record = node(identifier, value["body"])
        if "createDiscussion" in query:
            record.update(title=value["title"], category={"id": value["categoryId"]}, number=self.writes)
            self.discussions.append(record)
            result = {"createDiscussion": {"discussion": record}}
        elif "addDiscussionComment" in query:
            dest = self.replies if "replyToId" in value else self.comments
            key = value.get("replyToId", value["discussionId"])
            dest.setdefault(key, []).append(record)
            result = {"addDiscussionComment": {"comment": record}}
        else:
            raise AssertionError(query)
        if self.fail_after_write:
            self.fail_after_write = False
            raise coord.CoordError("Unknown write outcome")
        return result


class CoordinationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.api = MemoryGitHub()
        coord.create(self.api, "owner/repo", request())

    def test_sessions_with_same_actor_keep_distinct_identities(self) -> None:
        run = "claude-code/20260919T000000Z/1234abcd"
        coord.create(self.api, "owner/repo", request(run=run, agent="anvil-1234abcd", message=run + "/register"))
        identities = [coord.parse(r["body"])["run"] for r in self.api.discussions]
        self.assertEqual(len(set(identities)), 2)
        self.assertEqual({r["author"]["login"] for r in self.api.discussions}, {"same-account"})

    def test_registration_retry_reuses_post_after_lost_response(self) -> None:
        api = MemoryGitHub()
        api.fail_after_write = True
        with self.assertRaises(coord.CoordError):
            coord.create(api, "owner/repo", request())
        self.assertTrue(coord.create(api, "owner/repo", request())["reused"])
        self.assertEqual(api.writes, 1)

    def test_changed_registration_or_title_rejected(self) -> None:
        for change in ({"text": "Different"}, {"title": "Different"}):
            with self.assertRaises(coord.CoordError):
                coord.create(self.api, "owner/repo", request(**change))
        self.assertEqual(self.api.writes, 1)

    def test_categories_match_record_kind_before_any_mutation(self) -> None:
        invalid = [
            request("topic", category="Agent Sessions", message=request()["run"] + "/bad-topic"),
            request(category="Questions", run="other/run", message="other/run/register"),
        ]
        missing = request("topic", message=request()["run"] + "/missing-category")
        del missing["category"]
        invalid.append(missing)
        for item in invalid:
            with self.assertRaisesRegex(coord.CoordError, "category"):
                coord.create(self.api, "owner/repo", item)
        self.assertEqual(self.api.writes, 1)

    def test_malformed_cursors_fail_without_partial_inbox(self) -> None:
        valid = coord.inbox(self.api, "owner/repo", [1], {})["cursor"]
        invalid: list[Any] = [[], 1, {**valid, "seen": []}, {**valid, "seen": {"N1": 3}}, {**valid, "schema": True}]
        for value in invalid:
            with self.assertRaises(coord.CoordError):
                coord.inbox(self.api, "owner/repo", [1], value)

    def test_thread_roots_share_record_budget_with_comments(self) -> None:
        self.api.comments["N1"] = [node("C1", "unattributed")]
        self.api.count = 0
        self.api.limit = 1
        with self.assertRaisesRegex(coord.CoordError, "Record bound"):
            coord.inbox(self.api, "owner/repo", [1], {})
        self.api.comments.clear()
        self.api.count = 0
        coord.thread(self.api, "owner/repo", 1)
        with self.assertRaisesRegex(coord.CoordError, "Record bound"):
            coord.thread(self.api, "owner/repo", 1)

    def test_topic_creation_and_retry(self) -> None:
        topic = request("topic", message=request()["run"] + "/design-1", title="Design question")
        self.assertFalse(coord.create(self.api, "owner/repo", topic)["reused"])
        self.assertTrue(coord.create(self.api, "owner/repo", topic)["reused"])

    def test_comment_retry_after_lost_response_and_content_conflict(self) -> None:
        message = request("message", message=request()["run"] + "/001")
        self.api.fail_after_write = True
        with self.assertRaises(coord.CoordError):
            coord.comment(self.api, "owner/repo", 1, message, None)
        self.assertTrue(coord.comment(self.api, "owner/repo", 1, message, None)["reused"])
        with self.assertRaises(coord.CoordError):
            coord.comment(self.api, "owner/repo", 1, {**message, "text": "Changed"}, None)
        self.assertEqual(self.api.writes, 2)

    def test_reply_target_is_validated_and_preserved(self) -> None:
        msg = request("message", message=request()["run"] + "/001")
        top = coord.comment(self.api, "owner/repo", 1, msg, None)
        reply = {**msg, "message": request()["run"] + "/002", "to": "claude/other/run"}
        coord.comment(self.api, "owner/repo", 1, reply, top["id"])
        self.assertEqual(self.api.calls[-1][1]["input"]["replyToId"], top["id"])
        with self.assertRaises(coord.CoordError):
            coord.comment(self.api, "owner/repo", 1, reply, None)
        with self.assertRaises(coord.CoordError):
            coord.comment(self.api, "owner/repo", 1, reply, "outside-thread")
        self.assertEqual(self.api.writes, 3)

    def test_duplicate_existing_message_id_fails_closed(self) -> None:
        self.api.discussions.append(copy.deepcopy(self.api.discussions[0]))
        with self.assertRaisesRegex(coord.CoordError, "Duplicate"):
            coord.create(self.api, "owner/repo", request())
        self.assertEqual(self.api.writes, 1)

    def test_inbox_includes_replies_and_detects_old_comment_edits(self) -> None:
        msg = request("message", message=request()["run"] + "/001")
        top = coord.comment(self.api, "owner/repo", 1, msg, None)
        coord.comment(self.api, "owner/repo", 1, {**msg, "message": request()["run"] + "/002"}, top["id"])
        first = coord.inbox(self.api, "owner/repo", [1], {})
        self.assertEqual(len(first["messages"]), 3)
        self.assertEqual(coord.inbox(self.api, "owner/repo", [1], first["cursor"])["messages"], [])
        self.api.comments["N1"][0]["body"] += "Edited evidence."
        changed = coord.inbox(self.api, "owner/repo", [1], first["cursor"])
        self.assertEqual([r["id"] for r in changed["messages"]], [top["id"]])
        with self.assertRaisesRegex(coord.CoordError, "scope"):
            coord.inbox(self.api, "other/repo", [1], first["cursor"])

    def test_other_run_cannot_change_directory_session_state(self) -> None:
        msg = request("message", run="other/run", message="other/run/001", state="finished")
        coord.comment(self.api, "owner/repo", 1, msg, None)
        self.assertIn("| active |", coord.directory(self.api, "owner/repo"))
        msg = request("message", message=request()["run"] + "/done", event="DONE", state="finished")
        result = coord.comment(self.api, "owner/repo", 1, msg, None)
        self.api.comments["N1"][-1]["createdAt"] = "2026-09-19T00:01:00Z"
        report = coord.directory(self.api, "owner/repo")
        self.assertIn("| finished |", report)
        self.assertNotIn(result["body"], report)

    def test_directory_state_uses_top_level_updates_and_same_second_order(self) -> None:
        msg = request("message", message=request()["run"] + "/pause", state="paused")
        top = coord.comment(self.api, "owner/repo", 1, msg, None)
        self.assertIn("| paused |", coord.directory(self.api, "owner/repo"))
        reply = {**msg, "message": request()["run"] + "/reply", "state": "finished"}
        coord.comment(self.api, "owner/repo", 1, reply, top["id"])
        self.assertIn("| paused |", coord.directory(self.api, "owner/repo"))

    def test_empty_reply_threads_do_not_cost_extra_requests(self) -> None:
        for i in range(20):
            self.api.comments.setdefault("N1", []).append(node(f"C{i}", "unattributed"))
        self.api.calls.clear()
        self.assertEqual(len(coord.thread(self.api, "owner/repo", 1)), 21)
        self.assertEqual(len(self.api.calls), 2)

    def test_envelope_ignores_examples_and_rejects_header_injection(self) -> None:
        body = coord.envelope(request())
        self.assertEqual(coord.parse("An example follows\n\n" + body), {})
        self.assertEqual(coord.parse(body)["agent"], "anvil-abcd1234")
        for change in (
            {"agent": "anvil\nTo: victim"},
            {"role": "reviewer\nState: finished"},
            {"message": "different/run/001"},
            {"unknown": "ignored"},
        ):
            with self.assertRaises(coord.CoordError):
                coord.envelope(request(**change))

    def test_category_form_envelope_is_recognized(self) -> None:
        body = coord.envelope(request())
        self.assertEqual(coord.parse("### Coordination record\n\n" + body), coord.parse(body))
        self.assertEqual(coord.parse("Unrelated prose\n\n### Coordination record\n\n" + body), {})

    def test_malformed_request_types_are_rejected(self) -> None:
        invalid: list[coord.Record] = [{"schema": True}, {"to": 3}, {"state": []}, {"text": None}]
        for change in invalid:
            with self.assertRaises(coord.CoordError):
                coord.envelope(request(**change))
        body = coord.envelope(request())
        self.assertEqual(coord.parse(body.replace("\n", "\r\n")), coord.parse(body))

    def test_user_text_is_a_graphql_variable(self) -> None:
        text = '$(touch /tmp/nope) `command` " } mutation { unexpected }'
        coord.create(self.api, "owner/repo", request("topic", message=request()["run"] + "/topic", text=text))
        query, variables = self.api.calls[-1]
        self.assertNotIn(text, query)
        self.assertIn(text, variables["input"]["body"])

    def test_metadata_fails_when_discussions_disabled(self) -> None:
        with (
            patch.object(self.api, "call", return_value={"repository": {"hasDiscussionsEnabled": False}}),
            self.assertRaisesRegex(coord.CoordError, "Enable Discussions"),
        ):
            coord.metadata(self.api, "owner/repo")


class PaginationTests(unittest.TestCase):
    def test_unexpected_page_shapes_fail_with_coord_error(self) -> None:
        invalid: list[coord.Record] = [
            {"items": None},
            {"items": []},
            {"items": {"nodes": None, "pageInfo": {"hasNextPage": False}}},
            {"items": {"nodes": []}},
            {"items": {"nodes": [], "pageInfo": {"hasNextPage": "false"}}},
            {"items": {"nodes": [3], "pageInfo": {"hasNextPage": False}}},
        ]
        api = coord.GitHub("fixture")
        for response in invalid:
            with (
                patch.object(api, "call", return_value={"node": response}),
                self.assertRaises(coord.CoordError),
            ):
                api.pages(coord.COMMENTS, {"id": "D"}, "node")

    def test_non_object_graphql_response_fails_with_coord_error(self) -> None:
        api = coord.GitHub("fixture")
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "response.json"
            path.write_text("[]")
            with (
                patch("urllib.request.urlopen", return_value=path.open()),
                self.assertRaises(coord.CoordError),
            ):
                api.call("query{}", {})

    def test_every_page_is_read_and_repeated_cursor_fails(self) -> None:
        api = coord.GitHub("fixture")
        responses = [{"node": page([node("1", "one")], True, "next")}, {"node": page([node("2", "two")])}]
        with patch.object(api, "call", side_effect=responses) as call:
            rows = api.pages(coord.COMMENTS, {"id": "D"}, "node")
        self.assertEqual([r["id"] for r in rows], ["1", "2"])
        self.assertEqual(call.call_args_list[1].args[1]["after"], "next")
        api = coord.GitHub("fixture")
        with (
            patch.object(api, "call", return_value=responses[0]),
            self.assertRaisesRegex(coord.CoordError, "no progress"),
        ):
            api.pages(coord.REPLIES, {"id": "C"}, "node")

    def test_record_bound_never_returns_partial_success(self) -> None:
        api = coord.GitHub("fixture", limit=1)
        with (
            patch.object(api, "call", return_value={"node": page([node("1", "one"), node("2", "two")])}),
            self.assertRaisesRegex(coord.CoordError, "bound"),
        ):
            api.pages(coord.COMMENTS, {"id": "D"}, "node")

    def test_request_budget_and_graphql_errors_fail_closed(self) -> None:
        api = coord.GitHub("fixture", max_requests=1)
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "response.json"
            path.write_text(json.dumps({"data": {"partial": True}, "errors": [{"message": "sensitive"}]}))
            with patch("urllib.request.urlopen", return_value=path.open()) as send:
                with self.assertRaisesRegex(coord.CoordError, "GraphQL failed"):
                    api.call("query{}", {})
                with self.assertRaisesRegex(coord.CoordError, "Request bound"):
                    api.call("query{}", {})
            self.assertEqual(send.call_count, 1)

    def test_network_failure_does_not_blindly_retry(self) -> None:
        api = coord.GitHub("fixture")
        with (
            patch("urllib.request.urlopen", side_effect=TimeoutError("sensitive details")) as send,
            self.assertRaisesRegex(coord.CoordError, "outcome may be unknown"),
        ):
            api.call("mutation{}", {})
        self.assertEqual(send.call_count, 1)


if __name__ == "__main__":
    unittest.main()
