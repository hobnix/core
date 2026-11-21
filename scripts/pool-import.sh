#!/usr/bin/env bash
# help: bring in a ZFS pool that is already on the disks, under its own name (nothing is erased; plan first, you type a disk name)
# help.de: einen ZFS-Pool übernehmen, der schon auf den Platten ist, unter seinem Namen (nichts wird gelöscht; erst der Plan, dann den Namen einer Platte tippen)
# args: <pool> [--use data] [--dry-run] [--yes]  |  plan|start <pool> [--use data] [--confirm <disk>]
# Imports a healthy, exported ZFS pool by its id (zpool import -N, never -f), checks that it mounts at /<pool>, writes its row to the
# pools line of machine.toml and creates <pool>/shares and <pool>/sensitive when they are missing. Nothing on the disks is erased.
# plan: the plan as key<TAB>value lines (the contract of hs sys pool plan: status, heading, text, step, note, command, confirm_name, long,
#   option); exit 0 allowed, 1 refused. start: the same checks, then a background job; --confirm must be the name of a disk of the pool.
# Terminal (hs pool <pool> import): the plan, then you type the name of a disk; --dry-run stops after the plan; --yes is the job body.
# Refused, with one reason each: a name outside the pool name rule, a server without a pools line, an imported pool, the SnapRAID pool,
# no or two pools of that name, a damaged pool, a pool last used by another system, a member that is not a whole disk, a disk that is not
# free of this pool, an apps pool, files already under /<pool>.
# Test knobs: HS_ZPOOL, HS_ZFS, HS_DISCOVER, HS_BYID, HS_POOLS_ROOT, HS_RUN_DIR, HS_GUIDED_TTY, and those of lib/pools.sh.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib/ui.sh
. "$here/lib/ui.sh"
# shellcheck source=scripts/lib/admin.sh
. "$here/lib/admin.sh"
# shellcheck source=scripts/lib/pools.sh
. "$here/lib/pools.sh"
# shellcheck source=scripts/lib/admin.sh
. "$here/lib/admin.sh"
# shellcheck source=scripts/lib/pools-write.sh
. "$here/lib/pools-write.sh"
# shellcheck source=scripts/lib/effect.sh
. "$here/lib/effect.sh"
# shellcheck source=scripts/lib/live.sh
. "$here/lib/live.sh"

zpool=${HS_ZPOOL:-zpool}
zfs=${HS_ZFS:-zfs}
byid=${HS_BYID:-/dev/disk/by-id}
discover=${HS_DISCOVER:-$here/storage-discover.sh}
tab=$'\t'

machine=false mode=terminal pool="" use="" confirm_word="" dry=false assume_yes=false
case "${1:-}" in plan|start) mode=$1; machine=true; shift ;; esac
[ $# -gt 0 ] || { say "usage: hs pool <pool> import [--use data] [--dry-run]"; exit 1; }
pool=$1; shift
while [ $# -gt 0 ]; do
  case "$1" in
    --use)      use=${2:-}; shift 2 || shift ;;
    --confirm)  confirm_word=${2:-}; shift 2 || shift ;;
    --dry-run)  dry=true; shift ;;
    --yes)      assume_yes=true; shift ;;
    *) if $machine; then printf 'status\trefused\nreason\tunknown option %s\n' "$1"; else say "usage: hs pool <pool> import [--use data] [--dry-run]"; fi; exit 1 ;;
  esac
done

interactive() { { [ -t 0 ] && [ -t 1 ] && [ -z "${HS_CALLER:-}" ]; } || [ -n "${HS_GUIDED_TTY:-}" ]; }

refuse() {   # refuse <reason>: one line to the interface, or a failure on the terminal
  if $machine; then printf 'status\trefused\nreason\t%s\n' "$1"; exit 1; fi
  fail "$1"
}

pid="" confirm_disk="" disks=() sizes=()

# The listing of importable pools (never with a pool name: nothing is imported by looking). Lines:
#   B<TAB>pool<TAB>id<TAB>state<TAB>status and action text      one per pool
#   M<TAB>pool<TAB>id<TAB>member<TAB>state                      one per disk
import_listing() {
  "$zpool" import -d "$byid" 2>/dev/null | awk -v T="$tab" '
    function flush() { if (name != "" && !done) { print "B" T name T id T state T text; done = 1 } }
    /^[ \t]*pool:/ { flush(); name = $2; id = "-"; state = "-"; text = ""; cfg = 0; done = 0; field = ""; next }
    /^[ \t]*id:/ && !cfg { id = $2; next }
    /^[ \t]*state:/ && !cfg { state = $2; field = ""; next }
    /^[ \t]*(status|action|see):/ && !cfg { s = $0; sub(/^[ \t]*[a-z]+:[ \t]*/, "", s); text = text " " s; field = "t"; next }
    /^[ \t]*config:/ { flush(); cfg = 1; field = ""; next }
    /^[ \t]*errors:/ { cfg = 0; next }
    !cfg && field == "t" && NF { s = $0; sub(/^[ \t]+/, "", s); text = text " " s; next }
    cfg && NF >= 2 && $1 != "NAME" && $1 != name && $1 !~ /^(mirror|raidz[123]?|draid[0-9a-z:]*|spares?|logs?|cache|special|dedup|replacing)(-[0-9]+)?$/ \
      && $2 ~ /^(ONLINE|DEGRADED|UNAVAIL|FAULTED|OFFLINE|REMOVED|AVAIL|INUSE)$/ { print "M" T name T id T $1 T $2 }
    END { flush() }'
}

# import_check <pool> <use>: sets pid, disks, sizes and confirm_disk, or refuses (the first reason that applies)
import_check() {
  local p=$1 u=$2 listing blocks members n state text m disk base row k l s ids line
  pool_name_ok "$p" || refuse "the name '$p' does not fit the pool name rule (a lower case letter, then up to 11 lower case letters or digits)"
  [ "$(pools_source)" != legacy ] || refuse "Run hs pool record first: this server has no pools line, so the pool would not be known to the system."
  if "$zpool" list -H "$p" >/dev/null 2>&1; then refuse "$p is imported already"; fi
  if pool_is_snapraid "$p"; then refuse "$p is the SnapRAID pool of this server"; fi
  listing=$(import_listing || true)
  blocks=$(awk -F'\t' -v p="$p" '$1 == "B" && $2 == p' <<<"$listing")
  n=0; [ -z "$blocks" ] || n=$(wc -l <<<"$blocks" | tr -d ' ')
  [ "$n" -gt 0 ] || refuse "no pool called $p is waiting to be imported (hs sys storage discover lists what is on the disks)"
  if [ "$n" -gt 1 ]; then
    ids=$(cut -f3 <<<"$blocks" | paste -sd, - | sed 's/,/, /g')
    refuse "two pools are called $p (ids $ids): import by id is not offered"
  fi
  pid=$(cut -f3 <<<"$blocks"); state=$(cut -f4 <<<"$blocks"); text=$(cut -f5 <<<"$blocks")
  members=$(awk -F'\t' -v p="$p" '$1 == "M" && $2 == p' <<<"$listing")
  if [ "$state" != ONLINE ] || grep -qE "${tab}(UNAVAIL|FAULTED|REMOVED|OFFLINE)\$" <<<"$members"; then
    refuse "$p is damaged (state $state): it is not imported here"
  fi
  if grep -qE "(^|[ '\"])-f([ '\".]|\$)|another system" <<<"$text"; then
    refuse "$p was last used by another system: export it there first (it is never forced)"
  fi
  disks=(); sizes=()
  local seen=" " rows=""
  rows=$(bash "$discover" 2>/dev/null || true)
  while IFS="$tab" read -r _ _ _ m _; do
    [ -n "$m" ] || continue
    case "$m" in
      "$byid"/*) ;;
      /dev/disk/by-id/*) m="$byid/${m#/dev/disk/by-id/}" ;;
      /*) refuse "a disk of $p is not a whole disk here ($m)" ;;
      *) m="$byid/$m" ;;
    esac
    base=${m#"$byid"/}
    case "$base" in */*|*[!0-9]*) ;; *) refuse "a disk of $p is not a whole disk here ($base)" ;; esac
    [ -e "$m" ] || refuse "a disk of $p is not a whole disk here ($base)"
    disk=$(sed -E 's/-part[0-9]+$//' <<<"$base")
    case "$seen" in *" $disk "*) continue ;; esac
    seen+="$disk "
    row=$(awk -F'\t' -v d="$disk" '$1 == d' <<<"$rows")
    [ -n "$row" ] || refuse "$disk is not a disk this server sees, not a free disk of $p"
    k=$(cut -f5 <<<"$row"); l=$(cut -f6 <<<"$row"); s=$(cut -f7 <<<"$row")
    if [ "$k" != zfs ] || [ "$l" != "$p" ] || [ "$s" != importable ]; then
      refuse "$disk is $k $s, not a free disk of $p"
    fi
    disks+=("$disk"); sizes+=("$(numfmt --to=iec --suffix=B "$(cut -f2 <<<"$row")" 2>/dev/null || cut -f2 <<<"$row")")
  done <<<"$members"
  [ ${#disks[@]} -gt 0 ] || refuse "no disk of $p is a whole disk here"
  [ "$u" = data ] || refuse "importing an apps pool comes later"
  case "$(pool_role "$p" 2>/dev/null || true)" in apps) refuse "importing an apps pool comes later" ;; esac
  local root; root=$(pool_root "$p")
  if [ -d "$root" ] && ! pool_mounted "$p" && [ -n "$(ls -A "$root" 2>/dev/null || true)" ]; then
    refuse "/$p already holds files on the system disk"
  fi
  # the disk to type: the first of the pool's disks in sorted order
  line=$(printf '%s\n' "${disks[@]}" | sort | head -n1)
  confirm_disk=$line
}

plan_lines() {   # plan_lines <pool>: the plan as data (the contract of hs sys pool plan)
  local p=$1 i
  printf 'status\tok\n'
  printf 'heading\timport the ZFS pool %s (%s disks); nothing on the disks is erased\n' "$p" "${#disks[@]}"
  for i in "${!disks[@]}"; do printf 'text\tdisk %s (%s)\n' "${disks[$i]}" "${sizes[$i]}"; done
  printf 'step\timport %s without mounting it\n' "$p"
  printf 'step\tcheck that %s mounts at /%s, then mount its datasets\n' "$p" "$p"
  printf 'step\tcreate %s/shares and %s/sensitive when they are missing (nothing else is written)\n' "$p" "$p"
  printf 'step\tadd %s to the pools line of machine.toml (role data, kind zfs)\n' "$p"
  printf 'note\tIf %s is encrypted it stays locked until hs unlock.\n' "$p"
  printf 'note\t%s\n' "$(effect_rebuild)"
  printf 'command\tzpool import -N -d %s %s\n' "$byid" "$pid"
  printf 'confirm_name\t%s\n' "$confirm_disk"
  printf 'long\tno\n'
  printf 'option\tuse\tdata\tdata\n'
}

refresh_topics() {
  live_refresh event:pool.imported
}

do_import() {   # do_import <pool>: the job body
  local p=$1 mp alt name canmount made=false
  step "Importing the ZFS pool $p"
  spin "Importing $p without mounting it" "$zpool" import -N -d "$byid" "$pid" || exit 1
  mp=$("$zfs" get -H -o value mountpoint "$p" 2>/dev/null || true)
  alt=$("$zpool" get -H -o value altroot "$p" 2>/dev/null || true)
  if [ "$mp" != "/$p" ] || [ "$alt" != - ]; then
    "$zpool" export "$p" || true
    fail "$(t '%s mounts at %s, not /%s; it was exported again, nothing changed' "$p" "$mp" "$p")"
  fi
  if "$zfs" get -H -r -o value keystatus "$p" 2>/dev/null | grep -qx unavailable; then
    note "$(t '%s is encrypted: hs unlock opens it' "$p")"
  else
    step "Mounting $p"
    while IFS="$tab" read -r name canmount; do
      [ "$canmount" = on ] || continue
      "$zfs" mount "$name" || warn "$(t 'Could not mount %s' "$name")"
    done < <("$zfs" list -H -o name,canmount -r "$p")
    if ! "$zfs" list -H -o name "$p/shares" >/dev/null 2>&1; then "$zfs" create "$p/shares" && made=true || warn "$(t 'Could not create %s' "$p/shares")"; fi
    "$zfs" list -H -o name "$p/sensitive" >/dev/null 2>&1 || "$zfs" create "$p/sensitive" || warn "$(t 'Could not create %s' "$p/sensitive")"
    # a new shares dataset is written as adminuser, like a pool made here (an existing one is not touched)
    if $made && id "$(admin_user)" >/dev/null 2>&1; then chown "$(admin_user):users" "/$p/shares"; chmod 2775 "/$p/shares"; fi
  fi
  step "Recording $p"
  effect_say rebuild
  if pools_add_row "$p" data zfs; then
    ok "$(t 'The pools line of machine.toml has the row for %s' "$p")"
  else
    warn "$(t 'The pool is imported, but its row could not be written. Add it to the pools line of /etc/nixos/machine.toml: %s = { role = "data", kind = "zfs" }  (then hs rebuild)' "$p")"
  fi
  refresh_topics "$p"
  ok "$(t 'The pool %s is imported' "$p")"
}

[ -n "$use" ] || use=data
case "$use" in data|apps) ;; *) refuse "--use: data or apps" ;; esac

case "$mode" in
  plan)
    import_check "$pool" "$use"
    plan_lines "$pool"
    exit 0 ;;
  start)
    import_check "$pool" "$use"
    if [ "$confirm_word" != "$confirm_disk" ]; then refuse "type the name to confirm: $confirm_disk"; fi
    # shellcheck source=scripts/lib/job.sh
    . "$here/lib/job.sh"
    unit=$(hs_job "pool-import-$pool" "hs pool $pool import" -- bash "$here/pool-import.sh" "$pool" --use data --yes) \
      || refuse "the job could not be started"
    printf 'status\tstarted\nunit\t%s\n' "$unit"
    exit 0 ;;
esac

# terminal
import_check "$pool" "$use"
if $assume_yes; then do_import "$pool"; exit 0; fi
plan=$(plan_lines "$pool")
while IFS="$tab" read -r tag val; do
  case "$tag" in
    heading) step "$val" ;;
    text)    kv "$(t 'Disk')" "${val#disk }" ;;
    step)    line "- $val" ;;
    note)    note "$val" ;;
    command) kv "$(t 'Command')" "$val" ;;
  esac
done <<<"$plan"
if $dry; then exit 0; fi
interactive || fail "$(t 'This asks for a disk name: run it on a terminal, or start it from the web interface.')"
confirm_name "$confirm_disk" "a disk of the pool" || fail "cancelled"
if confirm "Run the import as a background job? (recommended: it keeps going if the terminal closes; follow it with: hs job follow)"; then
  # shellcheck source=scripts/lib/job.sh
  . "$here/lib/job.sh"
  unit=$(hs_job "pool-import-$pool" "hs pool $pool import" -- bash "$here/pool-import.sh" "$pool" --use data --yes) || exit 1
  ok "$(t 'Started as job %s. Follow it: hs job follow %s' "$unit" "$unit")"
  exit 0
fi
do_import "$pool"
