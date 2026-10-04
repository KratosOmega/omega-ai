"""multica-bridge service: poll loop, lock, backoff, auth, self-test, status (#28, R5)."""
from __future__ import annotations

import logging
import os
import subprocess
import sys
import time
import traceback
from logging.handlers import RotatingFileHandler

from bridge import config, mirror, state, studio
from bridge import multica_cli as mc

BACKOFF_CAP = 300
AUTH_RETRY = 300
SELFTEST_INTERVAL = 600
DELAYED_NOTE_AFTER = 300
OSASCRIPT = os.environ.get("OMEGA_MULTICA_OSASCRIPT", "/usr/bin/osascript")   # test hook (R46)
USAGE = "usage: multica-bridge run|once|selftest|status"


def next_delay(poll, failures):
    return min(poll * (2 ** failures), BACKOFF_CAP) if failures else poll


def _set_secrets(log, secrets):
    for h in log.handlers:
        for f in h.filters:
            if isinstance(f, mc.RedactFilter):
                f.secrets = [s for s in secrets if s]


def setup_logging(paths):
    os.makedirs(paths.base, mode=0o700, exist_ok=True)
    os.makedirs(paths.cli_home, mode=0o700, exist_ok=True)
    log = logging.getLogger("multica-bridge")
    log.setLevel(logging.INFO)
    log.propagate = False
    # One handler per state dir (tests reuse the global logger across dirs). RotatingFileHandler is not
    # multi-process safe: a `once` beside `run` can rotate under the other, which keeps writing to bridge.log.1.
    for h in list(log.handlers):
        if isinstance(h, RotatingFileHandler) and h.baseFilename != os.path.abspath(paths.log):
            log.removeHandler(h)
            h.close()
    if not any(isinstance(h, RotatingFileHandler) for h in log.handlers):
        h = RotatingFileHandler(paths.log, maxBytes=1_000_000, backupCount=5, encoding="utf-8")
        h.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
        h.addFilter(mc.RedactFilter([]))
        log.addHandler(h)
    return log


class Service:
    def __init__(self, home, log=None):
        self.home = home
        self.paths = state.Paths(home)
        self.log = log or setup_logging(self.paths)
        self.secrets = []
        self.st = {}
        self._load()

    def _load(self):
        """(Re)read status.json: a `once` or a second `run` may have written it since."""
        disk = state.read_json(self.paths.status, None)
        if isinstance(disk, dict):
            self.st = disk
        for k, v in (("last_ok_poll", None), ("cli_version", None), ("failures", 0), ("outage_since", None),
                     ("notified", []), ("auth_until", 0)):
            self.st.setdefault(k, v)

    def _learn(self, token):
        self.secrets = [token]
        _set_secrets(self.log, self.secrets)

    def _save(self):
        os.makedirs(self.paths.base, mode=0o700, exist_ok=True)
        state.atomic_write_json(self.paths.status, self.st)

    def notify(self, kind, text):
        if kind in self.st["notified"]:
            return                                        # once per outage (R30)
        self.st["notified"].append(kind)
        safe = text.replace("\\", "").replace('"', "'")
        try:
            subprocess.run([OSASCRIPT, "-e", 'display notification "%s" with title "omega multica bridge"' % safe],
                           stdin=subprocess.DEVNULL, capture_output=True, timeout=10)
        except (OSError, subprocess.TimeoutExpired) as e:
            self.log.warning("notification failed: %s", e)

    def poll_once(self):
        self._load()
        try:
            cfg = config.load(self.paths.config)
        except config.ConfigError as e:
            self.log.error("%s", e)
            self.st["failures"] += 1                      # back off like an outage, without an outage span
            try:
                self._save()
            except OSError:
                pass
            return "config"
        now = time.time()
        if self.st["auth_until"] > now:
            self.log.info("waiting for the token retry until %s", state.iso_now(self.st["auth_until"]))
            return "auth"
        try:
            token = mc.read_token()
        except mc.KeychainError as e:                     # AC28: never a call without a token
            self.log.error("Keychain (%s): %s", e.kind, e)
            self.notify("keychain", "omega bridge: cannot read its Multica token from the Keychain")
            self.st["failures"] += 1
            try:
                self._save()
            except OSError:
                pass
            return "keychain"
        self._learn(token)
        ctx = state.Ctx(cfg, self.paths, mc.Cli(cfg, token, self.paths.cli_home, self.log), self.log, self.notify)
        try:
            if not self.st["cli_version"]:
                self.st["cli_version"] = ctx.cli.version().get("version")
            mirror.poll_runs(ctx)
            outage = self.st["outage_since"]
            if outage and now - outage > DELAYED_NOTE_AFTER:
                self._delayed_notes(ctx, outage, int(round((now - outage) / 60.0)))
        except mc.AuthError as e:
            self.log.error("Multica rejected the token: %s", e)
            self.notify("auth", "omega bridge: Multica rejected its token - run install.sh --new-token")
            self.st["auth_until"] = now + AUTH_RETRY
            self._save()
            return "auth"
        except mc.TransientError as e:
            self.log.warning("Multica unreachable (%d failed polls): %s", self.st["failures"] + 1, e)
            self.st["failures"] += 1
            self.st["outage_since"] = self.st["outage_since"] or now
            self._save()
            return "transient"
        self.st.update(failures=0, outage_since=None, notified=[], auth_until=0,
                       last_ok_poll=state.iso_now(time.time()))
        self._save()
        return "ok"

    def _delayed_notes(self, ctx, outage, n):
        for key in state.tracked_keys(self.paths):
            st = state.load_run(self.paths, key)
            if not st or not st.get("run_issue") or st.get("delayed_for") == outage:
                continue
            mirror.note(ctx, st, "studio: board was delayed %d min" % n)   # a write failure is logged, not raised
            st["delayed_for"] = outage
            state.save_run(self.paths, st)

    # ----- self-test (R31) ----------------------------------------------------

    def selftest(self):
        res = {"ok": False, "error": None, "kind": None, "interpreter": os.path.realpath(sys.executable),
               "checked_at": state.iso_now(time.time()), "checked": []}
        path = None
        try:
            cfg = config.load(self.paths.config)
            path = cfg.studio_overnight
            with open(path, "rb") as f:
                f.read(1)
            res["checked"].append(path)
            roots = list(cfg.roots) or [e["root"] for e in studio.read_registry(self.home)
                                        if studio.runner_live(e["pid"])]
            for root in roots:
                path = os.path.join(root, ".studio")
                os.listdir(path)
                res["checked"].append(path)
            for root in cfg.selftest_roots:               # install's --project: its run state must be readable too
                for path in (root, os.path.join(root, ".studio")):
                    if path == root or os.path.isdir(path):
                        os.listdir(path)
                        res["checked"].append(path)
            path = None
            token = mc.read_token()
            self._learn(token)
            cli = mc.Cli(cfg, token, self.paths.cli_home, self.log)
            prof = cli.profile()
            if prof.get("id") != cfg.operator_member_id:
                raise mc.AuthError("the token belongs to member %s, not the configured operator %s"
                                   % (prof.get("id"), cfg.operator_member_id))
            res["ok"] = True
            self._token_good(cli)
        except PermissionError as e:
            res["kind"], res["error"] = "file-access", "cannot read %s with %s: %s - grant it file access" % (
                path, res["interpreter"], e.strerror or e)
        except FileNotFoundError as e:
            res["kind"], res["error"] = "missing", "%s: not found" % (e.filename or path)
        except config.ConfigError as e:
            res["kind"], res["error"] = "config", str(e)
        except mc.KeychainError as e:
            res["kind"], res["error"] = "keychain", str(e)
        except mc.AuthError as e:
            res["kind"], res["error"] = "token", str(e)
        except mc.TransientError as e:
            res["kind"], res["error"] = "network", str(e)
        except mc.CliError as e:
            res["kind"], res["error"] = "cli", str(e)
        except OSError as e:
            res["kind"], res["error"] = "missing", "%s: %s" % (e.filename or path, e.strerror or e)
        if res["error"]:
            res["error"] = mc.redact(res["error"], self.secrets)      # AC29: a CLI error may echo the token
        if not res["ok"]:
            self.log.error("self-test failed (%s): %s", res["kind"], res["error"])
        self._write_selftest(res)
        return res

    def _token_good(self, cli):
        """A passing self-test proves the token: end the auth wait (a new token needs no 300 s idle) and
        refresh the CLI version, which `status` shows."""
        try:
            version = cli.version().get("version")        # the slow call runs before the lock is taken
        except mc.CliError:
            version = None
        with state.bridge_lock(self.paths, blocking=True):
            self._load()
            self.st["auth_until"] = 0     # not "notified": only an ok poll re-arms the auth notice (AC28)
            self.st["cli_version"] = version or self.st["cli_version"]
            try:
                self._save()
            except OSError as e:
                self.log.warning("cannot save status.json: %s", e)

    def _write_selftest(self, res):
        os.makedirs(self.paths.base, mode=0o700, exist_ok=True)
        state.atomic_write_json(self.paths.selftest, res)

    # ----- status (reads only) ------------------------------------------------

    def status_text(self):
        lines = ["cli: %s" % (self.st["cli_version"] or "unknown")]
        t = state.read_json(self.paths.selftest, None)
        if not t:
            lines.append("selftest: not run")
        elif t.get("ok"):
            lines.append("selftest: ok (%s)" % t.get("checked_at"))
        else:
            lines.append("selftest: %s: %s (%s)" % (t.get("kind"), mc.redact(t.get("error")), t.get("checked_at")))
        lines.append("last poll: %s" % (self.st["last_ok_poll"] or "never"))
        keys = state.tracked_keys(self.paths)
        for key in keys:
            st = state.load_run(self.paths, key)
            if not st:
                continue
            try:
                n = "%d unread events" % studio.unread_count(os.path.join(st["run_dir"], "events.jsonl"),
                                                              st.get("offset", 0), st.get("log_id"))
            except (OSError, studio.LogShrunk) as e:
                why = e.strerror if isinstance(e, OSError) and e.strerror else e
                n = "events unreadable (%s)" % why
            if st.get("poll_fails"):
                n += ", poll failing (%d): %s" % (st["poll_fails"], mc.redact(st.get("poll_error") or "unknown"))
            lines.append("run %s: %s, %s" % (key, st.get("run_issue") or "no Run issue yet", n))
        if not keys:
            lines.append("no tracked runs")
        return "\n".join(lines)

    # ----- the loop -----------------------------------------------------------

    def _poll_seconds(self):
        try:
            return config.load(self.paths.config).poll_seconds
        except config.ConfigError:
            return 15

    def run(self, sleep=None, monotonic=None):
        sleep, monotonic = sleep or time.sleep, monotonic or time.monotonic     # injectable for tests
        last_selftest = None
        while True:
            if last_selftest is None or monotonic() - last_selftest >= SELFTEST_INTERVAL:
                last_selftest = monotonic()
                try:
                    self.selftest()
                except Exception:
                    self.log.error("self-test crashed:\n%s", traceback.format_exc())
            try:
                with state.bridge_lock(self.paths, blocking=True):
                    result = self.poll_once()
            except Exception:
                self.log.error("unexpected error in a poll:\n%s", traceback.format_exc())
                self.st["failures"] += 1
                self.st["outage_since"] = self.st["outage_since"] or time.time()
                try:
                    self._save()
                except OSError:
                    pass
                result = "error"
            sleep(AUTH_RETRY if result == "auth" else next_delay(self._poll_seconds(), self.st["failures"]))


def main(argv):
    if len(argv) != 1 or argv[0] not in ("run", "once", "selftest", "status"):
        sys.stderr.write(USAGE + "\n")
        return 2
    cmd = argv[0]
    home = os.path.expanduser("~")
    if cmd == "status":
        quiet = logging.getLogger("multica-bridge-status")
        quiet.addHandler(logging.NullHandler())
        quiet.propagate = False
        print(Service(home, log=quiet).status_text())
        return 0
    if cmd == "run":
        Service(home).run()
        return 0
    svc = Service(home)
    if cmd == "selftest":
        import json
        res = svc.selftest()
        print(json.dumps(res, indent=2, sort_keys=True))
        return 0 if res["ok"] else 1
    try:
        with state.bridge_lock(svc.paths, blocking=False):
            result = svc.poll_once()
    except state.LockBusy:
        sys.stderr.write("multica-bridge: another bridge holds the lock\n")
        return 1
    except Exception:
        sys.stderr.write(mc.redact(traceback.format_exc(), svc.secrets))     # AC29
        return 1
    return 1 if result == "config" else 0
