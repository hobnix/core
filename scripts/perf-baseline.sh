#!/usr/bin/env bash
# help: the performance baseline: what the live collector and the web server cost, what each read costs and where its time goes; compare two runs
# args: [--minutes <N>] [--no-reads] [--latency <file.tsv>] [--out <file>] [--list]  |  --compare <before> <after> [--list]
# Takes the numbers of docs/PLAN-core-daemon.md section 14 (issue #1333; steps: docs/operations.md). It only reads: no setting, no data and
# no refresh of a topic; the one file it writes is the one --out names (a new file). Needs root like the reads it times.
# --out is written at the end: into a new file with a random name in the same folder, which then gets the name asked for as a hard link, only
# while that name is free (a link, a FIFO or a file put there during the run is not touched). If that fails, the result is kept under the random
# name, or printed when no file could be written. Ctrl-C stops the whole run.
# First it watches hs-live and hs-web for N minutes (default 10, 0 = not at all): systemd's CPU and memory counters, the CPU and memory of the
# main process, the collector's own numbers (the file `hs live load` shows) and whether a page is open (a lease in the live state).
# Processes started are counted for the WHOLE host (/proc/stat, threads too): Linux keeps no such counter for one service.
# Then it times the reads the pages run (`hs timing --split`, each twice with 1 s between reads; --no-reads leaves that out). Not
# `backup snapshots`: that one mounts the backup disk and locks the backup repository.
# --latency adds the change-to-page numbers of a result file of `sudo hs live measure` (<file>.tsv); this command starts no measurement.
# Its own load: every 10 s two `systemctl show` and one `jq`; a read of the live state at the start, every 5 minutes and at the end. Its CPU
# time is in the result.
# The result has numbers, the version and the words of the core reads: no host, user, share or package name, no address, no secret.
#   --list   name<TAB>value, one number per line (`-` = not known); with --compare: name<TAB>before<TAB>after<TAB>change
# Test knobs: HS_SYSTEMCTL, HS_PROC, HS_LIVE_LOAD_FILE, HS_RUN_DIR, HS_LIVE_STATE_PY, HS_PERF_MINUTE (seconds a minute lasts), HS_PERF_STEP,
# HS_PERF_PAUSE, HS_PERF_SHOW_TIMEOUT, HS_BIN, HS_PERF_TOOLS, HS_REPO.
set -uo pipefail
here=$(dirname "$0")
. "$here/lib/ui.sh"
. "$here/lib/version.sh"
. "$here/lib/perf-split.sh"   # perf_stoppable
usage="usage: hs perf baseline [--minutes <N>] [--no-reads] [--latency <file.tsv>] [--out <file>] [--list] | --compare <before> <after> [--list]"

minutes=10 reads=true latency="" out="" list=false compare=false before="" after=""
while [ $# -gt 0 ]; do
  case "$1" in
    --no-reads) reads=false; shift ;;
    --list)     list=true; shift ;;
    --minutes|--latency|--out)
      [ $# -ge 2 ] || { help_usage "$usage"; exit 1; }
      case "$1" in
        --minutes) minutes=$2 ;;
        --latency) latency=$2 ;;
        --out)     out=$2 ;;
      esac
      shift 2 ;;
    --compare)
      [ $# -ge 3 ] || { help_usage "$usage"; exit 1; }
      compare=true before=$2 after=$3; shift 3 ;;
    *) help_usage "$usage"; exit 1 ;;
  esac
done

# ---- compare two results -------------------------------------------------------------------------
if $compare; then
  for f in "$before" "$after"; do
    [ -r "$f" ] && grep -q $'^meta\\.format\t' "$f" || fail "not a result of hs perf baseline: $f"
  done
  rows=$(LC_ALL=C awk -F'\t' '
    function num(v) { return v ~ /^-?[0-9]+(\.[0-9]+)?$/ }
    NF < 2 { next }
    FNR == 1 { file++ }                      # counted, not by name: a file may be compared with itself
    !($1 in seen) { seen[$1] = 1; name[++n] = $1 }
    file == 1 { a[$1] = $2; next }
    { b[$1] = $2 }
    END {
      for (i = 1; i <= n; i++) {
        k = name[i]; x = (k in a) ? a[k] : "-"; y = (k in b) ? b[k] : "-"; c = "-"
        if (k !~ /^meta\./ && k !~ /\.exit$/ && num(x) && num(y) && x + 0 != 0) c = sprintf("%+.1f%%", (y - x) * 100 / x)
        printf "%s\t%s\t%s\t%s\n", k, x, y, c
      }
    }' "$before" "$after")
  if $list; then printf '%s\n' "$rows"; exit 0; fi
  for k in window.page meta.cores window.minutes; do
    pair=$(awk -F'\t' -v k="$k" '$1 == k && $2 != $3 { print $2 " and " $3 }' <<<"$rows")
    [ -z "$pair" ] || warn "The two runs differ in $k ($pair): their numbers are not like for like"
  done
  { thead 'NUMBER' 'BEFORE' 'AFTER' 'CHANGE'; printf '%s\n' "$rows"; } | table
  exit 0
fi

# ---- take the numbers ----------------------------------------------------------------------------
[[ "$minutes" =~ ^[0-9]{1,3}$ ]] && [ "$((10#$minutes))" -le 240 ] || { help_usage "$usage"; exit 1; }
minutes=$((10#$minutes))
# everything that can be refused is refused before the long part
if [ -n "$out" ]; then
  [ ! -e "$out" ] && [ ! -L "$out" ] || fail "$out exists already: name a new file (nothing is overwritten)"
  out_dir=$(dirname -- "$out")
  [ -d "$out_dir" ] && [ -w "$out_dir" ] || fail "no folder to write $out into"
fi
latency_rows=""
if [ -n "$latency" ]; then
  [ -r "$latency" ] || fail "cannot read $latency"
  # only the rows about the latency, and only numbers: nothing else of the file reaches the result
  latency_rows=$(tr -d '\r' < "$latency" | awk -F'\t' '
    BEGIN {
      m["period minutes"] = "period_min"; m["probes sent"] = "probes_sent"; m["probes matched"] = "probes_matched"
      m["probes with a stream open"] = "probes_with_page"; m["latency min ms"] = "min_ms"; m["latency median ms"] = "median_ms"
      m["latency p95 ms"] = "p95_ms"; m["latency max ms"] = "max_ms"
    }
    ($1 in m) { printf "latency.%s\t%s\n", m[$1], ($2 ~ /^[0-9]+(\.[0-9]+)?$/ ? $2 : "-") }')
  [ -n "$latency_rows" ] || fail "$latency is not a result file of hs live measure (name the .tsv file)"
fi

systemctl=${HS_SYSTEMCTL:-systemctl}
proc=${HS_PROC:-/proc}
load_file=${HS_LIVE_LOAD_FILE:-${HS_RUN_DIR:-/run/hs}/live-load.json}
state_py=${HS_LIVE_STATE_PY:-$here/live_state.py}
minute_s=${HS_PERF_MINUTE:-60}
every=${HS_PERF_STEP:-10}
tick=$(getconf CLK_TCK 2>/dev/null || echo 100)
units=(hs-live hs-web)

tmp=$(mktemp -d)
out_tmp=""   # the file beside --out, until the result has its final name
trap 'rm -rf "$tmp"; [ -z "$out_tmp" ] || rm -f -- "$out_tmp"' EXIT
res=$tmp/result
: > "$res"
: > "$tmp/load"

emit() { printf '%s\t%s\n' "$1" "${2:--}" >> "$res"; }
calc() { LC_ALL=C awk "BEGIN { printf \"%.${2:-3}f\", $1 }"; }   # calc <expression of numbers> [decimals]

svc_read() {   # svc_read <unit>: sv_cpu (ns) sv_mem (bytes) sv_pid (0 = no main process), `-` when systemd does not say
  local k v
  sv_cpu=- sv_mem=- sv_pid=-
  while IFS='=' read -r k v; do
    v=${v%$'\r'}
    [[ "$v" =~ ^[0-9]{1,18}$ ]] || continue      # "[not set]" and the largest 64 bit number mean the same: not known
    case "$k" in CPUUsageNSec) sv_cpu=$v ;; MemoryCurrent) sv_mem=$v ;; MainPID) sv_pid=$v ;; esac
  # --foreground: one process, no children, and Ctrl-C then reaches it
  done < <(timeout --foreground -k 2 "${HS_PERF_SHOW_TIMEOUT:-10}" "$systemctl" show "$1.service" -p CPUUsageNSec -p MemoryCurrent -p MainPID 2>/dev/null)
}
main_read() {   # main_read <pid>: pr_ticks (the process itself, without what it started) pr_rss (KiB)
  local line k v f
  pr_ticks=- pr_rss=-
  [ "$1" != 0 ] && [ -r "$proc/$1/stat" ] || return 0
  IFS= read -r line < "$proc/$1/stat" || true
  read -ra f <<<"${line##*) }"                  # the fields after "(name)": the first is field 3, utime and stime are 14 and 15
  [[ "${f[11]:-}" =~ ^[0-9]+$ && "${f[12]:-}" =~ ^[0-9]+$ ]] && pr_ticks=$((f[11] + f[12]))
  while read -r k v _; do
    [ "$k" != VmRSS: ] || pr_rss=$v
  done 2>/dev/null < "$proc/$1/status"
}
host_read() {   # ho_busy (ticks every core was busy, guests of containers and VMs included) ho_steal (ticks the host of a server that is a VM gave
                # to others: not work of this server) ho_tasks (processes and threads started since boot)
  local k a b c f g h
  ho_busy=- ho_steal=- ho_tasks=-
  while read -r k a b c _ _ f g h _; do   # cpu user nice system idle iowait irq softirq steal
    case "$k" in cpu) ho_busy=$((a + b + c + f + g)) ho_steal=$((h)) ;; processes) ho_tasks=$a ;; esac
  done 2>/dev/null < "$proc/stat"
}
cpu_of_times() {   # cpu_of_times <file>: CPU seconds in the output of `times`. Write it in the main shell: in $(...) it would be the subshell's.
  tr ',' '.' < "$1" | LC_ALL=C awk '{ for (i = 1; i <= NF; i++) { split($i, p, /[ms]/); s += p[1] * 60 + p[2] } } END { printf "%.3f", s }'
}

page_samples=0 page_open=0 have_state=false
page_read() {   # one read of the live state: is a page open now (a lease)? Keeps the document for the delay numbers.
  local n rc=0
  perf_stop_traps   # only here: elsewhere a signal ends this script as usual, also one sent to it alone
  perf_stoppable timeout -k 5 60 python3 "$state_py" inspect > "$tmp/inspect.new" 2>/dev/null || rc=$?
  trap - INT TERM HUP
  [ "$rc" -eq 0 ] || return 0
  n=$(jq -r '[.topics[] | select(.lease)] | length' "$tmp/inspect.new" 2>/dev/null) || return 0
  n=${n%$'\r'}
  [[ "$n" =~ ^[0-9]+$ ]] || return 0
  mv -f "$tmp/inspect.new" "$tmp/inspect"
  have_state=true
  page_samples=$((page_samples + 1))
  [ "$n" -eq 0 ] || page_open=$((page_open + 1))
}
load_read() {   # load_read <seconds into the window> <last: true|false>: the collector's own numbers, once their look-back lies inside the window
  local t w r b s
  [ -r "$load_file" ] || return 0
  IFS=$'\t' read -r t w r b s < <(jq -r '[.time, .window, .reads, .busy, .stretch] | map(. // "-") | @tsv' "$load_file" 2>/dev/null) || return 0
  s=${s%$'\r'}
  [[ "$t" =~ ^[0-9]+$ && "$w" =~ ^[0-9]+(\.[0-9]+)?$ ]] || return 0
  [ $((EPOCHSECONDS - t)) -le 30 ] || return 0   # an old file: the collector does not run
  $2 || [ "$1" -ge "${w%.*}" ] || return 0
  printf '%s\t%s\t%s\t%s\n' "$w" "$r" "$b" "$s" >> "$tmp/load"
}

emit meta.format 1
emit meta.date "$(date -u +%Y-%m-%dT%H:%MZ)"
emit meta.version "$(hobnix_version)"
emit meta.cores "$(nproc 2>/dev/null || echo -)"
la=-
[ ! -r "$proc/loadavg" ] || read -r la _ < "$proc/loadavg" || true
emit meta.load1_at_start "$la"

if [ "$minutes" -gt 0 ]; then
  command -v jq >/dev/null 2>&1 || fail "jq is missing"
  $list || { step "Watch hs-live and hs-web"; note "Minutes: $minutes. Leave the pages as they are for the whole run: all closed, or one open"; }
  declare -A cpu0 cpu1 pid0 main0 main1 restarted mem_sum mem_n mem_max rss_sum rss_n
  for u in "${units[@]}"; do
    svc_read "$u"; main_read "$sv_pid"
    cpu0[$u]=$sv_cpu pid0[$u]=$sv_pid main0[$u]=$pr_ticks restarted[$u]=no mem_sum[$u]=0 mem_n[$u]=0 mem_max[$u]=0 rss_sum[$u]=0 rss_n[$u]=0
  done
  host_read; busy0=$ho_busy steal0=$ho_steal tasks0=$ho_tasks
  times > "$tmp/times0"
  start=${EPOCHREALTIME/[.,]/}      # microseconds
  stop=$((start + minutes * minute_s * 1000000))
  page_read
  state_gap=$((5 * minute_s * 1000000))      # one read of the live state starts far more processes than the rest: not often
  next_state=$((start + state_gap)) next_note=1 last=false
  while ! $last; do
    left=$((stop - ${EPOCHREALTIME/[.,]/}))
    if [ "$left" -gt $((every * 1000000)) ]; then sleep "$every"
    else
      if [ "$left" -gt 0 ]; then printf -v rest_s '%d.%06d' $((left / 1000000)) $((left % 1000000)); sleep "$rest_s"; fi
      last=true
    fi
    now=${EPOCHREALTIME/[.,]/}
    for u in "${units[@]}"; do
      svc_read "$u"; main_read "$sv_pid"
      # a question without an answer (the time limit) is no restart
      [ "$sv_pid" = - ] || [ "${pid0[$u]}" = - ] || [ "$sv_pid" = "${pid0[$u]}" ] || restarted[$u]=yes
      if [ "$sv_mem" != - ]; then
        kib=$((sv_mem / 1024)); mem_sum[$u]=$((mem_sum[$u] + kib)); mem_n[$u]=$((mem_n[$u] + 1))
        [ "$kib" -le "${mem_max[$u]}" ] || mem_max[$u]=$kib
      fi
      [ "$pr_rss" = - ] || { rss_sum[$u]=$((rss_sum[$u] + pr_rss)); rss_n[$u]=$((rss_n[$u] + 1)); }
      cpu1[$u]=$sv_cpu main1[$u]=$pr_ticks
    done
    if $last; then host_read; end=$now; fi      # the window ends with the last sample of the counters
    load_read $(((now - start) / 1000000)) "$last"
    if $last || [ "$now" -ge "$next_state" ]; then
      page_read
      next_state=$((now + state_gap))
    fi
    if ! $list && [ $(((now - start) / (minute_s * 1000000))) -ge "$next_note" ] && ! $last; then
      note "minute $next_note of $minutes"
      next_note=$((next_note + 1))
    fi
  done
  times > "$tmp/times1"
  self0=$(cpu_of_times "$tmp/times0")
  self1=$(cpu_of_times "$tmp/times1")
  secs=$(calc "($end - $start) / 1000000")

  emit window.minutes "$minutes"
  emit window.seconds "$(calc "$secs" 0)"
  page=-
  if [ "$page_samples" -gt 0 ]; then
    if [ "$page_open" -eq 0 ]; then page=closed; elif [ "$page_open" -eq "$page_samples" ]; then page=open; else page=mixed; fi
  fi
  emit window.page "$page"
  emit window.page_open_samples "$([ "$page_samples" -gt 0 ] && echo "$page_open" || echo -)"
  emit window.page_samples "$page_samples"
  v=-; [ "$ho_busy" = - ] || [ "$busy0" = - ] || v=$(calc "($ho_busy - $busy0) / $tick / $secs")
  emit host.cpu_cores "$v"
  v=-; [ "$ho_steal" = - ] || [ "$steal0" = - ] || v=$(calc "($ho_steal - $steal0) / $tick / $secs")
  emit host.cpu_steal_cores "$v"
  v=-; [ "$ho_tasks" = - ] || [ "$tasks0" = - ] || v=$(calc "($ho_tasks - $tasks0) * 60 / $secs" 0)
  emit host.tasks_started_per_min "$v"
  for u in "${units[@]}"; do
    c1=${cpu1[$u]} m1=${main1[$u]}
    cores=- per_min=- main=-
    if [ "${restarted[$u]}" = no ] && [ "$c1" != - ] && [ "${cpu0[$u]}" != - ] && [ "$c1" -ge "${cpu0[$u]}" ]; then
      cores=$(calc "($c1 - ${cpu0[$u]}) / 1000000000 / $secs")
      per_min=$(calc "($c1 - ${cpu0[$u]}) / 1000000000 * 60 / $secs" 2)
    fi
    if [ "${restarted[$u]}" = no ] && [ "$m1" != - ] && [ "${main0[$u]}" != - ]; then
      main=$(calc "($m1 - ${main0[$u]}) / $tick / $secs")
    fi
    emit "$u.cpu_cores" "$cores"
    emit "$u.cpu_s_per_min" "$per_min"
    emit "$u.main_process_cpu_cores" "$main"
    avg=- max=- rss=-
    if [ "${mem_n[$u]}" -gt 0 ]; then avg=$(calc "${mem_sum[$u]} / ${mem_n[$u]} / 1024" 1); max=$(calc "${mem_max[$u]} / 1024" 1); fi
    [ "${rss_n[$u]}" -eq 0 ] || rss=$(calc "${rss_sum[$u]} / ${rss_n[$u]} / 1024" 1)
    emit "$u.memory_mib_avg" "$avg"
    emit "$u.memory_mib_max" "$max"
    emit "$u.main_process_rss_mib_avg" "$rss"
    emit "$u.restarted" "${restarted[$u]}"
  done
  IFS=$'\t' read -r per_min busy stretch < <(LC_ALL=C awk -F'\t' '
    $1 > 0 && $2 ~ /^[0-9]+(\.[0-9]+)?$/ { r += $2 * 60 / $1; rn++ }
    $3 ~ /^[0-9]+(\.[0-9]+)?$/ { b += $3; bn++ }
    $4 ~ /^[0-9]+(\.[0-9]+)?$/ { if ($4 + 0 > s) s = $4 + 0; sn++ }
    END { printf "%s\t%s\t%s\n", (rn ? sprintf("%.1f", r / rn) : "-"), (bn ? sprintf("%.3f", b / bn) : "-"), (sn ? sprintf("%.2f", s) : "-") }' "$tmp/load")
  emit hs-live.reads_per_min "$per_min"
  emit hs-live.read_wall_s_per_s "$busy"
  emit hs-live.stretch_max "$stretch"
  emit measuring.window_cpu_cores "$(calc "($self1 - $self0) / $secs")"
elif command -v jq >/dev/null 2>&1; then
  page_read
fi

# the delay the collector and the Live state page have recorded themselves (live_delay in the live state, #486): since each row exists
if $have_state; then
  jq -r '
    def med: sort | if length == 0 then "-" elif length % 2 == 1 then .[(length - 1) / 2] else ((.[length / 2 - 1] + .[length / 2]) / 2 | floor) end;
    def three(name; last; worst): [.topics[] | last | values] as $l | [.topics[] | worst | values] as $w
      | "delay.\(name).topics\t\($l | length)", "delay.\(name).median_last_ms\t\($l | med)", "delay.\(name).worst_ms\t\($w | max // "-")";
    three("change_to_stored"; .delay_ms_last; .delay_ms_worst), three("stored_to_page"; .delay_web_last; .delay_web_worst)' \
    "$tmp/inspect" 2>/dev/null | tr -d '\r' >> "$res"
fi
[ -z "$latency_rows" ] || printf '%s\n' "$latency_rows" >> "$res"

: > "$tmp/reads"
if $reads; then
  $list || { step "Time the reads"; note "Each read runs twice, one after the other, with a pause between two reads"; }
  HS_PLAIN=1 bash "$here/read-timing.sh" --list --split --pause "${HS_PERF_PAUSE:-1}" --skip "backup snapshots" > "$tmp/reads" \
    || fail "the reads could not be timed (hs timing --split)"
  LC_ALL=C awk -F'\t' '
    BEGIN {
      split("wall_s cpu_s dispatcher_wall_s dispatcher_cpu_s tools_wall_s tools_cpu_s tool_calls rest_wall_s rest_cpu_s", f, " ")
      split("1 4 5 6 7 8 9 10 11", col, " ")
    }
    NF >= 11 {
      n++; if ($2 != 0) failed++
      k = $3; gsub(/ /, "_", k)
      line[n] = "read." k ".exit\t" $2
      for (i = 1; i <= 9; i++) {
        v = $(col[i]); line[n] = line[n] "\nread." k "." f[i] "\t" v
        if (v == "-" || v == "") unknown[i] = 1; else sum[i] += v
      }
    }
    END {
      print "reads.count\t" n + 0; print "reads.failed\t" failed + 0
      for (i = 1; i <= 9; i++) printf "reads.sum.%s\t%s\n", f[i], (unknown[i] || !n ? "-" : sprintf(i == 7 ? "%d" : "%.3f", sum[i]))
      for (j = 1; j <= n; j++) print line[j]
    }' "$tmp/reads" >> "$res"
fi

if [ -n "$out" ]; then
  # the name was free at the start, which is long ago: never open it for writing
  mode=$(printf '%o' $((0666 & ~8#$(umask))))   # what a new file gets; mktemp alone would leave 600
  if ! { out_tmp=$(mktemp -- "$out_dir/hs-perf-baseline.XXXXXXXX") && cat "$res" > "$out_tmp" && chmod "$mode" -- "$out_tmp"; }; then
    cat "$res"
    fail "could not write into the folder of $out: the result is printed above, copy it now"
  fi
  if ! ln -T -- "$out_tmp" "$out" 2>/dev/null; then   # fails when the name exists, whatever it is
    kept=$out_tmp out_tmp=""
    fail "could not save as $out (the name is taken now, or the folder allows no hard link). The result is kept in $kept"
  fi
  rm -f -- "$out_tmp"
  out_tmp=""
fi
if $list; then cat "$res"; exit 0; fi

step "Result"
{ thead 'NUMBER' 'VALUE'; grep -v '^read\.' "$res"; } | table
if $reads; then
  {
    thead 'SECONDS' 'CPU' 'DISPATCHER' 'TOOLS' 'CALLS' 'REST' 'EXIT' 'COMMAND'
    awk -F'\t' '{ printf "%s\t%s\t%s/%s\t%s/%s\t%s\t%s/%s\t%s\ths sys %s\n", $1, $4, $5, $6, $7, $8, $9, $10, $11, ($2 == 0 ? "ok" : $2), $3 }' "$tmp/reads"
  } | table
fi
if [ -n "$out" ]; then
  ok "Saved: $out"
  next_step "hs perf baseline --compare <before> <after>"
else
  note "To keep it for a comparison, run with --out <file>"
fi
