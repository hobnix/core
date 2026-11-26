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
  printf 'cpu  %s 0 0 5000 0 0 0 0 0 0\nprocesses %s\n' "$1" "$2" > "$HS_PROC/stat"
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
  sed -i 's/^cpu  [0-9]*/cpu  1600/; s/^processes .*/processes 10300/' "$w/proc/stat"
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
# 6 s of CPU in a window of 3 s or a little more (a slow machine makes it longer, never shorter)
check "the CPU of hs-live from the systemd counter" between "$(val hs-live.cpu_cores)" 0.3 2.0
check "the CPU of hs-web" between "$(val hs-web.cpu_cores)" 0.02 0.2
check "the main process alone (60 ticks)" between "$(val hs-live.main_process_cpu_cores)" 0.02 0.21
check_eq "memory of the service" "100.0" "$(val hs-live.memory_mib_avg)"
check_eq "memory peak of the samples" "100.0" "$(val hs-live.memory_mib_max)"
check_eq "resident size of the main process" "20.0" "$(val hs-live.main_process_rss_mib_avg)"
check_eq "not restarted" "no" "$(val hs-live.restarted)"
check "busy cores of the host (600 ticks)" between "$(val host.cpu_cores)" 0.2 2.0
check "tasks started on the host (300 in the window)" between "$(val host.tasks_started_per_min)" 800 6100
check_eq "reads per minute from the collector's file" "180.0" "$(val hs-live.reads_per_min)"
check_eq "busy reads" "0.250" "$(val hs-live.read_wall_s_per_s)"
check_eq "the stretch" "1.50" "$(val hs-live.stretch_max)"
check "its own CPU time is told" between "$(val measuring.window_cpu_cores)" 0 8
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

echo "-- the reads, through hs timing --split"
cat > "$WORK/hs" <<'FAKE'
#!/usr/bin/env bash
[ "$*" != "sys backup snapshots" ] || exit 3
exec bash "$(dirname "$0")/quiet.sh"
FAKE
: > "$WORK/quiet.sh"
result=$(HS_BIN=$WORK/hs HS_PERF_TOOLS=none-installed B --minutes 0 --list)
check_eq "every read" "22 1" "$(val reads.count) $(val reads.failed)"
check_eq "the exit status of a read" "3" "$(val read.backup_snapshots.exit)"
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
check_out "a wrong file is refused" "not a result of hs perf baseline" B --compare "$WORK/a.tsv" "$WORK/lat.tsv"

echo "-- options"
check_eq "too many minutes" "1" "$(B --minutes 999 >/dev/null 2>&1; echo $?)"
check_eq "a bad number" "1" "$(B --minutes x >/dev/null 2>&1; echo $?)"
check_eq "a missing value" "1" "$(B --out >/dev/null 2>&1; echo $?)"
check_eq "compare needs two files" "1" "$(B --compare "$WORK/a.tsv" >/dev/null 2>&1; echo $?)"
check_eq "an unknown option" "1" "$(B --bogus >/dev/null 2>&1; echo $?)"

echo "-- it changes nothing"
check_eq "no changing word of systemctl, no refresh, no probe" "0" "$(grep -Ec 'live(\.sh)? refresh|topic-bump|live-measure\.sh|systemctl[^|]* (start|stop|restart|reload|enable|disable|set-property)' "$SCRIPTS/perf-baseline.sh" "$SCRIPTS/lib/perf-split.sh" | awk -F: '{ s += $NF } END { print s + 0 }')"

finish
