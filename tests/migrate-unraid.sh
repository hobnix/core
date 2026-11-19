#!/usr/bin/env bash
# hs migrate unraid, hs sys migrate plan|start unraid (scripts/migrate-unraid.sh): the plan as data, the typed word, the order of the job.
# No root, no disks: fake blkid and lsblk answer for the disks, a stand-in for manage-pool.sh records what the job calls (the adopt code itself is
# tested in tests/adopt.sh on Unraid-made loop disks), a fake systemd-run takes the job. Fakes must be chmod +x (CI has no zpool, xfs or restic).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
export HS_PLAIN=1 HS_LANG=en HS_STATE_DIR=$WORK/state HS_RUN_DIR=$WORK/run
unset HS_CALLER HS_GUIDED_TTY HS_DISK_PASSPHRASE HS_DISK_PASSPHRASE_FILE HS_UNRAID_PASSPHRASE_FILE
# shellcheck source=tests/lib-poolfakes.sh
. "$(dirname "$0")/lib-poolfakes.sh"
mkdir -p "$WORK/state" "$WORK/fs"
echo snapraid > "$BT"

# what is on a disk: $WORK/fs/<id> holds the TYPE blkid answers (no file = nothing)
cat > "$BIN/lsblk" <<FAKE
#!/usr/bin/env bash
for a in "\$@"; do case "\$a" in /dev/disk/by-id/*) echo "\$a" ;; esac; done
FAKE
cat > "$BIN/blkid" <<FAKE
#!/usr/bin/env bash
for a in "\$@"; do f="$WORK/fs/\$(basename "\$a")"; [ ! -f "\$f" ] || { cat "\$f"; exit 0; }; done
exit 2
FAKE
cat > "$BIN/systemd-run" <<FAKE
#!/usr/bin/env bash
printf "%s\n" "\$*" >> "$WORK/jobcalls"
env | grep "^HS_UNRAID_PASSPHRASE_FILE=" >> "$WORK/jobcalls" || true
FAKE
chmod +x "$BIN/lsblk" "$BIN/blkid" "$BIN/systemd-run"
export PATH=$BIN:$PATH

# the disks: three Unraid data disks (xfs, btrfs, xfs in LUKS), the old parities (no file system), a spare (empty), a ZFS array disk
for d in d1:xfs d2:btrfs d3:crypto_LUKS z1:zfs_member; do echo "${d#*:}" > "$WORK/fs/ata-U_${d%%:*}"; done
: > "$WORK/list.tsv"
for d in d1 d2 d3 z1 par1 par2 spare small; do
  sz=4000000000; [ "$d" != small ] || sz=1000000000
  printf 'ata-U_%s\t%s\tHDD\t\n' "$d" "$sz" >> "$WORK/list.tsv"
done

# the stand-in of manage-pool.sh
cat > "$WORK/manage" <<FAKE
#!/usr/bin/env bash
case " \$* " in *" --list-disks "*) cat "$WORK/list.tsv"; exit 0 ;; esac
if [[ " \$* " == *" --dry-run "* ]]; then
  [ ! -f "$WORK/dryrc" ] || { echo "Not possible: a data disk would be larger than a parity disk."; exit 1; }
  echo "Dry run: nothing is changed."
  echo "Plan: no file is erased or copied"
  [[ " \$* " != *" --merge "* ]] || echo "      moves into shares/ (merged with folders of the same name): Media Shared"
  [ -z "\${HS_UNRAID_PASSPHRASE_FILE:-}" ] || echo "ENCFILE \$(cat "\$HS_UNRAID_PASSPHRASE_FILE")" >> "$WORK/dryenc"
  exit 0
fi
echo "\$*" >> "$WORK/calls"
FAKE
printf '#!/usr/bin/env bash\necho "sync $*" >> "%s/calls"\n' "$WORK" > "$WORK/sync"
chmod +x "$WORK/manage" "$WORK/sync"
export HS_MANAGE_POOL=$WORK/manage HS_BULK_SYNC=$WORK/sync
M="bash $SCRIPTS/migrate-unraid.sh"
run() { rc=0; out=$($M "$@" </dev/null 2>&1) || rc=$?; }
has() { grep -q -- "$1" <<<"$out"; }

echo "-- no disks named: exit 2 and the candidates"
run plan
check_eq "needs disks: exit 2" 2 "$rc"
has '^needs	disks$' && pass "needs disks" || fail "needs disks: $out"
has '^candidate	ata-U_d1	4000000000	data	-$' && pass "an xfs disk is data" || fail "candidate d1: $out"
has '^candidate	ata-U_d3	4000000000	encrypted	' && pass "a LUKS disk is encrypted" || fail "candidate d3: $out"
has '^candidate	ata-U_par1	4000000000	empty	-$' && pass "a disk without a file system is empty" || fail "candidate par1: $out"
has '^candidate	ata-U_z1	4000000000	refused	holds zfs_member' && pass "a ZFS disk is refused" || fail "candidate z1: $out"

echo "-- refusals"
run plan --disks ata-U_z1
check_eq "a ZFS array disk: exit 1" 1 "$rc"; has 'holds zfs_member' && pass "reason names ZFS" || fail "zfs reason: $out"
run plan --disks ata-U_par1
has 'holds no file system' && pass "an empty disk is not a data disk" || fail "empty as data: $out"
run plan --disks ata-U_d1 --parity ata-U_d2
has 'an Unraid parity disk has no file system' && pass "a parity disk with files is refused" || fail "parity with fs: $out"
run plan --disks ata-U_d1 --spare ata-U_d2
has 'a spare disk is erased, so it must be empty' && pass "a spare with files is refused" || fail "spare with fs: $out"
run plan --disks ata-U_d1 --spare ata-U_small
has 'smaller than the largest data disk' && pass "a spare that is too small" || fail "small spare: $out"
run plan --disks ata-U_d1 --parity ata-U_small
has 'smaller than the largest data disk' && pass "an old parity that is too small" || fail "small parity: $out"
run plan --disks ata-U_nope
has 'not a free disk' && pass "an unknown disk" || fail "unknown: $out"
run plan --disks ata-U_d3
check_eq "encrypted without --unlock: exit 2" 2 "$rc"; has '^needs	unlock$' && pass "needs unlock" || fail "needs unlock: $out"
touch "$WORK/dryrc"
run plan --disks ata-U_d1 --parity ata-U_par1
check_eq "the adopt code refuses: exit 1" 1 "$rc"; has '^reason	Not possible' && pass "its reason is passed on" || fail "reason: $out"
rm -f "$WORK/dryrc"

echo "-- the plan with a spare disk"
run plan --disks ata-U_d1,ata-U_d2 --parity ata-U_par1,ata-U_par2 --spare ata-U_spare
check_eq "allowed" 0 "$rc"
has '^status	ok$' && pass "status ok" || fail "status: $out"
has '^disk	ata-U_d1	data	4000000000	xfs$' && pass "a data disk line" || fail "disk d1: $out"
has '^disk	ata-U_par1	old-parity	4000000000	-$' && pass "an old parity line" || fail "disk par1: $out"
has '^disk	ata-U_spare	spare	' && pass "a spare line" || fail "disk spare: $out"
has '^confirm_name	ata-U_spare$' && pass "the spare is typed" || fail "confirm_name: $out"
has '^danger	ALL DATA on ata-U_par1 (the old Unraid parity)' && pass "the old parity is a danger line" || fail "danger par1: $out"
has 'old Unraid parity disk ata-U_par2 is erased and added as parity' && pass "second old parity after the parity above" || fail "step par2: $out"
has '^text	moves into shares/ (merged' && pass "merged is the default" || fail "merge: $out"
has '^note	Files keep their owner nobody:users (99:100)' && pass "99:100 stays" || fail "owner: $out"
has '^option	shares	merged|per-disk	merged$' && pass "option shares" || fail "option: $out"
has '^long	yes$' && pass "long" || fail "long: $out"
has 'No spare disk' && fail "no 'no spare' warning with a spare" || pass "no 'no spare' warning with a spare"

echo "-- without a spare disk, per disk, chown"
run plan --disks ata-U_d1 --parity ata-U_par1 --per-disk --chown
check_eq "allowed" 0 "$rc"
has '^confirm_name	ata-U_par1$' && pass "the old parity is typed" || fail "confirm_name: $out"
has '^warn	No spare disk' && pass "the window is a warning" || fail "window: $out"
has 'Every folder becomes its own share' && pass "per disk" || fail "per disk: $out"
has 'All files are given to the share owner' && pass "chown" || fail "chown: $out"
run plan --disks ata-U_d1
has '^confirm_name	bulk$' && pass "no disk is erased: the pool name" || fail "pool word: $out"

echo "-- start: the typed word, the job, the order"
rc=0; out=$($M start --disks ata-U_d1 --parity ata-U_par1 --spare ata-U_spare </dev/null 2>&1) || rc=$?
check_eq "start without the word: exit 1" 1 "$rc"; has 'type the name to confirm: ata-U_spare' && pass "names the word" || fail "word: $out"
check "nothing started" test ! -f "$WORK/jobcalls"
rc=0; out=$($M start --disks ata-U_d1 --parity ata-U_par1 --spare ata-U_spare --confirm ata-U_spare </dev/null 2>&1) || rc=$?
check_eq "start with the word: exit 0" 0 "$rc"; has '^status	started$' && pass "started" || fail "started: $out"
check_out "the job runs the run verb" 'migrate-unraid.sh run --disks ata-U_d1 --pool bulk --parity ata-U_par1 --spare ata-U_spare' cat "$WORK/jobcalls"
rm -f "$WORK/calls"
rc=0; out=$($M run --disks ata-U_d1,ata-U_d2 --pool bulk --parity ata-U_par1,ata-U_par2 --spare ata-U_spare </dev/null 2>&1) || rc=$?
check_eq "run succeeds" 0 "$rc"
check_eq "adopt with --merge and --spare first, then each old parity followed by a sync" "bulk --role adopt --disks ata-U_d1,ata-U_d2 --merge --spare ata-U_spare --yes
bulk --role parity --disks ata-U_par1 --yes
sync --no-mover --force
bulk --role parity --disks ata-U_par2 --yes
sync --no-mover --force" "$(cat "$WORK/calls")"
rm -f "$WORK/calls"
$M run --disks ata-U_d1 --pool bulk --per-disk --chown </dev/null >/dev/null 2>&1
check_eq "per disk and chown are passed on, no merge" "bulk --role adopt --disks ata-U_d1 --chown --yes" "$(cat "$WORK/calls")"

echo "-- encrypted disks: the passphrases travel as files, never as arguments"
rm -f "$WORK/jobcalls" "$WORK/dryenc"; mkdir -p "$WORK/run"
rc=0; out=$(printf '%s\n' '{"unraid":"S3cret-unraid","server":"srv-pass"}' | $M plan --disks ata-U_d3 --unlock 2>&1) || rc=$?
check_eq "the plan with --unlock: exit 0" 0 "$rc"
check_out "the dry run saw the Unraid passphrase in a file" 'ENCFILE S3cret-unraid' cat "$WORK/dryenc"
has 'S3cret' && fail "the passphrase is not in the plan" || pass "the passphrase is not in the plan"
has 'key slot after a header backup' && pass "the plan names the header write" || fail "header note: $out"
rc=0; out=$(printf '%s\n' '{"unraid":"S3cret-unraid","server":""}' | $M start --disks ata-U_d3 --unlock --confirm bulk 2>&1) || rc=$?
check_eq "start with --unlock: exit 0" 0 "$rc"
check_out "the job gets the path of a file" '^HS_UNRAID_PASSPHRASE_FILE=.*job-unraid-pass' cat "$WORK/jobcalls"
grep -q 'S3cret' <(grep -v '^HS_UNRAID_PASSPHRASE_FILE=' "$WORK/jobcalls") && fail "the passphrase is not in the job command" || pass "the passphrase is not in the job command"
f=$(sed -n 's/^HS_UNRAID_PASSPHRASE_FILE=//p' "$WORK/jobcalls" | head -1)
check_eq "the file holds it, 0600" "S3cret-unraid 600" "$(cat "$f") $(stat -c %a "$f")"

finish
