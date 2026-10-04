"""Shared test harness for the Multica bridge (#28): the stub board and BridgeCase."""
from __future__ import annotations

import importlib.machinery
import importlib.util
import json
import logging
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

TESTS = os.path.dirname(os.path.abspath(__file__))
MULTICA = os.path.dirname(TESTS)
if MULTICA not in sys.path:
    sys.path.insert(0, MULTICA)

from bridge import config  # noqa: E402
from bridge.multica_cli import Cli  # noqa: E402

OPERATOR = "m-op"
TOKEN = "mul_testtoken123456"
WS = "ws-test"

# The stub doubles as the row-template library, so Board and the stub never drift.
_loader = importlib.machinery.SourceFileLoader("stub_multica", os.path.join(TESTS, "stub-multica"))
_spec = importlib.util.spec_from_loader("stub_multica", _loader)
stub = importlib.util.module_from_spec(_spec)
_loader.exec_module(stub)


class Board:
    """The stub's workspace on disk: cli_dir/multica (symlink) + cli_dir/stub-state/."""

    def __init__(self, cli_dir: str):
        self.cli_dir = cli_dir
        self.state = os.path.join(cli_dir, "stub-state")
        os.makedirs(os.path.join(self.state, "errors"))
        os.symlink(os.path.join(TESTS, "stub-multica"), os.path.join(cli_dir, "multica"))
        board = {"token": TOKEN, "role": "owner", "auto_runtime": True, "daemon_id": "daemon-1",
                 "version": "0.6.1", "now": None, "counters": {}, "deleted": [],
                 "user": {"id": OPERATOR, "name": "Operator", "email": "operator@example.com"},
                 "properties": [], "issues": [], "comments": [], "runs": {}, "runtimes": [],
                 "runtime_profiles": [], "agents": []}
        for name in ("omega_run", "omega_story"):
            board["properties"].append(stub.make_property(board, name, "text"))
        self.save(board)
        for src in sorted(os.listdir(os.path.join(TESTS, "fixtures", "cli", "errors"))):
            shutil.copy(os.path.join(TESTS, "fixtures", "cli", "errors", src),
                        os.path.join(self.state, "errors", src))

    @property
    def cli(self) -> str:
        return os.path.join(self.cli_dir, "multica")

    def data(self) -> dict:
        with open(os.path.join(self.state, "board.json"), encoding="utf-8") as f:
            return json.load(f)

    def save(self, d: dict) -> None:
        with open(os.path.join(self.state, "board.json"), "w", encoding="utf-8") as f:
            json.dump(d, f)

    def _prop_ids(self, d: dict, props: dict) -> dict:
        by_name = {p["name"]: p["id"] for p in d["properties"]}
        return {by_name.get(k, k): v for k, v in (props or {}).items()}

    def add_issue(self, title, status="todo", parent=None, props=None, assignee=None, created_at=None) -> str:
        """`props` is keyed by property name; `assignee` is (kind, id) or None; `parent` an identifier."""
        d = self.data()
        pid = None
        if parent:
            pid = next(r["id"] for r in d["issues"] if parent in (r["identifier"], r["id"]))
        kind, aid = assignee if assignee else (None, None)
        row = stub.make_issue(d, title, "", status, pid, kind, aid, self._prop_ids(d, props), created_at)
        self.save(d)
        return row["identifier"]

    def _row(self, d, ident):
        return next(r for r in d["issues"] if ident in (r["identifier"], r["id"]))

    def issue(self, ident) -> dict:
        return self._row(self.data(), ident)

    def assign(self, ident, kind, aid) -> None:
        d = self.data()
        r = self._row(d, ident)
        r["assignee_type"], r["assignee_id"] = (kind, aid) if kind else (None, None)
        self.save(d)

    def set_status(self, ident, status) -> None:
        d = self.data()
        r = self._row(d, ident)
        r["status"] = r["status_category"] = status
        self.save(d)

    def remove_issue(self, ident) -> None:
        d = self.data()
        d["deleted"].append(self._row(d, ident)["id"])
        self.save(d)

    def add_comment(self, ident, content, author_type="member", author_id=OPERATOR, parent=None, at=None) -> str:
        d = self.data()
        row = stub.make_comment(d, self._row(d, ident)["id"], content, author_type, author_id, parent, at)
        self.save(d)
        return row["id"]

    def comments(self, ident) -> list:
        d = self.data()
        iid = self._row(d, ident)["id"]
        return [c for c in d["comments"] if c["issue_id"] == iid]

    def add_run(self, ident, run_id, started_at, completed_at=None, status="completed") -> None:
        d = self.data()
        r = self._row(d, ident)
        d["runs"].setdefault(r["identifier"], []).append(
            stub.make_run(r["id"], run_id, started_at, completed_at, status))
        self.save(d)

    def calls(self, prefix: str = "") -> list:
        path = os.path.join(self.state, "calls.jsonl")
        if not os.path.exists(path):
            return []
        words = prefix.split()
        with open(path, encoding="utf-8") as f:
            rows = [json.loads(line) for line in f if line.strip()]
        return [r for r in rows if r["argv"][:len(words)] == words]

    def reset_calls(self) -> None:
        path = os.path.join(self.state, "calls.jsonl")
        if os.path.exists(path):
            os.remove(path)

    def fault(self, cmd, **rule) -> None:
        path = os.path.join(self.state, "faults.json")
        rules = []
        if os.path.exists(path):
            with open(path, encoding="utf-8") as f:
                rules = json.load(f)
        rules.append(dict(rule, cmd=cmd))
        with open(path, "w", encoding="utf-8") as f:
            json.dump(rules, f)

    def set_now(self, epoch) -> None:
        d = self.data()
        d["now"] = epoch
        self.save(d)


def make_project(tmp: str, name: str) -> str:
    """A project root with `.studio/reports/`."""
    root = os.path.join(tmp, name)
    os.makedirs(os.path.join(root, ".studio", "reports"))
    return root


def ev(event: str, **fields) -> dict:
    """An events.jsonl record with the v1 envelope."""
    d = {"v": 1, "ts": "2026-10-03T22:14:05Z", "run": "overnight-20261003-2214", "event": event}
    d.update(fields)
    return d


_DUMMIES = []


def kill_dummies() -> None:
    while _DUMMIES:
        p = _DUMMIES.pop()
        try:
            p.kill()
        except OSError:
            pass
        p.wait()


class Crash(BaseException):
    """A simulated process death: not an Exception, so no per-run handler may swallow it."""


def wait_gone(pid, limit=10.0) -> bool:
    """True once `pid` no longer exists, polling up to `limit` s (a reparented zombie needs a moment to be reaped)."""
    end = time.monotonic() + limit
    while time.monotonic() < end:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return True
        time.sleep(0.05)
    return False


class Run:
    """A fixture run: registry entry, run dir, events.jsonl, and a live dummy runner."""

    def __init__(self, home, root, basename, live, origin):
        self.root = root
        self.basename = basename
        self.run_dir = os.path.join(root, ".studio", "reports", basename)
        os.makedirs(self.run_dir)
        self.events = os.path.join(self.run_dir, "events.jsonl")
        open(self.events, "a").close()
        self.registry = os.path.join(home, ".claude-gamedev", "runs")
        os.makedirs(self.registry, exist_ok=True)
        self._proc = subprocess.Popen(["sh", "-c", "sleep 600; :", "studio-overnight"],
                                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        _DUMMIES.append(self._proc)
        self.pid = self._proc.pid
        self.entry = os.path.join(self.registry, "%s-%d" % (basename, self.pid))
        text = "root=%s\nstart=%s\nrun=%s\npid=%d\nstarted=2026-10-03T22:14:05Z\n" % (
            root, root, self.run_dir, self.pid)
        if origin is not None:
            text += "origin=%s\n" % origin
        with open(self.entry, "w", encoding="utf-8") as f:
            f.write(text)
        if not live:
            self.kill()

    def append(self, *events) -> None:
        with open(self.events, "ab") as f:
            for e in events:
                f.write(json.dumps(e, separators=(",", ":"), ensure_ascii=False).encode("utf-8") + b"\n")

    def append_raw(self, text: str) -> None:
        with open(self.events, "ab") as f:
            f.write(text.encode("utf-8"))

    def end_entry(self) -> None:
        """Move the entry to runs/last, with ended=."""
        with open(self.entry, encoding="utf-8") as f:
            text = f.read()
        os.remove(self.entry)
        with open(os.path.join(self.registry, "last"), "w", encoding="utf-8") as f:
            f.write(text + "ended=2026-10-03T23:00:00Z\n")

    def kill(self) -> None:
        try:
            self._proc.kill()
        except OSError:
            pass
        self._proc.wait()


def make_run(home, root, basename="overnight-20261003-2214", live=True, origin=None) -> Run:
    return Run(home, root, basename, live, origin)


class BridgeCase(unittest.TestCase):
    def setUp(self):
        self.addCleanup(kill_dummies)
        self.tmp = tempfile.mkdtemp(prefix="bridge-")
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.home = os.path.join(self.tmp, "home")
        os.makedirs(self.home)
        cli_dir = os.path.join(self.tmp, "cli")
        os.makedirs(cli_dir)
        self.board = Board(cli_dir)
        self.cfg_path = os.path.join(self.tmp, "config")
        with open(self.cfg_path, "w", encoding="utf-8") as f:
            f.write("cli=%s\nserver_url=http://stub.invalid\nworkspace_id=%s\noperator_member_id=%s\n"
                    "studio_overnight=%s\n" % (self.board.cli, WS, OPERATOR,
                                               os.path.join(TESTS, "stub-studio-overnight")))
        self.cfg = config.load(self.cfg_path)
        self.log = logging.getLogger("bridgetest")
        self.cli = Cli(self.cfg, TOKEN, os.path.join(self.home, ".claude-gamedev", "multica", "cli-home"),
                       self.log)


class MirrorCase(BridgeCase):
    """BridgeCase plus a Ctx whose clock can be skewed and whose notices are collected."""

    def setUp(self):
        super().setUp()
        from bridge import mirror, state
        self.mirror, self.state = mirror, state
        self.notes = []
        self.skew = 0.0
        self.t0 = time.time()                # frozen: only `skew` moves the clock (no wall-time flake)
        self.paths = state.Paths(self.home)
        self.ctx = state.Ctx(self.cfg, self.paths, self.cli, self.log,
                             lambda kind, text: self.notes.append((kind, text)),
                             now=lambda: self.t0 + self.skew)

    def poll(self):
        self.ctx.rows = {}
        self.mirror.poll_runs(self.ctx)

    def key(self, run) -> str:
        return self.state.run_key(run.run_dir, run.root)

    def _issues(self):
        d = self.board.data()
        return d, [r for r in d["issues"] if r["id"] not in d["deleted"]]

    def named_props(self, row) -> dict:
        d = self.board.data()
        names = {p["id"]: p["name"] for p in d["properties"]}
        return {names.get(k, k): v for k, v in row["properties"].items()}

    def run_issue(self, run) -> dict:
        _, rows = self._issues()
        hit = [r for r in rows if self.named_props(r).get("omega_run") == self.key(run)
               and "omega_story" not in self.named_props(r)]
        return hit[0] if hit else None

    def story_issue(self, run, story) -> dict:
        _, rows = self._issues()
        hit = [r for r in rows if self.named_props(r).get("omega_run") == self.key(run)
               and self.named_props(r).get("omega_story") == story]
        return hit[-1] if hit else None

    def comments_on(self, ident) -> list:
        return [c["content"] for c in self.board.comments(ident)]

    def status_calls(self) -> list:
        return [c["argv"] for c in self.board.calls("issue status")]
