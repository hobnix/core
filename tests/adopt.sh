#!/usr/bin/env bash
# hs pool bulk add --role adopt: disks that already hold files keep them (ext4, xfs, btrfs).
set -uo pipefail
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/lib-unraid.sh"
need_root
mkdir -p /etc/hs
echo snapraid > /etc/hs/bulk-type
export HS_TEST_LOOP=1 HS_ADOPT_SKIP_MERGE=1 HS_PLAIN=1 HS_STATE_DIR=$WORK/state
pool() { bash "$SCRIPTS/manage-pool.sh" "$@"; }

# a disk the way Unraid leaves it: share folders in the root, a hidden folder, a loose file
make_disk() {   # make_disk <name> <fs>
  local dev m="$WORK/m-$1"
  dev=$(mkloop "$1" 300M)
  case "$2" in xfs) mkfs.xfs -q -f "$dev" ;; btrfs) mkfs.btrfs -q -f "$dev" ;; *) mkfs.ext4 -q -F "$dev" ;; esac >/dev/null 2>&1
  mkdir -p "$m"; mount "$dev" "$m"
  mkdir -p "$m/Media/Movies" "$m/Backups" "$m/.Recycle.Bin"
  echo "film-$1" > "$m/Media/Movies/a.mkv"; echo "bk-$1" > "$m/Backups/b.zip"
  echo trash > "$m/.Recycle.Bin/r"; echo loose > "$m/loosefile"
  umount "$m"
}

next=0
for fs in ext4 xfs btrfs; do
  echo "-- $fs"
  if ! fs_works "$fs"; then skip "$fs is not available on this machine"; continue; fi
  next=$((next + 1)); name="$fs$next"
  make_disk "$name" "$fs"
  mp="/mnt/bulk/data-$(printf '%02d' "$next")"
  rm -rf "/mnt/bulk/data-0$next" 2>/dev/null
  out=$(pool bulk --role adopt --disks "ata-TEST_$name" --dry-run 2>&1 || true)
  check_out "$fs: the dry run lists the folders" "Media" echo "$out"
  dev=$(readlink -f "/dev/disk/by-id/ata-TEST_$name")
  case "$(blkid -s LABEL -o value "$dev" 2>/dev/null)" in bulk-*) fail "$fs: the dry run changes nothing" ;; *) pass "$fs: the dry run changes nothing" ;; esac
  echo bulk | pool bulk --role adopt --disks "ata-TEST_$name" >"$WORK/adopt-$name.log" 2>&1
  check "$fs: adopting succeeds" test -d "$mp/shares"
  label=$(blkid -s LABEL -o value "$(findmnt -no SOURCE "$mp" 2>/dev/null)" 2>/dev/null)
  check_eq "$fs: the label is bulk-data-$(printf '%02d' "$next")" "bulk-data-$(printf '%02d' "$next")" "$label"
  media=$(find "$mp/shares" -maxdepth 1 -name '*media*' -o -maxdepth 1 -name 'Media' | head -1)
  check_eq "$fs: the file is intact in its share" "film-$name" "$(cat "$media/Movies/a.mkv" 2>/dev/null)"
  check "$fs: the hidden folder stays" test -f "$mp/.Recycle.Bin/r"
  check "$fs: the loose file stays" test -f "$mp/loosefile"
  check "$fs: nothing is left of Media in the root" test ! -e "$mp/Media"
done

# ── With a spare disk (D9, step 8): the parity is built before an adopted disk is written to ──
# The sync is a fake that looks at the disks at the moment it runs: what it sees is what a real sync would see.
echo "-- adopting with a spare disk: no write to a data disk until the parity is synced"
export HS_ADOPTING_DIR=$WORK/adopting
cat > "$WORK/fake-sync.sh" <<'FAKE'
#!/usr/bin/env bash
d=$(readlink -f /dev/disk/by-id/ata-TEST_spd$FAKE_N)
md5sum < "$d" > "$FAKE_OUT/sum"
blkid -s LABEL -o value "$d" > "$FAKE_OUT/label" 2>/dev/null
ls "$HS_ADOPTING_DIR" > "$FAKE_OUT/records" 2>/dev/null
blkid -s LABEL -o value /dev/disk/by-id/ata-TEST_sps$FAKE_N > "$FAKE_OUT/spare" 2>/dev/null
exit "${FAKE_SYNC_RC:-0}"
FAKE
chmod +x "$WORK/fake-sync.sh"
devsum() { md5sum < "$(readlink -f "/dev/disk/by-id/ata-TEST_$1")"; }
for n in 1 2; do
  # the spare of the run before is a parity disk now: wipe it, so that the array has none again
  for p in 1 2; do [ -e "/dev/disk/by-id/ata-TEST_sps$p" ] && wipefs -a -q "/dev/disk/by-id/ata-TEST_sps$p"; done
  make_disk "spd$n" ext4; mkloop "sps$n" 400M >/dev/null
  export FAKE_N=$n FAKE_OUT=$WORK/fake$n; mkdir -p "$FAKE_OUT"
  before=$(devsum "spd$n")
  out=$(HS_BULK_SYNC=$WORK/fake-sync.sh pool bulk --role adopt --disks "ata-TEST_spd$n" --spare "ata-TEST_sps$n" --dry-run 2>&1 || true)
  check_out "n=$n: the plan states the order" "only after the sync has finished" echo "$out"
  check_eq "n=$n: the dry run wrote nothing to either disk" "$before" "$(devsum "spd$n")"
  check_eq "n=$n: the dry run left the spare alone" "" "$(blkid -s LABEL -o value "/dev/disk/by-id/ata-TEST_sps$n" 2>/dev/null)"
  if [ "$n" = 1 ]; then
    echo "ata-TEST_sps$n" | HS_BULK_SYNC=$WORK/fake-sync.sh pool bulk --role adopt --disks "ata-TEST_spd$n" --spare "ata-TEST_sps$n" >"$WORK/spare$n.log" 2>&1
    check_eq "n=$n: at sync time the data disk was byte for byte untouched" "$before" "$(cat "$FAKE_OUT/sum" 2>/dev/null)"
    check_eq "n=$n: at sync time it had no label" "" "$(cat "$FAKE_OUT/label" 2>/dev/null)"
    check_eq "n=$n: at sync time its record existed" "1" "$(wc -l < "$FAKE_OUT/records" 2>/dev/null | tr -d ' ')"
    check_eq "n=$n: at sync time the spare was already the parity disk" "bulk-parity-1" "$(cat "$FAKE_OUT/spare" 2>/dev/null)"
    case "$(blkid -s LABEL -o value "$(readlink -f "/dev/disk/by-id/ata-TEST_spd$n")" 2>/dev/null)" in bulk-data-*) pass "n=$n: after the sync the label is written" ;; *) fail "n=$n: no label after the sync ($(tail -n 3 "$WORK/spare$n.log" | tr '
' ' '))" ;; esac
    check_eq "n=$n: the record is gone after the label" "0" "$(ls "$HS_ADOPTING_DIR" 2>/dev/null | wc -l | tr -d ' ')"
  else
    # a sync that fails: nothing may have been written to the data disk, the record keeps it read-only
    if echo "ata-TEST_sps$n" | FAKE_SYNC_RC=1 HS_BULK_SYNC=$WORK/fake-sync.sh pool bulk --role adopt --disks "ata-TEST_spd$n" --spare "ata-TEST_sps$n" >"$WORK/spare$n.log" 2>&1; then fail "n=$n: a failed sync must stop the command"; else pass "n=$n: a failed sync stops the command"; fi
    check_eq "n=$n: no write to the data disk after a failed sync" "$before" "$(devsum "spd$n")"
    check_eq "n=$n: no label after a failed sync" "" "$(blkid -s LABEL -o value "$(readlink -f "/dev/disk/by-id/ata-TEST_spd$n")" 2>/dev/null)"
    check_eq "n=$n: the record stays" "1" "$(ls "$HS_ADOPTING_DIR" 2>/dev/null | wc -l | tr -d ' ')"
    rm -f "$HS_ADOPTING_DIR"/*
  fi
done
echo "n=3 spare smaller than the data disk"
wipefs -a -q /dev/disk/by-id/ata-TEST_sps2
make_disk spd3 ext4; mkloop sps3 100M >/dev/null
out=$(pool bulk --role adopt --disks ata-TEST_spd3 --spare ata-TEST_sps3 --dry-run 2>&1 || true)
check_out "a spare smaller than the data disk is refused" "smaller than the largest data disk" echo "$out"
out=$(pool bulk --role adopt --disks ata-TEST_spd3 --dry-run 2>&1 || true)
check_out "no spare: the unprotected window is stated" "data is NOT protected" echo "$out"
unset HS_ADOPTING_DIR FAKE_N FAKE_OUT

# ── Unraid disks (docs/PLAN-storage-nas.md D8, step 7): the plan only, nothing is written ──
export HS_DISK_PASSPHRASE=$UNRAID_PASS
dev_sum() { blkid -p -o export "${1}p1" 2>/dev/null | md5sum; }
echo "-- Unraid: one partition, files owned 99:100, the same top folder on two disks"
if unraid_data ux1 xfs && unraid_data ux2 xfs; then
  p=${UNRAID_DEV}p1
  sum=$(dev_sum "$UNRAID_DEV")
  out=$(pool bulk --role adopt --disks ata-TEST_ux1,ata-TEST_ux2 --merge --dry-run 2>&1 || true)
  check_out "xfs in a partition is adoptable: the plan lists its own folder" "Own-ux1" echo "$out"
  check_out "the same top folder on two disks is merged" "merged with folders of the same name\): .*Shared" echo "$out"
  check_eq "the dry run changed nothing on the disk" "$sum" "$(dev_sum "$UNRAID_DEV")"
  m=$WORK/m-own; mkdir -p "$m"; mount -o ro,norecovery "$p" "$m"
  check_eq "the files belong to 99:100" "99:100" "$(stat -c %u:%g "$m/Media/Movies/ux2.mkv" 2>/dev/null || stat -c %u:%g "$m/Media/Movies/ux1.mkv")"
  umount "$m"
  out=$(bash "$SCRIPTS/migrate-check.sh" 2>&1 || true)
  check_out "migrate check: xfs can be adopted" "ata-TEST_ux1.*xfs.*can be adopted" echo "$out"
else skip "Unraid xfs disks: $UNRAID_WHY"; fi

echo "-- Unraid: btrfs and LUKS (xfs inside) are adoptable"
if unraid_data ub1 btrfs; then
  out=$(pool bulk --role adopt --disks ata-TEST_ub1 --dry-run 2>&1 || true)
  check_out "btrfs in a partition is adoptable" "btrfs.*Own-ub1|Own-ub1" echo "$out"
else skip "Unraid btrfs disk: $UNRAID_WHY"; fi
if unraid_data ul1 xfs luks; then
  out=$(pool bulk --role adopt --disks ata-TEST_ul1 --dry-run 2>&1 || true)
  check_out "LUKS with xfs inside opens with the passphrase and is adoptable" "encrypted: unlocked" echo "$out"
  check_out "the LUKS disk shows its folders" "Own-ul1" echo "$out"
else skip "Unraid LUKS disk: $UNRAID_WHY"; fi

echo "-- Unraid: a parity disk has no file system"
if unraid_parity up1 200M; then
  check_eq "the parity partition has no file system" "" "$(blkid -p -o value -s TYPE "${UNRAID_DEV}p1" 2>/dev/null)"
  out=$(pool bulk --role adopt --disks ata-TEST_up1 --dry-run 2>&1 || true)
  check_out "a parity disk is not adopted (no data on it)" "expected exactly one" echo "$out"
  if [ -b "/dev/disk/by-id/ata-TEST_ux1" ]; then
    out=$(bash "$SCRIPTS/migrate-check.sh" --parity ata-TEST_up1 2>&1 || true)
    check_out "a parity disk smaller than the data disks is refused" "smaller than the largest data disk" echo "$out"
  fi
else skip "Unraid parity disk: $UNRAID_WHY"; fi

echo "-- Unraid: refused, with the reason"
if unraid_zfs uz1; then
  out=$(pool bulk --role adopt --disks ata-TEST_uz1 --dry-run 2>&1 || true)
  check_out "a ZFS array disk is refused" "formatted with ZFS" echo "$out"
  check_out "migrate check names ZFS" "ata-TEST_uz1.*ZFS" bash "$SCRIPTS/migrate-check.sh"
else skip "ZFS array disk: $UNRAID_WHY"; fi
if unraid_btrfs_multi um1 um2; then
  out=$(pool bulk --role adopt --disks ata-TEST_um1 --dry-run 2>&1 || true)
  check_out "a multi-device btrfs is refused" "one of 2 devices of one btrfs" echo "$out"
  check_out "migrate check names the multi-device btrfs" "REFUSED.*multi-device btrfs" bash "$SCRIPTS/migrate-check.sh"
else skip "multi-device btrfs: $UNRAID_WHY"; fi
if unraid_keyfile_luks uk1; then
  out=$(pool bulk --role adopt --disks ata-TEST_uk1 --dry-run 2>&1 || true)
  check_out "a LUKS disk that only a key file opens is refused" "key file only" echo "$out"
else skip "key file LUKS: $UNRAID_WHY"; fi
if unraid_dirty_xfs ud1; then
  sum=$(dev_sum "$UNRAID_DEV")
  out=$(pool bulk --role adopt --disks ata-TEST_ud1 --dry-run 2>&1 || true)
  check_out "a dirty xfs log is refused in the plan" "dirty log" echo "$out"
  check_out "migrate check names the dirty log" "ata-TEST_ud1.*dirty log" bash "$SCRIPTS/migrate-check.sh"
  check_eq "the dirty disk was not written to" "$sum" "$(dev_sum "$UNRAID_DEV")"
  rm -rf "$WORK/fakebin"
else skip "dirty xfs log: $UNRAID_WHY"; fi
unset HS_DISK_PASSPHRASE

echo "-- Unraid (D10): a reserved folder name gets a suffix when merged"
if unraid_disk uw1 300M; then
  mkfs.ext4 -q -F "${UNRAID_DEV}p1" >/dev/null 2>&1
  m=$WORK/m-uw1; mkdir -p "$m"; mount "${UNRAID_DEV}p1" "$m"
  mkdir -p "$m/Global" "$m/Media"; echo g > "$m/Global/g.txt"; echo m > "$m/Media/m.txt"
  umount "$m"
  out=$(pool bulk --role adopt --disks ata-TEST_uw1 --merge --dry-run 2>&1 || true)
  check_out "merged: the reserved name is renamed in the plan" "renamed: 'Global' is a reserved share name, it becomes 'Global-adopted'" echo "$out"
  out=$(pool bulk --role adopt --disks ata-TEST_uw1 --dry-run 2>&1 || true)
  check_out "per disk: only the note, no rename" "note: 'Global' is a reserved share name" echo "$out"
else skip "reserved names: $UNRAID_WHY"; fi

echo "-- Unraid (D11): an encrypted disk opened with the Unraid passphrase gets this server's passphrase as a key slot after the header backup"
if _unraid_need cryptsetup mkfs.ext4 && dm_works && unraid_disk ue1 300M; then
  dev=$UNRAID_DEV
  _unraid_luks "${dev}p1" hs-unraid-ue1 pass && mkfs.ext4 -q -F /dev/mapper/hs-unraid-ue1 >/dev/null 2>&1
  m=$WORK/m-ue1; mkdir -p "$m"; mount /dev/mapper/hs-unraid-ue1 "$m"; mkdir -p "$m/Media"; echo e > "$m/Media/e.txt"; umount "$m"
  cryptsetup close hs-unraid-ue1
  export HS_DISK_PASSPHRASE=server-pass-1 HS_LUKS_HEADERS=$WORK/luks-headers
  printf %s "$UNRAID_PASS" > "$WORK/unraid-pass"; chmod 600 "$WORK/unraid-pass"
  mkdir -p "$HS_STATE_DIR"
  # this server already has an encrypted disk (a recorded uuid), so the Unraid passphrase is only opening
  echo "00000000-0000-0000-0000-000000000000" > "$HS_STATE_DIR/luks-uuids"
  cp "$WORK/unraid-pass" "$WORK/unraid-pass.dry"
  out=$(HS_UNRAID_PASSPHRASE_FILE=$WORK/unraid-pass.dry pool bulk --role adopt --disks ata-TEST_ue1 --merge --dry-run 2>&1 || true)
  check_out "the plan names the key slot and the header write" "key slot after the header backup" echo "$out"
  check "the dry run wrote no header backup" test ! -e "$WORK/luks-headers"
  if printf %s server-pass-1 | cryptsetup open --test-passphrase --key-file - "${dev}p1" 2>/dev/null; then fail "before: the server passphrase does not open the disk"; else pass "before: the server passphrase does not open the disk"; fi
  cryptsetup close "hs-$(cryptsetup luksUUID "${dev}p1" | tr -d - | cut -c1-12)" 2>/dev/null || true   # the dry run left it open
  HS_UNRAID_PASSPHRASE_FILE=$WORK/unraid-pass HS_DISK_PASSPHRASE=server-pass-1 pool bulk --role adopt --disks ata-TEST_ue1 --merge --yes >"$WORK/adopt-ue1.log" 2>&1 || true
  check "a header backup exists" test -s "$WORK/luks-headers/$(cryptsetup luksUUID "${dev}p1").img"
  if printf %s server-pass-1 | cryptsetup open --test-passphrase --key-file - "${dev}p1" 2>/dev/null; then pass "after: this server's passphrase opens the disk"; else fail "after: this server's passphrase opens the disk ($(tail -3 "$WORK/adopt-ue1.log" | tr '\n' ' '))"; fi
  if printf %s "$UNRAID_PASS" | cryptsetup open --test-passphrase --key-file - "${dev}p1" 2>/dev/null; then pass "the Unraid passphrase still opens it"; else fail "the Unraid passphrase still opens it"; fi
  check "the unraid passphrase file was consumed" test ! -e "$WORK/unraid-pass"
  rm -f "$HS_STATE_DIR/luks-uuids"; unset HS_LUKS_HEADERS
  export HS_DISK_PASSPHRASE=$UNRAID_PASS
else skip "LUKS key slot: ${UNRAID_WHY:-device-mapper is not usable here}"; fi

echo "-- long folder names (issue 1245): the share is cut to 41 characters, the plan says so, two folders never become one share"
wipefs -a -q /dev/disk/by-id/ata-TEST_sps1 /dev/disk/by-id/ata-TEST_sps2 /dev/disk/by-id/ata-TEST_sps3 2>/dev/null || true
LONGDIR=CommunityApplicationsAppdataBackup
dev=$(mkloop long1 300M); mkfs.ext4 -q -F "$dev" >/dev/null 2>&1
m=$WORK/m-long1; mkdir -p "$m"; mount "$dev" "$m"; mkdir -p "$m/$LONGDIR"; echo l > "$m/$LONGDIR/f"; umount "$m"
sum=$(md5sum < "$dev")
out=$(pool bulk --role adopt --disks ata-TEST_long1 --dry-run 2>&1 || true)
check_out "the plan says the name is shortened" "shortened: '$LONGDIR' is too long for a share name" echo "$out"
planned=$(sed -n "s/^ *$LONGDIR -> //p" <<<"$out" | head -n 1)
check_eq "the planned share name has 41 characters" 41 "${#planned}"
check_eq "the dry run wrote nothing" "$sum" "$(md5sum < "$dev")"
echo bulk | pool bulk --role adopt --disks ata-TEST_long1 >"$WORK/adopt-long1.log" 2>&1
where=$(findmnt -rn -o TARGET --source "$(readlink -f /dev/disk/by-id/ata-TEST_long1)" | head -n 1)
check_eq "the folder got the planned name" l "$(cat "$where/shares/$planned/f" 2>/dev/null)"
dev=$(mkloop twins 300M); mkfs.ext4 -q -F "$dev" >/dev/null 2>&1
m=$WORK/m-twins; mkdir -p "$m"; mount "$dev" "$m"; mkdir -p "$m/My Media" "$m/my-media"; umount "$m"
sum=$(md5sum < "$dev")
if out=$(echo bulk | pool bulk --role adopt --disks ata-TEST_twins 2>&1); then fail "two folders with one share name must be refused"; else pass "two folders with one share name are refused"; fi
check_out "the refusal says why" "Two folders never become one share" echo "$out"
check_eq "nothing was written to the refused disk" "$sum" "$(md5sum < "$dev")"

echo "-- the disk with a dirty or foreign filesystem is refused, not changed"
dev=$(mkloop ntfsish 100M)
printf 'NTFS    ' | dd of="$dev" bs=1 seek=3 conv=notrunc 2>/dev/null
out=$(pool bulk --role adopt --disks ata-TEST_ntfsish --dry-run 2>&1 || true)
if grep -qiE "expected exactly one|temp-disk|not a free" <<<"$out"; then pass "an unsupported disk is refused"; else fail "an unsupported disk is refused ($out)"; fi

rm -f /etc/hs/bulk-type
finish
