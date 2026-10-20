#!/usr/bin/env python3
"""gate-wait-measure.py -- how long gated commands wait for vs hold the studio gate lock.

Read-only. Sources:
  * STATE_ROOT/.studio/gate.times (+ any gate.times.<n> snapshots), written by studio-gate after the
    command ends, while still holding the lock. Two row shapes, both read:
      4 fields  `<release epoch> <who> <hold s> <rc>` -- hold only; waiting is NOT recorded.
      8 fields  `<release epoch> <who> <hold s> <rc> <wait s> <lane> <class> <unit|->` -- exact:
                acquire = release - hold, request = acquire - wait, no inference.
    The file keeps the newest 50 lines per `who` (or any row younger than 14 days).
  * Claude Code transcripts (~/.claude-gamedev/projects/*phoenix*/**/*.jsonl and ~/.claude/...):
    the Bash tool_use timestamp (call start) and its tool_result timestamp (call end).

Derivation per gated Bash call:
  matched   -- the call's gate.times entry is found (same who, release within the call's end
               window). acquire = release - hold. The request time is the call start, raised to the
               end of the last idle gap (>GAP s with no holder) before acquire: the lock is serial and
               a waiter polls every 1 s, so if the lock was idle the request came after that idle
               spell. wait = acquire - request. Exact to ~1-2 s when gate.times is complete.
  inferred  -- no gate.times entry (history rotated away). Holders are the other gated calls and
               the remaining gate.times rows; since the lock is serial, release order = acquire
               order, so acquire >= the latest other release inside (start, end). wait = acquire -
               start. A lower bound when holders are missing from the data.
Loops (for/while around studio-test) and background calls are counted but not derived.

Usage: python3 -I gate-wait-measure.py [--root ~/GameDev/proj/phoenix] [--days 14]
       [--day 2026-10-19] [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--validate] [--top N]
       [--dump calls.tsv] [--transcripts DIRS]
       python3 -I gate-wait-measure.py --lanes [--root R] [--since D]   # the after-report (spec 13.7)
       python3 -I gate-wait-measure.py --check-overlap [--root R]       # acceptance 6
       python3 -I gate-wait-measure.py --selftest
"""
import argparse, bisect, glob, json, os, re, shutil, subprocess, sys, tempfile, time
from datetime import datetime, timedelta

GAP = 3          # seconds of no holder that count as "lock idle"
SHORT = 120      # a short hold (s)
LONG = 600       # a long hold (s)

HOME = os.path.expanduser("~")

# ---------------------------------------------------------------- gate.times
def load_gate_times(root):
    """Rows of every gate.times* file, de-duplicated, plus the spans in which no label had been
    rotated away (studio-gate keeps the newest 50 lines per who): only there is the holder
    timeline complete."""
    rows, seen = [], set()
    files = sorted(glob.glob(os.path.join(root, ".studio", "gate.times*")))
    cover = {}      # who -> [(lo, hi)] spans that file f fully covers for that label
    labels = set()
    for f in files:
        per = {}
        for line in open(f, errors="replace"):
            p = line.split()
            if len(p) not in (4, 8) or not p[0].isdigit() or not p[2].lstrip("-").isdigit():
                continue
            e, w, s, rc = int(p[0]), p[1], int(p[2]), p[3]
            wait, lane, cls, unit = None, "main", None, None
            if len(p) == 8:
                if not p[4].isdigit():
                    continue
                wait, lane, cls, unit = int(p[4]), p[5], p[6], p[7]
            per.setdefault(w, []).append(e - int(s))
            labels.add(w)
            if (e, w, s) in seen:
                continue
            seen.add((e, w, s))
            rows.append({"rel": e, "who": w, "hold": int(s), "acq": e - int(s), "rc": rc, "call": None,
                         "wait": wait, "lane": lane, "cls": cls, "unit": unit,
                         "req": None if wait is None else e - int(s) - wait})
        m = os.path.getmtime(f)
        for w in labels | set(per):
            lo = min(per[w]) if len(per.get(w, [])) >= 50 else 0
            cover.setdefault(w, []).append((lo, m))
    rows.sort(key=lambda r: r["rel"])
    # complete spans = intersection over labels of the union of each label's covered spans
    spans = [(0, float("inf"))]
    for w, cv in cover.items():
        new = []
        for lo, hi in spans:
            for clo, chi in cv:
                x, y = max(lo, clo), min(hi, chi)
                if x < y:
                    new.append((x, y))
        spans = merge_spans(new)
    first = rows[0]["acq"] if rows else 0
    spans = [(max(lo, first), hi) for lo, hi in spans if hi > first]
    return rows, spans, files


def merge_spans(v):
    v = sorted(v)
    out = []
    for lo, hi in v:
        if out and lo <= out[-1][1]:
            out[-1] = (out[-1][0], max(out[-1][1], hi))
        else:
            out.append((lo, hi))
    return out


def in_spans(t, spans):
    return any(lo <= t <= hi for lo, hi in spans)


# ---------------------------------------------------------------- transcripts
GATED = re.compile(r"(?:^|[\s;&|(`{]|\bdo\s|\bthen\s)(?:[^\s;&|]*/)?(studio-test|studio-gate|studio-run|studio-setup)(?=\s|$|;|\))([^\n]*)")
TS = re.compile(r'"timestamp":"([^"]+)"')
TSU = re.compile(r'"uuid":"[0-9a-f-]{36}","timestamp":"([^"]+)"')
TUID = re.compile(r'"tool_use_id":"(toolu_[A-Za-z0-9_]+)"')


def iso(s):
    s = s.rstrip("Z")
    if "." in s:
        s = s.split(".")[0] + "." + s.split(".")[1][:6]
        dt = datetime.strptime(s, "%Y-%m-%dT%H:%M:%S.%f")
    else:
        dt = datetime.strptime(s, "%Y-%m-%dT%H:%M:%S")
    return (dt - datetime(1970, 1, 1)).total_seconds()


def gated_invocations(cmd):
    """[(kind, who, text)] for each gated command word in a Bash command."""
    out = []
    if re.match(r"\s*(studio-overnight|studio-event|studio-brief)\b", cmd):
        return out            # directive / message text that only mentions the gate
    for m in GATED.finditer(cmd):
        kind, rest = m.group(1), m.group(2)
        if quoted_prose(cmd, m.start(1)):
            continue
        if kind == "studio-gate":
            t = rest.split()
            if len(t) < 2 or t[1] != "--":
                continue          # prose / usage text, not a call
            who = t[0].strip("'\"")
            tail = cmd[m.start(2):]
            out.append((kind, who, tail.split(" -- ", 1)[1] if " -- " in tail else tail))
        elif kind == "studio-test":
            who = "studio-test-file" if re.match(r"\s*(--file|-f)\b", rest) or " --file" in rest.split("|")[0] else "studio-test"
            out.append((kind, who, rest))
        elif kind == "studio-run":
            out.append((kind, "studio-run", rest))
        else:
            out.append((kind, "setup|gate", rest))
    return out


def quoted_prose(cmd, pos):
    """True when pos sits inside a quoted string that is not an `sh -c` script."""
    pre = cmd[:pos]
    for q in ("'", '"'):
        n = pre.count(q) - pre.count("\\" + q)
        if n % 2 == 1:
            k = pre.rfind(q)
            if not re.search(r"-c\s*$", pre[:k]):
                return True
    return False


def classify_text(who, text):
    t = text
    if who == "studio-test":
        return "suite"
    if who == "studio-test-file":
        return "file"
    if re.search(r"run-tests\.sh|merge\.sh", t) or who in ("final-gate", "gate") or who.startswith("merge"):
        return "final"
    if re.search(r"test:functional|cucumber|playwright", t):
        return "other"
    if re.search(r"\bvitest\b", t):
        m = re.search(r"\bvitest(?:\s+run)?((?:\s+[^\s;&|'\"\\)<>]+)*)", t)
        args = [a for a in (m.group(1) if m else "").split() if not a.startswith("-") and not a[0].isdigit()]
        files = [a for a in args if re.search(r"\.(test|spec)\.|\.(ts|js|mjs|tsx)$", a)]
        return "vitest-targeted" if args and len(files) == len(args) else "vitest-full"
    m = re.search(r"\bnpm\b[^;&|]*?\b(?:run\s+)?test\b([^;&|'\"]*)", t)
    if m:
        return "vitest-targeted" if re.search(r"--\s+\S", m.group(1)) else "vitest-full"
    if re.search(r"\btsc\b|\beslint\b|\blint\b|typecheck|studio-lint", t) or who in ("tsc", "lint"):
        return "tsc-lint"
    if who in ("godot", "import", "importer") or re.search(r"Godot[^\s]*\s", t):
        return "godot"
    return "other"


def classify_who(who):
    """Class of a gate.times row with no transcript call (runner rows, rotated transcripts)."""
    if who == "studio-test":
        return "suite"
    if who == "studio-test-file":
        return "file"
    if who in ("final-gate", "gate", "run-tests", "precheck") or who.startswith("merge") or who.startswith("precheck"):
        return "final"
    if who in ("tsc", "lint"):
        return "tsc-lint"
    if who == "vitest":
        return "vitest-?"
    if who in ("godot", "import", "importer"):
        return "godot"
    return "other"


def scan_transcripts(since, until, dirs):
    calls = []
    files = []
    for d in dirs:
        files += glob.glob(os.path.join(d, "*phoenix*", "**", "*.jsonl"), recursive=True)
    for f in files:
        try:
            if os.path.getmtime(f) < since:
                continue
        except OSError:
            continue
        src = "gamedev" if "/.claude-gamedev/" in f else "claude"
        uses = {}        # id -> dict
        order = []       # ids in order, with message id
        results = {}     # id -> (ts, text)
        try:
            fh = open(f, errors="replace")
        except OSError:
            continue
        for line in fh:
            if '"api-request-blob"' in line[:200]:
                continue
            if '"type":"tool_use"' in line and '"type":"assistant"' in line:
                try:
                    d = json.loads(line)
                except ValueError:
                    continue
                if d.get("type") != "assistant":
                    continue
                m = d.get("message") or {}
                for x in m.get("content") or []:
                    if not isinstance(x, dict) or x.get("type") != "tool_use":
                        continue
                    u = {"id": x["id"], "ts": iso(d["timestamp"]), "msg": m.get("id"), "name": x.get("name")}
                    if x.get("name") == "Bash":
                        inp = x.get("input") or {}
                        u["cmd"] = inp.get("command") or ""
                        u["bg"] = bool(inp.get("run_in_background"))
                    uses[x["id"]] = u
                    order.append(x["id"])
            elif '"tool_use_id"' in line:
                ids = TUID.findall(line)
                if not ids:
                    continue
                tm = TSU.search(line, line.find('"tool_use_id"'))
                if not tm:
                    continue
                ts = iso(tm.group(1))
                for i in ids:
                    u = uses.get(i)
                    if u is None or i in results:
                        continue
                    text = ""
                    if u.get("cmd") and GATED.search(u["cmd"]):
                        try:
                            d = json.loads(line)
                            for x in d["message"]["content"]:
                                if isinstance(x, dict) and x.get("tool_use_id") == i:
                                    c = x.get("content")
                                    text = c if isinstance(c, str) else json.dumps(c)
                        except (ValueError, KeyError, TypeError):
                            pass
                    results[i] = (ts, text)
        fh.close()
        prev_by_msg = {}
        for i in order:
            u = uses[i]
            pm = prev_by_msg.get(u["msg"])
            prev_by_msg[u["msg"]] = i
            if not u.get("cmd"):
                continue
            inv = gated_invocations(u["cmd"])
            if not inv:
                continue
            if u["ts"] < since or u["ts"] >= until:
                continue
            res = results.get(i)
            start = u["ts"]
            # Tools of one assistant message run one after another (Bash that writes is not
            # concurrency-safe): this call starts once the previous sibling's result is in.
            if pm and pm in results:
                start = max(start, results[pm][0])
            loop = bool(re.search(r"\b(for|while|until)\b[^\n]*\bdo\b", u["cmd"]))
            text = res[1] if res else ""
            bg = u.get("bg") or "running in background" in text[:300]
            denied = bool(res) and (res[0] - start) < 2 and not re.search(r"studio-test:|gate:", text)
            calls.append({
                "id": i, "file": f, "src": src, "proj": f.split("/projects/")[1].split("/")[0].replace("-Users-xinli-GameDev-proj-phoenix", "phoenix"),
                "start": start, "end": res[0] if res else None, "cmd": u["cmd"], "inv": inv,
                "who": [w for _, w, _ in inv], "cls": classify_text(inv[0][1], inv[0][2]),
                "loop": loop, "bg": bg, "denied": denied,
                "gate_msgs": text.count("gate: waiting for"), "rows": [], "how": None,
            })
    return calls


# ---------------------------------------------------------------- matching & derivation
def match(calls, rows):
    by_who = {}
    for r in rows:
        by_who.setdefault(r["who"], []).append(r)
    cands = [c for c in calls if c["end"] and not c["bg"] and not c["denied"] and not c["loop"]]
    cands.sort(key=lambda c: c["end"])
    for c in cands:
        want = c["who"]
        hi = c["end"] + 5
        lo = c["start"] - 2
        picked = []
        for w in reversed(want):
            pool = []
            for wl in (w.split("|")):
                pool += by_who.get(wl, [])
            best = None
            for r in pool:
                if r["call"] is None and lo <= r["acq"] and r["rel"] <= hi and r["rel"] >= lo:
                    if best is None or r["rel"] > best["rel"]:
                        best = r
            if best is None:
                break
            picked.append(best)
            hi = best["acq"] + 2
        if len(picked) == len(want):
            for r in picked:
                r["call"] = c["id"]
            c["rows"] = sorted(picked, key=lambda r: r["acq"])


def request_time(lower, acq, ivs, rels, own):
    """Walk back from acq through back-to-back holders (each acquired within GAP s of the previous
    release). Where the chain breaks the lock was idle, and a waiter polling every second would
    have taken it then, so the request came no earlier than the chain's start."""
    cur = acq
    while cur > lower:
        j = bisect.bisect_right(rels, cur + 0.5) - 1
        found = None
        while j >= 0 and rels[j] >= cur - GAP:
            iv = ivs[j]
            if iv["owner"] != own and iv["acq"] < cur - 0.5:
                found = iv
                break
            j -= 1
        if found is None:
            break
        cur = found["acq"]
    return max(lower, cur)


def derive(calls, rows, spans, use_rows=True):
    """Fill wait/hold/acq/how/blockers on each call. rows: gate.times rows; with use_rows False
    the calls' own rows are ignored (transcript-only inference, for validation)."""
    for c in calls:
        c.update(wait=None, hold=None, acq=None, blockers=[], waits=[])
        if c["denied"] or c["end"] is None:
            c["how"] = "denied/no-result"
        elif c["bg"]:
            c["how"] = "background"
        elif c["loop"]:
            c["how"] = "loop"
        elif c["rows"] and use_rows:
            c["how"] = "matched"
            c["acq"] = c["rows"][0]["acq"]
            c["hold"] = sum(r["hold"] for r in c["rows"])
        else:
            c["how"] = None
    # Inference for calls without a row: the lock is serial, so every holder that released
    # inside (start, end) was ahead of this call: acquire >= the latest such release.
    # A call that ended while a gate.times row shows someone else holding never held the lock:
    # it was stopped while waiting (Bash tool timeout, session end). Its whole span is wait.
    known = sorted([(r["acq"], r["rel"]) for r in rows if (use_rows or r["call"] is None)])
    kacq = [k[0] for k in known]
    for c in calls:
        if c["how"] is not None:
            continue
        j = bisect.bisect_left(kacq, c["end"] - 2) - 1
        while j >= 0 and j >= bisect.bisect_left(kacq, c["end"] - 4000):
            if known[j][1] > c["end"] + 2 and known[j][0] > c["start"] - 4000:
                c["how"] = "abandoned"
                c["acq"], c["hold"], c["cover_acq"] = c["end"], 0, known[j][0]
                break
            j -= 1
    rels_all = sorted([r["rel"] for r in rows if (use_rows or r["call"] is None)] +
                      [c["end"] for c in calls if c["how"] is None])
    for c in calls:
        if c["how"] is not None:
            continue
        lo = bisect.bisect_right(rels_all, c["start"])
        hi = bisect.bisect_left(rels_all, c["end"] - 1)
        acq = max([c["start"]] + rels_all[lo:hi])
        c["acq"], c["hold"], c["how"] = acq, c["end"] - acq, "inferred"
    # Holder timeline: gate.times rows + inferred holds.
    ivs = []
    for r in rows:
        if use_rows or r["call"] is None:
            ivs.append({"acq": r["acq"], "rel": r["rel"], "hold": r["hold"], "who": r["who"], "lane": r["lane"],
                        "owner": r["call"] if use_rows else None})
    for c in calls:
        if c["how"] == "inferred":
            ivs.append({"acq": c["acq"], "rel": c["end"], "hold": c["hold"], "who": c["cls"] + "*", "lane": "main", "owner": c["id"]})
    ivs.sort(key=lambda x: x["rel"])
    rels = [x["rel"] for x in ivs]
    # Per-lane attribution: the holder timeline of the main lane is the rows whose lane starts with
    # `main`. A `short` row (the slot) never blocks a main-lane call.
    mivs = [x for x in ivs if x["lane"].startswith("main")]
    mrels = [x["rel"] for x in mivs]
    for c in calls:
        if c["how"] not in ("matched", "inferred", "abandoned"):
            continue
        clane = c["rows"][0]["lane"] if c["how"] == "matched" and c["rows"] else "main"
        tl, trels = (ivs, rels) if clane.startswith("short") else (mivs, mrels)
        segs = [(r["acq"], r["rel"]) for r in c["rows"]] if c["how"] == "matched" else [(c["acq"], c["end"])]
        lower = c["start"]
        total = 0.0
        exact = c["how"] == "matched" and all(r["wait"] is not None for r in c["rows"])
        for n, (acq, rel) in enumerate(segs):
            if exact:                     # 8-field row: field 5 is the wait, no inference
                req = c["rows"][n]["req"]
            elif c["how"] == "abandoned":   # waited until stopped; chain back from the holder it sat behind
                req = request_time(lower, min(c["cover_acq"], acq), tl, trels, c["id"])
            else:
                req = request_time(lower, acq, tl, trels, c["id"])
            total += max(0.0, acq - req)
            c["waits"].append((req, acq))
            lower = rel
        # Each 60 s of waiting prints `gate: waiting for <who>` to stderr (the first at 0 s), so N
        # such lines in the visible output prove at least (N-1) min of wait (output may be cut).
        if c["gate_msgs"] > 0 and not exact:
            total = max(total, (c["gate_msgs"] - 1) * 60.0)
        c["wait"] = total
        for req, acq in c["waits"]:
            if acq - req < 1:
                continue
            j = bisect.bisect_right(trels, req)
            while j < len(tl) and tl[j]["acq"] < acq:
                if tl[j]["owner"] != c["id"]:
                    c["blockers"].append(tl[j])
                j += 1
        c["complete"] = in_spans(c["start"], spans) and in_spans(c["end"], spans)


# ---------------------------------------------------------------- reporting
CLASSES = ["suite", "file", "vitest-targeted", "vitest-full", "vitest-?", "tsc-lint", "final", "godot", "other"]
LABEL = {"suite": "whole-suite studio-test", "file": "studio-test-file", "vitest-targeted": "targeted vitest",
         "vitest-full": "full vitest / npm test", "vitest-?": "vitest (gate.times only, args unknown)",
         "tsc-lint": "tsc / lint", "final": "run-tests.sh / merge.sh / final gate", "godot": "godot import/script",
         "other": "other gated"}


def pct(v, p):
    if not v:
        return None
    v = sorted(v)
    k = (len(v) - 1) * p
    lo = int(k)
    hi = min(lo + 1, len(v) - 1)
    return v[lo] + (v[hi] - v[lo]) * (k - lo)


def fm(s):
    return "-" if s is None else ("%.1f" % (s / 60.0))


def table(calls, rows, since, until, title, out, only_complete=False):
    holds = {k: [] for k in CLASSES}
    waits = {k: [] for k in CLASSES}
    count = {k: 0 for k in CLASSES}
    nwait = {k: 0 for k in CLASSES}
    by_id = {c["id"]: c for c in calls}
    for r in rows:
        if not (since <= r["rel"] < until) or only_complete:
            continue
        if r["call"] and r["call"] in by_id and by_id[r["call"]]["how"] == "matched":
            continue
        k = classify_who(r["who"])
        holds[k].append(r["hold"])
        count[k] += 1
    sel = [c for c in calls if since <= c["start"] < until and c["how"] in ("matched", "inferred", "abandoned", "loop", "background")
           and (not only_complete or (c["how"] == "matched" and c.get("complete")))]
    for c in sel:
        k = c["cls"]
        if c["how"] in ("loop", "background"):
            continue      # their gate rows (if any) are counted above as untied rows
        count[k] += 1
        if c["hold"] is not None:
            holds[k].append(c["hold"])
        if c["wait"] is not None:
            waits[k].append(c["wait"])
    out.append("\n### %s\n" % title)
    out.append("| verb | count | hold p50 | hold p90 | hold max | n wait | wait p50 | wait p90 | wait max | queue-min total |")
    out.append("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
    for k in CLASSES:
        if not count[k]:
            continue
        h, w = holds[k], waits[k]
        out.append("| %s | %d | %s | %s | %s | %d | %s | %s | %s | %.0f |" % (
            LABEL[k], count[k], fm(pct(h, .5)), fm(pct(h, .9)), fm(max(h) if h else None),
            len(w), fm(pct(w, .5)), fm(pct(w, .9)), fm(max(w) if w else None), sum(w) / 60.0))
    allw = [c["wait"] for c in sel if c["wait"] is not None]
    out.append("\nAll verbs: %d calls with a wait, total queue %.0f min; %d waited > 1 min, %d > 10 min. "
               "(minutes; hold from gate.times where the row exists, else inferred; wait only for transcript calls)" % (
                   len(allw), sum(allw) / 60.0, sum(1 for x in allw if x > 60), sum(1 for x in allw if x > 600)))
    # short verbs behind long holds
    n = 0
    byb = {}
    lost = lost_all = 0.0
    short = [c for c in sel if c["wait"] is not None and c["hold"] is not None and c["hold"] < SHORT]
    for c in short:
        ov = []
        for req, acq in c["waits"]:
            for b in c["blockers"]:
                if b["hold"] > LONG:
                    x, y = max(b["acq"], req), min(b["rel"], acq)
                    if y > x:
                        ov.append((x, y))
        ov = merge_spans(ov)
        if not ov:
            continue
        for req, acq in c["waits"]:
            for b in c["blockers"]:
                if b["hold"] > LONG:
                    x, y = max(b["acq"], req), min(b["rel"], acq)
                    if y > x:
                        k = b["who"].rstrip("*")
                        k = k if k in CLASSES else classify_who(k)
                        byb[k] = byb.get(k, 0.0) + (y - x)
        n += 1
        lost += sum(y - x for x, y in ov)
        lost_all += c["wait"]
    out.append("\nShort verbs (hold < %d s) that waited behind a long hold (> %d s): %d of %d short calls; "
               "%.0f min of their wait was spent behind the long holds (%.0f min total wait for those calls)." % (
                   SHORT, LONG, n, len(short), lost / 60.0, lost_all / 60.0))
    if byb:
        out.append("Long holders those short calls waited behind (min): " + ", ".join(
            "%s %.0f" % (LABEL.get(k, k), v / 60.0) for k, v in sorted(byb.items(), key=lambda x: -x[1])))
    return {"n": n, "short": len(short), "lost": lost, "queue": sum(allw), "calls": len(allw)}


# ---------------------------------------------------------------- lanes report (spec 13.7)
# verb -> (the `who` labels that make it, target recovered share, spec 13.7 table)
VERBS = [("studio-test-file", ("studio-test-file",), 0.55),
         ("vitest", ("vitest",), 0.30),
         ("tsc/eslint/lint", ("tsc", "eslint", "lint"), 0.60),
         ("all three", ("studio-test-file", "vitest", "tsc", "eslint", "lint"), 0.50)]
JUDGE_MIN = 30 * 60      # a verb under 30 exposure-minutes is reported, not judged
FINAL_WHO = ("final-gate", "merge", "gate")


def is_final(who):
    return who in FINAL_WHO or who.startswith("merge")


def overlap(a0, a1, b0, b1):
    return max(0, min(a1, b1) - max(a0, b0))


def union_len(spans):
    return sum(hi - lo for lo, hi in merge_spans([s for s in spans if s[1] > s[0]]))


def lane_report(rows, since, until, out):
    """The after-report. Only 8-field rows carry a wait, so only they are calls; 4-field rows still
    count as holders (their lane is `main`). Returns the numbers for the selftest."""
    inwin = [r for r in rows if since <= r["rel"] < until]
    calls = [r for r in inwin if r["wait"] is not None]
    # whole suites that held the main lane as `shareable`
    suites = sorted([r for r in rows if r["who"] == "studio-test" and r["cls"] == "shareable"
                     and r["lane"].startswith("main")], key=lambda r: r["acq"])
    res = {"verbs": {}, "lane_counts": {}, "old_metric": None, "final": {}}
    out.append("\n### Lanes: recovered share per short verb (spec 13.7)\n")
    out.append("%d of %d rows in the window have a wait (8-field); %d are 4-field rows (holders only, never calls)." % (
        len(calls), len(inwin), len(inwin) - len(calls)))
    out.append("\nA call counts when it arrives (epoch - hold - wait) while a whole-suite `studio-test` of class shareable holds main.")
    out.append("exposure = suite release - arrival; waited = min(acquisition, release) - arrival; "
               "recovered share = 1 - sum(waited) / sum(exposure).\n")
    out.append("| verb | calls behind a suite | exposure min | waited min | recovered share | target | verdict |")
    out.append("|---|---:|---:|---:|---:|---:|---|")
    for name, whos, target in VERBS:
        n, expo, waited = 0, 0, 0
        for r in calls:
            if r["who"] not in whos:
                continue
            arr = r["acq"] - r["wait"]
            for s in suites:
                if s is not r and s["acq"] <= arr < s["rel"]:
                    n += 1
                    expo += s["rel"] - arr
                    waited += max(0, min(r["acq"], s["rel"]) - arr)
                    break
        share = (1.0 - float(waited) / expo) if expo else None
        if share is None or expo < JUDGE_MIN:
            verdict = "reported"
        else:
            verdict = "PASS" if share >= target else "FAIL"
        res["verbs"][name] = {"n": n, "exposure": expo, "waited": waited, "share": share, "verdict": verdict}
        out.append("| %s | %d | %.1f | %.1f | %s | >= %d%% | %s |" % (
            name, n, expo / 60.0, waited / 60.0, "-" if share is None else "%.1f%%" % (100 * share),
            round(100 * target), verdict))
    out.append("\nA verb with under 30 exposure-minutes is `reported`, not judged.")
    # short-eligible rows by lane value (A3: at least one must run in the slot)
    lc = {}
    for r in inwin:
        if r["cls"] == "short":
            lc[r["lane"]] = lc.get(r["lane"], 0) + 1
    res["lane_counts"] = lc
    out.append("\n#### Short-eligible rows (class `short`) by lane\n")
    out.append("| lane | rows | share |")
    out.append("|---|---:|---:|")
    tot = sum(lc.values())
    for k, v in sorted(lc.items(), key=lambda kv: -kv[1]):
        out.append("| %s | %d | %.0f%% |" % (k, v, 100.0 * v / tot))
    if not tot:
        out.append("| (none) | 0 | |")
    out.append("\nran in the slot (lane `short`): %d%s" % (lc.get("short", 0), "" if lc.get("short", 0) else "  <-- A3: the slot was never used"))
    refused = sorted(((k, v) for k, v in lc.items() if k != "short"), key=lambda kv: -kv[1])
    if refused and tot and 2 * refused[0][1] > tot:
        out.append("note: `%s` accounts for most short-eligible calls; the PR needs an explanation." % refused[0][0])
    # the old metric, not judged
    shorts = [r for r in calls if r["who"] in VERBS[3][1]]
    suite_spans = [(r["acq"], r["rel"]) for r in rows if r["who"] == "studio-test"]
    behind = 0
    for r in shorts:
        arr = r["acq"] - r["wait"]
        behind += union_len([(max(arr, a), min(r["acq"], b)) for a, b in suite_spans])
    per100 = (behind / 60.0) * 100.0 / len(shorts) if shorts else 0.0
    res["old_metric"] = per100
    out.append("\nOld metric (not judged): short-call minutes behind whole suites per 100 short calls: %.1f "
               "(%.1f min over %d short calls)." % (per100, behind / 60.0, len(shorts)))
    # waits behind final gates, reported apart (A2: expected unchanged)
    fin = [(r["acq"], r["rel"]) for r in rows if is_final(r["who"])]
    out.append("\n#### Waits behind final gates (final-gate, merge, gate), reported apart\n")
    out.append("| calls | calls that waited behind one | minutes behind final gates |")
    out.append("|---|---:|---:|")
    for name, whos, _ in VERBS[3:]:
        cs = [r for r in calls if r["who"] in whos and r["wait"] > 0]
        mins = nb = 0
        for r in cs:
            arr = r["acq"] - r["wait"]
            x = union_len([(max(arr, a), min(r["acq"], b)) for a, b in fin])
            if x:
                nb += 1
                mins += x
        res["final"][name] = {"n": len(cs), "behind": nb, "seconds": mins}
        out.append("| short verbs that waited: %d | %d | %.1f |" % (len(cs), nb, mins / 60.0))
    allc = [r for r in calls if r["wait"] > 0 and not is_final(r["who"])]
    nb = mins = 0
    for r in allc:
        arr = r["acq"] - r["wait"]
        x = union_len([(max(arr, a), min(r["acq"], b)) for a, b in fin])
        if x:
            nb += 1
            mins += x
    out.append("| all non-final verbs that waited: %d | %d | %.1f |" % (len(allc), nb, mins / 60.0))
    return res


def check_overlap(rows, since, until, out):
    """Acceptance 6: no lane-`short` row overlaps a class-`exclusive` row in time. Returns the pairs."""
    sh = [r for r in rows if r["lane"] == "short" and since <= r["rel"] < until]
    ex = [r for r in rows if r["cls"] == "exclusive"]
    pairs = []
    for s in sh:
        for e in ex:
            if s is not e and overlap(s["acq"], s["rel"], e["acq"], e["rel"]) > 0:
                pairs.append((s, e))
                out.append("overlap: short %s held %d..%d (release %d) overlaps exclusive %s held %d..%d (release %d)" % (
                    s["who"], s["acq"], s["rel"], s["rel"], e["who"], e["acq"], e["rel"], e["rel"]))
    out.append("check-overlap: %d short rows, %d exclusive rows, %d overlapping pairs" % (len(sh), len(ex), len(pairs)))
    return pairs


# ---------------------------------------------------------------- selftest
def selftest():
    """Synthetic gate.times; asserts the lane report, the 4-field parse and --check-overlap."""
    d = tempfile.mkdtemp(dir=os.environ["TMPDIR"])
    try:
        os.makedirs(os.path.join(d, ".studio"))
        t0 = 1700000000     # the suite's acquisition; a row is `<release> <who> <hold> <rc> [<wait> <lane> <class> <unit>]`
        rows = [
            "%d studio-test 100 0" % (t0 - 400),                                  # old 4-field row
            "%d studio-test 600 0 0 main shareable u1" % (t0 + 600),              # the suite: holds main t0..t0+600
            # three short file runs in the slot, waited 0, arriving at +100 / +200 / +250 (hold 10 s each)
            "%d studio-test-file 10 0 0 short short u2" % (t0 + 110),
            "%d studio-test-file 10 0 0 short short u2" % (t0 + 210),
            "%d studio-test-file 10 0 0 short short u2" % (t0 + 260),
            # one that went to main: arrived at +300, acquired at +600 (waited the remaining 300 s)
            "%d studio-test-file 10 0 300 main:slot-busy short u2" % (t0 + 610),
            # an exclusive final gate t0+700..t0+800, and a short row overlapping it (t0+750..t0+760)
            "%d final-gate 100 0 0 main exclusive -" % (t0 + 800),
            "%d studio-test-file 10 0 0 short short u2" % (t0 + 760),
        ]
        gt = os.path.join(d, ".studio", "gate.times")
        with open(gt, "w") as fh:
            fh.write("\n".join(rows) + "\n")
        loaded, _, _ = load_gate_times(d)
        assert len(loaded) == 8, len(loaded)
        old = [r for r in loaded if r["wait"] is None]
        assert len(old) == 1 and old[0]["who"] == "studio-test" and old[0]["lane"] == "main", old
        full = [r for r in loaded if r["wait"] is not None]
        assert len(full) == 7
        r4 = [r for r in full if r["who"] == "studio-test-file" and r["wait"] == 300][0]
        assert r4["acq"] == t0 + 600 and r4["req"] == t0 + 300, r4     # request = acquire - wait, exact
        # Recovered share (studio-test-file), by hand. Only the four calls that arrive inside the suite's
        # hold count (the 5th, at +750, arrives after it). Exposure = suite release - arrival:
        #   +100 -> 500, +200 -> 400, +250 -> 350, +300 -> 300; sum 1550 s.
        # Waited = min(acquisition, release) - arrival: 0, 0, 0 and min(+600, +600) - 300 = 300; sum 300 s.
        # Recovered share = 1 - 300 / 1550 = 1250 / 1550 = 0.806452.
        st = lane_report(loaded, 0, float("inf"), [])
        v = st["verbs"]["studio-test-file"]
        assert v["exposure"] == 1550 and v["waited"] == 300 and v["n"] == 4, v
        assert abs(v["share"] - 1250.0 / 1550.0) < 1e-9, v
        assert st["verbs"]["all three"]["share"] == v["share"]
        assert st["lane_counts"] == {"short": 4, "main:slot-busy": 1}, st["lane_counts"]
        # the CLI: --check-overlap finds exactly the planted pair and exits 1
        me = os.path.abspath(__file__)
        pr = subprocess.run([sys.executable, "-I", me, "--root", d, "--since", "2023-01-01", "--check-overlap"], capture_output=True, text=True)
        assert pr.returncode == 1, (pr.returncode, pr.stdout, pr.stderr)
        pairs = [ln for ln in pr.stdout.splitlines() if ln.startswith("overlap:")]
        assert len(pairs) == 1 and "final-gate" in pairs[0] and str(t0 + 760) in pairs[0], pr.stdout
        pl = subprocess.run([sys.executable, "-I", me, "--root", d, "--lanes", "--since", "2023-01-01"], capture_output=True, text=True)
        assert pl.returncode == 0 and "80.6%" in pl.stdout, (pl.returncode, pl.stdout, pl.stderr)
        # without the planted row the check is clean
        with open(gt, "w") as fh:
            fh.write("\n".join(rows[:-1]) + "\n")
        pc = subprocess.run([sys.executable, "-I", me, "--root", d, "--since", "2023-01-01", "--check-overlap"], capture_output=True, text=True)
        assert pc.returncode == 0, (pc.returncode, pc.stdout)
    finally:
        shutil.rmtree(d, ignore_errors=True)
    print("selftest: ok")


def lt(t):
    return datetime.fromtimestamp(t).strftime("%m-%d %H:%M:%S")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.path.join(HOME, "GameDev/proj/phoenix"))
    ap.add_argument("--days", type=int, default=14)
    ap.add_argument("--day", default=None, help="also report this local day (YYYY-MM-DD); default today")
    ap.add_argument("--since", default=None)
    ap.add_argument("--until", default=None)
    ap.add_argument("--validate", action="store_true", help="compare inferred vs matched waits")
    ap.add_argument("--top", type=int, default=15)
    ap.add_argument("--dump", default=None, help="write per-call TSV here")
    ap.add_argument("--transcripts", default=",".join([os.path.join(HOME, ".claude-gamedev/projects"), os.path.join(HOME, ".claude/projects")]))
    ap.add_argument("--lanes", action="store_true", help="the after-report: recovered share per verb, lane counts (spec 13.7)")
    ap.add_argument("--check-overlap", action="store_true", help="exit 1 if a lane-short row overlaps a class-exclusive row")
    ap.add_argument("--selftest", action="store_true", help="run against a synthetic gate.times and exit")
    a = ap.parse_args()
    if a.selftest:
        selftest()
        return 0
    now = time.time()
    until = time.mktime(time.strptime(a.until, "%Y-%m-%d")) if a.until else now + 1
    if a.since:
        since = time.mktime(time.strptime(a.since, "%Y-%m-%d"))
    else:
        d0 = datetime.fromtimestamp(now).replace(hour=0, minute=0, second=0, microsecond=0) - timedelta(days=a.days)
        since = d0.timestamp()
    day = a.day or datetime.fromtimestamp(min(now, until - 1)).strftime("%Y-%m-%d")
    ds = time.mktime(time.strptime(day, "%Y-%m-%d"))
    de = ds + 86400

    rows, spans, gfiles = load_gate_times(a.root)
    if a.check_overlap or a.lanes:
        out = []
        if a.check_overlap:
            pairs = check_overlap(rows, since, until, out)
            print("\n".join(out))
            return 1 if pairs else 0
        out.append("# Gate lanes (%s)\n" % datetime.fromtimestamp(now).strftime("%Y-%m-%d %H:%M"))
        out.append("gate.times files: %s; %d unique rows %s .. %s" % (
            ", ".join(os.path.basename(g) for g in gfiles), len(rows), lt(rows[0]["rel"]) if rows else "-",
            lt(rows[-1]["rel"]) if rows else "-"))
        lane_report(rows, since, until, out)
        print("\n".join(out))
        return 0
    t0 = time.time()
    calls = scan_transcripts(since - 3600, until, a.transcripts.split(","))
    match(calls, rows)
    derive(calls, rows, spans)
    out = []
    out.append("# Gate wait measurement (%s)\n" % datetime.fromtimestamp(now).strftime("%Y-%m-%d %H:%M"))
    out.append("gate.times files: %s; %d unique rows %s .. %s" % (
        ", ".join(os.path.basename(g) for g in gfiles), len(rows), lt(rows[0]["rel"]) if rows else "-",
        lt(rows[-1]["rel"]) if rows else "-"))
    out.append("holder timeline complete (no label rotated) in: %s" % (
        "; ".join("%s .. %s" % (lt(lo), lt(min(hi, now))) for lo, hi in spans) or "none"))
    srcs = {}
    for c in calls:
        if since <= c["start"] < until and c["how"] in ("matched", "inferred", "abandoned"):
            srcs[c["src"]] = srcs.get(c["src"], 0) + 1
    out.append("derived calls by config dir: %s (gamedev = ~/.claude-gamedev, the overnight/autopilot sessions)" % srcs)
    hows = {}
    for c in calls:
        if since <= c["start"] < until:
            hows[c["how"]] = hows.get(c["how"], 0) + 1
    out.append("transcript gated calls in window: %d (%s); scan %.0f s" % (
        sum(hows.values()), ", ".join("%s %d" % kv for kv in sorted(hows.items(), key=lambda x: -x[1])), time.time() - t0))
    out.append("gate.times rows tied to a transcript call: %d of %d in window" % (
        sum(1 for r in rows if r["call"] and since <= r["rel"] < until), sum(1 for r in rows if since <= r["rel"] < until)))
    table(calls, rows, since, until, "Last %d days (%s .. now)" % (a.days, lt(since)), out)
    table(calls, rows, ds, de, "Day %s" % day, out)
    table(calls, rows, since, until, "Matched calls inside a complete span only (most reliable)", out, only_complete=True)

    out.append("\n### Per day\n")
    out.append("| day | calls w/ wait | queue min | waits > 10 min | short-behind-long calls | their min behind long holds |")
    out.append("|---|---:|---:|---:|---:|---:|")
    d = datetime.fromtimestamp(since)
    while d.timestamp() < until:
        lo, hi = d.timestamp(), (d + timedelta(days=1)).timestamp()
        sink = []
        r = table(calls, rows, lo, hi, "", sink)
        big = sum(1 for c in calls if lo <= c["start"] < hi and c["wait"] is not None and c["wait"] > 600)
        if r["calls"]:
            out.append("| %s | %d | %.0f | %d | %d | %.0f |" % (d.strftime("%m-%d"), r["calls"], r["queue"] / 60.0, big, r["n"], r["lost"] / 60.0))
        d += timedelta(days=1)

    out.append("\n### Top %d waits in window\n" % a.top)
    out.append("| start | wait min | hold min | verb | how | session dir | longest blockers |")
    out.append("|---|---:|---:|---|---|---|---|")
    top = sorted([c for c in calls if since <= c["start"] < until and c["wait"] is not None], key=lambda c: -c["wait"])[:a.top]
    for c in top:
        bl = sorted(c["blockers"], key=lambda b: -b["hold"])[:2]
        bs = ", ".join("%s %.0fm" % (b["who"], b["hold"] / 60.0) for b in bl)
        out.append("| %s | %.1f | %s | %s | %s | %s | %s |" % (lt(c["start"]), c["wait"] / 60.0, fm(c["hold"]), c["cls"], c["how"], c["proj"][:45], bs))

    # Runner-side gates (final gate, lane landings) are not in any transcript; their logs keep
    # studio-gate's stderr, so N `gate: waiting` lines bound the wait to [(N-1), N] min.
    out.append("\n### Runner gates (final-gate / land / final-merge logs)\n")
    out.append("| log mtime | wait lines (~min) | log |")
    out.append("|---|---:|---|")
    logs = []
    for pat in ("final-gate.log", "final-merge.log", "*-land.log"):
        logs += glob.glob(os.path.join(a.root, ".studio", "reports", "overnight-*", "**", pat), recursive=True)
        logs += glob.glob(os.path.join(a.root, ".claude", "worktrees", "*", ".studio", "reports", "overnight-*", "**", pat), recursive=True)
    tot_lines = 0
    nlogs = 0
    for lg in sorted(set(logs)):
        try:
            m = os.path.getmtime(lg)
            if not (since <= m < until):
                continue
            nlogs += 1
            n = sum(1 for line in open(lg, errors="replace") if line.startswith("gate: waiting for"))
        except OSError:
            continue
        tot_lines += n
        if n:
            out.append("| %s | %d | %s |" % (lt(m), n, lg.replace(a.root + "/", "")))
    out.append("\n%d runner gate logs in window; %d wait lines (~%d min of runner wait in total)." % (nlogs, tot_lines, tot_lines))

    if a.validate:
        import copy
        allc = copy.deepcopy(calls)
        derive(allc, [dict(r) for r in rows], spans, use_rows=False)
        bym = {c["id"]: c for c in calls}
        pairs = [(bym[c["id"]]["wait"], c["wait"], bym[c["id"]]["hold"], c["hold"]) for c in allc
                 if bym[c["id"]]["how"] == "matched" and bym[c["id"]].get("complete") and c["wait"] is not None]
        if pairs:
            dw = [abs(x - y) for x, y, _, _ in pairs]
            dh = [abs(x - y) for _, _, x, y in pairs]
            out.append("\n### Validation: transcript-only inference vs gate.times-matched (%d calls in complete spans)\n" % len(pairs))
            out.append("|wait err| p50 %.0f s, p90 %.0f s, max %.0f s; |hold err| p50 %.0f s, p90 %.0f s; "
                       "within 60 s: %d%%; sum wait matched %.0f min vs inferred %.0f min" % (
                           pct(dw, .5), pct(dw, .9), max(dw), pct(dh, .5), pct(dh, .9),
                           100 * sum(1 for x in dw if x <= 60) // len(dw),
                           sum(x for x, _, _, _ in pairs) / 60.0, sum(y for _, y, _, _ in pairs) / 60.0))
        gm = [(c["gate_msgs"], c["wait"]) for c in calls if c["how"] in ("matched", "inferred") and c["gate_msgs"] > 0 and c["wait"] is not None]
        ok = sum(1 for n, w in gm if (n - 1) * 60 - 5 <= w <= n * 60 + 5)
        out.append("'gate: waiting' stderr cross-check (N lines => wait in [(N-1)*60, N*60) s): %d calls show the lines, %d consistent" % (len(gm), ok))
        bad = [(n, w, c) for c in calls for n, w in [(c["gate_msgs"], c["wait"])] if c["how"] in ("matched", "inferred") and n > 0 and w is not None and not ((n - 1) * 60 - 5 <= w <= n * 60 + 5)]
        for n, w, c in bad[:8]:
            out.append("  mismatch: %s %s %s lines=%d wait=%.0fs" % (lt(c["start"]), c["how"], c["cls"], n, w))

    if a.dump:
        with open(a.dump, "w") as fh:
            fh.write("start\tend\twait_s\thold_s\tcls\thow\twho\tproj\tgate_msgs\tcmd\n")
            for c in sorted(calls, key=lambda c: c["start"]):
                fh.write("%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%d\t%s\n" % (
                    lt(c["start"]), lt(c["end"]) if c["end"] else "-",
                    "" if c["wait"] is None else "%.0f" % c["wait"], "" if c["hold"] is None else "%.0f" % c["hold"],
                    c["cls"], c["how"], ",".join(c["who"]), c["proj"], c["gate_msgs"], c["cmd"][:160].replace("\n", " ").replace("\t", " ")))
    if any(r["wait"] is not None for r in rows):
        lane_report(rows, since, until, out)
    print("\n".join(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
