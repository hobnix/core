#!/usr/bin/env bash
# scripts/pool-import.sh (hs pool <pool> import, hs sys pool plan|start <pool> import): bring in a ZFS pool that is on the disks already.
# Runs against fake zpool, zfs, storage discover and systemd-run: no root, no disks. What is checked: the plan shape, every refusal with
# its reason, that a listing never names a pool and a plan never imports, that start needs the name of a disk, that the job imports by id
# without -f, checks the mountpoint (and exports again when it is wrong), creates the datasets only when missing and writes the row.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
T=$'\t'
FIX=$ROOT/tests/fixtures/pool-import
B=$WORK/bin; mkdir -p "$B" "$WORK/byid" "$WORK/state" "$WORK/run"
export HS_PLAIN=1 HS_LANG=en HS_STATE_DIR=$WORK/state HS_RUN_DIR=$WORK/run HS_LIVE_LOG=$WORK/live
export HS_MACHINE_FILE=$WORK/machine.toml HS_BULK_TYPE_FILE=$WORK/bulk-type HS_POOLS_ROOT=$WORK/root
export HS_ZPOOL=$B/zpool HS_ZFS=$B/zfs HS_BYID=$WORK/byid HS_DISCOVER=$WORK/discover.sh
unset HS_CALLER HS_GUIDED_TTY
LOG=$WORK/log
touch "$WORK/byid/ata-A-part1" "$WORK/byid/ata-B-part1" "$WORK/byid/ata-C-part1"

cat > "$B/zpool" <<'FAKE'
#!/usr/bin/env bash
W=$(dirname "$0")/..
echo "zpool $*" >> "$W/log"
case "$1" in
  list) grep -qx "$3" "$W/imported" 2>/dev/null ;;
  import) if [ "${2:-}" = -N ]; then echo "$5" >> "$W/imported"; echo tank >> "$W/imported"; else cat "$W/listing"; fi ;;
  get) cat "$W/altroot" 2>/dev/null || echo - ;;
  export) : ;;
esac
FAKE
cat > "$B/zfs" <<'FAKE'
#!/usr/bin/env bash
W=$(dirname "$0")/..
echo "zfs $*" >> "$W/log"
case "$1" in
  get) case "$*" in *keystatus*) cat "$W/keystatus" 2>/dev/null || echo - ;; *) cat "$W/mountpoint" ;; esac ;;
  list) case "$*" in
          *"-r"*) printf 'tank\ton\ntank/data\ton\ntank/off\toff\n' ;;
          *) grep -qx "${!#}" "$W/datasets" 2>/dev/null ;;
        esac ;;
  create) echo "$2" >> "$W/datasets" ;;
  mount) : ;;
esac
FAKE
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/jobcalls"\n' "$WORK" > "$B/systemd-run"
cat > "$WORK/discover.sh" <<'FAKE'
#!/usr/bin/env bash
cat "$(dirname "$0")/disc.tsv"
FAKE
chmod +x "$B/zpool" "$B/zfs" "$B/systemd-run"
export PATH=$B:$PATH
PI=$ROOT/scripts/pool-import.sh

good_disc() {
  printf 'ata-A\t3.6T\tsata\tM\tzfs\ttank\timportable\nata-B\t3.6T\tsata\tM\tzfs\ttank\timportable\n' > "$WORK/disc.tsv"
}
reset() {   # reset <listing fixture>
  rm -rf "$WORK/imported" "$WORK/log" "$WORK/jobcalls" "$WORK/datasets" "$WORK/keystatus" "$WORK/altroot" "$WORK/live" "$WORK/root"
  cp "$FIX/$1.txt" "$WORK/listing"
  echo "/tank" > "$WORK/mountpoint"
  printf 'language = "en"\npools = {}\n' > "$HS_MACHINE_FILE"
  rm -f "$HS_BULK_TYPE_FILE"
  good_disc
}
run() {   # run <args...>: stdout in $out, exit code in $rc
  rc=0; out=$(timeout 30 bash "$PI" "$@" </dev/null 2>/dev/null) || rc=$?
}
reason() {   # reason <what> <expected reason>: the last run was refused with exactly that reason
  check_eq "$1: exit 1" 1 "$rc"
  check_eq "$1: reason" "status${T}refused
reason${T}$2" "$out"
}

echo "-- the plan"
reset ok
run plan tank --use data
check_eq "plan: exit 0" 0 "$rc"
want="status${T}ok
heading${T}import the ZFS pool tank (2 disks); nothing on the disks is erased
text${T}disk ata-A (3.6T)
text${T}disk ata-B (3.6T)
step${T}import tank without mounting it
step${T}check that tank mounts at /tank, then mount its datasets
step${T}create tank/shares and tank/sensitive when they are missing (nothing else is written)
step${T}add tank to the pools line of machine.toml (role data, kind zfs)
note${T}If tank is encrypted it stays locked until hs unlock.
note${T}This takes effect with hs rebuild. A rebuild takes several minutes; none has been timed on this server yet.
command${T}zpool import -N -d $WORK/byid 11111111111111111
confirm_name${T}ata-A
long${T}no
option${T}use${T}data${T}data"
check_eq "plan: the whole output" "$want" "$out"
run plan tank
check_eq "plan without --use is the data plan" "$want" "$out"
check_eq "the listing never names a pool" 0 "$(grep '^zpool import ' "$LOG" | grep -vc "^zpool import -d $WORK/byid\$" || true)"
check_eq "a plan imports nothing" 0 "$(grep -c 'import -N\|export\|create' "$LOG")"
check_eq "a plan writes no row" "language = \"en\"
pools = {}" "$(cat "$HS_MACHINE_FILE")"

echo "-- the refusals"
reset ok
run plan Tank
reason "name rule" "the name 'Tank' does not fit the pool name rule (a lower case letter, then up to 11 lower case letters or digits)"
run plan incus
reason "reserved name" "the name 'incus' does not fit the pool name rule (a lower case letter, then up to 11 lower case letters or digits)"
printf 'language = "en"\n' > "$HS_MACHINE_FILE"
run plan tank --use data
reason "legacy server" "Run hs pool record first: this server has no pools line, so the pool would not be known to the system."
reset ok
echo tank > "$WORK/imported"
run plan tank --use data
reason "imported already" "tank is imported already"
reset ok
printf 'language = "en"\npools = { tank = { role = "data", kind = "snapraid" } }\n' > "$HS_MACHINE_FILE"
run plan tank --use data
reason "the SnapRAID pool" "tank is the SnapRAID pool of this server"
reset ok
run plan other --use data
reason "no such pool" "no pool called other is waiting to be imported (hs sys storage discover lists what is on the disks)"
reset twice
run plan tank --use data
reason "two pools" "two pools are called tank (ids 11111111111111111, 22222222222222222): import by id is not offered"
reset degraded
run plan tank --use data
reason "degraded" "tank is damaged (state DEGRADED): it is not imported here"
reset unavail
run plan tank --use data
reason "newer features" "tank is damaged (state UNAVAIL): it is not imported here"
reset other-system
run plan tank --use data
reason "another system" "tank was last used by another system: export it there first (it is never forced)"
reset dm
run plan tank --use data
reason "device-mapper member" "a disk of tank is not a whole disk here (/dev/mapper/x)"
reset ok
printf 'ata-A\t3.6T\tsata\tM\tzfs\ttank\timportable\nata-B\t3.6T\tsata\tM\tluks\t-\tlocked\n' > "$WORK/disc.tsv"
run plan tank --use data
reason "a member that is luks" "ata-B is luks locked, not a free disk of tank"
printf 'ata-A\t3.6T\tsata\tM\tzfs\ttank\timportable\nata-B\t3.6T\tsata\tM\tos\t-\tsystem\n' > "$WORK/disc.tsv"
run plan tank --use data
reason "a member that is the system disk" "ata-B is os system, not a free disk of tank"
printf 'ata-A\t3.6T\tsata\tM\tzfs\ttank\timportable\nata-B\t3.6T\tsata\tM\tzfs\tother\timportable\n' > "$WORK/disc.tsv"
run plan tank --use data
reason "a member in another pool" "ata-B is zfs importable, not a free disk of tank"
printf 'ata-A\t3.6T\tsata\tM\tzfs\ttank\timportable\n' > "$WORK/disc.tsv"
run plan tank --use data
reason "a member discover does not list" "ata-B is not a disk this server sees, not a free disk of tank"
good_disc
run plan tank --use apps
reason "apps pool" "importing an apps pool comes later"
run plan tank --use bogus
reason "bad --use" "--use: data or apps"
mkdir -p "$WORK/root/tank"; echo x > "$WORK/root/tank/file"
run plan tank --use data
reason "files under /tank" "/tank already holds files on the system disk"
run start tank --use data --confirm ata-A
check_eq "start refuses the same way: exit 1" 1 "$rc"
check_eq "a refused start started nothing" 0 "$(wc -l < "$WORK/jobcalls" 2>/dev/null || echo 0)"

echo "-- start needs the name of a disk"
reset ok
run start tank --use data
reason "no --confirm" "type the name to confirm: ata-A"
run start tank --use data --confirm tank
reason "the pool name is not the word" "type the name to confirm: ata-A"
run start tank --use data --confirm ata-B
reason "another disk is not the word" "type the name to confirm: ata-A"
check_eq "nothing started" 0 "$(wc -l < "$WORK/jobcalls" 2>/dev/null || echo 0)"
run start tank --use data --confirm ata-A
check_eq "start: exit 0" 0 "$rc"
check_eq "start: status started" "status${T}started" "$(grep '^status' <<<"$out")"
check_eq "start: a unit line" 1 "$(grep -c "^unit${T}hs-job-pool-import-tank-" <<<"$out")"
check_eq "start: the job repeats the command with --yes" 1 "$(grep -c 'pool-import.sh tank --use data --yes' "$WORK/jobcalls")"
check_eq "start: nothing imported yet" 0 "$(grep -c 'import -N' "$LOG")"

echo "-- the job"
reset ok
rc=0; out=$(timeout 30 bash "$PI" tank --use data --yes </dev/null 2>&1) || rc=$?
check_eq "job: exit 0" 0 "$rc"
check_eq "job: imports by id" 1 "$(grep -c "^zpool import -N -d $WORK/byid 11111111111111111\$" "$LOG")"
check_eq "job: no -f anywhere" 0 "$(grep -c ' -f' "$LOG")"
check_eq "job: mounts the datasets that mount (not the others)" "zfs mount tank
zfs mount tank/data" "$(grep '^zfs mount' "$LOG")"
check_eq "job: creates tank/shares" 1 "$(grep -c '^zfs create tank/shares$' "$LOG")"
check_eq "job: creates tank/sensitive" 1 "$(grep -c '^zfs create tank/sensitive$' "$LOG")"
check_eq "job: the row is written" 1 "$(grep -c '^pools = { tank = { role = "data", kind = "zfs" } }' "$HS_MACHINE_FILE")"
check_eq "job: says it is done" 1 "$(grep -c 'The pool tank is imported' <<<"$out")"
check_eq "job: no export" 0 "$(grep -c '^zpool export' "$LOG")"
reset ok
printf 'tank/shares\ntank/sensitive\n' > "$WORK/datasets"
rc=0; out=$(timeout 30 bash "$PI" tank --use data --yes </dev/null 2>&1) || rc=$?
check_eq "present datasets: exit 0" 0 "$rc"
check_eq "present datasets: nothing created" 0 "$(grep -c '^zfs create' "$LOG")"

echo "-- a pool that mounts elsewhere is exported again"
reset ok
echo "/srv/x" > "$WORK/mountpoint"
rc=0; out=$(timeout 30 bash "$PI" tank --use data --yes </dev/null 2>&1) || rc=$?
check_eq "wrong mountpoint: exit 1" 1 "$rc"
check_eq "wrong mountpoint: exported again" 1 "$(grep -c '^zpool export tank$' "$LOG")"
check_eq "wrong mountpoint: says so" 1 "$(grep -c 'tank mounts at /srv/x, not /tank; it was exported again, nothing changed' <<<"$out")"
check_eq "wrong mountpoint: nothing mounted or created" 0 "$(grep -c '^zfs mount\|^zfs create' "$LOG")"
check_eq "wrong mountpoint: machine.toml unchanged" "language = \"en\"
pools = {}" "$(cat "$HS_MACHINE_FILE")"
reset ok
echo "/tank" > "$WORK/mountpoint"; echo "/mnt" > "$WORK/altroot"
rc=0; out=$(timeout 30 bash "$PI" tank --use data --yes </dev/null 2>&1) || rc=$?
check_eq "an altroot: exit 1 and exported again" "1 1" "$rc $(grep -c '^zpool export tank$' "$LOG")"

echo "-- an encrypted pool stays locked"
reset ok
echo unavailable > "$WORK/keystatus"
rc=0; out=$(timeout 30 bash "$PI" tank --use data --yes </dev/null 2>&1) || rc=$?
check_eq "locked: exit 0" 0 "$rc"
check_eq "locked: nothing mounted or created" 0 "$(grep -c '^zfs mount\|^zfs create' "$LOG")"
check_eq "locked: the row is written" 1 "$(grep -c 'tank = { role = "data", kind = "zfs" }' "$HS_MACHINE_FILE")"
check_eq "locked: a note about hs unlock" 1 "$(grep -c 'tank is encrypted: hs unlock opens it' <<<"$out")"

echo "-- the terminal"
reset ok
rc=0; out=$(timeout 30 bash "$PI" tank --dry-run </dev/null 2>&1) || rc=$?
check_eq "dry run: exit 0" 0 "$rc"
check_eq "dry run: names the disks" 2 "$(grep -c 'ata-[AB]' <<<"$out" | tr -d ' ')"
check_eq "dry run: imports nothing" 0 "$(grep -c 'import -N' "$LOG")"
rc=0; out=$(timeout 30 bash "$PI" tank </dev/null 2>&1) || rc=$?
check_eq "no terminal, no --yes: refused" 1 "$rc"
check_eq "no terminal: imports nothing" 0 "$(grep -c 'import -N' "$LOG")"
rc=0; out=$(printf 'tank\n' | HS_GUIDED_TTY=1 timeout 30 bash "$PI" tank 2>&1) || rc=$?
check_eq "the pool name is not the word to type" 1 "$rc"
check_eq "wrong word: imports nothing" 0 "$(grep -c 'import -N' "$LOG")"
rc=0; out=$(printf 'ata-A\nn\n' | HS_GUIDED_TTY=1 timeout 30 bash "$PI" tank 2>&1) || rc=$?
check_eq "the disk name and no job: imports" 0 "$rc"
check_eq "the disk name and no job: imported by id" 1 "$(grep -c "^zpool import -N -d $WORK/byid 11111111111111111\$" "$LOG")"

echo "-- the script"
check_eq "no -f option anywhere in pool-import.sh" 0 "$(grep -cE 'import[^#]* -f( |$)|--force' "$PI")"
bash -n "$PI" && pass "bash -n" || fail "bash -n"
finish
