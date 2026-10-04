#!/usr/bin/python3
"""P6 check, run by launchd (see p6-launchd.sh); copied to $RES/p6/.

Usage: p6_check.py PROJECT [LABEL]
Lists PROJECT/.studio and writes out-LABEL.json next to this file (LABEL
defaults to "run"): ok, error, sys.executable, its realpath. Reads nothing
else and touches no network.
"""
import json
import os
import sys


def main():
    project = sys.argv[1]
    label = sys.argv[2] if len(sys.argv) > 2 else 'run'
    result = {
        'ok': False,
        'error': '',
        'executable': sys.executable,
        'realpath': os.path.realpath(sys.executable),
        'entries': [],
    }
    try:
        result['entries'] = sorted(os.listdir(os.path.join(project, '.studio')))
        result['ok'] = True
    except OSError as e:
        result['error'] = '%s: %s' % (type(e).__name__, e)
    here = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(here, 'out-%s.json' % label), 'w') as f:
        json.dump(result, f, indent=2)
        f.write('\n')


if __name__ == '__main__':
    main()
