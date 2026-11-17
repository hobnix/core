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

echo "-- the disk with a dirty or foreign filesystem is refused, not changed"
dev=$(mkloop ntfsish 100M)
printf 'NTFS    ' | dd of="$dev" bs=1 seek=3 conv=notrunc 2>/dev/null
out=$(pool bulk --role adopt --disks ata-TEST_ntfsish --dry-run 2>&1 || true)
if grep -qiE "expected exactly one|temp-disk|not a free" <<<"$out"; then pass "an unsupported disk is refused"; else fail "an unsupported disk is refused ($out)"; fi

rm -f /etc/hs/bulk-type
finish
