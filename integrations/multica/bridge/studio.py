"""The studio side of the bridge: registry, liveness, links, events.jsonl reader, verb calls (#28).

Reads only the core's public files (docs/game-dev/overnight-events.md) and calls its public verbs.
"""
from __future__ import annotations

import json
import logging
import os
import re
import signal
import subprocess

from .state import parse_ts

VERB_TIMEOUT = 30
KNOWN_EVENTS = frozenset({"run_started", "story_listed", "story_state", "unit_started", "unit_ended",
                          "story_synced", "session_wait", "message_queued", "message_delivered",
                          "message_requeued", "control", "run_ended"})
_log = logging.getLogger("bridge.studio")
_TASK = re.compile(r"^[A-Za-z0-9-]+$")
_WORKDIR = re.compile(r"^([a-z0-9]+-\d+)-[0-9a-f]{12}$", re.I)


class LogShrunk(Exception):
    pass


def _kv(path: str) -> dict:
    """First value per key of a `key=value` file; {} when unreadable."""
    out = {}
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f.read().split("\n"):
                k, eq, v = line.partition("=")
                if eq and k and k not in out:
                    out[k] = v
    except OSError:
        pass
    return out


def read_registry(home: str) -> list:
    """Each `overnight-*` entry (never `last`); `origin` is the raw value or None (R55)."""
    reg = os.path.join(home, ".claude-gamedev", "runs")
    try:
        names = sorted(n for n in os.listdir(reg) if n.startswith("overnight-"))
    except OSError:
        return []
    rows = []
    for n in names:
        path = os.path.join(reg, n)
        if not os.path.isfile(path):
            continue
        kv = _kv(path)
        pid = kv.get("pid", "")
        if not kv.get("root") or not kv.get("run") or not re.match(r"^\d+$", pid):
            _log.debug("registry entry %s skipped: missing root, run or pid", n)
            continue
        rows.append({"file": path, "root": kv["root"], "start": kv.get("start", ""), "run": kv["run"],
                     "pid": int(pid), "started": kv.get("started", ""), "origin": kv.get("origin")})
    return rows


def origin_task(origin):
    if not origin or not origin.startswith("multica:"):
        return None
    task = origin[len("multica:"):]
    return task if _TASK.match(task) else None


def runner_live(pid) -> bool:
    """The core's reg_live: the pid is alive and `ps` shows studio-overnight."""
    try:
        pid = int(pid)
        if pid <= 0:
            return False
        os.kill(pid, 0)
    except (OSError, ValueError, TypeError, OverflowError):  # includes PermissionError: alive, not ours
        return False
    try:
        r = subprocess.run(["ps", "-o", "args=", "-p", str(pid)], stdin=subprocess.DEVNULL,
                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=10)
    except (OSError, subprocess.TimeoutExpired):
        return False
    return b"studio-overnight" in r.stdout


def _link_path(paths, task_id: str) -> str:
    return os.path.join(paths.links, task_id)


def read_link(paths, task_id: str):
    if not task_id or "/" in task_id or task_id.startswith("."):
        return None
    kv = _kv(_link_path(paths, task_id))
    return kv if kv.get("task") else None


def delete_link(paths, task_id: str) -> None:
    if not task_id or "/" in task_id or task_id.startswith("."):
        return
    try:
        os.remove(_link_path(paths, task_id))
    except OSError:
        pass


def prune_links(paths, now: float) -> None:
    try:
        names = os.listdir(paths.links)
    except OSError:
        return
    for n in names:
        p = os.path.join(paths.links, n)
        try:
            written = _kv(p).get("written")
            try:
                t = parse_ts(written) if written else os.path.getmtime(p)
            except ValueError:
                t = os.path.getmtime(p)
            if now - t > 24 * 3600:
                os.remove(p)
        except OSError:
            continue


def issue_from_workdir(workdir: str):
    m = _WORKDIR.match(os.path.basename(os.path.dirname(workdir.rstrip("/"))))
    return m.group(1).upper() if m else None


def log_ident(path: str) -> list:
    """[st_dev, st_ino] of the log: the identity a saved offset belongs to."""
    st = os.stat(path)
    return [st.st_dev, st.st_ino]


def read_lines(path: str, offset: int, ident=None) -> list:
    """Complete lines from byte `offset`: (start, end, line without the newline).

    Raises LogShrunk when the file is smaller than `offset`, or, when `ident` (from
    `log_ident`) is given, when the file is no longer the one the offset was saved for.
    """
    with open(path, "rb") as f:
        fst = os.fstat(f.fileno())
        size = fst.st_size
        if size < offset:
            raise LogShrunk("%s: size %d is below offset %d" % (path, size, offset))
        if ident is not None and list(ident) != [fst.st_dev, fst.st_ino]:
            raise LogShrunk("%s: replaced (identity changed)" % path)
        f.seek(offset)
        data = f.read()
    out = []
    pos = 0
    while True:
        nl = data.find(b"\n", pos)
        if nl < 0:
            break
        out.append((offset + pos, offset + nl + 1, data[pos:nl]))
        pos = nl + 1
    return out


def unread_count(path: str, offset: int, ident=None) -> int:
    return len(read_lines(path, offset, ident))


def parse_event(line: bytes):
    try:
        obj = json.loads(line.decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        return ("bad", None)
    if not isinstance(obj, dict):
        return ("bad", None)
    v = obj.get("v")
    if isinstance(v, int) and not isinstance(v, bool) and v > 1:
        return ("version", obj)
    if obj.get("event") not in KNOWN_EVENTS:
        return ("unknown", obj)
    return ("ok", obj)


def call_verb(path, root, args, timeout=None):
    env = {k: v for k, v in os.environ.items() if not k.startswith("MULTICA_")}
    try:
        p = subprocess.Popen([path] + list(args), cwd=root, env=env, stdin=subprocess.DEVNULL,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
    except OSError as e:  # missing or non-executable binary, vanished root
        return (127, "", "cannot run studio-overnight: %s" % e, False)
    try:
        out, err = p.communicate(timeout=timeout if timeout is not None else VERB_TIMEOUT)
        timed_out = False
    except subprocess.TimeoutExpired:
        try:
            os.killpg(p.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        out, err = p.communicate()
        timed_out = True
    return (p.returncode, out.decode("utf-8", "replace"), err.decode("utf-8", "replace"), timed_out)
