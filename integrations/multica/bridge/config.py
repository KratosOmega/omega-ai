"""Bridge config: key=value lines at ~/.claude-gamedev/multica/config (#28)."""
from __future__ import annotations

import os
import shutil

DESKTOP_CLI = "/Applications/Multica.app/Contents/Resources/app.asar.unpacked/resources/bin/multica"
CHECKOUT_STUDIOS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "studios")
DEFAULT_SERVER = "https://api.multica.ai"
KEYS = ("server_url", "workspace_id", "operator_member_id", "roots", "poll_seconds", "cli", "studio_overnight",
        "selftest_roots")
REQUIRED = ("workspace_id", "operator_member_id")


class ConfigError(Exception):
    pass


class Config:
    def __init__(self, server_url: str, workspace_id: str, operator_member_id: str, roots: list,
                 poll_seconds: int, cli: str, studio_overnight: str, selftest_roots: list | None = None):
        self.server_url = server_url
        self.workspace_id = workspace_id
        self.operator_member_id = operator_member_id
        self.roots = roots
        self.poll_seconds = poll_seconds
        self.cli = cli
        self.studio_overnight = studio_overnight
        self.selftest_roots = selftest_roots or []      # read-checked by the self-test only (install's --project)


def load(path: str) -> Config:
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.read().splitlines()
    except OSError as e:
        raise ConfigError("%s: cannot read the config: %s" % (path, e.strerror or e))
    raw = {}
    for n, line in enumerate(lines, 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        key, eq, value = line.partition("=")
        key = key.strip()
        if not eq:
            raise ConfigError("%s: %s: expected key=value (line %d)" % (path, line, n))
        if key not in KEYS:
            raise ConfigError("%s: %s: unknown key" % (path, key))
        if key in raw:
            raise ConfigError("%s: %s: given twice (line %d)" % (path, key, n))
        raw[key] = value.strip()
    for key in REQUIRED:
        if not raw.get(key):
            raise ConfigError("%s: %s: required" % (path, key))
    poll = raw.get("poll_seconds", "15")
    try:
        if not poll.isdigit():          # int() would also take "1_0" and " +7"
            raise ValueError(poll)
        poll_seconds = int(poll)
    except ValueError:
        raise ConfigError("%s: poll_seconds: %r is not an integer" % (path, poll))
    if not 5 <= poll_seconds <= 300:
        raise ConfigError("%s: poll_seconds: %d is outside 5-300" % (path, poll_seconds))
    cli = raw.get("cli")
    if not cli:
        cli = DESKTOP_CLI if os.path.isfile(DESKTOP_CLI) else (shutil.which("multica") or DESKTOP_CLI)
    studio = raw.get("studio_overnight")
    if not studio:
        if not os.path.isdir(CHECKOUT_STUDIOS):
            raise ConfigError("%s: studio_overnight: required outside a checkout" % path)
        studio = os.path.normpath(os.path.join(CHECKOUT_STUDIOS, "game-dev", "bin", "studio-overnight"))
    roots = [r.strip() for r in raw.get("roots", "").split(",") if r.strip()]
    selftest_roots = [r.strip() for r in raw.get("selftest_roots", "").split(",") if r.strip()]
    return Config(raw.get("server_url") or DEFAULT_SERVER, raw["workspace_id"], raw["operator_member_id"],
                  roots, poll_seconds, cli, studio, selftest_roots)
