"""Config loader gaps (#28 Task 4 fix round)."""
import os
import shutil
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from bridge import config  # noqa: E402

BASE = "workspace_id=w\noperator_member_id=m\n"


class ConfigGapTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.path = os.path.join(self.tmp, "config")

    def write(self, text):
        with open(self.path, "w") as f:
            f.write(text)
        return self.path

    def test_line_without_equals_names_the_line(self):
        with self.assertRaises(config.ConfigError) as cm:
            config.load(self.write(BASE + "junk\n"))
        self.assertIn("%s: junk:" % self.path, str(cm.exception))

    def test_duplicate_key_refused(self):
        with self.assertRaises(config.ConfigError) as cm:
            config.load(self.write(BASE + "workspace_id=x\n"))
        self.assertIn("workspace_id", str(cm.exception))
        self.assertIn("twice", str(cm.exception))

    def test_poll_seconds_rejects_underscores_and_signs(self):
        for bad in ("1_0", "+7", "-9", "7x"):
            with self.assertRaises(config.ConfigError, msg=bad):
                config.load(self.write(BASE + "poll_seconds=%s\n" % bad))

    def test_cli_falls_back_to_path_then_desktop(self):
        with mock.patch.object(config.os.path, "isfile", lambda p: False), \
                mock.patch.object(config.shutil, "which", lambda n: "/opt/bin/multica" if n == "multica" else None):
            self.assertEqual(config.load(self.write(BASE)).cli, "/opt/bin/multica")
        with mock.patch.object(config.os.path, "isfile", lambda p: False), \
                mock.patch.object(config.shutil, "which", lambda n: None):
            self.assertEqual(config.load(self.write(BASE)).cli, config.DESKTOP_CLI)
        self.assertEqual(config.load(self.write(BASE + "cli=/x/mc\n")).cli, "/x/mc")

    def test_default_cli_is_an_absolute_path(self):
        self.assertTrue(os.path.isabs(config.load(self.write(BASE)).cli))

    def test_server_url_override_and_empty_value_defaults(self):
        self.assertEqual(config.load(self.write(BASE + "server_url=http://h:1\n")).server_url, "http://h:1")
        self.assertEqual(config.load(self.write(BASE + "server_url=\n")).server_url, config.DEFAULT_SERVER)


if __name__ == "__main__":
    unittest.main()
