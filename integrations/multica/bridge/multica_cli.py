"""The only door to Multica: a thin adapter over the `multica` CLI (#28)."""
from __future__ import annotations

import html
import json
import logging
import os
import pwd
import re
import subprocess

CLI_TIMEOUT = 60
RUN_ISSUES_MAX_PAGES = 50
PREFIX = "studio: "
KEYCHAIN_SERVICE = "omega-multica-bridge"
SECURITY = os.environ.get("OMEGA_MULTICA_SECURITY", "/usr/bin/security")   # test hook (R46)
_ENVELOPE_KEYS = ("issues", "comments", "runs", "data", "items", "rows")
# `mention:` and the escaped forms a link destination may decode (`mention\:`, `mention&#58;`); the
# `no-` lookbehind keeps sanitize idempotent. Whether Multica decodes them is unknown, so be safe.
_MENTION = re.compile(r"(?i)(?<!no-)mention(?::|(?=[\\&]))")
_TICKS = re.compile(r"`{3,}|~{3,}")
# A status code is a code only when it is not part of an identifier such as OMEG-401.
_AUTH = re.compile(r"(?i)(?<![\w-])401(?![\w-])|unauthori[sz]ed|invalid (?:api )?token|token (?:is )?(?:expired|revoked|invalid)"
                   r"|not authenticated|not logged in|not signed in|session has expired|multica login")
_NOT_FOUND = re.compile(r"(?i)(?<![\w-])404(?![\w-])|not found|no such issue|\barchived\b|\bdeleted\b")
_TRANSIENT = re.compile(r"(?i)(?<![\w-])429(?![\w-])|too many requests|rate.?limit|(?<![\w-])50[0-4](?![\w-])|bad gateway|service unavailable"
                        r"|gateway timeout|internal server error|timed? ?out|timeout|connection refused"
                        r"|connection reset|no such host|network is unreachable|unexpected eof|temporar"
                        r"|retryable|dial tcp|could not connect")
# A leading boundary keeps `format_x` from matching (D7).
_TOKEN_RE = re.compile(r"(^|[^A-Za-z0-9])(?:mul|mat)_[A-Za-z0-9_-]{6,}")


class CliError(Exception):
    def __init__(self, message: str, stderr: str = "", code: int | None = None):
        super().__init__(message)
        self.stderr, self.code = stderr, code


class TransientError(CliError):
    pass


class AuthError(CliError):
    pass


class PermanentError(CliError):
    pass


class NotFoundError(PermanentError):
    pass


class ForbiddenWrite(Exception):
    pass


class KeychainError(Exception):
    def __init__(self, kind: str, message: str):
        super().__init__(message)
        self.kind = kind


def sanitize(text: str) -> str:
    """AC18: no mention can form, and no html or mermaid fence can open."""
    decoded = text                          # `&#109;ention://` may be decoded by the renderer: neutralize a decoded copy
    for _ in range(8):                      # to a fixed point: `&amp;#109;` must not stop at `&#109;`
        step = html.unescape(decoded)
        if step == decoded:
            break
        decoded = step
    if decoded != text and (_MENTION.search(decoded) or "@" in decoded):
        text = decoded
    text = _MENTION.sub(lambda m: "no-" + m.group(0), text)
    text = text.replace("@", "＠")
    return _TICKS.sub(lambda m: "​".join(m.group(0)), text)


def classify(code: int, stderr: str, timed_out: bool = False) -> CliError:
    first = (stderr.strip().splitlines() or [""])[0][:300]
    if timed_out:
        return TransientError("timed out after %d s" % CLI_TIMEOUT, stderr, code)
    if _AUTH.search(stderr):
        return AuthError(first, stderr, code)
    if _NOT_FOUND.search(stderr):
        return NotFoundError(first, stderr, code)
    if _TRANSIENT.search(stderr):
        return TransientError(first, stderr, code)
    if code == 3:           # the recorded exit codes, for text we do not recognise (2 is ambiguous: usage)
        return AuthError(first or "exit 3", stderr, code)
    if code == 4:
        return NotFoundError(first or "exit 4", stderr, code)
    return PermanentError(first or "exit %s" % code, stderr, code)


def rows(obj) -> list:
    if isinstance(obj, list):
        return obj
    if isinstance(obj, dict):
        for k in _ENVELOPE_KEYS:
            if isinstance(obj.get(k), list):
                return obj[k]
    return []


def _dedupe(items: list) -> list:
    """A server that ignores --offset repeats rows: keep the first of each id (rows without an id stay)."""
    seen, out = set(), []
    for r in items:
        i = r.get("id") if isinstance(r, dict) else None
        if i is not None:
            if i in seen:
                continue
            seen.add(i)
        out.append(r)
    return out


def read_token(account: str | None = None) -> str:
    account = account or pwd.getpwuid(os.getuid()).pw_name      # `id -un` (R11)
    try:
        r = subprocess.run([SECURITY, "find-generic-password", "-s", KEYCHAIN_SERVICE, "-a", account, "-w"],
                           stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise KeychainError("error", "cannot read the Keychain: %s" % e)
    if r.returncode == 44:
        raise KeychainError("missing", "no Keychain item %s for %s - run install.sh" % (KEYCHAIN_SERVICE, account))
    if r.returncode != 0:
        raise KeychainError("locked", "the Keychain refused (exit %d) - is it locked?" % r.returncode)
    token = r.stdout.strip()
    if not token:
        raise KeychainError("empty", "the Keychain item is empty - run install.sh --new-token")
    return token


def redact(text, secrets=()):
    """AC29: the explicit secrets, then anything shaped like a Multica token."""
    text = str(text)
    for s in secrets:
        if s:
            text = text.replace(s, "<token>")
    return _TOKEN_RE.sub(lambda m: m.group(1) + "<token>", text)


class RedactFilter(logging.Filter):
    """AC29: no token value reaches a log handler."""

    def __init__(self, secrets: list[str]):
        super().__init__()
        self.secrets = [s for s in secrets if s]

    def filter(self, record: logging.LogRecord) -> bool:
        record.msg, record.args = redact(record.getMessage(), self.secrets), None
        return True


class Cli:
    def __init__(self, cfg, token: str, cli_home: str, log: logging.Logger):
        self.cfg, self.token, self.cli_home, self.log = cfg, token, cli_home, log
        self.forbidden: set[str] = set()     # the request issue (AC17)

    def call(self, args: list[str], stdin: str | None = None, parse: bool = True):
        if not self.token:
            raise KeychainError("empty", "refusing to call the Multica CLI with an empty token")
        os.makedirs(self.cli_home, mode=0o700, exist_ok=True)
        argv = [self.cfg.cli] + list(args) + (["--output", "json"] if parse else [])
        env = {"MULTICA_TOKEN": self.token, "MULTICA_SERVER_URL": self.cfg.server_url,
               "MULTICA_WORKSPACE_ID": self.cfg.workspace_id, "HOME": self.cli_home, "PATH": "/usr/bin:/bin"}
        kw = {"input": stdin} if stdin is not None else {"stdin": subprocess.DEVNULL}
        try:
            r = subprocess.run(argv, capture_output=True, encoding="utf-8", errors="replace",
                               env=env, timeout=CLI_TIMEOUT, **kw)
        except subprocess.TimeoutExpired:
            raise classify(-1, "", timed_out=True)
        except OSError as e:
            raise PermanentError("cannot run %s: %s" % (self.cfg.cli, e))
        if r.stderr.strip():
            self.log.debug("multica %s: %s", " ".join(args[:3]), r.stderr.strip()[:500])
        if r.returncode != 0:
            raise classify(r.returncode, r.stderr)
        if not parse:
            return None
        try:
            return json.loads(r.stdout)
        except ValueError:
            raise PermanentError("output of multica %s is not JSON" % " ".join(args[:3]))

    # ----- reads ------------------------------------------------------------

    def version(self) -> dict:
        return self.call(["version"])

    def profile(self) -> dict:
        return self.call(["user", "profile", "get"])

    def run_issues(self, run_key: str) -> list[dict]:
        out, offset = [], 0
        for _ in range(RUN_ISSUES_MAX_PAGES):
            page = self.call(["issue", "list", "--property", "omega_run=" + run_key,
                              "--limit", "100", "--offset", str(offset)])
            got = rows(page)
            out.extend(got)
            if not (isinstance(page, dict) and page.get("has_more") and got):
                return _dedupe(out)
            offset += len(got)
            total = page.get("total")
            if isinstance(total, int) and offset >= total:       # a server that ignores --offset
                return _dedupe(out)
        raise PermanentError("issue list for run %s did not end after %d pages" % (run_key, RUN_ISSUES_MAX_PAGES))

    def find_issues(self, run_key: str, story: str | None) -> list[dict]:
        # P7c: the `__none__` filter works server-side.
        return rows(self.call(["issue", "list", "--property", "omega_run=" + run_key,
                               "--property", "omega_story=" + ("__none__" if story is None else story),
                               "--limit", "100"]))

    def assigned_issues(self, agent_id: str) -> list[dict]:
        return rows(self.call(["issue", "list", "--assignee-id", agent_id, "--sort", "created_at",
                               "--direction", "desc", "--limit", "20"]))

    def get_issue(self, ident: str) -> dict:
        return self.call(["issue", "get", ident])

    def issue_runs(self, ident: str) -> list[dict]:
        return rows(self.call(["issue", "runs", ident]))

    def list_comments(self, ident: str, since: str) -> list[dict]:
        # P7e: --since is inclusive; callers de-duplicate by comment id.
        return rows(self.call(["issue", "comment", "list", ident, "--since", since]))

    # ----- writes -----------------------------------------------------------

    def create_issue(self, title: str, description: str, parent: str | None, props: dict[str, str]) -> dict:
        args = ["issue", "create", "--title", self._clean(title), "--status", "todo", "--allow-duplicate",
                "--description-stdin"]
        if parent:
            args += ["--parent", parent]
        for k, v in props.items():
            args += ["--property", "%s=%s" % (k, v)]
        return self.call(args, stdin=self._clean(description))

    def _clean(self, text: str) -> str:
        return sanitize(redact(text, [self.token]))       # AC29: redact first; a sanitized token would no longer match

    clean = _clean                                        # public: the repost check compares against exactly what a post sends

    def _guard(self, ident: str) -> None:
        # AC17; identifiers compare case-insensitively. Callers add the UUID too once they know it.
        if ident.upper() in {f.upper() for f in self.forbidden}:
            raise ForbiddenWrite(ident)

    def set_status(self, ident: str, status: str) -> dict:
        self._guard(ident)
        return self.call(["issue", "status", ident, status, "--no-start"])

    def add_comment(self, ident: str, text: str, parent: str | None = None) -> dict:
        self._guard(ident)
        if not text.startswith(PREFIX):
            raise ValueError("a bridge comment must start with %r" % PREFIX)
        args = ["issue", "comment", "add", ident, "--content-stdin"]
        if parent:
            args += ["--parent", parent]
        return self.call(args, stdin=self._clean(text))
