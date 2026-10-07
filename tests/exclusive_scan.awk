# excl-scan.awk — mechanical R5 scan. For each test_* function body, flag:
#  a: an elapsed upper bound (date +%s arithmetic compared with -lt/-le, or "under N s"/"well under" text)
#  b: a signal sent to a live process the test started (kill -INT/-TERM/-HUP/-QUIT/-s)
#  d: a short window: a literal sleep/--seconds/*_SECONDS=/*_WAIT=/*_MINUTES-free value 1..6 that code under test or a stub must beat
# Output: suite<TAB>test<TAB>flags<TAB>first evidence line numbers
function flush() {
  if (name != "" && flags != "") printf "%s\t%s\t%s\t%s\n", suite, name, flags, ev
  name = ""; flags = ""; ev = ""
}
function flag(f, why) {
  if (index(flags, f) == 0) flags = flags f
  if (length(ev) < 160) ev = ev (ev == "" ? "" : " ") f ":" FNR
}
FNR == 1 { flush(); suite = FILENAME; sub(/.*\//, "", suite); sub(/\.sh$/, "", suite) }
/^test_[A-Za-z0-9_]*\(\) *\{/ { flush(); name = $0; sub(/\(.*/, "", name); next }
/^[A-Za-z_][A-Za-z0-9_]*\(\) *\{/ { flush(); next }
name == "" { next }
{
  line = $0
  if (line ~ /date \+%s/ && line ~ /-l[te] [0-9]/) flag("a")
  if (line ~ /(well )?(under|within) [0-9.]+ ?s|< ?[0-9]+ ?s|<= ?[0-9]+ ?s/) flag("a")
  if (line ~ /kill -(INT|TERM|HUP|QUIT|s )/) flag("b")
  if (line ~ /(^|[^0-9.])sleep [1-6]([^0-9]|$)/ && line ~ /printf|SCEN|scenario|STUB|_CMD|sh -c/) flag("d")
  if (line ~ /--seconds [1-6]([^0-9]|$)/) flag("d")
  if (line ~ /_(SECONDS|WAIT|TIMEOUT)=[1-6]([^0-9]|$)/) flag("d")
}
END { flush() }
