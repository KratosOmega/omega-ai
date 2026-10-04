"""Comment commands on Multica issues → core verbs (#28, AC20–AC25)."""
from __future__ import annotations

import os
import re

from bridge import mirror, state, studio
from bridge import multica_cli as mc

STALE_SECONDS = 600
REPLY_CUT = 1000
OVERLAP_SECONDS = 60
REPOST_SLACK = 5            # D5: seconds of clock slack when matching a reply already on the board
COMMANDS = ("say", "unit", "hold", "resume", "stop", "unsay", "said")
WARN = "studio: ⚠ may or may not have applied — check `/said` or the board"
HELP = ("studio: commands — on a story issue: /say <text>, /unit <text>, /hold, /resume, /stop, "
        "/unsay <id>, /said; on the Run issue: /stop run (a single-plan run takes every command there)")
_WORD = re.compile(r"(\S*)(.*)", re.S)


def parse(content):
    lines = content.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    for i, line in enumerate(lines):
        if line.strip():
            first = line.lstrip()
            break
    else:
        return None, None
    if not first.startswith("/"):
        return None, None
    word, tail = _WORD.match(first[1:]).groups()
    return word.lower(), "\n".join([tail] + lines[i + 1:]).strip()


def _lev(a, b):
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1]


def near_miss(word):
    return bool(word) and word not in COMMANDS and any(_lev(word, c) <= 2 for c in COMMANDS)


def plan_call(word, text, where, story, single, basename):
    tok = text.split()[0] if text.split() else ""
    run_cmd = word == "stop" and tok.lower() == "run"
    if where == "story" or single:
        s = story if where == "story" else "-"
        if run_cmd:
            if where == "story":
                return "reply", "studio: ✗ /stop run works on the Run issue; /stop here stops this story"
            return "call", ["stop", "--run", basename]
        if word in ("say", "unit"):
            if not text:
                return "reply", "studio: ✗ usage: /%s <text>" % word
            return "call", ["say", "--run", basename, s] + (["--unit"] if word == "unit" else []) + ["--", text]
        if word in ("hold", "resume", "stop", "said"):
            return "call", [word, "--run", basename, s]
        if word == "unsay":
            if not re.fullmatch(r"[0-9]+", tok):
                return "reply", "studio: ✗ usage: /unsay <id> — the id is the number /said lists"
            return "call", ["unsay", "--run", basename, s, tok]
    else:
        if run_cmd:
            return "call", ["stop", "--run", basename]
        if word == "stop":
            return "reply", "studio: ✗ on the Run issue use /stop run; /stop on a story issue stops that story"
        if word in COMMANDS:
            return "reply", "studio: ✗ /%s goes on the story's own issue" % word
    if near_miss(word):
        return "reply", HELP
    return "ignore", None


def format_reply(code, out, err, timed_out):
    ok = code == 0 and not timed_out
    body = mc.sanitize((out if ok else err).strip())     # sanitize THEN cut: a prefix cannot form a mention
    if timed_out:
        body = (body + "\n" if body else "") + "timed out after %d s" % studio.VERB_TIMEOUT
    if not body:
        body = "done" if ok else "exit %d" % code
    if len(body) > REPLY_CUT:
        body = body[:REPLY_CUT] + "…"
    return ("studio: ✓ " if ok else "studio: ✗ ") + body


def poll_commands(ctx, st):
    recover_journal(ctx, st)
    base = os.path.basename(st["run_dir"])
    targets = [(st["run_issue"], "run", None)] + [(i, "story", s) for s, i in st["stories"].items()]
    for ident, where, story in targets:
        row = ctx.rows.get(ident)
        if where == "run" and st["mode"] is None:
            continue                                      # single or manifest is not known yet: read it later
        if row is not None:
            _poll_issue(ctx, st, ident, row, where, story, base)


def _ts(c, default):
    try:
        return state.parse_ts(c["created_at"])
    except (KeyError, TypeError, ValueError):
        return default


def _poll_issue(ctx, st, ident, row, where, story, base):
    created = state.parse_ts(row["created_at"])
    since = st["cursors"].get(ident) or state.fmt_since(created)
    newest = st["cursor_ts"].get(ident, created)
    seen = st["seen"].setdefault(ident, {})
    released = st.get("released", {}).get(ident, 0)       # R43: server time the issue left hands-off
    for c in sorted(ctx.cli.list_comments(ident, since), key=lambda c: _ts(c, newest)):
        cid = c.get("id")
        if not cid or cid in seen:                        # --since is inclusive: dedupe by id
            continue
        ts = _ts(c, newest)
        seen[cid], newest = ts, max(newest, ts)
        if ident in st["hands_off"] or ts < released or cid in st["journal"] or not _actionable(ctx, st, c):
            continue                                      # R43: read, never acted on
        word, text = parse(c.get("content") or "")
        if word is None:
            continue
        kind, val = plan_call(word, text, where, story, st["mode"] == "single", base)
        if kind == "ignore":
            continue
        if ctx.now() + st["clock_offset"] - ts > STALE_SECONDS:    # AC24, server clock
            kind, val = "reply", "studio: ✗ too old, repost"
        _run(ctx, st, ident, c, kind, val)
    st["cursor_ts"][ident] = newest
    st["cursors"][ident] = state.fmt_since(newest - OVERLAP_SECONDS)
    st["seen"][ident] = {k: v for k, v in seen.items() if v >= newest - 2 * OVERLAP_SECONDS}


def _actionable(ctx, st, c):
    return (c.get("author_type") == "member" and c.get("author_id") == ctx.cfg.operator_member_id
            and c.get("id") not in st["posted"] and not (c.get("content") or "").startswith(mc.PREFIX))


def _run(ctx, st, ident, c, kind, val):
    cid = c["id"]
    entry = {"issue": ident, "parent": c.get("parent_id") or cid, "at": ctx.now(),
             "created_at": c.get("created_at"), "attempts": 0}
    if kind == "call":
        st["journal"][cid] = dict(entry, state="running")
        state.save_run(ctx.paths, st)                     # AC23.1: before the core runs
        try:
            code, out, err, timed_out = studio.call_verb(ctx.cfg.studio_overnight, st["root"], val)
            reply = format_reply(code, out, err, timed_out)
        except (OSError, ValueError) as e:                # the core never started: certainly not applied
            reply = format_reply(1, "", "cannot run studio-overnight: %s" % e, False)
    else:
        reply = val
    st["journal"][cid] = dict(entry, state="result", reply=reply)
    state.save_run(ctx.paths, st)                         # AC23.2
    _post(ctx, st, cid)


def _post(ctx, st, cid):
    e = st["journal"][cid]
    if e["issue"] in st["hands_off"]:
        return                                            # kept for later: no attempt, no list call
    if e["attempts"] and _already_posted(ctx, st, e):     # R25
        e["state"] = "done"
        state.save_run(ctx.paths, st)
        return
    if "first_try" not in e:                              # D5: recorded before the first post
        e["first_try"] = ctx.now()
    e["attempts"] += 1
    state.save_run(ctx.paths, st)
    try:
        posted = mirror.post_comment(ctx, st, e["issue"], e["reply"], parent=e["parent"], count_held=False)
    except mc.PermanentError as err:
        ctx.log.error("run %s: reply to %s not posted: %s", st["key"], cid, err)
        if e["attempts"] >= mirror.PERMANENT_ATTEMPTS:
            e["state"] = "done"
        state.save_run(ctx.paths, st)
        return
    if posted is None:                                    # hands-off now, kept for later: not an attempt
        e["attempts"] -= 1
    else:
        e["state"] = "done"
    state.save_run(ctx.paths, st)


def _already_posted(ctx, st, e):
    # D5: only a reply stamped at or after the first try counts; an older identical reply
    # (R11 id reuse, two /hold) must not hide a missing one.
    first = e.get("first_try")
    if first is None:
        first = e["at"]
    floor = first + st["clock_offset"] - REPOST_SLACK
    want = ctx.cli.clean(e["reply"])           # exactly what the post sent: redacted, then sanitized
    for c in ctx.cli.list_comments(e["issue"], state.fmt_since(floor)):
        if c.get("id") in st["posted"]:
            continue                                      # a post seen to succeed is never the unconfirmed one
        if c.get("parent_id") == e["parent"] and c.get("content") == want and _ts(c, floor) >= floor:
            return True
    return False


def recover_journal(ctx, st):
    for cid, e in list(st["journal"].items()):
        if e["state"] == "running":                       # AC23.4: never run again
            e.update(state="result", reply=WARN)
            state.save_run(ctx.paths, st)
        if e["state"] == "result":                        # AC23.3: re-post, never re-run
            _post(ctx, st, cid)
    cutoff = ctx.now() - 86400
    st["journal"] = {k: v for k, v in st["journal"].items() if v["state"] != "done" or v["at"] >= cutoff}


def flush_replies(ctx, st):
    """At retirement: post any reply still waiting. Transient errors propagate, so retirement is retried;
    a reply on a hands-off issue cannot be posted and is dropped with a log line."""
    for cid, e in list(st["journal"].items()):
        if e["state"] == "result":
            _post(ctx, st, cid)
            if e["state"] == "result":
                ctx.log.warning("run %s: reply to %s not posted before retirement: %s", st["key"], cid, e["reply"])
