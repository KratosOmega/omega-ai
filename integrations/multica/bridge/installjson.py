"""JSON questions for install.sh / uninstall.sh (#28, R6). Python 3.9, stdlib only."""
from __future__ import annotations

import json
import os
import sys
from xml.sax.saxutils import escape

from bridge.multica_cli import rows


def _load(src=None):
    if src is None:
        return json.load(sys.stdin)
    with open(src, encoding="utf-8") as f:
        return json.load(f)


def get(key):
    v = _load().get(key)
    if v in (None, ""):
        raise SystemExit("installjson: no %r in the CLI's answer" % key)
    return str(v)


def property_state(name):
    for p in rows(_load()):
        if p.get("name") == name:
            if p.get("archived") or p.get("archived_at"):
                return "archived"
            return "ok" if p.get("type") == "text" else "wrong-type:%s" % p.get("type")
    return "absent"


def profile_for_command(cmd):
    # By basename: a profile made with the bare name or with $HOME/.local/bin/<name> (D1a) is the same profile.
    want = os.path.basename(cmd)
    return "\n".join(p["id"] for p in rows(_load()) if os.path.basename(p.get("command_name") or "") == want)


def _online(rt):
    return rt.get("status") == "online"


def daemons_of(rts, profiles):
    sets = [{r.get("daemon_id") for r in rts if r.get("profile_id") == p} for p in profiles]
    both = set.intersection(*sets) if sets else set()
    return sorted(d for d in both if d)


def daemons(*profiles):
    return "\n".join(daemons_of([r for r in rows(_load()) if _online(r)], profiles))


def daemon_names(*profiles):
    """One `daemon_id (runtime name)` per daemon serving every profile; the host is inside the name (P7g)."""
    rts = [r for r in rows(_load()) if _online(r)]
    out = []
    for d in daemons_of(rts, profiles):
        name = next((r.get("name") or r.get("device_info") or "" for r in rts
                     if r.get("daemon_id") == d and r.get("profile_id") == profiles[0]), "")
        out.append("%s (%s)" % (d, name) if name else d)
    return "\n".join(out)


def selftest_fresh(path, since):
    """`fresh` when the self-test file holds a checked_at at or after SINCE (ISO-8601 UTC), else nothing."""
    try:
        at = _load(path).get("checked_at")
    except (OSError, ValueError, AttributeError):
        return ""
    return "fresh" if isinstance(at, str) and at >= since else ""


def runtime_for(profile, daemon):
    return "\n".join(r["id"] for r in rows(_load())
                     if _online(r) and r.get("profile_id") == profile and r.get("daemon_id") == daemon)


def agent_state(name):
    for a in rows(_load()):
        if a.get("name") == name:
            return "archived" if a.get("archived") or a.get("archived_at") else "active"
    return "absent"


def bound_agents(agents_file, runtimes_file, *profiles):
    rts = {r["id"] for r in rows(_load(runtimes_file)) if r.get("profile_id") in profiles}
    return "\n".join(sorted(a["name"] for a in rows(_load(agents_file))
                            if a.get("runtime_id") in rts and not (a.get("archived") or a.get("archived_at"))))


def selftest_kind(path):
    d = _load(path)
    if d.get("ok"):
        return "ok"
    return "\t".join(str(d.get(k) or "") for k in ("kind", "error", "interpreter")).replace("\n", " ")


def json_env(key, value):
    return json.dumps({key: value})


def plist(template, interpreter, lib, base, home, path):
    with open(template, encoding="utf-8") as f:
        text = f.read()
    for k, v in (("@INTERPRETER@", interpreter), ("@LIB@", lib), ("@BASE@", base),
                 ("@HOME@", home), ("@PATH@", path)):
        text = text.replace(k, escape(v))
    return text.rstrip("\n")


QUESTIONS = {"get": get, "property-state": property_state, "profile-for-command": profile_for_command,
             "daemons": daemons, "daemon-names": daemon_names, "selftest-fresh": selftest_fresh,
             "runtime-for": runtime_for, "agent-state": agent_state,
             "bound-agents": bound_agents, "selftest-kind": selftest_kind, "json-env": json_env,
             "plist": plist}


def main(argv):
    if not argv or argv[0] not in QUESTIONS:
        sys.stderr.write("usage: installjson %s …\n" % "|".join(QUESTIONS))
        return 2
    try:
        out = QUESTIONS[argv[0]](*argv[1:])
    except (ValueError, OSError, KeyError, TypeError) as e:
        sys.stderr.write("installjson %s: %s\n" % (argv[0], e))
        return 1
    if out:
        print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
