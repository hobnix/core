#!/usr/bin/env bash
# hs pool <pool> import on two loop devices with the real zpool: make a mirror, export it, plan the import, import it by the typed disk
# name's job body and check it is mounted, has its datasets and its row. Needs root, the ZFS tools and the zfs kernel module (WSL often
# has none: then the test skips and says so). Never imports a pool of another system (that case cannot be made safely here).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
need_root
T=$'\t'
have zpool || { skip "zpool is not installed"; finish; exit 0; }
modprobe zfs 2>/dev/null || { skip "the zfs kernel module cannot be loaded here (run it in a throwaway VM: scripts/dev/t vm)"; finish; exit 0; }
export HS_PLAIN=1 HS_TEST_LOOP=1 HS_MACHINE_FILE=$WORK/machine.toml HS_STATE_DIR=$WORK/state HS_RUN_DIR=$WORK/run HS_LIVE_LOG=$WORK/live
unset HS_CALLER HS_GUIDED_TTY
mkdir -p "$WORK/state" "$WORK/run"
printf 'language = "en"\npools = {}\n' > "$HS_MACHINE_FILE"
P=hsimpt
trap 'zpool destroy -f "$P" 2>/dev/null || true; zpool export "$P" 2>/dev/null || true' EXIT
mkloop i1 256M >/dev/null; mkloop i2 256M >/dev/null
zpool create -m "/$P" "$P" mirror /dev/disk/by-id/ata-TEST_i1 /dev/disk/by-id/ata-TEST_i2 >/dev/null 2>&1 || { skip "zpool create failed on loop devices here"; finish; exit 0; }
zpool export "$P"

echo "-- plan"
rc=0; out=$(bash "$SCRIPTS/pool-import.sh" plan "$P" --use data 2>&1) || rc=$?
if [ "$rc" -ne 0 ] && grep -q 'not a whole disk\|not a disk this server sees' <<<"$out"; then
  skip "this machine shows no by-id names for loop partitions (udev): $(tr '\n' ' ' <<<"$out" | head -c 200)"; finish; exit 0
fi
check_eq "plan: exit 0" 0 "$rc"
check_eq "plan: status ok" 1 "$(grep -c "^status${T}ok\$" <<<"$out")"
check_eq "plan: the disk to type" "confirm_name${T}ata-TEST_i1" "$(grep '^confirm_name' <<<"$out")"
check_eq "plan: nothing imported" 1 "$(zpool import -d /dev/disk/by-id 2>/dev/null | grep -c "pool: $P")"

echo "-- the job body"
rc=0; bash "$SCRIPTS/pool-import.sh" "$P" --use data --yes >"$WORK/job.out" 2>&1 || rc=$?
check_eq "import: exit 0" 0 "$rc"
check "the pool is imported" zpool list -H "$P"
check "the pool is mounted at /$P" mountpoint -q "/$P"
check "the shares dataset exists" test -d "/$P/shares"
check "the sensitive dataset exists" test -d "/$P/sensitive"
check_eq "the row is written" 1 "$(grep -c "$P = { role = \"data\", kind = \"zfs\" }" "$HS_MACHINE_FILE")"
check_eq "imported already: refused" 1 "$(bash "$SCRIPTS/pool-import.sh" plan "$P" --use data >/dev/null 2>&1; echo $?)"
finish
