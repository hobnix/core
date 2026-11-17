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
finish
