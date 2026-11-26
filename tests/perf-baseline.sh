#!/usr/bin/env bash
# hs perf baseline (scripts/perf-baseline.sh, #1333): stand-ins for systemctl, /proc, the collector's load file and the hs dispatcher; the real
# live-state reader on a temporary state database. No root, no server.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
export HS_PLAIN=1 HS_LANG=en
unset HS_CALLER
B() { timeout 120 bash "$SCRIPTS/perf-baseline.sh" "$@"; }

if ! command -v jq >/dev/null 2>&1 || [ -z "${EPOCHREALTIME:-}" ]; then
  skip "needs jq and bash 5"
  finish
  exit
fi

export HS_STATE_DB=$WORK/state.db HS_STATE_DIR=$WORK HS_PACKAGES_DIR=$WORK/no-packages HS_REPO=$WORK/no-repo
export HS_PROC=$WORK/proc HS_SYSTEMCTL=$WORK/systemctl HS_LIVE_LOAD_FILE=$WORK/load.json
export HS_PERF_MINUTE=3 HS_PERF_STEP=1 HS_PERF_PAUSE=0

# the live state as hs-live and hs-web leave it: delay samples of two topics; no lease yet
db() {   # db <python statements with s = state-db.py and c = the connection>
  python3 - "$SCRIPTS/state-db.py" "$1" <<'PY'
import importlib.util, sys, time
spec = importlib.util.spec_from_file_location("state_db", sys.argv[1])
s = importlib.util.module_from_spec(spec)
spec.loader.exec_module(s)
c = s.live_open()
exec(sys.argv[2])
c.commit()
c.close()
PY
}
db 'c.execute("INSERT INTO live_delay (topic, ms_last, ms_worst, ms_n, web_last, web_worst, web_n) VALUES (\"status\", 100, 900, 3, 250, 400, 1)")
c.execute("INSERT INTO live_delay (topic, ms_last, ms_worst, ms_n) VALUES (\"jobs-list\", 300, 700, 2)")
c.execute("INSERT INTO live (topic, payload, updated) VALUES (\"status\", \"secretbox.lan /bulk/shares/anna 192.168.7.9\", ?)", (int(time.time()),))'

# /proc: the host counters, the loadavg and the two main processes
mkproc() {   # mkproc <busy ticks> <tasks> <utime of the main processes>
  mkdir -p "$HS_PROC/4242" "$HS_PROC/4343"
  printf 'cpu  %s 0 0 5000 0 0 0 400 0 0\nprocesses %s\n' "$1" "$2" > "$HS_PROC/stat"
  echo '1.50 1.00 0.50 1/100 999' > "$HS_PROC/loadavg"
  for p in 4242 4343; do
    printf '%s (python3 x) S 1 1 1 0 -1 0 0 0 0 0 %s 0 900 900 20 0\n' "$p" "$3" > "$HS_PROC/$p/stat"
    printf 'Name:\tpython3\nVmRSS:\t   20480 kB\n' > "$HS_PROC/$p/status"
  done
}
# systemctl show: the first answer of a unit is the start value; later ones moved on, and the host with it
cat > "$WORK/systemctl" <<'FAKE'
#!/usr/bin/env bash
w=$(dirname "$0")
[ "$1" = show ] || exit 1
u=${2%.service}
n=$(cat "$w/calls-$u" 2>/dev/null || echo 0); echo $((n + 1)) > "$w/calls-$u"
cpu=1000000000 pid=4242
[ "$u" = hs-web ] && pid=4343
if [ "$n" -gt 0 ]; then
  cpu=7000000000
  [ "$u" = hs-web ] && cpu=1600000000
  sed -i 's/^cpu  [0-9]*/cpu  1600/; s/ 400 0 0$/ 9400 0 0/; s/^processes .*/processes 10300/' "$w/proc/stat"
  sed -i 's/ 100 0 900 900 / 160 0 900 900 /' "$w/proc/$pid/stat"
  if [ -e "$w/restart-$u" ]; then pid=9999; fi
fi
printf 'MainPID=%s\nMemoryCurrent=104857600\nCPUUsageNSec=%s\n' "$pid" "$cpu"
FAKE
chmod +x "$WORK/systemctl"
fresh() {
  rm -f "$WORK"/calls-* "$WORK"/restart-*
  mkproc 1000 10000 100
  printf '{"time": %s, "window": 1, "reads": 3, "busy": 0.25, "stretch": 1.5, "topics": {"ext-secretpkg-list": {"reads": 3, "ms": 5}}}' "$(($(date +%s) + 5))" > "$HS_LIVE_LOAD_FILE"
}
val() { awk -F'\t' -v k="$1" '$1 == k { print $2 }' <<<"$result"; }
between() { awk -v v="$1" -v lo="$2" -v hi="$3" 'BEGIN { exit !(v != "-" && v != "" && v + 0 >= lo && v + 0 <= hi) }'; }

echo "-- the window, no page open"
fresh
result=$(B --minutes 1 --no-reads --list)
check_eq "exit code" "0" "$?"
check_eq "every line is name and value" "2" "$(awk -F'\t' '{ print NF }' <<<"$result" | sort -u)"
check_eq "the format" "1" "$(val meta.format)"
check_eq "the load at the start" "1.50" "$(val meta.load1_at_start)"
check_eq "no page open" "closed" "$(val window.page)"
check "the window length" between "$(val window.seconds)" 3 20
check_eq "the length asked for" "1" "$(val window.minutes)"
# 6 s of CPU in a window of 3 s or a little more (a slow machine makes it longer, never shorter)
check "the CPU of hs-live from the systemd counter" between "$(val hs-live.cpu_cores)" 0.3 2.0
check "the CPU of hs-web" between "$(val hs-web.cpu_cores)" 0.02 0.2
check "the main process alone (60 ticks)" between "$(val hs-live.main_process_cpu_cores)" 0.02 0.21
check_eq "memory of the service" "100.0" "$(val hs-live.memory_mib_avg)"
check_eq "memory peak of the samples" "100.0" "$(val hs-live.memory_mib_max)"
check_eq "resident size of the main process" "20.0" "$(val hs-live.main_process_rss_mib_avg)"
check_eq "not restarted" "no" "$(val hs-live.restarted)"
check "busy cores of the host (600 ticks)" between "$(val host.cpu_cores)" 0.2 2.0
check "steal time (9000 ticks) is its own line, not busy time" between "$(val host.cpu_steal_cores)" 3 31
check "tasks started on the host (300 in the window)" between "$(val host.tasks_started_per_min)" 800 6100
check_eq "reads per minute from the collector's file" "180.0" "$(val hs-live.reads_per_min)"
check_eq "busy reads" "0.250" "$(val hs-live.read_wall_s_per_s)"
check_eq "the stretch" "1.50" "$(val hs-live.stretch_max)"
# one read of the live state alone costs more than a thousandth of a core in so short a window
check "its own CPU time is told" between "$(val measuring.window_cpu_cores)" 0.001 8
check_eq "topics with a delay sample" "2" "$(val delay.change_to_stored.topics)"
check_eq "the middle delay" "200" "$(val delay.change_to_stored.median_last_ms)"
check_eq "the worst delay" "900" "$(val delay.change_to_stored.worst_ms)"
check_eq "the page's own samples" "1 250 400" "$(val delay.stored_to_page.topics) $(val delay.stored_to_page.median_last_ms) $(val delay.stored_to_page.worst_ms)"
check_eq "no name, path, address or package in the result" "0" "$(grep -Ec 'secretbox|anna|/bulk|192\.168|secretpkg|jobs-list' <<<"$result")"

echo "-- a page is open; hs-live restarts during the run"
fresh
touch "$WORK/restart-hs-live"
db 's.demand_put(c, ["status", "monitor-disks"], time.time(), lease=600)'
result=$(B --minutes 1 --no-reads --list)
check_eq "page open" "open" "$(val window.page)"
check_eq "a restart is told" "yes" "$(val hs-live.restarted)"
check_eq "and its CPU is not guessed" "- -" "$(val hs-live.cpu_cores) $(val hs-live.main_process_cpu_cores)"
check "hs-web is still measured" between "$(val hs-web.cpu_cores)" 0.02 0.2
db 'c.execute("DELETE FROM demand")'

echo "-- an old load file, a systemd that says nothing"
fresh
printf '{"time": 1000, "window": 1, "reads": 3, "busy": 0.25, "stretch": 1.5}' > "$HS_LIVE_LOAD_FILE"
printf '#!/bin/sh\nprintf "MainPID=0\\nMemoryCurrent=[not set]\\nCPUUsageNSec=18446744073709551615\\n"\n' > "$WORK/nothing"; chmod +x "$WORK/nothing"
result=$(HS_SYSTEMCTL=$WORK/nothing B --minutes 1 --no-reads --list)
check_eq "unknown stays unknown" "- - - -" "$(val hs-live.cpu_cores) $(val hs-live.memory_mib_avg) $(val hs-live.main_process_rss_mib_avg) $(val hs-live.reads_per_min)"

echo "-- a systemctl that hangs is ended; no answer is no restart"
fresh
cat > "$WORK/hanging" <<'FAKE'
#!/usr/bin/env bash
w=$(dirname "$0")
n=$(cat "$w/hang-calls" 2>/dev/null || echo 0); echo $((n + 1)) > "$w/hang-calls"
[ "$n" -ne 2 ] || exec sleep 60      # the second question about hs-live
exec "$w/systemctl" "$@"
FAKE
chmod +x "$WORK/hanging"
SECONDS=0
result=$(HS_SYSTEMCTL=$WORK/hanging HS_PERF_SHOW_TIMEOUT=1 B --minutes 1 --no-reads --list)
check_eq "exit code" "0" "$?"
check "the run did not wait for it" test "$SECONDS" -lt 40
check_eq "hs-live is not told as restarted" "no" "$(val hs-live.restarted)"

echo "-- the reads, through hs timing --split"
cat > "$WORK/hs" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$(dirname "$0")/read-calls"
[ "$*" != "sys users list" ] || exit 3
exec bash "$(dirname "$0")/quiet.sh"
FAKE
: > "$WORK/quiet.sh"
result=$(HS_BIN=$WORK/hs HS_PERF_TOOLS=none-installed B --minutes 0 --list)
check_eq "every read but one" "21 1" "$(val reads.count) $(val reads.failed)"
check_eq "the read that mounts the backup disk is not run" "0" "$(grep -c '^sys backup snapshots$' "$WORK/read-calls")"
check_eq "only sys reads are run" "0" "$(grep -Evc '^sys [a-z ]+$' "$WORK/read-calls")"
check_eq "the exit status of a read" "3" "$(val read.users_list.exit)"
check "a read's CPU time" between "$(val read.pool_info_bulk.cpu_s)" 0 30
check "the dispatcher part" between "$(val read.pool_info_bulk.dispatcher_wall_s)" 0 30
check_eq "no tool" "0" "$(val read.pool_info_bulk.tool_calls)"
check "the sum of the reads" between "$(val reads.sum.wall_s)" 0 300
check_eq "a part that one read does not know has no sum" "-" "$(val reads.sum.dispatcher_wall_s)"
check_eq "no window without minutes" "" "$(val window.seconds)"

echo "-- the latency file of hs live measure"
printf 'period minutes\t10.0\nmode\tdb\nhost of mine\tsecretbox\nprobes sent\t60\nprobes with a stream open\t60\nlatency median ms\t540\nlatency p95 ms\t900\nlatency max ms\tsecretbox\n' > "$WORK/lat.tsv"
result=$(B --minutes 0 --no-reads --latency "$WORK/lat.tsv" --list)
check_eq "latency rows" "540 900 60" "$(val latency.median_ms) $(val latency.p95_ms) $(val latency.probes_with_page)"
check_eq "a value that is no number is dropped" "-" "$(val latency.max_ms)"
check_eq "nothing else of the file comes through" "0" "$(grep -c secretbox <<<"$result")"
check_out "a wrong file is refused" "not a result file" B --minutes 0 --no-reads --latency "$WORK/quiet.sh" --list

echo "-- saved results, the table for people"
fresh
out=$(B --minutes 0 --no-reads --out "$WORK/before.tsv")
check_eq "exit code" "0" "$?"
check "the file has the format line" grep -q '^meta\.format	1$' "$WORK/before.tsv"
check_out "the table" "delay\.change_to_stored\.worst_ms" echo "$out"
check_out "where it is" "Saved: " echo "$out"
echo keep > "$WORK/mine"
check_out "an existing file is never overwritten" "exists already" B --minutes 0 --no-reads --out "$WORK/mine"
check_eq "and stays as it was" "keep" "$(cat "$WORK/mine")"
check_out "a missing folder is refused before the run" "no folder" B --minutes 1 --out "$WORK/nowhere/x.tsv"
fresh
out=$(HS_BIN=$WORK/hs HS_PERF_TOOLS=none-installed B --minutes 1)
check_out "progress and both tables" "hs sys pool info bulk" echo "$out"
check_out "the window in the table" "hs-live\.cpu_cores" echo "$out"

echo "-- the name of --out is taken during the run"
# the stand-in dispatcher runs after the check at the start and before the result is written
cat > "$WORK/quiet.sh" <<'FAKE'
if [ -n "${PLANT:-}" ] && [ ! -e "$PLANT_DONE" ]; then
  : > "$PLANT_DONE"
  case "$PLANT" in
    symlink) ln -s "$PLANT_VICTIM" "$PLANT_AT" ;;
    dangling) ln -s "$PLANT_VICTIM.none" "$PLANT_AT" ;;
    dirlink) ln -s "$(dirname "$PLANT_VICTIM")" "$PLANT_AT" ;;
    fifo) mkfifo "$PLANT_AT" ;;
    file) echo theirs > "$PLANT_AT" ;;
    gone) rm -rf "$(dirname "$PLANT_AT")" ;;
  esac
fi
FAKE
planted() {   # planted <what>: out (the output), rc, dir, kept (the files left beside the name)
  dir=$WORK/plant-$1
  mkdir -p "$dir/out" "$dir/else"
  echo keep > "$dir/else/victim"
  out=$(PLANT=$1 PLANT_AT=$dir/out/r.tsv PLANT_VICTIM=$dir/else/victim PLANT_DONE=$dir/done \
    HS_BIN=$WORK/hs HS_PERF_TOOLS=none-installed B --minutes 0 --out "$dir/out/r.tsv" 2>&1)
  rc=$?
  kept=("$dir"/out/hs-perf-baseline.*)
}
for what in symlink dangling dirlink fifo file; do
  planted "$what"
  check_eq "$what: fails, and does not hang" "1" "$rc"
  check "$what: the result is kept" grep -q '^meta\.format	1$' "${kept[0]}"
  check_out "$what: and its place is told" "kept in $dir/out/hs-perf-baseline\." echo "$out"
  check_eq "$what: the other file is untouched" "keep" "$(cat "$dir/else/victim")"
  check_eq "$what: nothing is written through a link" "victim" "$(ls -A "$dir/else")"
done
check "the FIFO is still one" test -p "$WORK/plant-fifo/out/r.tsv"
check "the link is still one" test -L "$WORK/plant-symlink/out/r.tsv"
check_eq "the file stays as it was" "theirs" "$(cat "$WORK/plant-file/out/r.tsv")"
planted gone
check_eq "no folder any more: fails" "1" "$rc"
check_out "and prints the result" "^meta\.format	1$" echo "$out"
for m in 022:644 077:600; do
  (umask "${m%:*}"; B --minutes 0 --no-reads --out "$WORK/mode-${m%:*}.tsv" >/dev/null)
  check_eq "umask ${m%:*}: the mode of a new file" "${m#*:}" "$(stat -c %a "$WORK/mode-${m%:*}.tsv")"
done
check_eq "no second file after a good run" "" "$(find "$WORK" -maxdepth 1 -name 'hs-perf-baseline.*')"
# a signal while the file gets its name: a stand-in for ln sends it
mkdir -p "$WORK/lnbin" "$WORK/stopped"
printf '#!/bin/sh\nkill -TERM "$PPID"\nsleep 0.3\n' > "$WORK/lnbin/ln"; chmod +x "$WORK/lnbin/ln"
PATH="$WORK/lnbin:$PATH" B --minutes 0 --no-reads --out "$WORK/stopped/r.tsv" >/dev/null 2>&1
check_eq "stopped while saving: ends by the signal" "143" "$?"
check_eq "and leaves no file behind" "" "$(ls -A "$WORK/stopped")"
: > "$WORK/quiet.sh"

echo "-- Ctrl-C during a read stops the whole run"
mkdir -p "$WORK/int-tmp" "$WORK/int-out"
cat > "$WORK/slow-hs" <<'FAKE'
#!/usr/bin/env bash
w=$(dirname "$0")
printf '%s\n' "$*" >> "$w/slow-calls"
sleep 30 &
echo "$! $$" > "$w/slow-pids"
wait
FAKE
rc=$(TMPDIR=$WORK/int-tmp HS_BIN=$WORK/slow-hs HS_PERF_TOOLS=none-installed \
  ctrl_c "$WORK/slow-pids" bash "$SCRIPTS/perf-baseline.sh" --minutes 0 --out "$WORK/int-out/r.tsv")
check_eq "it ends by the interrupt" "-2" "$rc"
check_eq "no second read is started" "1" "$(wc -l < "$WORK/slow-calls" | tr -d ' ')"
check "the read and what it started are gone" gone "$WORK/slow-pids"
check_eq "no temporary file is left" "" "$(ls -A "$WORK/int-tmp" "$WORK/int-out" | grep -v -e ':$' -e '^$')"

cat > "$WORK/slow-state.py" <<'PY'
import os, subprocess
c = subprocess.Popen(["sleep", "30"])
with open(os.path.join(os.environ["HS_STATE_DIR"], "state-pids"), "w") as f:
    f.write("%d %d" % (c.pid, os.getpid()))
c.wait()
PY
fresh
rc=$(HS_LIVE_STATE_PY=$WORK/slow-state.py ctrl_c "$WORK/state-pids" bash "$SCRIPTS/perf-baseline.sh" --minutes 1 --no-reads --list)
check_eq "during the read of the live state: ends by the interrupt" "-2" "$rc"
check "and that read is gone with what it started" gone "$WORK/state-pids"

echo "-- compare"
printf 'meta.format\t1\nmeta.cores\t8\nwindow.page\tclosed\nhs-live.cpu_cores\t2.000\nread.status.exit\t1\nonly.before\t5\nzero\t0\n' > "$WORK/a.tsv"
printf 'meta.format\t1\nmeta.cores\t8\nwindow.page\topen\nhs-live.cpu_cores\t0.500\nread.status.exit\t2\nzero\t4\nonly.after\t7\n' > "$WORK/b.tsv"
result=$(B --compare "$WORK/a.tsv" "$WORK/b.tsv" --list)
col() { awk -F'\t' -v k="$1" '$1 == k { print $2 " " $3 " " $4 }' <<<"$result"; }
check_eq "the change in percent" "2.000 0.500 -75.0%" "$(col hs-live.cpu_cores)"
check_eq "a number only in the first run" "5 - -" "$(col only.before)"
check_eq "a number only in the second run" "- 7 -" "$(col only.after)"
check_eq "no percent from zero" "0 4 -" "$(col zero)"
check_eq "no percent of an exit status or the meta lines" "1 2 - 8 8 -" "$(col read.status.exit) $(col meta.cores)"
check_out "runs that differ in the page are told" "differ in window.page" B --compare "$WORK/a.tsv" "$WORK/b.tsv"
result=$(B --compare "$WORK/a.tsv" "$WORK/a.tsv" --list)
check_eq "a file compared with itself" "2.000 2.000 +0.0%" "$(col hs-live.cpu_cores)"
check_out "a wrong file is refused" "not a result of hs perf baseline" B --compare "$WORK/a.tsv" "$WORK/lat.tsv"

echo "-- options"
check_eq "too many minutes" "1" "$(B --minutes 999 >/dev/null 2>&1; echo $?)"
check_eq "a bad number" "1" "$(B --minutes x >/dev/null 2>&1; echo $?)"
check_eq "a missing value" "1" "$(B --out >/dev/null 2>&1; echo $?)"
check_eq "compare needs two files" "1" "$(B --compare "$WORK/a.tsv" >/dev/null 2>&1; echo $?)"
check_eq "an unknown option" "1" "$(B --bogus >/dev/null 2>&1; echo $?)"

echo "-- it changes nothing"
changing='live(\.sh)? refresh|live_refresh|topic-bump|live-measure\.sh|systemctl(\}?")? (start|stop|restart|reload|enable|disable|set-property)'
check_eq "no changing word of systemctl, no refresh, no probe" "" "$(cat "$SCRIPTS/perf-baseline.sh" "$SCRIPTS/lib/perf-split.sh" | grep -E "$changing" || true)"
check_eq "systemctl is only asked to show" "show" "$(grep -oE '"\$systemctl" [a-z-]+' "$SCRIPTS/perf-baseline.sh" | awk '{ print $2 }' | sort -u)"

finish
