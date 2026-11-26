#!/usr/bin/env bash
# help: how long the reads of the interface take (every tab loads through these), slowest first
# help.de: wie lange die Lesezugriffe der Oberfläche dauern (jeder Reiter lädt damit), die langsamsten zuerst
# args: [--list] [--repeat <N>] [--split] [--pause <S>] [--skip <read>]
# Runs the read-only `hs sys ...` commands the tabs call at load time, one after the other, and prints seconds per command, slowest first.
# Needs root like the interface (the hs wrapper asks for it). Changes nothing: only reads; `sys system report` (writes a file) and every plan/start is left out.
#   --list         tab separated seconds<TAB>exit<TAB>command (for tools)
#   --repeat N     run each command N times and show the slowest of them (default 1: the first run is the one a person waits for)
#   --split        also CPU time, and where the time goes: the dispatcher, external tools, the rest (script, shells, Python). Each command then
#                  also runs a second time with stand-ins in its PATH (scripts/lib/perf-split.sh); the parts come from that run. With --list the
#                  same three columns, then: cpu<TAB>dispatcher wall<TAB>dispatcher cpu<TAB>tools wall<TAB>tools cpu<TAB>tool calls<TAB>rest wall<TAB>rest cpu
#                  (seconds, `-` = not known)
#   --pause S      wait S seconds between two commands (default 0): spreads the load on a busy server
#   --skip <read>  leave one read out, as its words after `hs sys` (may be given again). `backup snapshots` mounts the backup disk and locks the
#                  backup repository while it reads: hs perf baseline skips it.
# Test knobs: HS_BIN (stand-in for the hs dispatcher), HS_PERF_TOOLS.
# shellcheck disable=SC2154  # the ps_ results come from lib/perf-split.sh
set -euo pipefail
here=$(dirname "$0")
. "$here/lib/ui.sh"
hsbin=${HS_BIN:-$here/lib/hs.sh}
usage="usage: hs timing [--list] [--repeat <N>] [--split] [--pause <S>] [--skip <read>]"
list=false repeat=1 split=false pause=0 skip=()
while [ $# -gt 0 ]; do
  case "$1" in
    --list)   list=true; shift ;;
    --split)  split=true; shift ;;
    --repeat|--pause)
      [ $# -ge 2 ] || { say "$usage"; exit 1; }
      if [ "$1" = --repeat ]; then repeat=$2; else pause=$2; fi
      shift 2 ;;
    --skip)
      [ $# -ge 2 ] || { say "$usage"; exit 1; }
      skip+=("$2"); shift 2 ;;
    *) say "$usage"; exit 1 ;;
  esac
done
[[ "$repeat" =~ ^[1-9][0-9]*$ ]] && [[ "$pause" =~ ^[0-9]{1,3}$ ]] || { say "$usage"; exit 1; }

# the reads of the tabs (placeholder-free; the per-item ones such as `sys ct bindings <ct>` only run when an item is opened)
reads=(
  "status"
  "monitor disks"
  "pool info bulk"
  "pool info fast"
  "pool members bulk"
  "pool members fast"
  "pool disks"
  "shares overview"
  "shares principals"
  "shares deleted"
  "users list"
  "users groups"
  "ct list"
  "backup state"
  "backup overview"
  "backup snapshots"
  "jobs list"
  "jobs running"
  "logs units"
  "system doctor"
  "system cleanup"
  "system config"
)

for s in ${skip[@]+"${skip[@]}"}; do
  kept=() found=false
  for c in "${reads[@]}"; do
    if [ "$c" = "$s" ]; then found=true; else kept+=("$c"); fi
  done
  $found || { say "$usage"; exit 1; }   # a word that names no read would silently leave it in
  reads=("${kept[@]}")
done

now_ms() { echo $(( $(date +%s%N) / 1000000 )); }

if $split; then
  . "$here/lib/perf-split.sh"
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  perf_split_setup "$tmp"
  timeout_bin=$(type -P timeout)
fi

rows="" first=true
for c in "${reads[@]}"; do
  $first || [ "$pause" -eq 0 ] || sleep "$pause"
  first=false
  worst=0 rc=0 cpu=- slowest=-1 parts=""
  for ((i = 0; i < repeat; i++)); do
    r=0
    t0=$(now_ms)
    if $split; then
      TIMEFORMAT='%3U %3S'
      # shellcheck disable=SC2086
      { time HS_CALLER=ui timeout 120 bash "$hsbin" sys $c >/dev/null 2>&1 </dev/null; } 2>"$tmp/clean" || r=$?
    else
      # shellcheck disable=SC2086
      HS_CALLER=ui timeout 120 bash "$hsbin" sys $c >/dev/null 2>&1 </dev/null || r=$?
    fi
    t1=$(now_ms)
    if [ $((t1 - t0)) -ge "$worst" ]; then
      worst=$((t1 - t0))
      ! $split || cpu=$(tail -n 1 "$tmp/clean" | tr ',' '.' | LC_ALL=C awk '{ printf "%.3f", $1 + $2 }')
    fi
    [ "$r" -eq 0 ] || rc=$r
    if $split; then
      # shellcheck disable=SC2086
      HS_CALLER=ui perf_split_run "$timeout_bin" 120 "$BASH" "$hsbin" sys $c
      total_ms=$(LC_ALL=C awk -v s="$ps_total_wall" 'BEGIN { printf "%d", s * 1000 }')
      if [ "$total_ms" -gt "$slowest" ]; then
        slowest=$total_ms
        parts=$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s' "$ps_disp_wall" "$ps_disp_cpu" "$ps_tool_wall" "$ps_tool_cpu" "$ps_tool_calls" "$ps_rest_wall" "$ps_rest_cpu")
      fi
    fi
  done
  row=$(printf '%s\t%s\t%s' "$worst" "$rc" "$c")
  ! $split || row+=$(printf '\t%s\t%s' "$cpu" "$parts")
  rows+=$row$'\n'
done
sorted=$(printf '%s' "$rows" | sort -t$'\t' -k1,1nr)

if $list; then
  printf '%s\n' "$sorted" | awk -F'\t' -v OFS='\t' '{ $1 = sprintf("%d.%03d", $1 / 1000, $1 % 1000); print }'
  exit 0
fi

total=$(printf '%s\n' "$sorted" | awk -F'\t' '{ s += $1 } END { print s + 0 }')
slow=$(printf '%s\n' "$sorted" | awk -F'\t' '$1 > 1000 { n++ } END { print n + 0 }')
failed=$(printf '%s\n' "$sorted" | awk -F'\t' '$2 != 0 { n++ } END { print n + 0 }')
if [ "$failed" -gt 0 ]; then status_line "Reads that failed" "$failed" warn; else status_line "Reads that failed" "None" ok; fi
if [ "$slow" -gt 0 ]; then status_line "Slower than 1 s" "$slow" warn; else status_line "Slower than 1 s" "None" ok; fi
if $split; then
  {
    thead 'SECONDS' 'CPU' 'DISPATCHER' 'TOOLS' 'CALLS' 'REST' 'EXIT' 'COMMAND'
    printf '%s\n' "$sorted" | awk -F'\t' '{ printf "%d.%02d\t%s\t%s/%s\t%s/%s\t%s\t%s/%s\t%s\ths sys %s\n", $1 / 1000, ($1 % 1000) / 10, $4, $5, $6, $7, $8, $9, $10, $11, ($2 == 0 ? "ok" : $2), $3 }'
  } | table
  note "DISPATCHER, TOOLS and REST: wall/CPU seconds of a second run. CPU of a service that a tool talks to (incusd, smbd) is not counted."
else
  {
    thead 'SECONDS' 'EXIT' 'COMMAND'
    printf '%s\n' "$sorted" | awk -F'\t' '{ printf "%d.%02d\t%s\t%s\n", $1 / 1000, ($1 % 1000) / 10, ($2 == 0 ? "ok" : $2), "hs sys " $3 }'
  } | table
fi
note "$(t 'All reads one after the other: %s s. The interface runs them in parallel and shows the visible tab first.' "$(awk -v ms="$total" 'BEGIN { printf "%.1f", ms / 1000 }')")"
