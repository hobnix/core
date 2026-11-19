#!/usr/bin/env bash
# Mitigation level 1 (pause the sync, scrub and cache mover), acknowledging problems, the pause marker in bulklock.sh
#. A fake zpool makes a degraded pool; no root, no real pools.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
mkdir -p "$WORK/bin" "$WORK/state"
cat > "$WORK/bin/zpool" <<'FAKE'
#!/usr/bin/env bash
case "$*" in
  "list -H -o name") echo tank ;;
  "status -x tank") echo "pool 'tank' is DEGRADED" ;;
  "list -H -o health tank") cat "$HS_STATE_DIR/poolstate" 2>/dev/null || echo DEGRADED ;;
  "list -Hp -o name,alloc,size") printf 'tank\t100\t1000\n' ;;
  "list -H -o name,cap") printf 'tank\t10%%\n' ;;
  "status tank") echo "  scan: scrub repaired 0B in 00:01:00 with 0 errors on Sun Oct  4 00:24:01 2099" ;;
esac
FAKE
printf '#!/usr/bin/env bash
exit 0
' > "$WORK/bin/flock"   # the lock itself is tests/bulklock.sh's business
chmod +x "$WORK/bin/zpool" "$WORK/bin/flock"
export PATH=$WORK/bin:$PATH HS_PLAIN=1 HS_CALLER=test HS_LANG=en
export HS_STATE_DIR=$WORK/state HS_HEALTH_STATE=$WORK/h.state HS_ACK_FILE=$WORK/ack HS_BULK_PAUSE=$WORK/paused
export HS_BACKUP_STATE=$WORK/none HS_TEMP_ROOT=$WORK/t HS_RUN_DIR=$WORK/run HS_REPO=$WORK/norepo HS_NOTIFY_URL= HS_HEARTBEAT_URL=
export HS_CAP_CACHE=$WORK/nocache HS_SELFTEST_STATE=$WORK/none HS_SCRUB_STATE=$WORK/none
mkdir -p "$WORK/run" "$WORK/t"
HC="bash $SCRIPTS/health-check.sh"
HA="bash $SCRIPTS/health-ack.sh"
keys() { $HC --keys 2>/dev/null; }

echo "-- the degraded pool is a problem and a trigger"
check_out "the pool key is listed" "^zfs:tank:DEGRADED" keys
export HS_AUTO_MITIGATE=false
$HC >/dev/null 2>&1 || true
[ ! -e "$WORK/paused" ] && pass "off by default: nothing is paused" || fail "off by default: nothing is paused"
export HS_AUTO_MITIGATE=true
$HC >/dev/null 2>&1 || true
[ -e "$WORK/paused" ] && pass "on: the pause marker is written" || fail "on: the pause marker is written"
check_out "the marker names the cause" "^keys=zfs:tank:DEGRADED" cat "$WORK/paused"
check_out "the pause is itself a problem" "^mitigation:paused" keys
check_out "the message says what is paused" "paused because of zfs:tank:DEGRADED. Nothing was deleted" $HC --dry-run

echo "-- the jobs skip while paused"
export HS_LOCK=$WORK/lock HS_LOCK_ADMIN=$WORK/admin
out=$(bash -c ". '$SCRIPTS/lib/bulklock.sh'; bulk_lock_job 1; echo RAN" 2>&1)
check_out "a timer job exits quietly" "Paused by the health check" echo "$out"
if grep -q RAN <<<"$out"; then fail "the job did not continue"; else pass "the job did not continue"; fi
out=$(HS_IGNORE_PAUSE=1 bash -c ". '$SCRIPTS/lib/bulklock.sh'; bulk_lock_job 1; echo RAN" 2>&1)
check_out "HS_IGNORE_PAUSE runs it anyway" "RAN" echo "$out"
out=$(bash -c ". '$SCRIPTS/lib/bulklock.sh'; bulk_lock_admin 1; echo RAN" 2>&1)
check_out "a pool change is never paused" "RAN" echo "$out"

echo "-- the pause lifts itself when the cause is gone"
cat > "$WORK/bin/zpool" <<'FAKE'
#!/usr/bin/env bash
case "$*" in
  "list -H -o name") echo tank ;;
  "status -x tank") echo "pool 'tank' is healthy" ;;
  "list -Hp -o name,alloc,size") printf 'tank\t100\t1000\n' ;;
  "list -H -o name,cap") printf 'tank\t10%%\n' ;;
  "status tank") echo "  scan: scrub repaired 0B in 00:01:00 with 0 errors on Sun Oct  4 00:24:01 2099" ;;
esac
FAKE
$HC >/dev/null 2>&1 || true
[ ! -e "$WORK/paused" ] && pass "healthy again: the marker is gone" || fail "healthy again: the marker is gone"

echo "-- hs health resume acknowledges the cause"
cat > "$WORK/bin/zpool" <<'FAKE'
#!/usr/bin/env bash
case "$*" in
  "list -H -o name") echo tank ;;
  "status -x tank") echo "pool 'tank' is DEGRADED" ;;
  "list -H -o health tank") cat "$HS_STATE_DIR/poolstate" 2>/dev/null || echo DEGRADED ;;
  "list -Hp -o name,alloc,size") printf 'tank\t100\t1000\n' ;;
  "list -H -o name,cap") printf 'tank\t10%%\n' ;;
  "status tank") echo "  scan: scrub repaired 0B in 00:01:00 with 0 errors on Sun Oct  4 00:24:01 2099" ;;
esac
FAKE
$HC >/dev/null 2>&1 || true
check_out "paused again" "keys=zfs:tank:DEGRADED" cat "$WORK/paused"
check_out "resume says so" "Lifted" $HA resume
[ ! -e "$WORK/paused" ] && pass "resume removes the marker" || fail "resume removes the marker"
check_out "the cause is acknowledged" "^zfs:tank:DEGRADED" cut -f1 "$WORK/ack"
$HC >/dev/null 2>&1 || true
[ ! -e "$WORK/paused" ] && pass "the next run does not pause again" || fail "the next run does not pause again"
check_out "the problem is marked acknowledged in the list" "zfs:tank:DEGRADED	.*	acked" $HC --list

echo "-- acknowledging"
out=$($HC --dry-run 2>&1)
if grep -q "ZFS pool tank" <<<"$out"; then fail "an acknowledged problem is not shown"; else pass "an acknowledged problem is not shown"; fi
check_out "the count is mentioned" "1 acknowledged problem" echo "$out"
check_out "unack puts it back" "Back in the reports" $HA unack zfs:tank:DEGRADED
check_out "it is listed again" "ZFS pool tank is not healthy" $HC --dry-run
check_out "an unknown id is refused" "not an active problem" $HA ack nonsense:id
check_out "ack of a real id works" "Acknowledged zfs:tank:DEGRADED" $HA ack zfs:tank:DEGRADED
echo "-- an entry whose problem cleared is dropped"
printf 'gone:thing\t1\n' >> "$WORK/ack"
$HC >/dev/null 2>&1 || true
if grep -q '^gone:thing' "$WORK/ack"; then fail "the cleared entry is dropped"; else pass "the cleared entry is dropped"; fi
check_out "the live one stays" "^zfs:tank:DEGRADED" cut -f1 "$WORK/ack"

echo "-- since when, and which channels were told"
rm -f "$WORK/health-since"
check_out "a new problem is open since now" "^zfs:tank:DEGRADED	.*	acked	1000	-	[^	]*	[^	]*$" env HS_NOW=1000 $HC --list
check_out "a later run keeps the first time" "acked	1000	-	[^	]*	[^	]*$" env HS_NOW=2000 $HC --list
mkdir -p "$WORK/state/notify-channels"
printf 'zfs:tank:FAULTED	5	main,second
' > "$WORK/state/notify-channels/.told"
echo FAULTED > "$WORK/state/poolstate"
check_out "a changed key starts again, with the channels that were told" "^zfs:tank:FAULTED	.*	-	3000	main,second	[^	]*	[^	]*$" env HS_NOW=3000 $HC --list
if grep -q '^zfs:tank:DEGRADED' "$WORK/health-since"; then fail "the cleared key is dropped from the since file"; else pass "the cleared key is dropped from the since file"; fi
check_out "the acknowledge command still lists the problem" "^zfs:tank:FAULTED" $HA ack
rm -f "$WORK/state/poolstate"

echo "-- a pool above 95 % pauses, and the pause lifts itself"
mkzp() { cat > "$WORK/bin/zpool" <<FAKE
#!/usr/bin/env bash
case "\$*" in
  "list -H -o name") echo tank ;;
  "status -x tank") echo "pool 'tank' is healthy" ;;
  "list -Hp -o name,alloc,size") printf 'tank	100	1000
' ;;
  "list -H -o name,cap") printf 'tank	$1%%
' ;;
  "status tank") echo "  scan: scrub repaired 0B in 00:01:00 with 0 errors on Sun Oct  4 00:24:01 2099" ;;
esac
FAKE
}
rm -f "$WORK/paused" "$WORK/ack"; export HS_AUTO_MITIGATE=true
mkzp 92; $HC >/dev/null 2>&1 || true
[ ! -e "$WORK/paused" ] && pass "92 % full: a warning, no pause" || fail "92 % full: a warning, no pause"
mkzp 97; $HC >/dev/null 2>&1 || true
check_out "97 % full: the pool pauses" "^keys=space:pool:tank" cat "$WORK/paused"
mkzp 10; $HC >/dev/null 2>&1 || true
[ ! -e "$WORK/paused" ] && pass "space freed: the pause lifts" || fail "space freed: the pause lifts"

echo "-- the daily SMART check: failing pauses, watch does not"
if command -v python3 >/dev/null; then
  if command -v cygpath >/dev/null 2>&1; then export HS_TEST_BASH=$(cygpath -m "$BASH"); export HS_STATE_DIR=$(cygpath -m "$WORK/state"); fi
  cat > "$WORK/bin/zpool" <<'FAKE'
#!/usr/bin/env bash
case "$*" in
  "list -H -o name") echo tank ;;
  "status -x tank") echo "pool 'tank' is healthy" ;;
  "list -Hp -o name,alloc,size") printf 'tank\t100\t1000\n' ;;
  "list -H -o name,cap") printf 'tank\t10%%\n' ;;
  "status tank") echo "  scan: scrub repaired 0B in 00:01:00 with 0 errors on Sun Oct  4 00:24:01 2099" ;;
esac
FAKE
  printf '#!/usr/bin/env bash\ncat "$RD"\n' > "$WORK/dh"; chmod +x "$WORK/dh"
  export RD=$WORK/rd.txt HS_DISK_HEALTH=$WORK/dh HS_AUTO_MITIGATE=true HS_DISK_HEALTH_NOROOT=1
  rdl() { printf 'sda\tread\tHDD\tS9\tW9\t100\t0\t%s\t0\t%s\t-\t-\t-\t-\t-\tWDC\n' "$1" "$2"; }
  rdl 0 0 > "$RD"; bash "$SCRIPTS/state.sh" baseline-run
  rdl 0 4 > "$RD"; bash "$SCRIPTS/state.sh" baseline-run
  check_out "CRC errors only: smart-watch is listed" "^disk:S9:smart-watch" keys
  $HC >/dev/null 2>&1 || true
  [ ! -e "$WORK/paused" ] && pass "smart-watch does not pause" || fail "smart-watch does not pause"
  rdl 2 4 > "$RD"; bash "$SCRIPTS/state.sh" baseline-run
  $HC >/dev/null 2>&1 || true
  check_out "smart-failing pauses" "^keys=.*disk:S9:smart-failing" cat "$WORK/paused"
else
  skip "python3 missing: the SMART check part not run"
fi

echo "-- level 2 (freeze) and level 3 (backup): off by default, each once"
mkdir -p "$WORK/l"
cat > "$WORK/l/inc.sh" <<'X'
#!/usr/bin/env bash
d=$(dirname "$0")
case "$1" in
  pause) echo "pause full=$HS_INCIDENT_FULL" >> "$d/calls"; echo immich > "$HS_INCIDENT_PAUSED" ;;
  resume) echo resume >> "$d/calls"; rm -f "$HS_INCIDENT_PAUSED" ;;
  --alert-line) ;;
esac
X
cat > "$WORK/l/bak.sh" <<'X'
#!/usr/bin/env bash
echo run >> "$(dirname "$0")/bcalls"
X
chmod +x "$WORK/l/inc.sh" "$WORK/l/bak.sh"
cat > "$WORK/bin/zpool" <<'FAKE'
#!/usr/bin/env bash
case "$*" in
  "list -H -o name") echo tank ;;
  "status -x tank") echo "pool 'tank' is healthy" ;;
  "list -Hp -o name,alloc,size") printf 'tank	990	1000
' ;;
  "list -H -o name,cap") printf 'tank	99%%
' ;;
  "status tank") echo "  scan: scrub repaired 0B in 00:01:00 with 0 errors on Sun Oct  4 00:24:01 2099" ;;
esac
FAKE
export HS_STORAGE_INCIDENT=$WORK/l/inc.sh HS_INCIDENT_PAUSED=$WORK/l/paused HS_AUTO_MITIGATE=false
unset HS_AUTO_MITIGATE_FREEZE HS_AUTO_MITIGATE_BACKUP
export HS_STATE_DIR=$WORK/lstate; mkdir -p "$HS_STATE_DIR"
: > "$WORK/l/calls"
$HC >/dev/null 2>&1 || true
[ ! -s "$WORK/l/calls" ] && pass "freeze off by default: nothing is frozen" || fail "freeze off by default: nothing is frozen"
export HS_AUTO_MITIGATE_FREEZE=true
$HC >/dev/null 2>&1 || true
$HC >/dev/null 2>&1 || true
check_eq "pool at 99 %: the apps are frozen once" "1" "$(grep -c '^pause full=tank' "$WORK/l/calls")"
check_out "the message names the app and the resume command" "immich.*hs storage incident resume" $HC --list
check_eq "one message for the freeze" "1" "$(keys | grep -c '^mitigation:frozen$')"
bash "$WORK/l/inc.sh" resume
check_eq "after resume the notice is gone" "0" "$(keys | grep -c '^mitigation:frozen$')"
unset HS_AUTO_MITIGATE_FREEZE
rm -f "$WORK/l/paused" "$HS_STATE_DIR/mitigation-frozen"

# a failing disk with an old backup
printf 'last_ok=%s
status=ok
' "$(( $(date +%s) - 200000 ))" > "$WORK/bs"
export HS_BACKUP_STATE=$WORK/bs HS_MITIGATE_BACKUP_CMD="bash $WORK/l/bak.sh"
cat > "$WORK/l/sw.sh" <<'X'
#!/usr/bin/env bash
exit 0
X
export HS_FAKE_FAILING=1
# the failing disk comes from the SMART path of the tests above: reuse the state database fixture when python3 is there
if command -v python3 >/dev/null 2>&1; then
  export HS_DISK_HEALTH=$WORK/dh HS_DISK_HEALTH_NOROOT=1
  rdl() { printf 'sda	read	HDD	S8	W8	100	0	%s	0	%s	-	-	-	-	-	WDC
' "$1" "$2"; }
  printf '#!/usr/bin/env bash
cat "$RD"
' > "$WORK/dh"; chmod +x "$WORK/dh"; export RD=$WORK/rd2.txt
  rdl 0 0 > "$RD"; bash "$SCRIPTS/state.sh" baseline-run
  rdl 2 4 > "$RD"; bash "$SCRIPTS/state.sh" baseline-run
  rm -f "$WORK/l/bcalls"
  $HC >/dev/null 2>&1 || true; sleep 1
  [ ! -e "$WORK/l/bcalls" ] && pass "backup off by default: no backup started" || fail "backup off by default: no backup started"
  export HS_AUTO_MITIGATE_BACKUP=true
  $HC >/dev/null 2>&1 || true; $HC >/dev/null 2>&1 || true; sleep 1
  check_eq "failing disk, old backup: exactly one backup" "1" "$(grep -c run "$WORK/l/bcalls" 2>/dev/null || echo 0)"
  check_out "the message names hs disk move" "hs disk <disk> move" $HC --dry-run
  printf 'last_ok=%s
status=ok
' "$(date +%s)" > "$WORK/bs"; rm -f "$HS_STATE_DIR/mitigation-backup" "$WORK/l/bcalls"
  $HC >/dev/null 2>&1 || true; sleep 1
  [ ! -e "$WORK/l/bcalls" ] && pass "a fresh backup: nothing started" || fail "a fresh backup: nothing started"
fi

finish
