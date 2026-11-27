#!/usr/bin/env bash
# Both event writers at the same time on one state.db (hobnix/core#1336): 4 python and 4 Rust emitters with 200 events each, beside a
# loop of `topic-bump` (a third writer, as hs-live is) and a reader that lists events. Every event must arrive once, with its own id, and
# nobody may see a locked or busy database. The binary: HOBNIX_BIN, else rust/target/debug|release/hobnix; without one, or off Linux,
# the test is skipped (77). Where nix is there it runs in scripts/dev/rust-shell.nix, so that python links a SQLite with the WAL-reset fix too:
# two writers on one file are what that bug needs. No root. The database is in /tmp: WAL does not work on every mount (/mnt/c of WSL).
if [ -z "${CI:-}${HOBNIX_RUST_SHELL:-}" ] && [ "$(uname -s)" = Linux ] && command -v nix-shell >/dev/null; then
  exec nix-shell "$(dirname "$0")/../scripts/dev/rust-shell.nix" --run "$(printf 'exec bash %q' "$0")"
fi
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
command -v python3 >/dev/null || { echo "  skip  python3 missing"; exit 77; }
[ "$(uname -s)" = Linux ] || { echo "  skip  needs Linux (WSL)"; exit 77; }
bin=${HOBNIX_BIN:-}
if [ -z "$bin" ]; then
  for b in "$ROOT/rust/target/debug/hobnix" "$ROOT/rust/target/release/hobnix"; do [ -x "$b" ] && { bin=$b; break; }; done
fi
[ -n "$bin" ] && [ -x "$bin" ] || { echo "  skip  no hobnix binary (cargo build in rust/, or HOBNIX_BIN)"; exit 77; }

emitters=4 each=200
total=$((2 * emitters * each))
export HS_PLAIN=1 HS_LANG=en HS_CALLER=test PYTHONUTF8=1 HS_SCRIPTS=$SCRIPTS HS_EVENT_KEEP=100000
export HS_STATE_DIR=$WORK/state HS_STATE_DB=$WORK/state/state.db HS_PKG_EVENTS_DIR=$WORK/pe HS_LIVE_SOCK=$WORK/nobody.sock
unset HS_NOW HS_EVENT_DAYS
mkdir -p "$WORK/state" "$WORK/pe" "$WORK/rc" "$WORK/err"
SD=$SCRIPTS/state-db.py
python3 "$SD" forget nothing >/dev/null 2>&1
sql() { python3 -c 'import sqlite3,sys; r=sqlite3.connect(sys.argv[1], timeout=30).execute(sys.argv[2]).fetchall(); print("\n".join("|".join(str(x) for x in row) for row in r))' "$HS_STATE_DB" "$1"; }
echo "  python links SQLite $(python3 -c 'import sqlite3; print(sqlite3.sqlite_version)')"

# emitter <name> command...: 200 events one after the other; every exit code that is not 0 goes into rc/<name>
emitter() {
  local name=$1 n; shift
  : > "$WORK/rc/$name"
  for ((n = 1; n <= each; n++)); do
    "$@" job.ok "$name-$n" "event $n" --payload "{\"n\":$n}" >> "$WORK/err/$name" 2>&1 || echo "$n:$?" >> "$WORK/rc/$name"
  done
}
# repeat <name> command...: until the emitters are done; writes how often it ran
repeat() {
  local name=$1 runs=0; shift
  : > "$WORK/rc/$name"
  while [ ! -e "$WORK/stop" ]; do
    "$@" > /dev/null 2>> "$WORK/err/$name" || echo "run $runs:$?" >> "$WORK/rc/$name"
    runs=$((runs + 1))
  done
  echo "$runs" > "$WORK/$name.runs"
}

repeat bumper python3 "$SD" topic-bump concurrent &
bumper=$!
repeat reader python3 "$SD" event-list 50 &
reader=$!
pids=()
for ((i = 1; i <= emitters; i++)); do
  emitter "python$i" python3 "$SD" emit & pids+=("$!")
  emitter "rust$i" "$bin" event-emit & pids+=("$!")
done
wait "${pids[@]}"
touch "$WORK/stop"
wait "$bumper" "$reader"

check_eq "every call exited 0" "" "$(cd "$WORK/rc" && grep -H . -- * | head -n 5)"
check_eq "no output of an emitter, of the bumper or of the reader" "" "$(cd "$WORK/err" && grep -H . -- * 2>/dev/null | head -n 5)"
check_eq "nobody saw a locked or busy database" "" "$(grep -rilE 'locked|busy' "$WORK/err")"
check_eq "every event is there once" "$total|$total" "$(sql 'SELECT count(*), count(DISTINCT subject) FROM events')"
check_eq "every id is used once, with no gap" "$total|1|$total" "$(sql 'SELECT count(DISTINCT id), min(id), max(id) FROM events')"
check_eq "the ids of each emitter rise in the order it wrote" "0" "$(sql "SELECT count(*) FROM (SELECT json_extract(payload, '\$.n') AS n, lag(json_extract(payload, '\$.n')) OVER (PARTITION BY substr(subject, 1, instr(subject, '-')) ORDER BY id) AS before FROM events) WHERE n <= before")"
bumps=$(cat "$WORK/bumper.runs") reads=$(cat "$WORK/reader.runs")
check "the bumper and the reader ran beside the emitters ($bumps bumps, $reads reads)" test "$bumps" -gt 5 -a "$reads" -gt 5
# topic-bump is silent when it cannot write: the counter shows that none was lost
check_eq "no bump was lost" "$bumps" "$(sql "SELECT gen FROM topics WHERE topic = 'concurrent'")"
check_eq "the database is sound" "ok" "$(sql 'PRAGMA integrity_check')"
check_eq "and still in WAL mode" "wal" "$(sql 'PRAGMA journal_mode')"
finish
