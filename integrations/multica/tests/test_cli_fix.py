"""Pinned contract points of the stub and the adapter (#28 Task 4 fix round)."""
import html
import logging
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bridgetest import BridgeCase  # noqa: E402
from bridge import multica_cli  # noqa: E402
from bridge.multica_cli import (AuthError, ForbiddenWrite, KeychainError, NotFoundError,  # noqa: E402
                                PermanentError, TransientError)

TESTS = os.path.dirname(os.path.abspath(__file__))
FIX = os.path.join(TESTS, "fixtures", "cli")
Z_SECONDS = r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$"


class StubContractTest(BridgeCase):
    def test_timeout_after_apply_lands(self):
        self.board.add_issue("x")
        self.board.reset_calls()
        self.board.fault("issue comment add", sleep=20, apply=True)
        with mock.patch.object(multica_cli, "CLI_TIMEOUT", 8):
            with self.assertRaises(TransientError):
                self.cli.add_comment("OMEG-1", "studio: landed")
        self.assertEqual([c["content"] for c in self.board.comments("OMEG-1")], ["studio: landed"])
        calls = self.board.calls("issue comment add")
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0]["stdin"], "studio: landed")

    def test_timeout_without_apply_logs_call_but_writes_nothing(self):
        self.board.add_issue("x")
        self.board.fault("issue comment add", sleep=20)
        with mock.patch.object(multica_cli, "CLI_TIMEOUT", 8):
            with self.assertRaises(TransientError):
                self.cli.add_comment("OMEG-1", "studio: lost")
        self.assertEqual(self.board.comments("OMEG-1"), [])
        self.assertEqual(len(self.board.calls("issue comment add")), 1)

    def test_timestamps_are_z_second_resolution(self):
        row = self.cli.create_issue("t", "d", None, {})
        self.assertRegex(row["created_at"], Z_SECONDS)
        self.assertRegex(row["updated_at"], Z_SECONDS)
        self.assertRegex(self.cli.set_status("OMEG-1", "done")["updated_at"], Z_SECONDS)
        self.assertRegex(self.cli.add_comment("OMEG-1", "studio: hi")["created_at"], Z_SECONDS)
        self.board.set_now(1759554000)
        self.assertEqual(self.cli.create_issue("u", "d", None, {})["created_at"], "2025-10-04T05:00:00Z")

    def test_properties_are_keyed_by_property_id(self):
        ids = {p["name"]: p["id"] for p in self.cli.call(["property", "list"])}
        row = self.cli.create_issue("t", "d", None, {"omega_run": "k", "omega_story": "S1"})
        self.assertEqual(row["properties"], {ids["omega_run"]: "k", ids["omega_story"]: "S1"})
        self.assertEqual(self.board.issue("OMEG-1")["properties"][ids["omega_run"]], "k")

    def test_deleted_issue_is_hidden(self):
        self.board.add_issue("gone", props={"omega_run": "k"})
        self.board.add_issue("kept", props={"omega_run": "k"})
        self.board.remove_issue("OMEG-1")
        with self.assertRaises(NotFoundError):
            self.cli.get_issue("OMEG-1")
        with self.assertRaises(NotFoundError):
            self.cli.issue_runs("OMEG-1")
        self.assertEqual([r["identifier"] for r in self.cli.run_issues("k")], ["OMEG-2"])

    def test_status_category_mirrors_status(self):
        self.board.add_issue("x")
        row = self.cli.set_status("OMEG-1", "blocked")
        self.assertEqual((row["status"], row["status_category"]), ("blocked", "blocked"))
        self.assertEqual(self.cli.get_issue("OMEG-1")["status_category"], "blocked")

    def test_list_comments_passes_since_and_filters(self):
        self.board.add_issue("x")
        self.board.add_comment("OMEG-1", "old", at="2026-10-04T04:59:59Z")
        self.board.add_comment("OMEG-1", "edge", at="2026-10-04T05:00:00Z")
        got = self.cli.list_comments("OMEG-1", "2026-10-04T05:00:00Z")
        self.assertEqual([c["content"] for c in got], ["edge"])
        argv = self.board.calls("issue comment list")[0]["argv"]
        self.assertEqual(argv[argv.index("--since") + 1], "2026-10-04T05:00:00Z")

    def test_find_issues_passes_limit(self):
        self.cli.find_issues("k", None)
        argv = self.board.calls("issue list")[0]["argv"]
        self.assertEqual(argv[argv.index("--limit") + 1], "100")

    def test_duplicate_refused_without_allow_duplicate(self):
        self.cli.call(["issue", "create", "--title", "same"])
        with self.assertRaises(PermanentError) as cm:
            self.cli.call(["issue", "create", "--title", "same"])
        self.assertEqual(cm.exception.code, 1)
        self.assertIn("Active duplicate issue exists: OMEG-1 same (status: backlog)", cm.exception.stderr)
        self.cli.call(["issue", "create", "--title", "same", "--allow-duplicate"])
        self.assertEqual(len(self.board.data()["issues"]), 2)

    def test_bad_status_text_names_the_status(self):
        self.board.add_issue("x")
        with self.assertRaises(PermanentError) as cm:
            self.cli.set_status("OMEG-1", "nope")
        self.assertEqual(cm.exception.code, 5)
        self.assertIn('invalid status "nope"', cm.exception.stderr)

    def test_fixture_duplicate_is_synthetic(self):
        with open(os.path.join(FIX, "errors", "duplicate.txt")) as f:
            self.assertNotIn("probe", f.read())

    def test_stdin_is_devnull_even_when_fd0_holds_data(self):
        r, w = os.pipe()
        os.write(w, b"leaked-from-parent")
        os.close(w)
        saved = os.dup(0)
        try:
            os.dup2(r, 0)
            self.cli.version()
        finally:
            os.dup2(saved, 0)
            os.close(saved)
            os.close(r)
        self.assertEqual(self.board.calls()[0]["stdin"], "")

    def test_run_issues_stops_when_server_ignores_offset(self):
        page = {"has_more": True, "issues": [{"id": "a"}], "limit": 100, "offset": 0, "total": 1}
        with mock.patch.object(self.cli, "call", return_value=page) as m:
            self.assertEqual(self.cli.run_issues("k"), [{"id": "a"}])
        self.assertEqual(m.call_count, 1)
        page = {"has_more": True, "issues": [{"id": "a"}]}          # no total at all
        with mock.patch.object(self.cli, "call", return_value=page) as m:
            with self.assertRaises(PermanentError):
                self.cli.run_issues("k")
        self.assertEqual(m.call_count, multica_cli.RUN_ISSUES_MAX_PAGES)

    def test_run_issues_dedupes_by_id_and_survives_null_total(self):
        pages = [{"has_more": True, "issues": [{"id": "a"}, {"id": "b"}], "total": 300},
                 {"has_more": True, "issues": [{"id": "a"}, {"id": "b"}], "total": 300},
                 {"has_more": False, "issues": [{"id": "c"}], "total": 300}]
        with mock.patch.object(self.cli, "call", side_effect=pages):
            self.assertEqual([r["id"] for r in self.cli.run_issues("k")], ["a", "b", "c"])
        pages = [{"has_more": True, "issues": [{"id": "a"}], "total": None},
                 {"has_more": False, "issues": [{"id": "b"}], "total": None}]
        with mock.patch.object(self.cli, "call", side_effect=pages):          # was a TypeError
            self.assertEqual([r["id"] for r in self.cli.run_issues("k")], ["a", "b"])

    def test_token_is_redacted_before_it_reaches_a_comment_or_issue(self):
        self.board.add_issue("x")
        self.board.reset_calls()
        self.cli.add_comment("OMEG-1", "studio: failed: bad header %s" % self.cli.token)
        self.cli.create_issue("Run %s" % self.cli.token, "desc %s" % self.cli.token, None, {})
        blob = repr([(c["argv"], c["stdin"]) for c in self.board.calls()])
        self.assertNotIn(self.cli.token, blob)
        self.assertIn("<token>", blob)

    def test_forbidden_compares_identifiers_case_insensitively(self):
        self.board.add_issue("request")
        self.board.reset_calls()
        self.cli.forbidden.add("omeg-1")
        with self.assertRaises(ForbiddenWrite):
            self.cli.set_status("OMEG-1", "done")
        self.cli.forbidden.add("OMEG-1")
        with self.assertRaises(ForbiddenWrite):
            self.cli.add_comment("omeg-1", "studio: hi")
        self.assertEqual(self.board.calls(), [])


class CleanTest(BridgeCase):
    def test_public_clean_is_what_a_post_sends(self):
        # N7: the repost check compares against this, so a reply holding a token-shaped string still matches.
        out = self.cli.clean("see mul_abcdef123456 @all")
        self.assertEqual(out, multica_cli.sanitize(multica_cli.redact("see mul_abcdef123456 @all", [self.cli.token])))
        self.assertNotIn("mul_abcdef123456", out)


class PureTest(unittest.TestCase):
    def test_read_token_empty_and_error_kinds(self):
        import tempfile
        sdir = tempfile.mkdtemp()
        self.addCleanup(__import__("shutil").rmtree, sdir, True)
        with mock.patch.dict(os.environ, {"STUB_SECURITY_DIR": sdir}), \
                mock.patch.object(multica_cli, "SECURITY", os.path.join(TESTS, "stub-security")):
            with open(os.path.join(sdir, "omega-multica-bridge-tester"), "w") as f:
                f.write("\n")
            with self.assertRaises(KeychainError) as cm:
                multica_cli.read_token("tester")
            self.assertEqual(cm.exception.kind, "empty")
        with mock.patch.object(multica_cli, "SECURITY", os.path.join(sdir, "no-such-security")):
            with self.assertRaises(KeychainError) as cm:
                multica_cli.read_token("tester")
            self.assertEqual(cm.exception.kind, "error")

    def test_redact_filter_explicit_secret_without_prefix(self):
        h = multica_cli.RedactFilter(["abcdef-plain", ""])
        rec = logging.LogRecord("x", logging.INFO, "", 0, "got abcdef-plain and %s", ("abcdef-plain",), None)
        h.filter(rec)
        self.assertEqual(rec.getMessage(), "got <token> and <token>")

    def test_sanitize_tilde_fences(self):
        for text in ("~~~mermaid\ngraph\n~~~", "~~~~html", "a ~~~ b"):
            self.assertNotIn("~~~", multica_cli.sanitize(text), text)
        self.assertEqual(multica_cli.sanitize("~~ x ~"), "~~ x ~")
        self.assertEqual(multica_cli.sanitize("```"), "`\u200b`\u200b`")

    def test_sanitize_neutralizes_escaped_mentions(self):
        for text in ("[x](mention\\://all/all)", "[x](mention&#58;//all/all)", "[x](mention&colon;//all/all)"):
            out = multica_cli.sanitize(text)
            self.assertIn("no-mention", out, text)
            self.assertNotRegex(out, r"(?<!no-)mention[\\&:]", text)

    def test_sanitize_neutralizes_entity_encoded_mentions(self):
        for text in ("[x](&#109;ention://all/all)", "[x](m&#101;ntion://all/all)", "&#64;everyone", "[x](&#x6d;ention://a/b)"):
            out = multica_cli.sanitize(text)
            self.assertNotRegex(out, r"(?i)(?<!no-)mention:", text)
            self.assertNotIn("@", out, text)
            self.assertEqual(multica_cli.sanitize(out), out, text)
        self.assertEqual(multica_cli.sanitize("fish &amp; chips"), "fish &amp; chips")     # untouched without a hit

    def test_sanitize_double_encoded_and_at_signs_stay_closed_and_idempotent(self):
        for text in ("[x](&amp;#109;ention://all/all) cc @b", "x &amp;#64; @y", "&amp;amp;#109;ention://a/b @c",
                     "[x](&amp;amp;amp;#109;ention://all/all) @", "&amp;#64;everyone", "a &amp; b @c"):
            out = multica_cli.sanitize(text)
            self.assertNotRegex(html.unescape(out), r"(?i)(?<!no-)mention:", text)
            self.assertNotIn("@", html.unescape(out), text)
            self.assertEqual(multica_cli.sanitize(out), out, text)

    def test_429_status_is_not_an_identifier_suffix(self):
        self.assertNotIsInstance(multica_cli.classify(1, "Issue OMEG-429 refused the change"), TransientError)
        self.assertIsInstance(multica_cli.classify(1, "HTTP 429"), TransientError)
        self.assertIsInstance(multica_cli.classify(1, "429 Too Many Requests"), TransientError)

    def test_sanitize_is_idempotent(self):
        for text in ("mention:", "[x](MENTION://a/b)", "no-mention:", "@a ```x ~~~y", "mention\\:",
                     "mention&#58;", "plain"):
            once = multica_cli.sanitize(text)
            self.assertEqual(multica_cli.sanitize(once), once, text)
        self.assertEqual(multica_cli.sanitize("mention:"), "no-mention:")

    def test_identifier_digits_are_not_status_codes(self):
        self.assertNotIsInstance(multica_cli.classify(1, "Issue OMEG-401 already has a parent"), AuthError)
        e = multica_cli.classify(1, "OMEG-503 refused the change")
        self.assertIsInstance(e, PermanentError)
        self.assertNotIsInstance(e, TransientError)
        self.assertIsInstance(multica_cli.classify(1, "HTTP 401"), AuthError)
        self.assertIsInstance(multica_cli.classify(1, "HTTP 404: x"), NotFoundError)
        self.assertIsInstance(multica_cli.classify(1, "503"), TransientError)

    def test_exit_code_fallback_for_unknown_text(self):
        self.assertIsInstance(multica_cli.classify(3, "garbled"), AuthError)
        self.assertIsInstance(multica_cli.classify(4, "garbled"), NotFoundError)
        e = multica_cli.classify(2, "garbled")
        self.assertIsInstance(e, PermanentError)
        self.assertNotIsInstance(e, (AuthError, NotFoundError))


if __name__ == "__main__":
    unittest.main()
