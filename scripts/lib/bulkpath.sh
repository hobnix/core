# shellcheck shell=bash
# Where the disks of the bulk array (snapraid layout) are mounted: ONE place, so that moving them changes one line.
# Sourced, not run:   . "$(dirname "$0")/lib/bulkpath.sh"
#
#   disks_root          the folder whose data-NN and parity-N children are the mounted disks
#   disk_dir <member>   data-04, bulk-data-04 or parity-1 -> <root>/data-04
#
# The root is /var/lib/hs/disks since the switch of  (it was /mnt/bulk): nobody browses there by accident. A DETACHED disk lives under /mnt/bulk. The pool views (/bulk, /mnt/bulk/pool) and the upload cache (/mnt/bulk/cache) are NOT disks and keep their own paths.
# Never browse a disk's folder and copy into the pool view: the files are the same files (docs/Entwicklungsnotizen.md). Test knob: HS_DISKS_ROOT (a script's own
# older knob, e.g. HS_BULK_BASE or HS_MNT_BULK, still wins where it exists).
# shellcheck source=scripts/lib/pools.sh
. "${BASH_SOURCE[0]%/*}/pools.sh"
disks_root() { printf '%s\n' "${HS_DISKS_ROOT:-/var/lib/hs/disks}"; }
# snap_root: the merged SnapRAID view: HS_BULK if set, else the folder of the SnapRAID pool row, else the legacy folder.
# Labels, the pool view, the cache, the lock and the fsname keep their old names (internal identifiers, xfs label length).
snap_root() {
  local n
  if [ -n "${HS_BULK:-}" ]; then printf '%s\n' "$HS_BULK"
  elif n=$(pool_snapraid 2>/dev/null); then pool_root "$n"
  else printf '/bulk\n'; fi
}
disk_dir() { local m=${1#bulk-}; printf '%s/%s\n' "$(disks_root)" "$m"; }
# a DETACHED disk (hs sys disk start detach <member>) is mounted here; it is not in the pool. Under /mnt/bulk, away from the pool disks.
detached_dir() { local m=${1#bulk-}; printf '%s/%s\n' "${HS_DETACHED_ROOT:-/mnt/bulk}" "$m"; }
