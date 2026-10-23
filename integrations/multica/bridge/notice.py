"""Hold and expiry notice texts, and the held-set step (#85). Pure: reads no files, makes no calls.

Spec: docs/game-dev/specs/2026-10-22-hold-notice-and-plan-probes.md ("Notice text").
"""
from __future__ import annotations

import re
import time

from .multica_cli import NOTICE_PREFIX
from .state import parse_ts

NOTICE_TAIL = "Notify only: reply with one short line. Run no command; never resume, stop, say to or hold a story."
# The runner's hold-expiry stop: `<why> (held <h>h<m>m, no reply)`, at the very end of the why.
_EXPIRY = re.compile(r" \(held \d+h\d+m, no reply\)\Z")


def until_line(until) -> str:
    """`Until <local> (<until> UTC); then it stops.`, or `Until <until or ?>; then it stops.` when the
    value does not parse."""
    try:
        local = time.strftime("%Y-%m-%d %H:%M %Z", time.localtime(parse_ts(until)))
    except (ValueError, TypeError, AttributeError):
        return "Until %s; then it stops." % (until if until is not None else "?")
    return "Until %s (%s UTC); then it stops." % (local, until)


def is_expiry(why) -> bool:
    return bool(_EXPIRY.search(str(why or "")))


def held_after(held: list, ev: dict) -> list:
    """The held-story list after `ev`: a new list, order kept."""
    out = list(held)
    if ev.get("event") != "story_state":
        return out
    story = ev.get("story")
    if ev.get("state") == "held":
        if story not in out:
            out.append(story)
    else:
        out = [s for s in out if s != story]
    return out


def hold_body(story: str, why, until, issue, run: str) -> str:
    """The held text without the leading `studio: `. `story == "-"` is the single-plan form."""
    if story == "-":
        head = "the run is held: %s" % why
    else:
        head = "story %s held: %s" % (story, why)
    if issue:
        multica = "Multica: on %s post /say <text>, then /resume — or /stop." % issue
    else:
        multica = "Multica: %s has no issue — use the terminal." % story
    term = "Terminal: studio-overnight say %s --run %s -- <text> · studio-overnight resume %s --run %s" \
           " · studio-overnight stop %s --run %s" % (story, run, story, run, story, run)
    return "\n".join([head, until_line(until), multica, term])


def expiry_body(story: str, why) -> str:
    who = "the run" if story == "-" else "story %s" % story
    return "%s stopped — hold ran out with no reply. Why: %s" % (who, why)


def kickoff_text(body: str) -> str:
    return NOTICE_PREFIX + body + "\n" + NOTICE_TAIL


def banner_text(story: str, run: str, why=None, expired: bool = False) -> str:
    who = "run" if story == "-" else story
    if expired:
        return "%s stopped in %s: hold ran out" % (who, run)
    return "%s held in %s: %s" % (who, run, why)
