#!/usr/bin/python3
"""pj.py - JSON helper for the #28 open probes (Python 3.9, standard library).

Reads JSON on stdin (except `epoch`).
  get PATH               value at a dotted path (identifier, 0.id, issues.0.id);
                         dict/list print as JSON; exit 1 when absent
  count                  rows in a list, or in the first list value of an object
  rows FIELD             FIELD of each row, one per line
  keys                   top-level keys, one per line (or <list>)
  first                  the first row, as JSON (exit 1 when none)
  where FIELD VALUE      rows whose FIELD equals VALUE, as a JSON list
  startswith FIELD TEXT  number of rows whose string FIELD starts with TEXT
  contains FIELD TEXT    number of rows whose string FIELD contains TEXT
  find FIELD VALUE OUT   OUT of the first row whose FIELD equals VALUE
  redact                 the JSON made safe to publish (see below)
  epoch VALUE            ISO-8601 timestamp to Unix seconds (no stdin)

redact: strings matching (^|[^A-Za-z0-9])(mul|mat)_[A-Za-z0-9_-]+ lose the
token; e-mail addresses become operator@example.com; /Users/<name> becomes
/Users/operator; the local host name becomes host.example. By key: `email` ->
operator@example.com, `custom_env` -> {}, `avatar_url` -> "", any host/hostname
field -> host.example, and a member/user `name` -> Operator.
"""
import calendar
import json
import re
import socket
import sys
import time

TOKEN = re.compile(r'(^|[^A-Za-z0-9])(mul|mat)_[A-Za-z0-9_-]+', re.M)
EMAIL = re.compile(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]+')
HOME = re.compile(r'/Users/[^/\s"\'`]+')
HOSTKEY = re.compile(r'(^|_)host')
PERSON_KEYS = {'user', 'member', 'owner', 'creator', 'author', 'operator',
               'created_by', 'updated_by'}
TYPE_KEYS = ('type', 'author_type', 'creator_type', 'owner_type', 'kind')


def die(msg, code=2):
    sys.stderr.write('pj: %s\n' % msg)
    sys.exit(code)


def emit(v):
    if isinstance(v, str):
        print(v)
    elif isinstance(v, (dict, list, bool)) or v is None:
        print(json.dumps(v, ensure_ascii=False))
    else:
        print(v)


def load():
    try:
        return json.load(sys.stdin)
    except ValueError as e:
        die('stdin is not JSON: %s' % e)


def rows_of(data):
    if isinstance(data, list):
        return data
    if isinstance(data, dict):
        for v in data.values():
            if isinstance(v, list):
                return v
    return []


def dig(data, path):
    cur = data
    for part in path.split('.'):
        if isinstance(cur, list):
            try:
                cur = cur[int(part)]
            except (ValueError, IndexError):
                raise KeyError(path)
        elif isinstance(cur, dict) and part in cur:
            cur = cur[part]
        else:
            raise KeyError(path)
    return cur


def _hostnames():
    names = set()
    try:
        full = socket.gethostname()
        names.add(full)
        names.add(full.split('.')[0])
    except OSError:
        pass
    return [n for n in names if len(n) >= 3]


HOSTNAMES = _hostnames()


def scrub_str(s):
    s = TOKEN.sub(r'\1<token>', s)
    s = EMAIL.sub('operator@example.com', s)
    s = HOME.sub('/Users/operator', s)
    for h in HOSTNAMES:
        s = re.sub(re.escape(h), 'host.example', s, flags=re.I)
    return s


def is_person(obj, parent_key):
    if parent_key and parent_key.lower() in PERSON_KEYS:
        return True
    if 'email' in obj:
        return True
    return any(obj.get(t) == 'member' for t in TYPE_KEYS)


def walk(obj, parent_key=None):
    if isinstance(obj, dict):
        person = is_person(obj, parent_key)
        out = {}
        for k, v in obj.items():
            lk = k.lower()
            if lk == 'email' and isinstance(v, str):
                out[k] = 'operator@example.com' if v else v
            elif lk == 'custom_env':
                out[k] = {}
            elif lk == 'avatar_url':
                out[k] = ''
            elif HOSTKEY.search(lk) and isinstance(v, str):
                out[k] = 'host.example' if v else v
            elif lk == 'name' and person and isinstance(v, str):
                out[k] = 'Operator'
            else:
                out[k] = walk(v, k)
        return out
    if isinstance(obj, list):
        return [walk(x, parent_key) for x in obj]
    if isinstance(obj, str):
        return scrub_str(obj)
    return obj


def epoch(value):
    m = re.match(r'^(\d{4}-\d\d-\d\d)[T ](\d\d:\d\d:\d\d)(\.\d+)?(Z|[+-]\d\d:?\d\d)?$', value)
    if not m:
        die('unrecognised timestamp: %s' % value)
    base = calendar.timegm(time.strptime(m.group(1) + ' ' + m.group(2), '%Y-%m-%d %H:%M:%S'))
    tz = m.group(4)
    if tz and tz != 'Z':
        sign = 1 if tz[0] == '+' else -1
        digits = tz[1:].replace(':', '')
        base -= sign * (int(digits[:2]) * 3600 + int(digits[2:]) * 60)
    return base


def main(argv):
    if len(argv) < 2:
        die('usage: pj.py get|count|rows|keys|first|where|startswith|contains|find|redact|epoch ...')
    cmd, args = argv[1], argv[2:]
    if cmd == 'epoch':
        if len(args) != 1:
            die('usage: epoch VALUE')
        print(epoch(args[0]))
        return 0
    data = load()
    if cmd == 'get':
        try:
            emit(dig(data, args[0]))
        except KeyError:
            return 1
    elif cmd == 'count':
        print(len(rows_of(data)))
    elif cmd == 'rows':
        for r in rows_of(data):
            if isinstance(r, dict) and args[0] in r:
                emit(r[args[0]])
    elif cmd == 'keys':
        if isinstance(data, dict):
            for k in data:
                print(k)
        else:
            print('<list>')
    elif cmd == 'first':
        rs = rows_of(data)
        if not rs:
            return 1
        emit(rs[0])
    elif cmd == 'where':
        emit([r for r in rows_of(data) if isinstance(r, dict) and str(r.get(args[0])) == args[1]])
    elif cmd == 'startswith':
        print(sum(1 for r in rows_of(data) if isinstance(r, dict)
                  and isinstance(r.get(args[0]), str) and r[args[0]].lstrip().startswith(args[1])))
    elif cmd == 'contains':
        print(sum(1 for r in rows_of(data) if isinstance(r, dict)
                  and isinstance(r.get(args[0]), str) and args[1] in r[args[0]]))
    elif cmd == 'find':
        for r in rows_of(data):
            if isinstance(r, dict) and str(r.get(args[0])) == args[1] and args[2] in r:
                emit(r[args[2]])
                return 0
        return 1
    elif cmd == 'redact':
        sys.stdout.write(json.dumps(walk(data), indent=2, ensure_ascii=False) + '\n')
    else:
        die('unknown command: %s' % cmd)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
