"""Mirror live overnight runs into Multica: Run and story issues, events as statuses and comments (#28).

Part 1: adoption, the request issue, the Run and story issues, event mapping. The bridge writes
only issues it created (the Run and story issues) and never the request issue.
"""
from __future__ import annotations

import os
import traceback

from . import multica_cli as mc
from . import state, studio

STATUS = {"queued": "todo", "waiting": "todo", "running": "in_progress", "repair": "in_progress",
          "gate-repair": "in_progress", "sync-repair": "in_progress", "landing": "in_progress", "held": "blocked",
          "landed": "done", "stopped": "cancelled", "skipped": "cancelled"}
TERMINAL_STATUS = ("done", "cancelled")
TERMINAL_CATEGORIES = ("done", "cancelled", "closed")          # R14: with TERMINAL_STATUS, what counts as closed
REQUEST_LIMIT_SECONDS = 300
PERMANENT_ATTEMPTS = 3
GONE_POLLS = 3
POSTED_KEEP = 500
LOG_GONE = "studio: event log replaced or removed — mirroring stopped"


def cost(usd) -> str:
    try:
        return "$%.2f" % float(usd)
    except (TypeError, ValueError):
        return "cost unknown"


def event_writes(st, ev):
    """The writes one event asks for, in order, as (kind, target, value):
    kind "status" (value: status key), "comment" (value: the full text) or
    "story" (value: the story issue's description). target is "run" or a
    story id. Pure: reads st, writes nothing."""
    e, s = ev.get("event"), str(ev.get("story", "-"))
    single = st.get("mode") == "single" or s == "-"
    routed = s in st["story_failed"] and not st["stories"].get(s)   # AC12: its issue could not be made
    tgt = "run" if (single or routed) else s
    pre = "studio: [%s] " % s if routed else "studio: "

    def say(text):
        return ("comment", tgt, pre + text)

    if e == "run_started":
        return [("status", "run", "in_progress"), ("comment", "run", "studio: run started (%s)" % ev.get("mode", "?"))]
    if e == "story_listed":
        if single:
            return []
        deps = ev.get("depends") or []
        chain = ev.get("chain")
        chain = ", ".join(map(str, chain)) if isinstance(chain, list) else ("-" if chain is None else str(chain))
        return [("story", s, "Story %s of run %s. Chain: %s. Depends on: %s." % (
            s, os.path.basename(st["run_dir"]), chain, ", ".join(map(str, deps)) or "none"))]
    if e == "story_state":
        out, state_ = [], ev.get("state")
        status = STATUS.get(state_)
        if status and not routed and not (tgt == "run" and status in TERMINAL_STATUS):
            out.append(("status", tgt, status))
        if state_ == "held":
            out.append(say("held: %s — until %s — /say, /resume or /stop" % (ev.get("why", "?"), ev.get("until", "?"))))
        elif state_ in ("stopped", "skipped"):
            out.append(say("%s: %s" % (state_, ev.get("why", "?"))))
        return out
    if e == "story_synced":
        if ev.get("refs"):
            return [say("synced %s (%s)" % (", ".join(map(str, ev.get("refs") or [])), str(ev.get("sha", "?"))[:7]))]
        if ev.get("skipped"):
            return [say("sync skipped: %s" % ev.get("skipped"))]
        return [say("sync failed: %s" % ev.get("failed", "?"))]
    if e == "unit_started":
        return [say("unit %s (%s) started" % (ev.get("unit"), ev.get("label")))]
    if e == "unit_ended":
        return [say("unit %s (%s) ended: %s, %s" % (ev.get("unit"), ev.get("label"), ev.get("outcome"), cost(ev.get("usd"))))]
    if e == "message_queued":
        return [say("message %s queued (%s)" % (ev.get("id"), ev.get("scope")))]
    if e == "message_delivered":
        return [say("message %s delivered to unit %s" % (ev.get("id"), ev.get("unit")))]
    if e == "message_requeued":
        return [say("message %s not recorded by unit %s; requeued (%s)" % (ev.get("id"), ev.get("unit"), ev.get("requeues")))]
    if e == "control":
        return [say("%s by operator" % ev.get("action"))]
    if e == "run_ended":   # comment first: closing wakes the agent, which reads it (R17)
        return [("comment", "run", "studio: run ended: %s — report: %s" % (ev.get("ending"), ev.get("report"))),
                ("status", "run", "done")]
    return []   # includes session_wait: not mirrored; the unit's own unit_started follows


# ----- adoption --------------------------------------------------------------

def _same_root(a: str, b: str) -> bool:
    return os.path.realpath(a) == os.path.realpath(b)


def adopt(ctx) -> list:
    """AC8: start tracking each live registry run that is in scope and not seen before."""
    tracked, retired = set(state.tracked_keys(ctx.paths)), state.load_retired(ctx.paths)
    new = []
    for entry in studio.read_registry(ctx.paths.home):
        key = state.run_key(entry["run"], entry["root"])
        if key in tracked or key in retired or key in new:
            continue
        if ctx.cfg.roots and not any(_same_root(entry["root"], r) for r in ctx.cfg.roots):
            continue
        if not studio.runner_live(entry["pid"]):
            continue
        state.save_run(ctx.paths, state.new_run_state(key, entry, ctx.now()))
        new.append(key)
        ctx.log.info("adopted run %s", key)
    return new


def _confirm(ctx, ident, task):
    try:
        return ident if any(r.get("id") == task for r in ctx.cli.issue_runs(ident)) else None
    except mc.PermanentError:          # includes NotFoundError: an unconfirmed candidate
        return None


def resolve_request(ctx, st):
    """AC9, R21, R22: find the issue whose agent task started this run (None: top-level Run issue)."""
    rq = st["request"]
    if rq["state"] != "pending":
        return
    link = studio.read_link(ctx.paths, rq["task"])
    agent = (link or {}).get("agent")
    tried = set()
    try:
        found = None
        first = studio.issue_from_workdir((link or {}).get("workdir", ""))
        if first:
            tried.add(first)
            found = _confirm(ctx, first, rq["task"])
        if not found and agent:
            for row in ctx.cli.assigned_issues(agent):
                ident = row.get("identifier")
                if ident and ident not in tried:
                    tried.add(ident)
                    found = _confirm(ctx, ident, rq["task"])
                    if found:
                        break
    except (mc.TransientError, mc.PermanentError) as e:     # a failed search is retried, then falls back
        ctx.log.warning("run %s: request issue search failed: %s", st["key"], e)
        if ctx.now() - rq["since"] > REQUEST_LIMIT_SECONDS:
            ctx.log.warning("run %s: request issue unresolved after 5 min; Run issue goes top level", st["key"])
            rq["state"] = "none"
        return
    rq["state"], rq["issue"] = ("found", found) if found else ("none", None)
    if link:
        state.save_run(ctx.paths, st)          # the resolution is durable before its link goes
        studio.delete_link(ctx.paths, rq["task"])


# ----- the Run issue and story issues ---------------------------------------

def retire(ctx, st):
    from bridge import commands         # imported here: commands imports mirror
    commands.flush_replies(ctx, st)     # a reply still waiting is posted before the run goes
    state.retire(ctx.paths, st)
    st["retired"] = True


def ensure_run_issue(ctx, st) -> bool:
    """AC10: the run's Run issue exists (reused by property, else created). False: gave up and retired."""
    if st.get("run_issue"):
        return True
    key, base = st["key"], os.path.basename(st["run_dir"].rstrip("/"))
    found = ctx.cli.find_issues(key, None)
    if found:
        ident, status = found[0]["identifier"], found[0].get("status") or "todo"
    else:
        parent = st["request"].get("issue")
        desc = "Overnight run %s.\nRun dir: %s\nProject: %s\nKey: %s\nComment /stop run to stop it." % (
            base, st["run_dir"], st["root"], key)
        row = None
        try:
            row = ctx.cli.create_issue("Run " + base, desc, parent, {"omega_run": key})
        except mc.PermanentError as e:
            ctx.log.error("run %s: Run issue create failed%s: %s", key, " under the request issue" if parent else "", e)
            if parent:
                try:
                    row = ctx.cli.create_issue("Run " + base, desc, None, {"omega_run": key})
                except mc.PermanentError as e2:
                    ctx.log.error("run %s: Run issue create failed at top level: %s", key, e2)
        if row is None:
            ctx.notify("create", "omega bridge: could not create the Run issue for " + base)
            retire(ctx, st)
            return False
        ident, status = row["identifier"], "todo"
    st["run_issue"] = ident
    st["intended"][ident] = st["last_set"][ident] = status
    state.save_run(ctx.paths, st)
    return True


def ensure_story_issue(ctx, st, story, description):
    """AC12: the story's issue exists (reused by property, else created); a failed create routes its events to the Run issue."""
    st["story_desc"][story] = description
    if st["stories"].get(story):
        return
    key = st["key"]
    found = ctx.cli.find_issues(key, story)
    if found:
        st["stories"][story] = found[0]["identifier"]
        _seed(st, found[0]["identifier"], found[0].get("status") or "todo")
        return
    try:
        row = ctx.cli.create_issue(story, description, st["run_issue"], {"omega_run": key, "omega_story": story})
    except mc.PermanentError as e:
        if story not in st["story_failed"]:
            st["story_failed"].append(story)
        note(ctx, st, "studio: [%s] its issue could not be created (%s); its events go here" % (story, e))
        return
    st["stories"][story] = row["identifier"]
    _seed(st, row["identifier"], "todo")
    if story in st["story_failed"]:
        st["story_failed"].remove(story)           # it has an issue now: its events go there


def _seed(st, ident, status):
    """A story issue starts with the status it has: its first `queued` needs no write."""
    st["intended"].setdefault(ident, status)
    st["last_set"].setdefault(ident, status)


# ----- writes ---------------------------------------------------------------

def post_comment(ctx, st, ident, text, parent=None, count_held=True):
    """Post one comment; the clock offset is learned from the server's stamp (AC24).

    None when the issue is hands-off: nothing is posted (AC14.1) and, with count_held, the
    comment is counted for the catch-up (R40)."""
    if hands_off_now(ctx, st, ident):
        if count_held:
            cu = _catchup(st, ident)
            if text.startswith(("studio: run ended:", "studio: runner gone")):
                cu["run_ended"] = text
            else:
                cu["units"] += 1
        return None
    t0 = ctx.now()
    c = ctx.cli.add_comment(ident, text, parent)
    st["posted"] = (st["posted"] + [c["id"]])[-POSTED_KEEP:]
    try:
        st["clock_offset"] = state.parse_ts(c["created_at"]) - t0
    except (KeyError, ValueError, TypeError):
        pass
    return c


def note(ctx, st, text):
    """A comment on the Run issue; with no Run issue, or when it cannot be written, only the log (AC27)."""
    ident = st.get("run_issue")
    if not ident:
        ctx.log.warning("run %s: %s", st["key"], text)
        return
    try:
        post_comment(ctx, st, ident, text)
    except (mc.PermanentError, mc.ForbiddenWrite) as e:
        ctx.log.error("run %s: note not posted (%s): %s", st["key"], e, text)


def is_hands_off(row) -> bool:
    return row.get("assignee_type") in ("agent", "squad")


def is_terminal(row) -> bool:
    return row.get("status") in TERMINAL_STATUS or row.get("status_category") in TERMINAL_CATEGORIES


def _catchup(st, ident):
    """The record of what happened while ident was hands-off; `from` is its status at hand-off."""
    cu = st["catchup"].get(ident)
    if cu is not None and cu.get("leaving"):      # handed off again mid catch-up: keep what is still owed
        cu.pop("leaving")
        cu.pop("line_posted", None)
        cu.pop("fails", None)
        return cu
    if cu is None:
        cu = st["catchup"][ident] = {"changes": [], "units": 0, "run_ended": "",
                                     "from": st["last_set"].get(ident) or st["intended"].get(ident)}
    return cu


def _enter_hands_off(st, ident):
    if ident not in st["hands_off"]:
        st["hands_off"].append(ident)
    _catchup(st, ident)


def _held_change(st, ident, status):
    cu = _catchup(st, ident)
    if status != (cu["changes"][-1] if cu["changes"] else cu.get("from")):
        cu["changes"].append(status)


def hands_off_now(ctx, st, ident) -> bool:
    """AC14.1: re-read the assignee just before a write."""
    if ident in st["hands_off"]:
        return True
    row = ctx.cli.get_issue(ident)
    ctx.rows[ident] = row
    if is_hands_off(row):
        _enter_hands_off(st, ident)
        return True
    return False


def stop_repair(ctx, st, ident, why):
    st["repair_stopped"].append(ident)
    note(ctx, st, "studio: %s — the bridge leaves its status alone from now on" % why)
    state.save_run(ctx.paths, st)       # the note is not idempotent: a later transient must not repeat it


def write_status(ctx, st, ident):
    """R15: set the intended status unless someone else owns the issue or its status."""
    intended = st["intended"].get(ident)
    if intended is None or ident in st["repair_stopped"]:
        return
    if ident in st["hands_off"]:
        _held_change(st, ident, intended)
        return
    if _row_rules(ctx, st, ident, intended):
        return
    if (intended in TERMINAL_STATUS and ident != st["run_issue"]
            and st["run_issue"] in st["hands_off"]):
        st["held_back"][ident] = intended                     # AC14.2
        return
    if hands_off_now(ctx, st, ident):                         # AC14.1 re-read
        _held_change(st, ident, intended)
        return
    if _row_rules(ctx, st, ident, intended):                  # the re-read row is the freshest: check it again
        return
    ctx.cli.set_status(ident, intended)
    st["last_set"][ident] = intended
    row = ctx.rows.get(ident)
    if row is not None:
        row["status"] = row["status_category"] = intended


def _row_rules(ctx, st, ident, intended) -> bool:
    """AC14.4: True when the row says nothing is left to write (applied, or someone else's to keep)."""
    row = ctx.rows.get(ident)
    if row is None:
        return st["last_set"].get(ident) == intended          # already applied; the next refresh checks the row
    if row.get("status") == intended:
        st["last_set"][ident] = intended                      # AC14.4: applied, even after a timeout
        return True
    if is_terminal(row) and row.get("status") != st["last_set"].get(ident):
        stop_repair(ctx, st, ident, "%s was set to %s by someone else" % (ident, row.get("status")))
        return True
    if intended in TERMINAL_STATUS and st["last_set"].get(ident) == intended:
        stop_repair(ctx, st, ident, "%s was reopened by someone else" % ident)
        return True
    return False


def set_intended(ctx, st, ident, status):
    st["intended"][ident] = status
    state.save_run(ctx.paths, st)       # persisted before the write: a timed-out write must not be "repaired" back
    write_status(ctx, st, ident)


def _write(ctx, st, kind, ident, value):
    if kind == "status":
        set_intended(ctx, st, ident, value)
    else:
        post_comment(ctx, st, ident, value)


def _to_run_issue(ctx, st, tgt, kind, value):
    """A story with no issue: its comments go to the Run issue with a prefix; its status changes are dropped."""
    if kind == "comment":
        post_comment(ctx, st, st["run_issue"], "studio: [%s] %s" % (tgt, value[len(mc.PREFIX):]))


def _do_write(ctx, st, w):
    kind, tgt, value = w
    if kind == "story":
        ensure_story_issue(ctx, st, tgt, value)
        return
    if tgt == "run":
        _write(ctx, st, kind, st["run_issue"], value)
        return
    ident = st["stories"].get(tgt)
    if not ident:
        _to_run_issue(ctx, st, tgt, kind, value)
        return
    try:
        _write(ctx, st, kind, ident, value)
    except mc.NotFoundError:
        st["intended"].pop(ident, None)               # gone: its status is not reconciled again
        st["last_set"].pop(ident, None)
        if tgt in st["story_recreated"]:
            # lost a second time: stop recreating; its events go to the Run issue (AC12), not a 3-poll stall each
            st["stories"].pop(tgt, None)
            if tgt not in st["story_failed"]:
                st["story_failed"].append(tgt)
            note(ctx, st, "studio: [%s] its issue was lost again; its events go here" % tgt)
            _to_run_issue(ctx, st, tgt, kind, value)
            return
        st["story_recreated"].append(tgt)
        st["stories"].pop(tgt, None)
        ensure_story_issue(ctx, st, tgt, st["story_desc"].get(tgt, ""))
        ident = st["stories"].get(tgt)
        if ident:
            _write(ctx, st, kind, ident, value)
        else:
            _to_run_issue(ctx, st, tgt, kind, value)


# ----- events ---------------------------------------------------------------

def _events_path(st):
    return os.path.join(st["run_dir"], "events.jsonl")


def _log_ident(st):
    """The identity the saved offset belongs to: recorded at the first read, then checked on every read."""
    if st.get("log_id") is None:
        st["log_id"] = studio.log_ident(_events_path(st))
    return st["log_id"]


def _run_ended_unread(st) -> bool:
    try:
        lines = studio.read_lines(_events_path(st), st["offset"], _log_ident(st))
    except (OSError, studio.LogShrunk):
        return False
    for _, _, raw in lines:
        if b"run_ended" in raw:
            ev = studio.parse_event(raw)[1]
            if ev and ev.get("event") == "run_ended":
                return True
    return False


def apply_events(ctx, st):
    try:
        lines = studio.read_lines(_events_path(st), st["offset"], _log_ident(st))
    except FileNotFoundError:
        if not os.path.isdir(st["run_dir"]):
            note(ctx, st, LOG_GONE)
            retire(ctx, st)
        return
    except studio.LogShrunk:
        note(ctx, st, LOG_GONE)
        retire(ctx, st)
        return
    for start, end, raw in lines:
        kind, ev = studio.parse_event(raw)
        if kind == "version":
            note(ctx, st, "studio: event log version %s is newer than this bridge reads (1) — mirroring stopped" % ev.get("v"))
            retire(ctx, st)
            return
        if kind in ("bad", "unknown"):
            ctx.log.warning("run %s: skipped %s event line at byte %d", st["key"], kind, start)
        else:
            if ev["event"] == "run_started":
                st["mode"] = "single" if ev.get("mode") == "single" else "manifest"
            if ev["event"] == "story_state" and ev.get("state") not in STATUS:
                ctx.log.warning("run %s: unknown story state %r left the status unchanged", st["key"], ev.get("state"))
            if not _apply_one(ctx, st, start, ev):
                return                                    # retried on the next poll
            if ev["event"] == "run_ended":
                st["ended"] = True
        st["offset"], st["pending"] = end, None
        state.save_run(ctx.paths, st)


def _apply_one(ctx, st, offset, ev):
    """True when the event is finished (all writes done, or skipped)."""
    p = st["pending"]
    if not p or p["offset"] != offset:
        p = st["pending"] = {"offset": offset, "done": [], "fails": 0, "error": "",
                             "writes": [list(w) for w in event_writes(st, ev)]}   # fixed once: done[] indexes this list
    try:
        for i, w in enumerate(p["writes"]):
            if i in p["done"]:
                continue
            _do_write(ctx, st, w)                         # TransientError propagates
            p["done"].append(i)
            state.save_run(ctx.paths, st)
        return True
    except mc.PermanentError as e:
        p["fails"] += 1
        p["error"] = str(e)
        state.save_run(ctx.paths, st)
        if p["fails"] < PERMANENT_ATTEMPTS:
            return False
        ctx.log.error("run %s: skipped %s after %d failed polls: %s", st["key"], ev.get("event"), p["fails"], e)
        for i, w in enumerate(p["writes"]):               # M6: the comment is given up on, its status writes are not
            if w[0] == "status" and i not in p["done"]:
                try:
                    _do_write(ctx, st, w)                 # once, best effort; a TransientError retries the whole skip
                except (mc.PermanentError, mc.ForbiddenWrite) as e2:
                    ctx.log.error("run %s: status write of skipped %s failed: %s", st["key"], ev.get("event"), e2)
        note(ctx, st, "studio: skipped %s (story %s) after %d failed attempts: %s"
             % (ev.get("event"), ev.get("story", "-"), PERMANENT_ATTEMPTS, e))
        return True


# ----- refresh, reconcile, catch-up -----------------------------------------

def _mirrored(st):
    return ([st["run_issue"]] if st.get("run_issue") else []) + [i for i in st["stories"].values() if i]


def refresh(ctx, st):
    """AC14: one paged `issue list` per run per poll fills ctx.rows; hands-off transitions follow."""
    ctx.rows.update({r["identifier"]: r for r in ctx.cli.run_issues(st["key"]) if r.get("identifier")})
    for ident in _mirrored(st):
        row = ctx.rows.get(ident)
        if row is None:
            continue
        if is_hands_off(row):
            if ident not in st["hands_off"]:
                _enter_hands_off(st, ident)
        elif ident in st["hands_off"] or st["catchup"].get(ident, {}).get("leaving"):
            try:
                catch_up(ctx, st, ident)
            except (mc.PermanentError, mc.ForbiddenWrite) as e:      # one issue must not stop the others (AC27)
                ctx.log.error("run %s: catch-up of %s failed: %s", st["key"], ident, e)
            if st["retired"]:
                return


def reconcile(ctx, st):
    """R15: every intended status is applied (the rules skip stopped, hands-off and held-back ones)."""
    for ident in list(st["intended"]):
        try:
            write_status(ctx, st, ident)
        except mc.NotFoundError as e:                         # vanished: warn once; an event for its story recreates it
            st["intended"].pop(ident, None)
            st["last_set"].pop(ident, None)
            ctx.log.warning("run %s: status of %s not reconciled: %s", st["key"], ident, e)
        except (mc.PermanentError, mc.ForbiddenWrite) as e:
            ctx.log.warning("run %s: status of %s not reconciled: %s", st["key"], ident, e)


def _cu_post(ctx, st, ident, cu, text) -> bool:
    """One catch-up comment. True: posted, or given up on after PERMANENT_ATTEMPTS 4xx polls (AC27)."""
    try:
        c = post_comment(ctx, st, ident, text, count_held=False)
    except (mc.PermanentError, mc.ForbiddenWrite) as e:
        cu["fails"] = cu.get("fails", 0) + 1
        ctx.log.error("run %s: catch-up comment on %s not posted (%d): %s", st["key"], ident, cu["fails"], e)
        if cu["fails"] < PERMANENT_ATTEMPTS:
            state.save_run(ctx.paths, st)
            return False
        note(ctx, st, "studio: catch-up comment on %s skipped after %d failures" % (ident, cu["fails"]))
        c = True
    cu.pop("fails", None)
    return c is not None


def catch_up(ctx, st, ident):
    """R40: an issue left hands-off — the held end, one comment, the intended status, held-back closures.

    Each post is saved before the next step and the record stays until its posts are done, so a
    transient failure later in the poll resumes here instead of posting a second comment."""
    cu = st["catchup"].get(ident) or _catchup(st, ident)
    cu["leaving"] = True
    if ident in st["hands_off"]:
        st["hands_off"].remove(ident)
        st.setdefault("released", {})[ident] = ctx.now() + st["clock_offset"]   # R43: older comments never run
    state.save_run(ctx.paths, st)
    if cu["run_ended"] and not cu.get("end_posted"):
        if not _cu_post(ctx, st, ident, cu, cu["run_ended"]):
            return                                    # handed off again, or a 4xx to retry on the next poll
        cu["end_posted"] = True
        state.save_run(ctx.paths, st)
    if not cu.get("line_posted"):
        parts = ([cu["from"]] if cu.get("from") and cu["changes"] else []) + cu["changes"]
        changes = " → ".join(parts) if cu["changes"] else "no state changes"
        if not _cu_post(ctx, st, ident, cu, "studio: while assigned: %s, %d unit events" % (changes, cu["units"])):
            return
        cu["line_posted"] = True
        state.save_run(ctx.paths, st)
    st["catchup"].pop(ident, None)
    state.save_run(ctx.paths, st)
    write_status(ctx, st, ident)
    if ident == st.get("run_issue"):
        held, st["held_back"] = st["held_back"], {}
        for story_ident in held:
            write_status(ctx, st, story_ident)
        if st["retire_after_catchup"]:
            retire(ctx, st)


# ----- ending ---------------------------------------------------------------

def _held(st, ident) -> bool:
    return ident in st["hands_off"] or bool(st["catchup"].get(ident, {}).get("leaving"))


def check_end_or_gone(ctx, st):
    """AC15: a clean end retires the run; a dead runner with no end does after GONE_POLLS polls."""
    if st["ended"]:
        if _held(st, st["run_issue"]):
            st["retire_after_catchup"] = True         # R40: the catch-up comes first
            return
        retire(ctx, st)
        return
    if studio.runner_live(st["pid"]):
        st["gone_polls"] = 0
        return
    if _run_ended_unread(st):
        return                                        # AC15: the end is still in the log; keep draining to it
    st["gone_polls"] += 1
    if st["gone_polls"] >= GONE_POLLS:
        if st["retire_after_catchup"]:                # the note is held or posted: only the catch-up is left
            if not _held(st, st["run_issue"]):
                retire(ctx, st)
            return
        note(ctx, st, "studio: runner gone, no clean end — see `studio-overnight status`")
        if _held(st, st["run_issue"]):
            st["retire_after_catchup"] = True         # R40: the catch-up first, as for run_ended
            return
        retire(ctx, st)


# ----- the poll -------------------------------------------------------------

def poll_run(ctx, st):
    if st["request"].get("issue"):
        ctx.cli.forbidden.add(st["request"]["issue"])     # AC17: never written
    resolve_request(ctx, st)
    if st["request"].get("issue"):
        ctx.cli.forbidden.add(st["request"]["issue"])
    state.save_run(ctx.paths, st)       # a resolved request must survive a later transient (its link is gone)
    if st["request"]["state"] == "pending":
        return
    if not ensure_run_issue(ctx, st):
        return
    refresh(ctx, st)
    if st["retired"]:
        return
    reconcile(ctx, st)
    apply_events(ctx, st)
    if st["retired"]:
        return
    from bridge import commands         # imported here: commands imports mirror
    commands.poll_commands(ctx, st)
    check_end_or_gone(ctx, st)
    if not st["retired"]:
        state.save_run(ctx.paths, st)


def poll_runs(ctx):
    adopt(ctx)
    studio.prune_links(ctx.paths, ctx.now())
    for key in state.tracked_keys(ctx.paths):
        st = state.load_run(ctx.paths, key)
        if st is None:
            ctx.log.warning("run %s: state file unreadable; skipped", key)
            continue
        try:
            poll_run(ctx, st)
        except (mc.TransientError, mc.AuthError, mc.KeychainError):
            raise                       # the global backoff and auth handling need these; progress is already saved
        except Exception as e:          # PermanentError, a file-access block, a malformed row: one run must not starve the others
            _poll_failed(ctx, key, e)
        else:
            if st.get("poll_fails") and not st["retired"]:
                st["poll_fails"] = 0
                st.pop("poll_fail_noted", None)
                st.pop("poll_error", None)
                state.save_run(ctx.paths, st)


def _poll_failed(ctx, key, e):
    """One run's poll failed for good this time: a redacted log entry, a count, and one note on its Run issue (M7)."""
    st = state.load_run(ctx.paths, key)           # the saved state: the failed poll's partial changes were not
    first = st is None or not st.get("poll_fails")
    if first:                                     # the traceback once per failure streak, one line after that
        ctx.log.error("run %s: poll failed, retried next poll:\n%s", key,
                      mc.redact(traceback.format_exc(), [ctx.cli.token]))
    else:
        ctx.log.error("run %s: poll failed (%s), retried next poll: %s", key, type(e).__name__,
                      mc.redact(e, [ctx.cli.token]))
    if st is None:
        return
    st["poll_fails"] = st.get("poll_fails", 0) + 1
    st["poll_error"] = "%s: %s" % (type(e).__name__, mc.redact(e, [ctx.cli.token]).splitlines()[0][:200] if str(e) else "")
    state.save_run(ctx.paths, st)
    if st["poll_fails"] >= PERMANENT_ATTEMPTS and not st.get("poll_fail_noted"):
        note(ctx, st, "studio: mirroring this run keeps failing (%d polls): %s — see `multica-bridge status`"
             % (PERMANENT_ATTEMPTS, mc.redact(e, [ctx.cli.token])))
        st["poll_fail_noted"] = True              # only after note() returned: a transient on the post retries it
        state.save_run(ctx.paths, st)
