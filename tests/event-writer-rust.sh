#!/usr/bin/env bash
# What writing one event does (hobnix/core#1336, ADR 0001): every row and exit code of `state-db.py emit`, written down as expected values.
# The same cases then run against the Rust writer of the core (`hobnix event-emit`), and both write seeded random events side by side. The
# binary: HOBNIX_BIN, else rust/target/debug|release/hobnix (build it in scripts/dev/rust-shell.nix); without one, or off Linux, only the
# python writer runs. No root, python3 only.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
command -v python3 >/dev/null || { echo "python3 missing: skipped"; exit 0; }
wp() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else echo "$1"; fi; }
export HS_PLAIN=1 HS_LANG=en HS_CALLER=test PYTHONUTF8=1
mkdir -p "$WORK/state" "$WORK/pe"
HS_STATE_DIR=$(wp "$WORK/state") HS_PKG_EVENTS_DIR=$(wp "$WORK/pe") HS_STATE_DB=$(wp "$WORK/state/state.db")
export HS_STATE_DIR HS_PKG_EVENTS_DIR HS_STATE_DB
unset HS_EVENT_KEEP HS_EVENT_DAYS HS_EVENT_EPHEMERAL_DAYS HS_EVENT_METRIC_DAYS
export HS_NOW=1000000000
SD=$SCRIPTS/state-db.py

printf 'pkg.rapp.loud\twarn\t-\tLoud\t-\ta loud one\t-\t-\t-\t-\taudit\n' > "$WORK/pe/rapp.tsv"
printf 'pkg.rapp.flash\tinfo\t-\tFlash\t-\ta flash\t-\t-\t-\t-\tephemeral\n' >> "$WORK/pe/rapp.tsv"
printf 'pkg.rapp.tick\tinfo\t-\tTick\t-\ta tick\t-\t-\t-\t-\tmetric\n' >> "$WORK/pe/rapp.tsv"

bin=${HOBNIX_BIN:-}
if [ -z "$bin" ] && [ "$(uname -s)" = Linux ]; then
  for b in "$ROOT/rust/target/debug/hobnix" "$ROOT/rust/target/release/hobnix"; do [ -x "$b" ] && { bin=$b; break; }; done
fi
[ -x "$bin" ] || bin=""
export HS_SCRIPTS=$SCRIPTS                  # where the Rust writer reads the kind lists
WRITER=python
writer_words() { if [ "$WRITER" = rust ]; then printf '%s\n' "$bin" event-emit; else printf '%s\n' python3 "$SD" emit; fi; }
emit() {                                    # the writer under test
  if [ "$WRITER" = rust ]; then "$bin" event-emit "$@"; else python3 "$SD" emit "$@"; fi
}
sql() { python3 -c 'import sqlite3,sys; sys.stdout.reconfigure(newline=chr(10)); c=sqlite3.connect(sys.argv[1]); r=c.execute(sys.argv[2]).fetchall(); c.commit(); print(chr(10).join("|".join(str(x) for x in row) for row in r))' "$HS_STATE_DB" "$1"; }
# a database as the schema owner makes it, with no event in it
reset() { rm -f "$WORK/state/state.db"*; python3 "$SD" forget nothing >/dev/null 2>&1; }
# one column of the newest row as a JSON value: control characters and non-ASCII stay visible, NULL is null
last() { python3 -c 'import json,sqlite3,sys; r=sqlite3.connect(sys.argv[1]).execute("SELECT %s FROM events ORDER BY id DESC LIMIT 1" % sys.argv[2]).fetchone(); print(json.dumps(r[0]) if r else "no row")' "$HS_STATE_DB" "$1" | tr -d '\r'; }
# stored <column>: the stored text itself, without JSON quoting
stored() { python3 -c 'import sqlite3,sys; sys.stdout.reconfigure(newline=""); v=sqlite3.connect(sys.argv[1]).execute("SELECT %s FROM events ORDER BY id DESC LIMIT 1" % sys.argv[2]).fetchone()[0]; sys.stdout.write("NULL" if v is None else v)' "$HS_STATE_DB" "$1"; }
rows() { sql 'SELECT count(*) FROM events'; }

cases() {
echo "== the $WRITER writer"
echo "-- one event, every column"
reset
emit storage.new S1 "first" >/dev/null; rc=$?
check_eq "exit 0" "0" "$rc"
check_eq "the row" "1|1000000000|storage|new|S1|info|first|None|1" "$(sql 'SELECT id,time,source,kind,subject,level,text,payload,v FROM events')"
emit pkg.rapp.some.thing-else x >/dev/null
check_eq "the kind is split at the first dot" "pkg|rapp.some.thing-else" "$(sql 'SELECT source,kind FROM events WHERE id = 2')"
check_eq "no output on success" "" "$(emit storage.new S1 quiet 2>&1)"

echo "-- subject and text are one line of at most 500 characters"
reset
emit storage.new >/dev/null
check_eq "a missing subject and text are empty" '""|""' "$(last subject)|$(last text)"
emit storage.new $'  a\tb\r\n\nc  ' $'\nline one\r\nline two\t' >/dev/null
check_eq "runs of tab and line breaks become one space, the ends are stripped" '"a b c"|"line one line two"' "$(last subject)|$(last text)"
emit storage.new $'\x1fx\x1f' >/dev/null
check_eq "the unit separator counts as white space at the ends" '"x"' "$(last subject)"
long=$(printf 'x%.0s' $(seq 1 600))
emit storage.new "$long" "$long" >/dev/null
check_eq "600 characters are cut to 500" "500|500" "$(sql 'SELECT length(subject),length(text) FROM events ORDER BY id DESC LIMIT 1')"
wide=$(python3 -c 'import sys; sys.stdout.buffer.write(("\u00e4\U0001F600"*300).encode())')
emit storage.new s "$wide" >/dev/null
check_eq "the limit counts characters, not bytes" "500|1500" "$(sql 'SELECT length(text),length(CAST(text AS BLOB)) FROM events ORDER BY id DESC LIMIT 1')"
emit storage.new s "$(printf 'x%.0s' $(seq 1 499)) yz" >/dev/null
check_eq "stripped first, then cut: a space can end the text" "500|1" "$(sql "SELECT length(text), substr(text,500) = ' ' FROM events ORDER BY id DESC LIMIT 1")"

echo "-- the kind"
reset
for good in a.b 9.9 job.failed pkg.my-app.x storage.a.b-c; do
  emit "$good" s >/dev/null 2>&1; check_eq "kind $good is taken" "0" "$?"
done
reset
for bad in storage Storage.new storage.New my-source.new storage.-new storage. .new "storage.new " "storage new" storage_x.new ""; do
  out=$(emit "$bad" s 2>&1); rc=$?
  check_eq "kind '$bad' is a usage error (exit 2)" "2" "$rc"
done
check_out "with the usage line" "usage: emit <source>\.<kind>" echo "$out"
emit >/dev/null 2>&1; check_eq "no arguments: exit 2" "2" "$?"
check_eq "none of them wrote a row" "0" "$(rows)"

echo "-- the level"
reset
emit storage.new s >/dev/null;       check_eq "an unlisted or info kind" '"info"' "$(last level)"
emit storage.missing s >/dev/null;   check_eq "warn from event-kinds.tsv" '"warn"' "$(last level)"
emit job.failed s >/dev/null;        check_eq "error from event-kinds.tsv" '"error"' "$(last level)"
emit job.failed s --level info >/dev/null; check_eq "--level wins over the list" '"info"' "$(last level)"
emit pkg.rapp.loud s >/dev/null;     check_eq "the level a package declares" '"warn"' "$(last level)"
emit pkg.nosuch.kind s >/dev/null;   check_eq "an undeclared package kind" '"info"' "$(last level)"
emit --level warn storage.new s t >/dev/null; check_eq "options may stand first" '"warn"|"t"' "$(last level)|$(last text)"
before=$(rows)
out=$(emit storage.new s --level loud 2>&1); check_eq "another level: exit 2" "2" "$?"
check_out "with the reason" "level is info, warn or error" echo "$out"
check_eq "and no row" "$before" "$(rows)"
emit storage.new --level >/dev/null
check_eq "--level without a value is an ordinary word" '"--level"' "$(last subject)"

echo "-- the payload: a JSON object, written again in one form"
reset
payload() { emit storage.new s t --payload "$1" >/dev/null 2>&1; echo "$?:$(stored payload)"; }
check_eq "spaces go" '0:{"a":[1,2]}' "$(payload '{ "a" : [1, 2] }')"
check_eq "the key order stays" '0:{"b":1,"a":2}' "$(payload '{"b":1,"a":2}')"
check_eq "of a repeated key the last value stays, at the first place" '0:{"a":3,"b":2}' "$(payload '{"a":1,"b":2,"a":3}')"
check_eq "non-ASCII is escaped, beyond the basic plane as a pair" '0:{"n":"\u00e4\ud83d\ude00"}' "$(payload "$(python3 -c 'import sys; sys.stdout.buffer.write("{\"n\":\"\u00e4\U0001F600\"}".encode())')")"
check_eq "control characters and DEL are escaped, a slash is not" '0:{"s":"a/b\u0001\u007f\n"}' "$(payload '{"s":"a\/b\u0001\u007f\n"}')"
check_eq "a lone surrogate is kept as it is" '0:{"s":"\ud800"}' "$(payload '{"s":"\ud800"}')"
check_eq "floats keep a point" '0:{"x":1.0,"y":1000.0,"z":0.1}' "$(payload '{"x":1.0,"y":1e3,"z":0.10}')"
check_eq "large and small floats get an exponent" '0:{"x":1e+22,"y":1e-07}' "$(payload '{"x":1e22,"y":0.0000001}')"
check_eq "halfway between two shortest forms: the even digit" '0:{"x":868321580294690.2,"y":868321580294690.8}' "$(payload '{"x":868321580294690.25,"y":868321580294690.75}')"
check_eq "a whole number of any size stays exact" '0:{"big":123456789012345678901234567890}' "$(payload '{"big":123456789012345678901234567890}')"
check_eq "nesting, true, false and null" '0:{"a":{"b":[true,false,null,{}]}}' "$(payload '{"a":{"b":[true,false,null,{}]}}')"
# 1e400 is too large for a float: it is read as infinity, so it counts like Infinity
for none in '[1,2]' '"text"' 7 null nonsense '' '{"a":NaN}' '{"a":Infinity}' '{"a":-Infinity}' '{"a":1}x' \
            '{"a":1e400}' '{"a":[{"b":-1e400}]}' '[1e400]'; do
  check_eq "payload '$none' is stored as NULL, the event is written" "0:NULL" "$(payload "$none")"
done

echo "-- retention runs with every event"
reset
for n in 1 2 3 4 5; do HS_EVENT_KEEP=3 emit storage.new "S$n" >/dev/null; done
check_eq "the newest rows stay, ids are not used again" "3|S3
4|S4
5|S5" "$(sql 'SELECT id,subject FROM events ORDER BY id')"
reset
day=86400
HS_NOW=$((1000000000 - 91 * day)) emit storage.new too-old >/dev/null
HS_NOW=$((1000000000 - 90 * day)) emit storage.new just-inside >/dev/null
emit storage.new now >/dev/null
check_eq "older than 90 days goes" "just-inside
now" "$(sql 'SELECT subject FROM events ORDER BY id')"
reset
HS_NOW=$((1000000000 - 36 * day)) emit pkg.rapp.tick metric-old >/dev/null
HS_NOW=$((1000000000 - 36 * day)) emit pkg.rapp.loud audit-old >/dev/null
HS_NOW=$((1000000000 - 8 * day)) emit pkg.rapp.flash flash-old >/dev/null
HS_NOW=$((1000000000 - 8 * day)) emit pkg.rapp.tick metric-young >/dev/null
HS_NOW=$((1000000000 - 6 * day)) emit pkg.rapp.flash flash-young >/dev/null
emit storage.new now >/dev/null
check_eq "a package's ephemeral kinds go after 7 days, its metric kinds after 35, the rest stays" "audit-old
metric-young
flash-young
now" "$(sql 'SELECT subject FROM events ORDER BY id')"

echo "-- after the write the web server is poked"
if python3 -c 'import socket,sys; sys.exit(0 if hasattr(socket, "AF_UNIX") else 1)'; then
  local -a words
  mapfile -t words < <(writer_words)
  got=$(python3 -c '
import os, socket, subprocess, sys
path = os.path.join(sys.argv[1], "live.sock")
s = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM); s.bind(path); s.settimeout(5)
def run(*args):
    subprocess.run(sys.argv[2:] + list(args), env=dict(os.environ, HS_LIVE_SOCK=path), capture_output=True)
run("storage.new", "s")
print(s.recv(16).decode())
run("bad", "s")
s.settimeout(1)
try:
    print(s.recv(16).decode())
except socket.timeout:
    print("nothing")
' "$WORK" "${words[@]}")
  rm -f "$WORK/live.sock"
  check_eq "one datagram '1' after a write, none after a refusal" "1
nothing" "$got"
else
  skip "no unix sockets here"
fi

echo "-- a database of a newer release"
reset
sql "DELETE FROM meta WHERE key = 'oldest_writer'" >/dev/null
sql "PRAGMA user_version=99" >/dev/null
out=$(emit storage.new s 2>&1); rc=$?
check_eq "refused (exit 1)" "1" "$rc"
check_out "with a reason" "newer release" echo "$out"
check_eq "no row" "0" "$(rows)"
reset
sql "UPDATE meta SET value = '3' WHERE key = 'oldest_writer'" >/dev/null
out=$(emit storage.new s 2>&1); rc=$?
check_eq "an oldest writer above this one: refused" "1:0" "$rc:$(rows)"
check_out "with a reason" "newer release" echo "$out"
reset
sql "UPDATE meta SET value = '2' WHERE key = 'oldest_writer'" >/dev/null
sql "PRAGMA user_version=99" >/dev/null
emit storage.new s >/dev/null 2>&1; rc=$?
check_eq "newer, but its number allows this writer: written" "0:1" "$rc:$(rows)"
check_eq "and neither the version nor the number changes" "99|2" "$(sql "SELECT (SELECT * FROM pragma_user_version), value FROM meta WHERE key = 'oldest_writer'")"
}

cases

# What only the Rust writer does: Python owns the schema, so it makes no database and migrates none.
rust_only() {
  echo "-- the Rust writer makes and migrates nothing"
  reset; rm -f "$WORK/state/state.db"*
  out=$(emit storage.new s 2>&1); rc=$?
  check_eq "no database: exit 1" "1" "$rc"
  check_match "one line that says so" '^hobnix: no state database' "$out"
  check "and none is made" test ! -e "$WORK/state/state.db"
  reset
  sql "PRAGMA user_version=1" >/dev/null
  out=$(emit storage.new s 2>&1); rc=$?
  check_eq "an older schema: refused, no row, the version stays" "1:0:1" "$rc:$(rows):$(sql 'PRAGMA user_version')"
  check_match "with a reason" '^hobnix: .*older than 2' "$out"
  reset
  sql "PRAGMA journal_mode=DELETE" >/dev/null
  out=$(emit storage.new s 2>&1); rc=$?
  check_eq "not in WAL mode: refused, no row, the mode stays" "1:0:delete" "$rc:$(rows):$(sql 'PRAGMA journal_mode')"
  check_match "with a reason" '^hobnix: .*WAL mode' "$out"
  reset
  out=$(emit nokind s 2>&1)
  check_eq "a usage error is one line" "1" "$(wc -l <<<"$out" | tr -d ' ')"
  check_match "that starts like every error of the program" '^hobnix: usage: emit ' "$out"
  out=$(HS_EVENT_KEEP=many emit storage.new s 2>&1); rc=$?
  check_eq "a knob that is no number: exit 1, no row" "1:0" "$rc:$(rows)"
}

if [ -z "$bin" ]; then
  echo "  skip  no hobnix binary: only the python writer ran (HOBNIX_BIN, or build in scripts/dev/rust-shell.nix)"
else
  WRITER=rust
  cases
  rust_only

  echo "== side by side: seeded random events, every byte of every column"
  python3 "$ROOT/tests/event-writer-sides.py" "$SD" "$bin" "$WORK/sides" > "$WORK/sides.log" 2>&1; rc=$?
  if [ "$rc" -eq 0 ]; then pass "$(tail -n 1 "$WORK/sides.log")"; else fail "the writers differ: $(head -c 600 "$WORK/sides.log" | tr '\n' ' ')"; fi
fi

finish
