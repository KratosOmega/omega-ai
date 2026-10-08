#!/bin/sh
# studio-event: one versioned, escaped JSON line per call (spec AC28-29, R16).
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"
EV="$REPO_ROOT/studios/game-dev/bin/studio-event"
TMP="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/studio_event_test.XXXXXX")" && pwd -P)"
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
R="$TMP/overnight-demo-20261003-210400"
fresh() { rm -rf "$R"; mkdir -p "$R"; }
# field_len KEY — the character count of the last line's string field KEY
# (the field holds no escaped quote).
field_len() {
  tail -n 1 "$R/events.jsonl" | sed -n "s/.*\"$1\":\"\([^\"]*\)\".*/\1/p" \
    | LC_ALL=C tr -d '\200-\277\n' | wc -c | tr -d ' '
}
# utf8_locale — an installed UTF-8 locale name, empty when none.
utf8_locale() { locale -a 2>/dev/null | grep -iE '^(en_US|C)\.utf-?8$' | head -n 1; }

test_event_line_shape() {
  fresh
  assert_status 0 "a line is written" -- sh "$EV" "$R" run_started mode=single max_lanes:=1 hold_minutes:=0
  assert_contains "$R/events.jsonl" '^{"v":1,"ts":"[0-9-]*T[0-9:]*Z","run":"overnight-demo-20261003-210400","event":"run_started","mode":"single","max_lanes":1,"hold_minutes":0}$' "v, ts, run, event, then the fields in order"
  sh "$EV" "$R/" story_listed story=- chain:=1 'depends[]='
  assert_eq 2 "$(wc -l < "$R/events.jsonl" | tr -d ' ')" "a second call appends (a trailing / on RUN_DIR is fine)"
  assert_contains "$R/events.jsonl" '"event":"story_listed","story":"-","chain":1,"depends":\[\]}$' "an empty array is []"
}
test_event_escaping() {
  fresh
  nl='
'
  sh "$EV" "$R" story_state story=S1 state=held "why=a\"b\\c${nl}d	e$(printf '\001')f" until=2026-10-03T21:04:00Z
  assert_contains "$R/events.jsonl" '"why":"a\\"b\\\\c\\nd\\tef","until":"2026-10-03T21:04:00Z"}$' "quote, backslash, newline, tab escaped; \\001 dropped"
  if command -v jq >/dev/null 2>&1; then
    assert_eq "a\"b\\c${nl}d	ef" "$(tail -n 1 "$R/events.jsonl" | jq -r .why)" "the line is valid JSON and round-trips"
  fi
}
test_event_backslash_portable() {
  for posix in 1 ""; do
    fresh
    if [ -n "$posix" ]; then
      POSIXLY_CORRECT=1 sh "$EV" "$R" story_state story=S1 'why=a\b"c' 'tail=x\'
    else
      sh "$EV" "$R" story_state story=S1 'why=a\b"c' 'tail=x\'
    fi
    assert_contains "$R/events.jsonl" '"why":"a\\\\b\\"c","tail":"x\\\\"}$' "each backslash is written as two (POSIXLY_CORRECT=${posix:-unset})"
  done
}
test_event_cut_500() {
  fresh
  sh "$EV" "$R" story_state story=S1 state=stopped "why=$(printf '%600s' '' | tr ' ' b)"
  assert_eq 500 "$(field_len why)" "a string field is cut to 500 characters"
}
test_event_utf8_cut() {
  a499="$(printf '%499s' '' | tr ' ' a)"
  for loc in "" "$(utf8_locale)"; do
    fresh
    if [ -n "$loc" ]; then ( LC_ALL="$loc"; export LC_ALL; sh "$EV" "$R" story_state "why=${a499}—tail" )
    else sh "$EV" "$R" story_state "why=${a499}—tail"; fi
    assert_eq 1 "$(grep -cF "\"why\":\"${a499}—\"" "$R/events.jsonl")" "cut after the 500th character, the em dash whole (locale '${loc:-default}')"
  done
  fresh
  e300="$(printf '%300s' '' | sed 's/ /é/g')"
  sh "$EV" "$R" story_state "why=$e300"
  assert_eq 1 "$(grep -cF "\"why\":\"$e300\"" "$R/events.jsonl")" "300 two-byte characters are not cut"
}
test_event_line_cap_4k() {
  fresh
  big="$(printf '%450s' '' | tr ' ' c)"
  sh "$EV" "$R" story_state fa="$big" fb="$big" fc="$big" fd="$big" fe="$big" ff="$big" fg="$big" fh="$big" fi="$big" fj="$big"
  assert_eq 1 "$(awk 'length($0) <= 4096' "$R/events.jsonl" | wc -l | tr -d ' ')" "the line is at most 4096 bytes"
  assert_contains "$R/events.jsonl" ',"cut":true}$' "a capped line says cut"
  assert_contains "$R/events.jsonl" '"fa":"ccc' "the first fields are kept"
  assert_not_contains "$R/events.jsonl" '"fj":' "the last fields are dropped"
}
test_event_numbers_null_arrays() {
  fresh
  sh "$EV" "$R" unit_ended story=- usd:=1.25 n:=unknown e:= big:=1e3 neg:=-2 'depends[]=A,B'
  assert_contains "$R/events.jsonl" '"usd":1.25,"n":null,"e":null,"big":1e3,"neg":-2,"depends":\["A","B"\]}$' "numbers, null for a non-number, string arrays"
}
test_event_usage() {
  fresh
  assert_status 2 "no arguments" -- sh "$EV"
  assert_status 2 "no event" -- sh "$EV" "$R"
  assert_status 2 "an event outside [a-z_]" -- sh "$EV" "$R" Bad-Name
  assert_status 2 "a digit in the event" -- sh "$EV" "$R" run2
  assert_status 2 "a field with no key" -- sh "$EV" "$R" ok =x
  assert_status 2 "an upper-case key" -- sh "$EV" "$R" ok Key=x
  assert_status 2 "a field with no =" -- sh "$EV" "$R" ok noeq
  assert_status 2 "a [] key with a : too" -- sh "$EV" "$R" ok 'a[]:=1'
  assert_status 2 "a digit in a key" -- sh "$EV" "$R" ok a1=x
  assert_status 2 "a bracket inside a key" -- sh "$EV" "$R" ok 'a[b]=x'
  assert_missing "$R/events.jsonl" "bad usage writes nothing"
  assert_status 0 "a key may start with _" -- sh "$EV" "$R" ok _k=x _n:=1 '_a[]=p'
  assert_contains "$R/events.jsonl" '"_k":"x","_n":1,"_a":\["p"\]}$' "and the line carries it"
  assert_status 0 "a value may hold = and []=" -- sh "$EV" "$R" ok 'v=a[]=b=c'
  rm -f "$R/events.jsonl"
  assert_status 1 "a missing run dir" -- sh "$EV" "$R/nope" ok
  sh "$EV" "$R/nope" ok 2> "$TMP/ev.err"
  assert_contains "$TMP/ev.err" "^studio-event: no run dir " "a missing run dir is named on stderr"
  if [ "$(id -u)" != 0 ]; then
    chmod 555 "$R"
    assert_status 1 "an unwritable run dir" -- sh "$EV" "$R" ok
    sh "$EV" "$R" ok 2> "$TMP/ev.err"
    assert_eq 1 "$(wc -l < "$TMP/ev.err" | tr -d ' ')" "a failed write prints one stderr line (R27)"
    assert_contains "$TMP/ev.err" "^studio-event: cannot write " "and it names the write"
    chmod 755 "$R"
  fi
}
test_event_minimal_path() {
  fresh
  mkdir -p "$TMP/mini"
  for u in sh date awk; do ln -sf "$(command -v "$u")" "$TMP/mini/$u"; done
  assert_status 0 "only sh, date and awk on PATH" -- env PATH="$TMP/mini" sh "$EV" "$R" ok a=b
  assert_contains "$R/events.jsonl" '"event":"ok","a":"b"}$' "and the line is written"
}

run_tests test_event_line_shape test_event_escaping test_event_backslash_portable test_event_cut_500 test_event_utf8_cut \
  test_event_line_cap_4k test_event_numbers_null_arrays test_event_usage test_event_minimal_path
