"""Config loader tests (#28 Task 4)."""
import os
import shutil
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from bridge import config  # noqa: E402


class ConfigTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.path = os.path.join(self.tmp, "config")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def write(self, text):
        with open(self.path, "w") as f:
            f.write(text)
        return self.path

    def test_defaults(self):
        c = config.load(self.write("workspace_id=ws1\noperator_member_id=m1\n"))
        self.assertEqual(c.server_url, "https://api.multica.ai")
        self.assertEqual((c.workspace_id, c.operator_member_id), ("ws1", "m1"))
        self.assertEqual(c.roots, [])
        self.assertEqual(c.poll_seconds, 15)
        self.assertTrue(c.cli)
        self.assertTrue(c.studio_overnight.endswith("studios/game-dev/bin/studio-overnight"))

    def test_cli_default_is_desktop_when_present(self):
        with mock.patch.object(config.os.path, "isfile", lambda p: p == config.DESKTOP_CLI):
            c = config.load(self.write("workspace_id=w\noperator_member_id=m\n"))
        self.assertEqual(c.cli, config.DESKTOP_CLI)

    def test_studio_overnight_required_outside_checkout(self):
        body = "workspace_id=w\noperator_member_id=m\n"
        with mock.patch.object(config, "CHECKOUT_STUDIOS", "/nonexistent/studios"):
            with self.assertRaises(config.ConfigError) as cm:
                config.load(self.write(body))
            self.assertIn("studio_overnight", str(cm.exception))
            c = config.load(self.write(body + "studio_overnight=/x/so\n"))
            self.assertEqual(c.studio_overnight, "/x/so")

    def test_missing_file(self):
        with self.assertRaises(config.ConfigError) as cm:
            config.load(os.path.join(self.tmp, "nope"))
        self.assertIn("nope", str(cm.exception))

    def test_required_missing(self):
        for body, key in (("operator_member_id=m\n", "workspace_id"), ("workspace_id=w\n", "operator_member_id")):
            with self.assertRaises(config.ConfigError) as cm:
                config.load(self.write(body))
            self.assertIn(key, str(cm.exception))
            self.assertIn(self.path, str(cm.exception))

    def test_unknown_key(self):
        with self.assertRaises(config.ConfigError) as cm:
            config.load(self.write("workspace_id=w\noperator_member_id=m\ncolour=red\n"))
        self.assertIn("colour", str(cm.exception))

    def test_line_without_equals(self):
        with self.assertRaises(config.ConfigError):
            config.load(self.write("workspace_id=w\noperator_member_id=m\njunk\n"))

    def test_poll_seconds_range(self):
        base = "workspace_id=w\noperator_member_id=m\npoll_seconds="
        for bad in ("4", "301", "x", ""):
            with self.assertRaises(config.ConfigError) as cm:
                config.load(self.write(base + bad + "\n"))
            self.assertIn("poll_seconds", str(cm.exception))
        for ok in (5, 300):
            self.assertEqual(config.load(self.write(base + str(ok) + "\n")).poll_seconds, ok)

    def test_selftest_roots_split_and_default_empty(self):
        c = config.load(self.write("workspace_id=w\noperator_member_id=m\nselftest_roots= /a , /b ,,\n"))
        self.assertEqual(c.selftest_roots, ["/a", "/b"])
        self.assertEqual(config.load(self.write("workspace_id=w\noperator_member_id=m\n")).selftest_roots, [])

    def test_roots_split_and_strip(self):
        c = config.load(self.write("workspace_id=w\noperator_member_id=m\nroots= /a , /b ,, \n"))
        self.assertEqual(c.roots, ["/a", "/b"])

    def test_comments_and_blank_lines(self):
        c = config.load(self.write("# hi\n\n  workspace_id = w \n  # x\noperator_member_id=m\n"))
        self.assertEqual((c.workspace_id, c.operator_member_id), ("w", "m"))


if __name__ == "__main__":
    unittest.main()
