#!/usr/bin/env bash
# help: let the spinning pool, parity and backup disks go to sleep after diskSpindownMinutes (per pool: diskSpindownPools) in machine.toml (0 = never); `power` shows sleep state and measured watts, `log` measures wake-ups
# help.de: lässt die drehenden Pool-, Parity- und Backup-Platten nach diskSpindownMinutes (je Pool: diskSpindownPools) in machine.toml schlafen (0 = nie); `power` zeigt Schlafzustand und gemessene Watt
# args: apply | status | power | log [hours]
# apply: set the standby timer (hdparm -S) on every rotational disk that is a bulk/parity/backup member. SSDs, NVMe, the system disk and
# the `fast` pool are never touched. 0/unset = hdparm -S 0 (timer off). status: plain tab separated lines
# (dev, rotational, member, state, minutes); `hdparm -C` reads the power state without waking the disk.
# Per pool: machine.toml `diskSpindownPools = { backup = 10, bulk = 30 }` replaces diskSpindownMinutes for the disks of that pool (0 = never; no per-disk
# value); test knob HS_SPINDOWN_POOLS (JSON of that table).
# power (hs sys disk power, plain, no root needed for the UPS reading): `disk<TAB>dev<TAB>state<TAB>since<TAB>wakes` per spinning member disk (state
# asleep|spinning|unknown, since = epoch seconds of the last change seen, wakes = asleep->awake changes seen today; counted at each reading, kept in
# $HS_STATE_DIR/spindown-power.tsv, so a wake between two readings counts once) and `power<TAB>source<TAB>what<TAB>watts` for every number that was
# MEASURED: the UPS output (ups.sh power) and the CPU package (RAPL, /sys/class/powercap, two readings HS_RAPL_INTERVAL s apart). Nothing is
# estimated and there is no number per disk. Test knobs: HS_STATE_DIR, HS_POWERCAP, HS_RAPL_INTERVAL, HS_SPINDOWN_NOW (epoch), HS_SPINDOWN_STATE (state
# of every disk: file with "dev state" lines; replaces hdparm).
# Test knobs: HS_SPINDOWN_SYSFS (default /sys/block), HS_SPINDOWN_MEMBERS (file with member disk names; replaces the lookup),
# HS_SPINDOWN_MINUTES (replaces machine.toml).
# log [hours] (root, default 24): every minute read /sys/block/<d>/stat (kernel counters, no disk access) and `hdparm -C` of each spinning member
# disk; a minute in which a disk did I/O or came out of standby is written to the log file (default /var/log/hs-spindown.log) with the systemd
# units that started in that minute (journal). Test knobs: HS_SPINDOWN_LOGFILE, HS_SPINDOWN_INTERVAL (seconds between samples, default 60),
# HS_SPINDOWN_SAMPLES (number of samples; replaces hours), HS_SPINDOWN_NOROOT.
set -euo pipefail
here=$(dirname "$0")
. "$here/lib/ui.sh"
. "$here/lib/machine.sh"

usage() { say "usage: hs disk spindown [apply|status|power|log [hours]]"; exit 1; }
mode=${1:-status}
case "$mode" in apply|status|log|power|--value) ;; *) usage ;; esac

minutes=${HS_SPINDOWN_MINUTES:-$(machine_get diskSpindownMinutes 2>/dev/null || echo 0)}
case "$minutes" in ''|*[!0-9]*) minutes=0 ;; esac

# minutes -> hdparm -S value: 1..240 = n * 5 s (up to 20 min), 241..251 = (n - 240) * 30 min. Over 20 minutes the value rounds up to
# whole half hours; the longest is 251 (5.5 h).
spindown_value() {
  local m=$1
  if [ "$m" -le 0 ]; then echo 0
  elif [ "$m" -le 20 ]; then echo $(( (m * 60 + 4) / 5 ))
  else
    local v=$(( 240 + (m + 29) / 30 ))
    [ "$v" -le 251 ] || v=251
    echo "$v"
  fi
}
if [ "${1:-}" = "--value" ]; then spindown_value "${2:-0}"; exit 0; fi

sysfs=${HS_SPINDOWN_SYSFS:-/sys/block}

# the disks that carry pool data, parity or the backup, with their pool: `disk<TAB>pool` (the backup disk's pool is `backup`). SnapRAID disks are found by
# file system label, ZFS pool members by `zpool status` of every ZFS data pool in machine.toml.
# Test file (HS_SPINDOWN_MEMBERS): one disk per line, an optional second word is its pool (none = the global default).
members_pairs() {
  if [ -n "${HS_SPINDOWN_MEMBERS:-}" ]; then
    awk 'NF { print $1 "	" (NF > 1 ? $2 : "-") }' "$HS_SPINDOWN_MEMBERS" 2>/dev/null || true; return 0
  fi
  . "$here/lib/pools.sh"
  local d p l pool pk sn
  sn=$(pool_snapraid 2>/dev/null || pool_default data 2>/dev/null || echo -)
  for d in "$sysfs"/*; do
    d=${d##*/}
    l=$(lsblk -rno LABEL "/dev/$d" 2>/dev/null | grep -E '^(bulk-data-[0-9]+|bulk-parity-[0-9]+|backup)$' | head -n 1 || true)
    case "$l" in
      backup) printf '%s	backup
' "$d" ;;
      ?*) printf '%s	%s
' "$d" "$sn" ;;
    esac
  done
  if command -v zpool >/dev/null 2>&1; then
    for pool in $(pool_names data); do
      pk=$(pool_kind "$pool" 2>/dev/null || true); [ "$pk" = zfs ] || continue
      zpool status -LP "$pool" 2>/dev/null | awk '$1 ~ /^\/dev\// {print $1}' | while read -r p; do
        d=$(lsblk -rno PKNAME "$p" 2>/dev/null | head -n 1 | grep . || basename "$p")
        printf '%s	%s
' "$d" "$pool"
      done
    done
  fi
  return 0
}
members() { members_pairs | cut -f1; }

# minutes of one pool: diskSpindownPools[pool], else diskSpindownMinutes. HS_SPINDOWN_POOLS (JSON) replaces machine.toml in tests.
pool_minutes_table() {   # pool<TAB>minutes per entry
  local json=${HS_SPINDOWN_POOLS:-} py=${HS_PYTHON:-python3}
  [ -n "$json" ] || json=$(machine_get_json diskSpindownPools 2>/dev/null || true)
  [ -n "$json" ] && [ "$json" != null ] || return 0
  command -v "$py" >/dev/null 2>&1 || py=python
  printf '%s' "$json" | PYTHONUTF8=1 "$py" -c 'import json,sys
d = json.load(sys.stdin)
for k, v in (d.items() if isinstance(d, dict) else []):
    if type(v) is int and v >= 0: print("%s	%d" % (k, v))' | tr -d ''
}
pool_minutes() {   # pool_minutes <pool>
  local m
  m=$(awk -F'	' -v p="$1" '$1 == p { print $2; exit }' <<<"$ptable")
  [ -n "$m" ] && echo "$m" || echo "$minutes"
}

is_rot() { [ "$(cat "$sysfs/$1/queue/rotational" 2>/dev/null || echo 0)" = 1 ]; }
sysdisk() {   # is this disk the one under / or /boot?
  local src
  for src in / /boot; do
    findmnt -no SOURCE "$src" 2>/dev/null | head -n 1 | xargs -r -I{} lsblk -rno PKNAME {} 2>/dev/null
  done | grep -qx "$1"
}

ptable=$(pool_minutes_table)
pairs=$(members_pairs | sort -u)
mem=$(cut -f1 <<<"$pairs" | sort -u)
disk_pool() { awk -F'	' -v d="$1" '$1 == d { print $2; exit }' <<<"$pairs"; }
disk_minutes() { local p; p=$(disk_pool "$1"); [ -n "$p" ] && [ "$p" != - ] && pool_minutes "$p" || echo "$minutes"; }
if [ "$mode" = log ]; then
  [ "$(id -u)" = 0 ] || [ -n "${HS_SPINDOWN_NOROOT:-}" ] || fail "$(t 'Measuring the spin-down needs root. Run it as: sudo hs disk spindown log')"
  hours=${2:-24}
  case "$hours" in ''|*[!0-9]*|0) fail "$(t 'The number of hours must be a whole number above 0.')" ;; esac
  interval=${HS_SPINDOWN_INTERVAL:-60}
  samples=${HS_SPINDOWN_SAMPLES:-$(( hours * 3600 / interval ))}
  logfile=${HS_SPINDOWN_LOGFILE:-/var/log/hs-spindown.log}
  disks=$(for d in $mem; do is_rot "$d" && ! sysdisk "$d" && echo "$d"; done || true)
  [ -n "$disks" ] || fail "$(t 'No spinning pool member disk found.')"
  # I/O counters: reads completed + writes completed (fields 1 and 5 of the stat file)
  ios() { awk '{print $1 + $5}' "$sysfs/$1/stat" 2>/dev/null || echo 0; }
  declare -A prev_io prev_st
  for d in $disks; do prev_io[$d]=$(ios "$d"); prev_st[$d]=$(hdparm -C "/dev/$d" 2>/dev/null | awk '/drive state is:/ {print $NF}'); done
  printf '# %s: hs disk spindown log, %s samples every %s s, disks: %s
' "$(date '+%F %T')" "$samples" "$interval" "$(echo $disks)" >> "$logfile"
  step "$(t 'Measuring for %s hours (every %s s); log: %s' "$hours" "$interval" "$logfile")"
  t0=$(date +%s); wakes=0
  for ((i = 0; i < samples; i++)); do
    sleep "$interval"
    t1=$(date +%s)
    units=""
    for d in $disks; do
      io=$(ios "$d"); st=$(hdparm -C "/dev/$d" 2>/dev/null | awk '/drive state is:/ {print $NF}'); [ -n "$st" ] || st=unknown
      delta=$(( io - ${prev_io[$d]} ))
      if [ "$delta" -gt 0 ] || { [ "${prev_st[$d]}" = standby ] && [ "$st" != standby ]; }; then
        if [ -z "$units" ]; then
          units=$(journalctl -q --no-pager -o cat --since "@$t0" --until "@$t1" 2>/dev/null             | awk '/^(Started|Starting) / {print $2}' | grep -E '\.(service|timer|mount|scope)$' | sort -u | paste -sd, - || true)
          [ -n "$units" ] || units=-
        fi
        wake=io; [ "${prev_st[$d]}" = standby ] && [ "$st" != standby ] && wake=woke
        printf '%s	%s	%s	%s	io+%s	%s
' "$(date -d "@$t1" '+%F %T')" "$d" "$wake" "$st" "$delta" "$units" >> "$logfile"
        wakes=$((wakes + 1))
      fi
      prev_io[$d]=$io; prev_st[$d]=$st
    done
    t0=$t1
  done
  ok "$(t '%s disk events written to %s' "$wakes" "$logfile")"
  { printf 'time	disk	event	state	io	units
'; grep -v '^#' "$logfile" | tail -n 40; } | table
  exit 0
fi
case "$mode" in
  status)
    printf 'disk\trotational\tmember\tstate\tminutes\n'
    for d in "$sysfs"/*; do
      d=${d##*/}
      case "$d" in loop*|ram*|zd*|dm-*|md*|sr*|nbd*) continue ;; esac
      rot=no; is_rot "$d" && rot=yes
      m=no; grep -qx "$d" <<<"$mem" && m=yes
      st=-
      if [ "$rot" = yes ] && command -v hdparm >/dev/null 2>&1; then
        st=$(hdparm -C "/dev/$d" 2>/dev/null | awk '/drive state is:/ {print $NF}')
        [ -n "$st" ] || st=-
      fi
      printf '%s\t%s\t%s\t%s\t%s\n' "$d" "$rot" "$m" "$st" "$([ "$rot$m" = yesyes ] && disk_minutes "$d" || echo -)"
    done ;;
  power)
    sf=${HS_STATE_DIR:-/var/lib/hs}/spindown-power.tsv
    now=${HS_SPINDOWN_NOW:-$(date +%s)}; day=$(date -d "@$now" +%F 2>/dev/null || date +%F)
    newstate=$(mktemp)
    for d in $mem; do
      is_rot "$d" || continue
      sysdisk "$d" && continue
      if [ -n "${HS_SPINDOWN_STATE:-}" ]; then st=$(awk -v d="$d" '$1 == d { print $2; exit }' "$HS_SPINDOWN_STATE" 2>/dev/null)
      else st=$(hdparm -C "/dev/$d" 2>/dev/null | awk '/drive state is:/ {print $NF}'); fi
      case "$st" in standby|sleeping|asleep) st=asleep ;; "") st=unknown ;; *) st=spinning ;; esac
      old=$(awk -F'	' -v d="$d" '$1 == d' "$sf" 2>/dev/null || true)
      since=$now wakes=0
      if [ -n "$old" ]; then
        IFS=$'	' read -r _ ost osince oday owakes <<<"$old"
        since=$osince; wakes=$owakes
        [ "$oday" = "$day" ] || wakes=0
        if [ "$ost" != "$st" ]; then
          since=$now
          [ "$ost" = asleep ] && [ "$st" = spinning ] && wakes=$((wakes + 1))
        fi
      fi
      printf '%s	%s	%s	%s	%s
' "$d" "$st" "$since" "$day" "$wakes" >> "$newstate"
      printf 'disk	%s	%s	%s	%s
' "$d" "$st" "$since" "$wakes"
    done
    mkdir -p "$(dirname "$sf")" 2>/dev/null && cp "$newstate" "$sf" 2>/dev/null || true
    rm -f "$newstate"
    # measured power only, each with its source
    w=$(bash "$here/ups.sh" power 2>/dev/null | head -n 1 || true)
    case "$w" in ''|*[!0-9]*) ;; *) printf 'power	ups	whole server (UPS output)	%s
' "$w" ;; esac
    pc=${HS_POWERCAP:-/sys/class/powercap}
    for z in "$pc"/intel-rapl:[0-9]; do
      [ -r "$z/energy_uj" ] || continue
      e1=$(cat "$z/energy_uj" 2>/dev/null) || continue
      iv=${HS_RAPL_INTERVAL:-1}; sleep "$iv"
      e2=$(cat "$z/energy_uj" 2>/dev/null) || continue
      max=$(cat "$z/max_energy_range_uj" 2>/dev/null || echo 0)
      case "$e1$e2" in *[!0-9]*|'') continue ;; esac
      [ "$e2" -ge "$e1" ] || { [ "$max" -gt 0 ] && e2=$((e2 + max)) || continue; }
      printf 'power	rapl	CPU package (%s)	%s
' "$(cat "$z/name" 2>/dev/null || echo package)" "$(awk -v a="$e1" -v b="$e2" -v i="$iv" 'BEGIN { printf "%.1f", (b - a) / 1000000 / i }')"
    done
    ;;
  apply)
    command -v hdparm >/dev/null 2>&1 || fail "hdparm is not installed."
    n=0
    for d in $mem; do
      is_rot "$d" || { note "$d: not a spinning disk, left alone"; continue; }
      sysdisk "$d" && { note "$d: system disk, left alone"; continue; }
      dm=$(disk_minutes "$d"); value=$(spindown_value "$dm")
      if hdparm -S "$value" "/dev/$d" >/dev/null 2>&1; then
        n=$((n + 1))
        if [ "$dm" -gt 0 ]; then ok "$d: standby after $dm min (hdparm -S $value)"; else ok "$d: standby timer off"; fi
      else
        warn "$d: refuses hdparm -S (USB bridge or firmware), left as it is"
      fi
    done
    [ "$n" -gt 0 ] || note "no disk to set"
    ;;
esac
