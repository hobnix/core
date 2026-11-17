# shellcheck shell=bash
# Why a file system on an old disk can not be adopted, read without changing the disk (docs/PLAN-storage-nas.md D8). Sourced, not run.
#
#   adopt_refusal <device> <fstype>   prints the reason and returns 1 when the file system can not be adopted; prints nothing and returns 0 otherwise
#
# Refused: a btrfs that spans several devices, an xfs or ext4 whose log was not replayed (it was not shut down cleanly: writing its label
# would fail or lose changes). A ZFS member and a LUKS disk that the passphrase does not open are refused where they are met (manage-pool.sh adopt_fs).
adopt_refusal() {
  local dev=$1 fs=$2 n rc=0
  case "$fs" in
    btrfs)
      command -v btrfs >/dev/null 2>&1 || return 0
      n=$(btrfs filesystem show "$dev" 2>/dev/null | awk '/Total devices/ { print $3; exit }')
      if [ "${n:-1}" -gt 1 ]; then
        echo "$dev is one of $n devices of one btrfs file system: a multi-device btrfs can not be adopted disk by disk (copy it with hs disk temp)."
        return 1
      fi ;;
    xfs)
      command -v xfs_repair >/dev/null 2>&1 || return 0
      xfs_repair -n "$dev" >/dev/null 2>&1 || rc=$?
      if [ "$rc" -eq 2 ]; then
        echo "$dev has a dirty log (it was not shut down cleanly). Stop the array in Unraid properly, or repair it (xfs_repair) first; nothing was changed."
        return 1
      fi ;;
    ext4)
      command -v dumpe2fs >/dev/null 2>&1 || return 0
      if dumpe2fs -h "$dev" 2>/dev/null | grep -qi 'features:.*needs_recovery'; then
        echo "$dev has a dirty log (it was not shut down cleanly). Stop the old server properly, or repair it (fsck) first; nothing was changed."
        return 1
      fi ;;
  esac
  return 0
}
