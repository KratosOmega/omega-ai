"""CLI adapter tests against the offline stub (#28 Task 4)."""
import glob
import json
import logging
import os
import re
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bridgetest  # noqa: E402
from bridgetest import BridgeCase, OPERATOR, TOKEN  # noqa: E402
from bridge import multica_cli  # noqa: E402
from bridge.multica_cli import (AuthError, Cli, ForbiddenWrite, KeychainError, NotFoundError,  # noqa: E402
                                PermanentError, TransientError)

TESTS = os.path.dirname(os.path.abspath(__file__))
FIX = os.path.join(TESTS, "fixtures", "cli")


class CliTest(BridgeCase):
    def test_env_is_exactly_five_keys(self):
        with mock.patch.dict(os.environ, {"MULTICA_DAEMON_PORT": "1", "MULTICA_TASK_ID": "t"}):
            self.cli.version()
        env = self.board.calls()[0]["env"]
        self.assertEqual(env, {"MULTICA_TOKEN": TOKEN, "MULTICA_SERVER_URL": self.cfg.server_url,
                               "MULTICA_WORKSPACE_ID": self.cfg.workspace_id, "HOME": self.cli.cli_home,
                               "PATH": "/usr/bin:/bin"})
        # The adapter writes nothing there; macOS's /usr/bin/python3 shim may create ~/Library itself.
        self.assertLessEqual(set(os.listdir(self.cli.cli_home)), {"Library"})

    def test_output_json_appended(self):
        self.cli.version()
        self.assertEqual(self.board.calls()[0]["argv"], ["version", "--output", "json"])

    def test_stdin_devnull_without_input(self):
        self.cli.version()
        self.assertEqual(self.board.calls()[0]["stdin"], "")

    def test_empty_token_refused_without_call(self):
        c = Cli(self.cfg, "", self.cli.cli_home, self.cli.log)
        with self.assertRaises(KeychainError) as cm:
            c.version()
        self.assertEqual(cm.exception.kind, "empty")
        self.assertFalse(os.path.exists(os.path.join(self.tmp, "cli", "stub-state", "calls.jsonl")))

    def test_sanitize_spec_cases(self):
        cases = ["[x](mention://agent/ab12)", "[x](MENTION://all/all)", "[r]: mention://member/1", "@name",
                 "```html\n<b>x</b>\n```", "````mermaid"]
        for text in cases:
            out = multica_cli.sanitize(text)
            self.assertNotRegex(out, r"(?i)(?<!no-)mention:", text)
            self.assertNotIn("@", out)
            self.assertNotIn("```", out)

    def test_sanitize_reaches_title_description_comment(self):
        self.board.add_issue("seed")
        self.cli.create_issue("T @bob [x](mention://agent/1)", "D @a ```html", None, {})
        call = self.board.calls("issue create")[0]
        title = call["argv"][call["argv"].index("--title") + 1]
        for text in (title, call["stdin"]):
            self.assertNotIn("@", text)
            self.assertNotIn("```", text)
            self.assertNotRegex(text, r"(?i)(?<!no-)mention:")
        self.cli.add_comment("OMEG-1", "studio: hi @x ```")
        c = self.board.calls("issue comment add")[0]
        self.assertNotIn("@", c["stdin"])
        self.assertNotIn("```", c["stdin"])

    def test_property_values_not_sanitized(self):
        self.cli.create_issue("t", "d", None, {"omega_story": "a@b"})
        argv = self.board.calls("issue create")[0]["argv"]
        self.assertIn("omega_story=a@b", argv)
        self.assertIn("--allow-duplicate", argv)
        self.assertIn("todo", argv)

    def test_comment_requires_prefix(self):
        self.board.add_issue("x")
        self.board.reset_calls()
        with self.assertRaises(ValueError):
            self.cli.add_comment("OMEG-1", "no prefix here")
        self.assertEqual(self.board.calls(), [])

    def test_request_issue_writes_forbidden(self):
        self.board.add_issue("request")
        self.board.reset_calls()
        self.cli.forbidden.add("OMEG-1")
        with self.assertRaises(ForbiddenWrite):
            self.cli.set_status("OMEG-1", "done")
        with self.assertRaises(ForbiddenWrite):
            self.cli.add_comment("OMEG-1", "studio: hi")
        self.assertEqual(self.board.calls(), [])
        row = self.cli.create_issue("Run x", "d", "OMEG-1", {})
        self.assertEqual(row["parent_issue_id"], "iss-1")

    def test_status_calls_pass_no_start(self):
        self.board.add_issue("x")
        row = self.cli.set_status("OMEG-1", "in_progress")
        self.assertEqual(row["status"], "in_progress")
        self.assertIn("--no-start", self.board.calls("issue status")[0]["argv"])

    def test_stub_refuses_unassign_with_no_start(self):
        self.board.add_issue("x", assignee=("agent", "ag-1"))
        with self.assertRaises(PermanentError):
            self.cli.call(["issue", "assign", "OMEG-1", "--unassign", "--no-start"])
        self.cli.call(["issue", "assign", "OMEG-1", "--unassign"])
        self.assertIsNone(self.board.issue("OMEG-1")["assignee_id"])

    def test_classify_recorded_errors(self):
        want = {"unauthorized": AuthError, "no-token": AuthError, "not-found": NotFoundError,
                "unreachable": TransientError, "duplicate": PermanentError, "bad-status": PermanentError}
        for name, cls in want.items():
            with open(os.path.join(FIX, "errors", name + ".txt")) as f:
                text = f.read()
            with open(os.path.join(FIX, "errors", name + ".exit")) as f:
                code = int(f.read().strip())
            err = multica_cli.classify(code, text)
            self.assertIsInstance(err, cls, name)
            if cls is PermanentError:
                self.assertNotIsInstance(err, NotFoundError, name)

    def test_classify_defaults(self):
        for text in ("429 Too Many Requests", "502 Bad Gateway", "retryable failure"):
            self.assertIsInstance(multica_cli.classify(1, text), TransientError, text)
        e = multica_cli.classify(1, "OMEG-500 not found")
        self.assertIsInstance(e, NotFoundError)
        self.assertNotIsInstance(e, TransientError)

    def test_stub_errors_classify_through_call(self):
        c = Cli(self.cfg, "wrong", self.cli.cli_home, self.cli.log)
        with self.assertRaises(AuthError):
            c.profile()
        with self.assertRaises(NotFoundError):
            self.cli.get_issue("OMEG-99")

    def test_timeout_is_transient(self):
        self.board.fault("issue get", sleep=3)
        with mock.patch.object(multica_cli, "CLI_TIMEOUT", 1):
            with self.assertRaises(TransientError):
                self.cli.get_issue("OMEG-1")

    def test_usage_exit_2_is_permanent(self):
        with self.assertRaises(PermanentError) as cm:
            self.cli.call(["bogus", "cmd"])
        self.assertEqual(cm.exception.code, 2)

    def test_non_json_is_permanent(self):
        self.board.fault("version", exit=0, stdout="not json")
        with self.assertRaises(PermanentError):
            self.cli.version()

    def test_rows_envelopes(self):
        self.assertEqual(multica_cli.rows([1]), [1])
        self.assertEqual(multica_cli.rows({"issues": [2]}), [2])
        self.assertEqual(multica_cli.rows({"comments": [3]}), [3])
        self.assertEqual(multica_cli.rows({"other": [4]}), [])
        self.assertEqual(multica_cli.rows(None), [])

    def test_run_issues_pages_on_has_more(self):
        for i in range(150):
            self.board.add_issue("s%d" % i, props={"omega_run": "k"})
        self.board.add_issue("other", props={"omega_run": "z"})
        self.board.reset_calls()
        got = self.cli.run_issues("k")
        self.assertEqual(len(got), 150)
        argvs = [c["argv"] for c in self.board.calls("issue list")]
        self.assertEqual(len(argvs), 2)
        self.assertEqual([a[a.index("--offset") + 1] for a in argvs], ["0", "100"])

    def test_find_issues_none_filter(self):
        self.board.add_issue("Run k", props={"omega_run": "k"})
        self.board.add_issue("story 1", props={"omega_run": "k", "omega_story": "1"})
        self.board.add_issue("story 2", props={"omega_run": "k", "omega_story": "2"})
        self.assertEqual([r["identifier"] for r in self.cli.find_issues("k", None)], ["OMEG-1"])
        self.assertEqual([r["identifier"] for r in self.cli.find_issues("k", "1")], ["OMEG-2"])

    def test_assigned_issues_one_page_newest_first(self):
        self.board.add_issue("a", assignee=("agent", "ag-1"), created_at="2026-10-04T05:00:00Z")
        self.board.add_issue("b", assignee=("agent", "ag-1"), created_at="2026-10-04T06:00:00Z")
        self.board.add_issue("c", assignee=("agent", "ag-2"))
        got = self.cli.assigned_issues("ag-1")
        self.assertEqual([r["title"] for r in got], ["b", "a"])

    def test_comments_since_inclusive_nested_and_runs(self):
        self.board.add_issue("x")
        a = self.board.add_comment("OMEG-1", "one", at="2026-10-04T05:00:00Z")
        self.board.add_comment("OMEG-1", "two", at="2026-10-04T05:00:05Z")
        self.board.add_run("OMEG-1", "run-1", "2026-10-04T05:00:00Z")
        got = self.cli.list_comments("OMEG-1", "2026-10-04T05:00:00Z")
        self.assertEqual([c["content"] for c in got], ["one", "two"])
        self.assertNotIn("issue_revision", got[0])
        r1 = self.cli.add_comment("OMEG-1", "studio: ok", parent=a)
        r2 = self.cli.add_comment("OMEG-1", "studio: ok2", parent=r1["id"])
        self.assertEqual(r2["parent_id"], r1["id"])           # P7b: nested
        self.assertEqual([r["id"] for r in self.cli.issue_runs("OMEG-1")], ["run-1"])

    def test_read_token_ok_missing_locked(self):
        sdir = os.path.join(self.tmp, "sec")
        os.makedirs(sdir)
        env = {"STUB_SECURITY_DIR": sdir}
        with mock.patch.dict(os.environ, env), \
                mock.patch.object(multica_cli, "SECURITY", os.path.join(TESTS, "stub-security")):
            with self.assertRaises(KeychainError) as cm:
                multica_cli.read_token("tester")
            self.assertEqual(cm.exception.kind, "missing")
            with open(os.path.join(sdir, "omega-multica-bridge-tester"), "w") as f:
                f.write("mul_secret0001\n")
            self.assertEqual(multica_cli.read_token("tester"), "mul_secret0001")
            open(os.path.join(sdir, "locked"), "w").close()
            with self.assertRaises(KeychainError) as cm:
                multica_cli.read_token("tester")
            self.assertEqual(cm.exception.kind, "locked")

    def test_redact_filter(self):
        seen = []

        class H(logging.Handler):
            def emit(self, record):
                seen.append(record.getMessage())

        log = logging.getLogger("t4.redact")
        log.setLevel(logging.DEBUG)
        h = H()
        h.addFilter(multica_cli.RedactFilter([TOKEN]))
        log.addHandler(h)
        try:
            log.info("token %s and %s ok", TOKEN, "mat_abcdef123")
        finally:
            log.removeHandler(h)
        self.assertEqual(seen, ["token <token> and <token> ok"])
        self.assertNotIn(TOKEN, seen[0])

    def test_token_regex_needs_a_boundary(self):
        h = multica_cli.RedactFilter([])
        rec = logging.LogRecord("x", logging.INFO, "", 0, "format_xyzabcdef and (mul_abcdef12)", None, None)
        h.filter(rec)
        self.assertEqual(rec.getMessage(), "format_xyzabcdef and (<token>)")

    # ---- the stub is pinned against the synthetic fixtures ------------------

    CONFORMANCE = {   # fixture -> argv run against a prepared board
        "version.json": ["version"],
        "user-profile.json": ["user", "profile", "get"],
        "issue-create.json": ["issue", "create", "--title", "new", "--property", "omega_run=k"],
        "issue-get.json": ["issue", "get", "OMEG-1"],
        "issue-list-run.json": ["issue", "list", "--property", "omega_run=k"],
        "issue-status.json": ["issue", "status", "OMEG-1", "done"],
        "issue-runs.json": ["issue", "runs", "OMEG-1"],
        "comment-add.json": ["issue", "comment", "add", "OMEG-1", "--content", "hello"],
        "comment-reply.json": ["issue", "comment", "add", "OMEG-1", "--content", "re", "--parent", "cm-1"],
        "comment-list.json": ["issue", "comment", "list", "OMEG-1"],
        "property-list.json": ["property", "list"],
        "runtime-list.json": ["runtime", "list"],
        "runtime-profile-list.json": ["runtime", "profile", "list"],
        "agent-list.json": ["agent", "list"],
    }

    @staticmethod
    def shape(obj):
        if isinstance(obj, list):
            assert obj, "empty list cannot pin a row shape"
            return ("list", frozenset(obj[0]))
        return ("obj", frozenset(obj))

    def test_stub_conformance(self):
        d = self.board.data()
        d["runtimes"].append(bridgetest.stub.make_runtime(d, "Claude (host.example.lan)", "rp-0"))
        d["runtime_profiles"].append(bridgetest.stub.make_profile(d, "P", "claude", "acp"))
        d["agents"].append(bridgetest.stub.make_agent(d, "gd-probe", "rt-1", 6, "", ["K"]))
        self.board.save(d)
        self.board.add_issue("fixture run", props={"omega_run": "k", "omega_story": "S1"})
        self.board.add_comment("OMEG-1", "seed", author_type="agent", author_id="ag-1")
        self.board.add_run("OMEG-1", "run-1", "2026-10-04T05:00:00Z", "2026-10-04T05:05:00Z")
        for fixture in sorted(os.listdir(FIX)):
            if fixture.endswith(".json"):
                self.assertIn(fixture, self.CONFORMANCE, "fixture without a stub mapping")
        for fixture, argv in self.CONFORMANCE.items():
            with open(os.path.join(FIX, fixture)) as f:
                want = json.load(f)
            got = self.cli.call(argv)
            self.assertEqual(self.shape(got), self.shape(want), fixture)

    def test_stub_rows_carry_bridge_keys(self):
        self.board.add_issue("x", props={"omega_run": "k"}, assignee=("agent", "a"))
        self.board.add_comment("OMEG-1", "c")
        self.board.add_run("OMEG-1", "r1", "2026-10-04T05:00:00Z")
        need = {
            "issue": ("identifier", "status", "status_category", "assignee_type", "assignee_id", "created_at",
                      "parent_issue_id", "properties"),
            "comment": ("id", "parent_id", "author_type", "author_id", "content", "created_at"),
            "run": ("id", "started_at", "completed_at"),
        }
        for k in need["issue"]:
            self.assertIn(k, self.cli.get_issue("OMEG-1"))
        for k in need["comment"]:
            self.assertIn(k, self.cli.list_comments("OMEG-1", "2026-01-01T00:00:00Z")[0])
        for k in need["run"]:
            self.assertIn(k, self.cli.issue_runs("OMEG-1")[0])

    def test_no_deprecated_calls(self):
        files = glob.glob(os.path.join(TESTS, "..", "bridge", "*.py"))
        self.assertTrue(files)
        for path in files:
            with open(path) as f:
                src = f.read()
            for bad in ("utcfromtimestamp", "utcnow", "fromisoformat"):
                self.assertNotIn(bad, src, path)
            body = re.sub(r'^(\s*#[^\n]*\n|\s*""".*?"""\s*\n)*', "", src, count=1, flags=re.S)
            self.assertTrue(body.startswith("from __future__ import annotations") or not body.strip(), path)


if __name__ == "__main__":
    unittest.main()
