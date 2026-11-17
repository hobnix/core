# shellcheck shell=bash
# Disks the way Unraid makes them, on loop devices (sourced after tests/lib.sh; tests/adopt.sh uses it, docs/dev-environment.md lists it).
# docs/PLAN-storage-nas.md step 7 (#460 a). An Unraid array disk has ONE partition (GPT, from sector 64) with xfs or btrfs in it (or LUKS with
# xfs or btrfs inside), the parity disk has the partition and NO file system, files belong to nobody:users (99:100), and the top folders
# (user shares) repeat on several disks. The helpers need root; one that cannot build a disk on this machine returns 1 and sets UNRAID_WHY
# (the reason, for `skip "$UNRAID_WHY"`; in CI a skip counts as a failure, so the tool must be there).
#
#   unraid_disk <name> <size>                  a loop disk with one empty partition; /dev/disk/by-id/ata-TEST_<name> points at it
#   unraid_data <name> <xfs|btrfs> [luks]      a data disk with its files (unraid_fill); luks: inside LUKS, opened with $UNRAID_PASS
#   unraid_parity <name>                       a parity disk: the partition, no file system
#   unraid_zfs <name>                          an array disk formatted with ZFS (Unraid 6.12): refused as it is
#   unraid_btrfs_multi <name1> <name2>         two disks that are one btrfs file system (raid1)
#   unraid_keyfile_luks <name>                 LUKS that only a key file opens ($UNRAID_KEYFILE), xfs inside
#   unraid_dirty_xfs <name>                    xfs whose log was not replayed (an array that was not stopped properly)
#   unraid_fill <mount point> <tag>            the shared top folders (Media, Shared) and one of its own (Own-<tag>), owner 99:100
# Each helper leaves the whole device in $UNRAID_DEV (call it plainly, not in $(...): the reason would be lost in the subshell).
# $UNRAID_PASS is the passphrase of this "server" (export it as HS_DISK_PASSPHRASE for the script under test).
UNRAID_PASS=unraid-test-pass
UNRAID_KEYFILE=${WORK:-/tmp}/unraid.key
UNRAID_SIZE=${UNRAID_SIZE:-320M}   # xfs needs about 300 MB
UNRAID_WHY=""; UNRAID_DEV=""

_unraid_need() {   # _unraid_need <tool>...: 0 when all exist
  local t
  for t in "$@"; do have "$t" || { UNRAID_WHY="$t is not installed on this machine"; return 1; }; done
}
_unraid_fs_ok() {   # the kernel can mount it (xfs may be missing in a sandbox)
  case "$1" in
    xfs|btrfs) _unraid_need "mkfs.$1" || return 1
               fs_works "$1" || { UNRAID_WHY="this kernel cannot mount $1"; return 1; } ;;
  esac
}
_unraid_mkfs() {   # _unraid_mkfs <device> <fs>
  case "$2" in xfs) mkfs.xfs -q -f "$1" ;; btrfs) mkfs.btrfs -q -f "$1" ;; esac >/dev/null 2>&1
}
_unraid_luks() {   # _unraid_luks <partition> <mapper name> <key>: format and open; key is "pass" or a key file path
  local key=$3
  if [ "$key" = pass ]; then
    printf %s "$UNRAID_PASS" | cryptsetup luksFormat --batch-mode --type luks2 --pbkdf pbkdf2 --pbkdf-force-iterations 1000 --key-file - "$1" >/dev/null 2>&1 &&
      printf %s "$UNRAID_PASS" | cryptsetup open --key-file - "$1" "$2" >/dev/null 2>&1
  else
    cryptsetup luksFormat --batch-mode --type luks2 --pbkdf pbkdf2 --pbkdf-force-iterations 1000 --key-file "$key" "$1" >/dev/null 2>&1 &&
      cryptsetup open --key-file "$key" "$1" "$2" >/dev/null 2>&1
  fi
}

unraid_disk() {   # unraid_disk <name> <size> -> sets UNRAID_DEV (the partition is ${UNRAID_DEV}p1)
  local img=$WORK/$1.img dev
  _unraid_need sfdisk losetup || return 1
  truncate -s "$2" "$img"
  dev=$(losetup -f --show -P "$img") || { UNRAID_WHY="no loop device"; return 1; }
  echo "$dev" >> "$LOOPS"
  mkdir -p /dev/disk/by-id
  ln -sf "$dev" "/dev/disk/by-id/ata-TEST_$1"; echo "/dev/disk/by-id/ata-TEST_$1" >> "$LINKS"
  printf 'label: gpt\nfirst-lba: 34\nstart=64, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4\n' | sfdisk -q --no-reread "$dev" >/dev/null 2>&1 || true
  udevadm settle 2>/dev/null || true
  [ -b "${dev}p1" ] || partx -a "$dev" 2>/dev/null || true
  [ -b "${dev}p1" ] || { UNRAID_WHY="this kernel makes no partition devices on loop devices (loop max_part=0, as in WSL2)"; return 1; }
  UNRAID_DEV=$dev
}

unraid_fill() {   # unraid_fill <mount point> <tag>
  local m=$1 t=$2
  mkdir -p "$m/Media/Movies" "$m/Shared" "$m/Own-$t"
  echo "film-$t" > "$m/Media/Movies/$t.mkv"
  echo "shared-$t" > "$m/Shared/from-$t.txt"
  echo "own-$t" > "$m/Own-$t/f.txt"
  chown -R 99:100 "$m/Media" "$m/Shared" "$m/Own-$t"
  chmod -R a+rwX "$m/Media" "$m/Shared" "$m/Own-$t"
}

unraid_data() {   # unraid_data <name> <xfs|btrfs> [luks]
  local name=$1 fs=$2 dev target m=$WORK/m-$1
  _unraid_fs_ok "$fs" || return 1
  [ "${3:-}" != luks ] || { _unraid_need cryptsetup || return 1; dm_works || { UNRAID_WHY="device-mapper (dm-crypt) is not usable here"; return 1; }; }
  unraid_disk "$name" "$UNRAID_SIZE" || return 1; dev=$UNRAID_DEV
  target=${dev}p1
  if [ "${3:-}" = luks ]; then
    _unraid_luks "$target" "hs-unraid-$name" pass || { UNRAID_WHY="cryptsetup failed"; return 1; }
    target=/dev/mapper/hs-unraid-$name
  fi
  _unraid_mkfs "$target" "$fs" || { UNRAID_WHY="mkfs.$fs failed"; return 1; }
  mkdir -p "$m"; mount "$target" "$m" || { UNRAID_WHY="cannot mount $fs"; return 1; }
  unraid_fill "$m" "$name"
  umount "$m"
  [ "${3:-}" != luks ] || cryptsetup close "hs-unraid-$name"
  UNRAID_DEV=$dev
}

unraid_parity() { unraid_disk "$1" "${2:-$UNRAID_SIZE}"; }

unraid_zfs() {
  local dev
  _unraid_need zpool || return 1
  unraid_disk "$1" "$UNRAID_SIZE" || return 1; dev=$UNRAID_DEV
  zpool create -f -m none "unraidz-$1" "${dev}p1" >/dev/null 2>&1 || { UNRAID_WHY="zpool create failed (no ZFS module?)"; return 1; }
  zpool export "unraidz-$1" >/dev/null 2>&1
  UNRAID_DEV=$dev
}

unraid_btrfs_multi() {
  local a b
  _unraid_fs_ok btrfs || return 1
  unraid_disk "$1" "$UNRAID_SIZE" || return 1; a=$UNRAID_DEV
  unraid_disk "$2" "$UNRAID_SIZE" || return 1; b=$UNRAID_DEV
  mkfs.btrfs -q -f -d raid1 -m raid1 "${a}p1" "${b}p1" >/dev/null 2>&1 || { UNRAID_WHY="mkfs.btrfs (raid1) failed"; return 1; }
  btrfs device scan >/dev/null 2>&1 || true
  UNRAID_DEV=$a
}

unraid_keyfile_luks() {
  local dev
  _unraid_fs_ok xfs || return 1
  _unraid_need cryptsetup || return 1
  dm_works || { UNRAID_WHY="device-mapper (dm-crypt) is not usable here"; return 1; }
  head -c 64 /dev/urandom > "$UNRAID_KEYFILE"
  unraid_disk "$1" "$UNRAID_SIZE" || return 1; dev=$UNRAID_DEV
  _unraid_luks "${dev}p1" "hs-unraid-$1" "$UNRAID_KEYFILE" || { UNRAID_WHY="cryptsetup failed"; return 1; }
  _unraid_mkfs "/dev/mapper/hs-unraid-$1" xfs
  cryptsetup close "hs-unraid-$1"
  UNRAID_DEV=$dev
}

unraid_dirty_xfs() {
  local dev m=$WORK/m-$1 rc=0
  _unraid_fs_ok xfs || return 1
  _unraid_need xfs_io xfs_repair || return 1
  unraid_disk "$1" "$UNRAID_SIZE" || return 1; dev=$UNRAID_DEV
  _unraid_mkfs "${dev}p1" xfs
  mkdir -p "$m"; mount "${dev}p1" "$m" || { UNRAID_WHY="cannot mount xfs"; return 1; }
  unraid_fill "$m" "$1"
  xfs_io -x -c 'shutdown' "$m" >/dev/null 2>&1   # stops the file system without writing a clean log
  umount "$m" 2>/dev/null
  xfs_repair -n "${dev}p1" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 2 ] || { UNRAID_WHY="this kernel left the xfs log clean after a forced shutdown (cannot make a dirty log)"; return 1; }
  UNRAID_DEV=$dev
}
