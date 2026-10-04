"""bridge.installjson: the JSON questions install.sh and uninstall.sh ask (#28)."""
from __future__ import annotations

import io
import json
import os
import plistlib
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from unittest import mock

TESTS = os.path.dirname(os.path.abspath(__file__))
MULTICA = os.path.dirname(TESTS)
if MULTICA not in sys.path:
    sys.path.insert(0, MULTICA)

from bridge import installjson as ij  # noqa: E402

FIX = os.path.join(TESTS, "fixtures", "cli")


def fixture(name):
    with open(os.path.join(FIX, name), encoding="utf-8") as f:
        return json.load(f)


def ask(question, *args, stdin=None):
    """Run main() with JSON on stdin; returns (exit code, stdout, stderr)."""
    out, err = io.StringIO(), io.StringIO()
    with mock.patch("sys.stdin", io.StringIO(json.dumps(stdin))), redirect_stdout(out), redirect_stderr(err):
        code = ij.main([question, *args])
    return code, out.getvalue().rstrip("\n"), err.getvalue()


def rt(rid, profile, daemon, status="online"):
    return {"id": rid, "profile_id": profile, "daemon_id": daemon, "status": status}


class InstallJsonTest(unittest.TestCase):
    def test_property_state(self):
        props = fixture("property-list.json")
        self.assertEqual(ask("property-state", "omega_run", stdin=props)[1], "ok")
        self.assertEqual(ask("property-state", "nope", stdin=props)[1], "absent")
        archived = [dict(props[0], archived=True)]
        self.assertEqual(ask("property-state", "omega_run", stdin=archived)[1], "archived")
        archived_at = [dict(props[0], archived_at="2026-10-04T05:19:43Z")]
        self.assertEqual(ask("property-state", "omega_run", stdin=archived_at)[1], "archived")
        wrong = [dict(props[0], type="select")]
        self.assertEqual(ask("property-state", "omega_run", stdin=wrong)[1], "wrong-type:select")

    def test_profile_for_command(self):
        profiles = fixture("runtime-profile-list.json")
        self.assertEqual(ask("profile-for-command", "claude", stdin=profiles)[1], profiles[0]["id"])
        self.assertEqual(ask("profile-for-command", "claude-multica", stdin=profiles)[1], "")
        two = profiles + [dict(profiles[0], id="second")]
        self.assertEqual(ask("profile-for-command", "claude", stdin=two)[1], profiles[0]["id"] + "\nsecond")

    def test_profile_for_command_matches_on_basename(self):
        profiles = [{"id": "p1", "command_name": "/Users/x/.local/bin/omega-multica-agent"},
                    {"id": "p2", "command_name": "claude-multica"}, {"id": "p3", "command_name": None}]
        self.assertEqual(ask("profile-for-command", "omega-multica-agent", stdin=profiles)[1], "p1")
        self.assertEqual(ask("profile-for-command", "/home/y/.local/bin/claude-multica", stdin=profiles)[1], "p2")
        self.assertEqual(ask("profile-for-command", "claude", stdin=profiles)[1], "")

    def test_daemons_needs_both_profiles_online(self):
        rts = [rt("1", "pa", "d1"), rt("2", "pb", "d1"),
               rt("3", "pa", "d2"),                       # d2 serves only pa
               rt("4", "pa", "d3"), rt("5", "pb", "d3", status="offline")]
        self.assertEqual(ask("daemons", "pa", "pb", stdin=rts)[1], "d1")
        rts += [rt("6", "pa", "d4"), rt("7", "pb", "d4")]
        self.assertEqual(ask("daemons", "pa", "pb", stdin=rts)[1], "d1\nd4")
        self.assertEqual(ask("daemons", "pa", "pb", stdin=[])[1], "")
        env = {"runtimes": rts}      # a bare list is the P7 shape, but an envelope still reads
        self.assertEqual(ask("daemons", "pa", "pb", stdin=env)[1], "")

    def test_daemons_on_the_p7_fixture(self):
        r = fixture("runtime-list.json")
        self.assertEqual(ask("daemons", r[0]["profile_id"], stdin=r)[1], r[0]["daemon_id"])

    def test_daemon_names_carry_the_host(self):
        rts = [dict(rt("1", "pa", "d1"), name="Claude (host-one)"), rt("2", "pb", "d1"),
               dict(rt("3", "pa", "d2"), name="Claude (host-two)"), rt("4", "pb", "d2"),
               rt("5", "pa", "d3")]
        self.assertEqual(ask("daemon-names", "pa", "pb", stdin=rts)[1],
                         "d1 (Claude (host-one))\nd2 (Claude (host-two))")

    def test_selftest_fresh(self):
        since = "2026-10-04T05:00:00Z"
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "selftest.json")
            self.assertEqual(ask("selftest-fresh", p, since, stdin=None)[1], "")
            for body, want in (('{"ok": true, "checked_at": "2026-10-04T05:00:00Z"}', "fresh"),
                               ('{"ok": true, "checked_at": "2026-10-04T04:59:59Z"}', ""),
                               ('{"ok": tr', ""), ('{"ok": true}', "")):
                with open(p, "w") as f:
                    f.write(body)
                self.assertEqual(ask("selftest-fresh", p, since, stdin=None)[1], want, body)

    def test_runtime_for(self):
        rts = [rt("1", "pa", "d1"), rt("2", "pb", "d1"), rt("3", "pa", "d2"), rt("4", "pa", "d1", "offline")]
        self.assertEqual(ask("runtime-for", "pa", "d1", stdin=rts)[1], "1")
        self.assertEqual(ask("runtime-for", "pa", "d9", stdin=rts)[1], "")

    def test_agent_state(self):
        agents = fixture("agent-list.json")
        name = agents[0]["name"]
        self.assertEqual(ask("agent-state", name, stdin=agents)[1], "active")
        self.assertEqual(ask("agent-state", "other", stdin=agents)[1], "absent")
        gone = [dict(agents[0], archived_at="2026-10-04T05:19:43Z")]
        self.assertEqual(ask("agent-state", name, stdin=gone)[1], "archived")

    def test_bound_agents_skips_archived(self):
        with tempfile.TemporaryDirectory() as d:
            agents = [{"name": "gd", "runtime_id": "r1", "archived_at": None},
                      {"name": "old", "runtime_id": "r1", "archived_at": "2026-10-04T05:19:43Z"},
                      {"name": "zed", "runtime_id": "r1"},
                      {"name": "elsewhere", "runtime_id": "r9"}]
            rts = [rt("r1", "pa", "d1"), rt("r9", "px", "d1")]
            fa, fr = os.path.join(d, "a.json"), os.path.join(d, "r.json")
            for path, data in ((fa, agents), (fr, rts)):
                with open(path, "w", encoding="utf-8") as f:
                    json.dump(data, f)
            self.assertEqual(ask("bound-agents", fa, fr, "pa", "pb", stdin=None)[1], "gd\nzed")
            self.assertEqual(ask("bound-agents", fa, fr, "pz", stdin=None)[1], "")

    def test_selftest_kind_tabs_and_newlines(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "selftest.json")

            def write(obj):
                with open(p, "w", encoding="utf-8") as f:
                    json.dump(obj, f)
            write({"ok": True})
            self.assertEqual(ask("selftest-kind", p, stdin=None)[1], "ok")
            write({"ok": False, "kind": "file-access", "error": "line one\nline two", "interpreter": "/x/python3"})
            self.assertEqual(ask("selftest-kind", p, stdin=None)[1],
                             "file-access\tline one line two\t/x/python3")
            write({"ok": False, "error": None})
            self.assertEqual(ask("selftest-kind", p, stdin=None)[1], "\t\t")
            code, _, err = ask("selftest-kind", os.path.join(d, "missing.json"), stdin=None)
            self.assertEqual(code, 1)
            self.assertIn("installjson selftest-kind", err)

    def test_get(self):
        profile = fixture("user-profile.json")
        self.assertEqual(ask("get", "id", stdin=profile)[1], profile["id"])
        with self.assertRaises(SystemExit) as cm:
            ask("get", "no_such_key", stdin=profile)
        self.assertIn("no_such_key", str(cm.exception))

    def test_json_env_escapes(self):
        value = 'a "quoted" back\\slash/proj'
        out = ask("json-env", "OMEGA_PROJECT", value, stdin=None)[1]
        self.assertEqual(json.loads(out), {"OMEGA_PROJECT": value})

    def test_plist_escapes_and_lints(self):
        template = os.path.join(MULTICA, "launchd", "ai.omega.multica-bridge.plist.in")
        home = "/Users/a&b<c>"
        code, out, _ = ask("plist", template, "/usr/bin/python3", home + "/lib", home + "/base", home,
                           home + "/.local/bin:/usr/bin", stdin=None)
        self.assertEqual(code, 0)
        d = plistlib.loads(out.encode("utf-8"))
        self.assertEqual(d["Label"], "ai.omega.multica-bridge")
        self.assertEqual(d["ProgramArguments"], ["/usr/bin/python3", home + "/lib/bin/multica-bridge", "run"])
        self.assertEqual(d["EnvironmentVariables"], {"PATH": home + "/.local/bin:/usr/bin", "HOME": home})
        self.assertIs(d["KeepAlive"], True)
        self.assertIs(d["RunAtLoad"], True)
        self.assertEqual(d["StandardOutPath"], home + "/base/launchd.out")
        self.assertEqual(d["StandardErrorPath"], home + "/base/launchd.err")

    def test_usage_exit_2(self):
        for argv in ([], ["nosuchquestion"]):
            err = io.StringIO()
            with redirect_stderr(err):
                self.assertEqual(ij.main(argv), 2)
            self.assertIn("usage: installjson", err.getvalue())

    def test_bad_input_exit_1(self):
        code, _, err = ask("plist", "/no/such/template", "a", "b", "c", "d", "e", stdin=None)
        self.assertEqual(code, 1)
        self.assertIn("installjson plist", err)
        code, _, err = ask("agent-state", stdin=[])        # missing argument: TypeError
        self.assertEqual(code, 1)


if __name__ == "__main__":
    unittest.main()
