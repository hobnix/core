#!/usr/bin/env bash
# scripts/read-timing.sh (hs timing): the reads of the interface, timed. A fake dispatcher with chosen delays: no root, no server.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
export HS_PLAIN=1 HS_LANG=en
unset HS_CALLER
cat > "$WORK/hs" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$(dirname "$0")/calls"
case "$*" in
  "sys users list") sleep 1.2 ;;
  "sys ct list") sleep 0.3 ;;
  "sys backup snapshots") exit 3 ;;
esac
FAKE
chmod +x "$WORK/hs"
export HS_BIN=$WORK/hs
T() { bash "$SCRIPTS/read-timing.sh" "$@"; }

echo "-- list"
out=$(T --list)
check_eq "every read is listed once" "22" "$(wc -l <<<"$out" | tr -d ' ')"
check_eq "the slowest comes first" "users list" "$(head -n1 <<<"$out" | cut -f3)"
check_out "seconds with milliseconds" "^1\.[0-9]{3}	0	users list$" echo "$out"
check_out "a failing read shows its exit status" "	3	backup snapshots$" echo "$out"
check_out "the second slowest" "^0\.[0-9]{3}	0	ct list$" echo "$(sed -n 2p <<<"$out")"

echo "-- what is called"
check "only sys reads" test "$(grep -vc '^sys ' "$WORK/calls")" = 0
check "no plan, start or report" test "$(grep -Ec ' (plan|start|report)( |$)' "$WORK/calls")" = 0
check_out "the doctor is a read" "sys system doctor" cat "$WORK/calls"

echo "-- the table for people"
out=$(T)
check_out "a count of failed reads" "Reads that failed: 1" echo "$out"
check_out "a count of slow reads" "Slower than 1 s: 1" echo "$out"
check_out "the table has the commands" "hs sys users list" echo "$out"
check_out "the closing note" "All reads one after the other" echo "$out"

echo "-- options"
: > "$WORK/calls"
T --list --repeat 2 >/dev/null
check_eq "--repeat 2 runs every read twice" "44" "$(wc -l < "$WORK/calls" | tr -d ' ')"
check_eq "a bad count is refused" "1" "$(T --repeat x >/dev/null 2>&1; echo $?)"
check_eq "an unknown option is refused" "1" "$(T --bogus >/dev/null 2>&1; echo $?)"
check_eq "a missing value is refused" "1" "$(timeout 20 bash "$SCRIPTS/read-timing.sh" --repeat >/dev/null 2>&1; echo $?)"
check_eq "a bad pause is refused" "1" "$(T --pause -1 >/dev/null 2>&1; echo $?)"
: > "$WORK/calls"
out=$(T --list --skip "backup snapshots" --skip "ct list")
check_eq "--skip leaves reads out" "20" "$(wc -l <<<"$out" | tr -d ' ')"
check_eq "and does not call them" "0" "$(grep -Ec '^sys (backup snapshots|ct list)$' "$WORK/calls")"
check_eq "a read that does not exist is refused" "1" "$(T --skip nothing >/dev/null 2>&1; echo $?)"

echo "-- Ctrl-C ends the read that runs, with what it started, and the whole run"
cat > "$WORK/slow-hs" <<'FAKE'
#!/usr/bin/env bash
w=$(dirname "$0")
printf '%s\n' "$*" >> "$w/slow-calls"
sleep 30 &
echo "$! $$" > "$w/slow-pids"
wait
FAKE
for mode in plain split; do
  opts=(--list)
  [ "$mode" = plain ] || { opts+=(--split); [ -n "${EPOCHREALTIME:-}" ] || continue; }
  rm -rf "$WORK/slow-calls" "$WORK/slow-pids" "$WORK/int-tmp"; mkdir "$WORK/int-tmp"
  SECONDS=0
  rc=$(TMPDIR=$WORK/int-tmp HS_BIN=$WORK/slow-hs HS_PERF_TOOLS=none-installed ctrl_c "$WORK/slow-pids" bash "$SCRIPTS/read-timing.sh" "${opts[@]}")
  check_eq "$mode: it ends by the interrupt" "-2" "$rc"
  check "$mode: at once" test "$SECONDS" -lt 15
  check_eq "$mode: no second read is started" "1" "$(wc -l < "$WORK/slow-calls" | tr -d ' ')"
  check "$mode: the read and what it started are gone" gone "$WORK/slow-pids"
  check_eq "$mode: no temporary file is left" "" "$(ls -A "$WORK/int-tmp")"
done

echo "-- split: dispatcher, external tools, rest (scripts/lib/perf-split.sh)"
if [ -z "${EPOCHREALTIME:-}" ]; then
  echo "  skip: needs bash 5"
else
  mkdir -p "$WORK/bin" "$WORK/split"
  cat > "$WORK/bin/faketool" <<'TOOL'
#!/usr/bin/env bash
printf '%s|%s\n' "$(basename "$0")" "$*" >> "$(dirname "$0")/../tool-calls"
case "$1" in nap) sleep 0.4 ;; fail) exit 7 ;; cat) cat ;; esac
TOOL
  chmod +x "$WORK/bin/faketool"
  # a dispatcher like the real one: some work of its own, then it hands over to the script with `exec bash`
  cat > "$WORK/split/hs" <<'FAKE'
#!/usr/bin/env bash
i=0; while [ "$i" -lt 60000 ]; do i=$((i + 1)); done
[ "$*" != "sys backup snapshots" ] || exec bash "$(dirname "$0")/fails.sh"
[ "$*" != "sys users list" ] || exec bash "$(dirname "$0")/tools.sh" "$*"
exec bash "$(dirname "$0")/quiet.sh"
FAKE
  cat > "$WORK/split/tools.sh" <<'SCRIPT'
faketool nap secret-argument &
faketool nap secret-argument
wait
echo hello | faketool cat > "$(dirname "$0")/piped"
faketool fail; echo $? > "$(dirname "$0")/toolrc"
bash -c 'faketool x'
SCRIPT
  echo 'exit 3' > "$WORK/split/fails.sh"
  : > "$WORK/split/quiet.sh"
  split=$(PATH="$WORK/bin:$PATH" HS_BIN="$WORK/split/hs" HS_PERF_TOOLS="faketool notinstalled-tool" T --list --split)
  row() { grep "	$1	" <<<"$split" | cut -f"$2"; }
  between() { awk -v v="$1" -v lo="$2" -v hi="$3" 'BEGIN { exit !(v + 0 >= lo && v + 0 <= hi) }'; }
  check_eq "every read has eleven columns" "11" "$(awk -F'\t' '{ print NF }' <<<"$split" | sort -u)"
  check_eq "the exit status stays" "3" "$(row 'backup snapshots' 2)"
  check_eq "the tool calls are counted, also one from a shell the script started" "5" "$(row 'users list' 9)"
  check "two calls side by side count once in the wall time of the tools" between "$(row 'users list' 7)" 0.35 0.75
  check "the dispatcher is a part with its own CPU time" between "$(row 'users list' 6)" 0.02 20
  check "the CPU time of the read is there" between "$(row 'users list' 4)" 0.02 20
  check_eq "a read without a tool has none" "0" "$(row 'status' 9)"
  check_eq "the tool got its stdin" "hello" "$(cat "$WORK/split/piped")"
  check_eq "the tool's exit status comes back" "7" "$(cat "$WORK/split/toolrc")"
  check "the real tool got its arguments" grep -qx 'faketool|nap secret-argument' "$WORK/tool-calls"
  check_out "no argument is printed" "^0$" bash -c 'grep -c secret-argument <<<"$1" || true' _ "$split"
  out=$(PATH="$WORK/bin:$PATH" HS_BIN="$WORK/split/hs" HS_PERF_TOOLS=faketool T --split)
  check_out "the table has the parts" "DISPATCHER" echo "$out"
  # a dispatcher that never starts bash (a Rust command): the dispatcher part is unknown
  split=$(HS_BIN="$WORK/hs" HS_PERF_TOOLS=faketool T --list --split)
  check_eq "no hand-over: the dispatcher part is -" "- -" "$(row 'status' 5) $(row 'status' 6)"
fi

finish
