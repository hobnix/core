#!/usr/bin/env bash
# hs disk spindown (scripts/disk-spindown.sh): minutes -> hdparm -S value, and that only rotational member disks are touched.
# Fake sysfs, member list and hdparm; no root.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
export HS_LANG=en HS_PLAIN=1
S=$SCRIPTS/disk-spindown.sh
BIN=$WORK/bin; SYS=$WORK/sys; mkdir -p "$BIN"
export CALLS=$WORK/hdparm.log; : > "$CALLS"
printf '#!/usr/bin/env bash\necho "$*" >> "$CALLS"\n[ "$1" = -C ] && echo " drive state is:  standby"\nexit 0\n' > "$BIN/hdparm"; chmod +x "$BIN/hdparm"
printf '#!/usr/bin/env bash\nexit 1\n' > "$BIN/findmnt"; chmod +x "$BIN/findmnt"   # the runner's own root disk (often sda) must not count as the system disk
export PATH=$BIN:$PATH
for d in sda sdb nvme0n1 sdc; do mkdir -p "$SYS/$d/queue"; done
echo 1 > "$SYS/sda/queue/rotational"; echo 1 > "$SYS/sdb/queue/rotational"; echo 0 > "$SYS/nvme0n1/queue/rotational"; echo 1 > "$SYS/sdc/queue/rotational"
printf 'sda\nnvme0n1\nsdb\n' > "$WORK/members"   # sdc is rotational but no member
export HS_SPINDOWN_SYSFS=$SYS HS_SPINDOWN_MEMBERS=$WORK/members

v() { bash "$S" --value "$1"; }
check_eq "1 min = 12" 12 "$(v 1)"
check_eq "20 min = 240" 240 "$(v 20)"
check_eq "21 min = 241 (30 min)" 241 "$(v 21)"
check_eq "60 min = 242" 242 "$(v 60)"
check_eq "330 min = 251" 251 "$(v 330)"
check_eq "1000 min capped at 251" 251 "$(v 1000)"
check_eq "0 = off" 0 "$(v 0)"

HS_SPINDOWN_MINUTES=10 bash "$S" apply >/dev/null 2>&1 || true
check "sda gets -S 120" grep -qx -- '-S 120 /dev/sda' "$CALLS"
check "sdb gets -S 120" grep -qx -- '-S 120 /dev/sdb' "$CALLS"
check_eq "nvme and non-member left alone" 2 "$(grep -c -- '-S' "$CALLS")"
: > "$CALLS"
HS_SPINDOWN_MINUTES=0 bash "$S" apply >/dev/null 2>&1 || true
check "0 turns the timer off" grep -qx -- '-S 0 /dev/sda' "$CALLS"
st=$(HS_SPINDOWN_MINUTES=10 bash "$S" status)
check "status: sda member standby 10" grep -qx $'sda\tyes\tyes\tstandby\t10' <<<"$st"
check "status: sdc not a member" grep -qx $'sdc\tyes\tno\tstandby\t-' <<<"$st"
check "status: nvme not rotational" grep -qx $'nvme0n1\tno\tyes\t-\t-' <<<"$st"

# log: a fake sysfs whose counter grows in the second minute, a fake journalctl that names the unit that started
LOG=$WORK/spindown.log
printf '1000 0 0 0 5 0 0 0
' > "$SYS/sda/stat"; printf '7 0 0 0 7 0 0 0
' > "$SYS/sdb/stat"
printf '#!/usr/bin/env bash
echo "$*" >> "$CALLS"
[ "$1" = -C ] && { [ -e "$WORK/awake" ] && [ "$2" = /dev/sda ] && echo " drive state is:  active/idle" || echo " drive state is:  standby"; }
exit 0
' > "$BIN/hdparm"
printf '#!/usr/bin/env bash
echo "Starting hs-backup.service - restic backup"
echo "Started hs-backup.service - restic backup"
echo "kernel noise"
' > "$BIN/journalctl"
chmod +x "$BIN/hdparm" "$BIN/journalctl"
export WORK
# the "sleep" between samples is 0 s; a background step changes sda's counter and state between the first and second sample
( sleep 1; echo "1200 0 0 0 5 0 0 0" > "$SYS/sda/stat"; touch "$WORK/awake" ) &
HS_SPINDOWN_NOROOT=1 HS_SPINDOWN_INTERVAL=2 HS_SPINDOWN_SAMPLES=2 HS_SPINDOWN_LOGFILE=$LOG bash "$S" log 1 >/dev/null 2>&1 || true
wait
check "log: sda woke is written" grep -qE $'	sda	woke	' "$LOG"
check "log: the waking unit is named" grep -q 'hs-backup.service' "$LOG"
check "log: sdb (idle) is not listed" bash -c "! grep -q $'	sdb	' '$LOG'"
check "log refuses 0 hours" bash -c "! HS_SPINDOWN_NOROOT=1 bash '$S' log 0 >/dev/null 2>&1"

# per pool: diskSpindownPools replaces the global minutes for the disks of that pool; a disk without a pool keeps the global value
printf 'sda bulk\nsdb backup\nnvme0n1\n' > "$WORK/members2"
export HS_SPINDOWN_MEMBERS=$WORK/members2
: > "$CALLS"
HS_SPINDOWN_MINUTES=60 HS_SPINDOWN_POOLS='{"backup":10,"bulk":0}' bash "$S" apply >/dev/null 2>&1 || true
check "pool bulk = 0: sda timer off" grep -qx -- '-S 0 /dev/sda' "$CALLS"
check "pool backup = 10: sdb gets -S 120" grep -qx -- '-S 120 /dev/sdb' "$CALLS"
: > "$CALLS"
HS_SPINDOWN_MINUTES=60 HS_SPINDOWN_POOLS='{"backup":10}' bash "$S" apply >/dev/null 2>&1 || true
check "a pool not listed keeps the global value (60 = 242)" grep -qx -- '-S 242 /dev/sda' "$CALLS"
st=$(HS_SPINDOWN_MINUTES=60 HS_SPINDOWN_POOLS='{"backup":10}' bash "$S" status)
check "status shows the per-pool minutes" grep -qE $'sdb\tyes\tyes\t[^	]*\t10' <<<"$st"
check "status shows the global minutes for the other pool" grep -qE $'sda\tyes\tyes\t[^	]*\t60' <<<"$st"

# power: states, since and wakes today across two readings; measured watts with their source, nothing estimated
export HS_STATE_DIR=$WORK/state HS_SPINDOWN_NOW=1700000000
printf 'sda asleep\nsdb spinning\n' > "$WORK/pstate"; export HS_SPINDOWN_STATE=$WORK/pstate
PC=$WORK/powercap; mkdir -p "$PC/intel-rapl:0"; echo package-0 > "$PC/intel-rapl:0/name"; echo 1000000 > "$PC/intel-rapl:0/energy_uj"
export HS_POWERCAP=$PC HS_RAPL_INTERVAL=1
# the fake sleep adds 5 J to the counter: 5 W over the 1 s interval
mkdir -p "$WORK/fakesleep"
printf '#!/usr/bin/env bash\necho 6000000 > "$HS_POWERCAP/intel-rapl:0/energy_uj"\n' > "$WORK/fakesleep/sleep"; chmod +x "$WORK/fakesleep/sleep"
export PATH=$WORK/fakesleep:$PATH
out=$(bash "$S" power)
check "power: sda asleep since now, no wakes" grep -qx $'disk\tsda\tasleep\t1700000000\t0' <<<"$out"
check "power: sdb spinning" grep -qx $'disk\tsdb\tspinning\t1700000000\t0' <<<"$out"
check "power: no UPS configured, no UPS line" bash -c "! grep -q $'^power\tups' <<<'$out'"
printf 'sda spinning\nsdb spinning\n' > "$WORK/pstate"; export HS_SPINDOWN_NOW=1700000600
out=$(bash "$S" power)
check "power: a wake is counted once and since moves" grep -qx $'disk\tsda\tspinning\t1700000600\t1' <<<"$out"
check "power: unchanged disk keeps since" grep -qx $'disk\tsdb\tspinning\t1700000000\t0' <<<"$out"
out=$(bash "$S" power)
check "power: a third reading does not count it again" grep -qx $'disk\tsda\tspinning\t1700000600\t1' <<<"$out"
echo 1000000 > "$PC/intel-rapl:0/energy_uj"
out=$(bash "$S" power)
check "power: CPU package watts measured over the interval, with source" grep -qx $'power	rapl	CPU package (package-0)	5.0' <<<"$out"
check "power: nothing per disk is estimated" bash -c "! grep -q $'^power	disk' <<<'$out'"
# UPS watts through ups.sh power (fake upsc, configured)
printf 'name=ups\nshutdownMinutes=5\n' > "$WORK/upsconf"
printf '#!/usr/bin/env bash\nprintf "ups.status: OL\nups.load: 20\nups.realpower.nominal: 500\n"\n' > "$BIN/upsc"; chmod +x "$BIN/upsc"
check_eq "ups power = load % of the nominal watts" 100 "$(HS_UPS_CONF=$WORK/upsconf HS_UPSC=$BIN/upsc bash "$SCRIPTS/ups.sh" power)"
out=$(HS_UPS_CONF=$WORK/upsconf HS_UPSC=$BIN/upsc bash "$S" power)
check "power: UPS watts line has its source" grep -qx $'power\tups\twhole server (UPS output)\t100' <<<"$out"
check_eq "ups power without a UPS = -" "-" "$(HS_UPS_CONF=$WORK/none bash "$SCRIPTS/ups.sh" power)"
finish
