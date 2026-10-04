"""Per-run state files, atomic writes, the bridge lock, retired keys, time helpers (#28)."""
from __future__ import annotations

import contextlib
import fcntl
import hashlib
import json
import math
import os
import re
import tempfile
import time
from datetime import datetime, timezone

_TS = re.compile(r"^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,9}))?(Z|[+-]\d{2}:?\d{2})?$")


class LockBusy(Exception):
    pass


class Paths:
    """Every file the bridge owns under `<home>/.claude-gamedev/multica/`."""

    def __init__(self, home: str):
        self.home = home
        self.base = os.path.join(home, ".claude-gamedev", "multica")
        self.config = os.path.join(self.base, "config")
        self.lock = os.path.join(self.base, "bridge.lock")
        self.selftest = os.path.join(self.base, "selftest.json")
        self.status = os.path.join(self.base, "status.json")
        self.lib = os.path.join(self.base, "lib")
        self.cli_home = os.path.join(self.base, "cli-home")
        self.links = os.path.join(self.base, "links")
        self.state_dir = os.path.join(self.base, "state")
        self.retired_dir = os.path.join(self.state_dir, "retired")
        self.retired_file = os.path.join(self.base, "retired")
        self.log = os.path.join(self.base, "bridge.log")


class Ctx:
    """What one poll passes around: cfg, paths, cli, log, notify, now.

    `notify(kind: str, text: str) -> None` raises an operator-visible notice.
    `rows` is the per-poll issue cache (identifier or id -> issue row) that the
    sync steps fill and share; it starts empty and the poll resets it.
    """

    def __init__(self, cfg, paths, cli, log, notify, now=time.time):
        self.cfg = cfg
        self.paths = paths
        self.cli = cli
        self.log = log
        self.notify = notify
        self.now = now
        self.rows = {}


def parse_ts(s: str) -> float:
    m = _TS.match(s.strip())
    if not m:
        raise ValueError("bad timestamp: %r" % s)
    y, mo, d, h, mi, se, frac, tz = m.groups()
    t = datetime(int(y), int(mo), int(d), int(h), int(mi), int(se), tzinfo=timezone.utc).timestamp()
    if frac:
        t += int(frac.ljust(9, "0")) / 1e9
    if tz and tz != "Z":
        sign = 1 if tz[0] == "+" else -1
        t -= sign * (int(tz[1:3]) * 3600 + int(tz[-2:]) * 60)
    return t


def fmt_since(t: float) -> str:
    return datetime.fromtimestamp(math.floor(t), timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def iso_now(t: float) -> str:
    return fmt_since(t)


def _mkdirs(*paths: str) -> None:
    """Create each directory (parents first) owner-only; existing ones are left as they are."""
    for p in paths:
        os.makedirs(p, mode=0o700, exist_ok=True)


def _fsync_dir(d: str) -> None:
    fd = os.open(d, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def atomic_write_json(path: str, data) -> None:
    d = os.path.dirname(path) or "."
    fd, tmp = tempfile.mkstemp(prefix=".tmp-", dir=d)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f, sort_keys=True)
            f.flush()
            os.fsync(f.fileno())
        os.chmod(tmp, 0o600)
        os.replace(tmp, path)
        _fsync_dir(d)
    except BaseException:
        with contextlib.suppress(OSError):
            os.remove(tmp)
        raise


def read_json(path: str, default=None):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def run_key(run_dir: str, root: str) -> str:
    return "%s-%s" % (os.path.basename(run_dir.rstrip("/")),
                      hashlib.sha1(root.encode("utf-8")).hexdigest()[:8])


def new_run_state(key: str, entry: dict, now: float) -> dict:
    from . import studio  # origin_task lives with the registry reader
    origin = entry.get("origin")
    task = studio.origin_task(origin)
    return {
        "key": key, "pid": entry["pid"], "started": entry.get("started"), "origin": origin,
        "root": entry["root"], "run_dir": entry["run"], "adopted_at": now,
        "request": {"state": "pending" if task else "none", "task": task, "issue": None, "since": now},
        "run_issue": None, "mode": None,
        "stories": {}, "story_desc": {}, "story_failed": [], "story_recreated": [],
        "offset": 0, "pending": None,
        "intended": {}, "last_set": {}, "hands_off": [], "held_back": {},
        "repair_stopped": [],
        "released": {},  # ident -> server time it left hands-off (R43)
        "catchup": {},  # ident -> {"changes": [...], "units": n, "run_ended": str ("" when none)}
        "cursors": {}, "cursor_ts": {}, "seen": {},
        "posted": [], "clock_offset": 0.0, "journal": {}, "delayed_for": None, "log_id": None,
        "ended": False, "gone_polls": 0, "poll_fails": 0, "retire_after_catchup": False, "retired": False,
    }


def _state_file(paths: Paths, key: str) -> str:
    return os.path.join(paths.state_dir, key + ".json")


def load_run(paths: Paths, key: str):
    return read_json(_state_file(paths, key), None)


def save_run(paths: Paths, st: dict) -> None:
    _mkdirs(paths.base, paths.state_dir)
    atomic_write_json(_state_file(paths, st["key"]), st)


def tracked_keys(paths: Paths) -> list:
    try:
        names = sorted(os.listdir(paths.state_dir))
    except OSError:
        return []
    return [n[:-5] for n in names if n.endswith(".json") and not n.startswith(".")]


def load_retired(paths: Paths) -> set:
    try:
        with open(paths.retired_file, encoding="utf-8") as f:
            return {line.strip() for line in f if line.strip()}
    except OSError:
        return set()


def retire(paths: Paths, st: dict) -> None:
    """R41: append the key to `retired`, move the state file to state/retired/."""
    key = st["key"]
    if key not in load_retired(paths):
        _mkdirs(paths.base)
        with open(paths.retired_file, "a", encoding="utf-8") as f:
            f.write(key + "\n")
            f.flush()
            os.fsync(f.fileno())
    _mkdirs(paths.base, paths.state_dir, paths.retired_dir)
    # The retired copy carries the caller's in-memory state, then the live file goes.
    atomic_write_json(os.path.join(paths.retired_dir, key + ".json"), dict(st, retired=True))
    with contextlib.suppress(FileNotFoundError):
        os.remove(_state_file(paths, key))
    _fsync_dir(paths.state_dir)


@contextlib.contextmanager
def bridge_lock(paths: Paths, blocking: bool):
    _mkdirs(paths.base)
    fd = os.open(paths.lock, os.O_RDWR | os.O_CREAT, 0o600)
    try:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | (0 if blocking else fcntl.LOCK_NB))
        except (BlockingIOError, PermissionError):
            raise LockBusy(paths.lock)
        try:
            yield
        finally:
            fcntl.flock(fd, fcntl.LOCK_UN)
    finally:
        os.close(fd)
