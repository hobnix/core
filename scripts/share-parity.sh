#!/usr/bin/env bash
# help: (snapraid layout) per share: folders the parity leaves out, and how many removed files stop the parity sync
# help.de: (Bauart snapraid) je Freigabe: Ordner, die die Parität auslässt, und wie viele gelöschte Dateien die Paritäts-Synchronisation anhalten
# args: <share> [parity] | <share> skip <folder> [--yes] [--dry-run] | <share> keep <folder> | <share> limit <N>|off|default [--yes] [--dry-run] | --state <share> | --refused
set -euo pipefail

# Why: SnapRAID cannot protect a folder whose files change while it reads them (downloads, unpacking), and a sync stops when
# many files vanished (normal app work in such a folder looks like a mistake). `skip` leaves a folder out of the parity;
# `limit` sets the number of removed files that stops the sync for one share (default: max(syncMaxRemoved, syncMaxRemovedPercent % of the files)).
#
# Used by the interfaces (plain, tab separated, no empty field):
#   --state <share>   limit<TAB>default|custom|off<TAB><N or ->, then default<TAB><floor><TAB><percent>, then skip<TAB><folder> per skipped folder
#   --refused         share<TAB>folder<TAB>removed<TAB>limit<TAB>share_total per row of the last refused sync (nothing = none)
#   --files <share> <folder>   number of files in the folder (for the plan)
# Test knobs: HS_BULK (the /bulk folder), HS_BULK_TYPE_FILE, HS_PARITY_SKIP, HS_PARITY_LIMITS, HS_SYNC_REFUSED, HS_SETTINGS_DIR, HS_BULK_MOUNT (stand-in for bulk-mount.sh), HS_LOCK.
here=$(dirname "$0")
. "$here/lib/ui.sh"
. "$here/lib/pools.sh"
. "$here/lib/bulkpath.sh"
. "$here/lib/setting.sh"
. "$here/lib/parity.sh"
root=$(snap_root)

usage() {
  say "usage: hs share <share> parity                          what is skipped and the limit of the share"
  say "       hs share <share> parity skip <folder>            leave a folder out of the parity (its files are not protected)"
  say "       hs share <share> parity keep <folder>            protect the folder again"
  say "       hs share <share> parity limit <N>|off|default    removed files that stop the sync for this share"
  say "       --yes skips the question, --dry-run only shows the plan"
  exit 1
}

supported() { [ "$(cat "${HS_BULK_TYPE_FILE:-/etc/hs/bulk-type}" 2>/dev/null || echo zfs)" = snapraid ] || { [ "$(pools_source)" = config ] && pool_snapraid >/dev/null; }; }

# shares/<name> or sensitive/<name> for a share name
rel_of() {
  local k
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || return 1
  for k in shares sensitive; do
    if [ -d "$root/$k/$1" ]; then echo "$k/$1"; return 0; fi
  done
  return 1
}

count_files() {   # count_files <rel> [<folder>]: files in the folder, or in the share without its skipped folders
  local rel=$1 dir f
  if [ -n "${2-}" ]; then find "$root/$rel/$2" -type f 2>/dev/null | wc -l | tr -d ' '; return; fi
  dir=$root/$rel
  local prune=()
  while IFS=$'\t' read -r _ f; do [ -z "$f" ] || prune+=(-path "$dir/$f" -prune -o); done < <(parity_skipped "$rel")
  find "$dir" ${prune[@]+"${prune[@]}"} -type f -print 2>/dev/null | wc -l | tr -d ' '
}

folder_ok() {
  [[ "$1" =~ ^[A-Za-z0-9._\ -]+(/[A-Za-z0-9._\ -]+)*$ ]] && [[ "/$1/" != *"/../"* ]] && [[ "/$1/" != *"/./"* ]]
}

yes=false dry=false args=()
for a in "$@"; do
  case "$a" in
    --yes) yes=true ;;
    --dry-run) dry=true ;;
    --plain) ;;
    *) args+=("$a") ;;
  esac
done
set -- ${args[@]+"${args[@]}"}

case "${1:-}" in
  --refused)
    f=$(parity_refused_file)
    [ ! -s "$f" ] || cat "$f"
    exit 0 ;;
  --state)
    [ $# -eq 2 ] || usage
    rel=$(rel_of "$2") || { printf 'limit\tdefault\t-\n'; exit 0; }
    m=$(parity_limit_mode "$rel")
    case "$m" in default) printf 'limit\tdefault\t-\n' ;; off) printf 'limit\toff\t-\n' ;; *) printf 'limit\tcustom\t%s\n' "$m" ;; esac
    printf 'default\t%s\t%s\n' "$(parity_limit_floor)" "$(parity_limit_percent)"
    parity_skipped "$rel" | while IFS=$'\t' read -r _ f; do printf 'skip\t%s\n' "$f"; done
    exit 0 ;;
  --files)
    [ $# -eq 3 ] || usage
    rel=$(rel_of "$2") || exit 1
    folder_ok "$3" || exit 1
    count_files "$rel" "$3"
    exit 0 ;;
esac

[ $# -ge 1 ] || usage
share=$1; shift
[ "${1:-}" != parity ] || shift
action=${1:-status}
supported || fail "Parity settings exist only on the snapraid layout. With /bulk on ZFS every file is protected the moment it is written."
rel=$(rel_of "$share") || fail "$(t "No share called '%s' under /bulk/shares or /bulk/sensitive." "$share")"
# the SnapRAID config is written again with the bulk lock held: never while a sync reads it
write_conf() {
  (
    exec 9>"${HS_LOCK:-/run/hs-bulk.lock}"
    flock -w 120 9 || exit 3
    bash "${HS_BULK_MOUNT:-$here/bulk-mount.sh}" >/dev/null
  ) || warn "The SnapRAID config could not be written now (a sync is running?). bulk-mount.sh writes it at the next start; the sync leaves the folders out in any case."
}

case "$action" in
  status)
    step "$(t "Parity of '%s'" "$share")"
    skipped=$(parity_skipped "$rel" | cut -f2)
    if [ -n "$skipped" ]; then
      note "Left out of the parity (not protected):"
      while read -r f; do [ -z "$f" ] || note "  $f"; done <<<"$skipped"
    else note "No folder is left out of the parity."; fi
    m=$(parity_limit_mode "$rel")
    case "$m" in
      off) note "Limit: off (a sync never stops for removed files in this share)" ;;
      default)
        n=$(count_files "$rel")
        note "$(t 'Limit: %s removed files (the higher of %s and %s %% of the %s files in the share)' "$(parity_limit_default "$n")" "$(parity_limit_floor)" "$(parity_limit_percent)" "$n")" ;;
      *) note "$(t 'Limit: %s removed files (set by hand; hs share %s parity limit default undoes it)' "$m" "$share")" ;;
    esac
    exit 0 ;;

  skip)
    [ $# -eq 2 ] || usage
    folder=${2%/}
    folder_ok "$folder" || fail "That is not a folder name inside the share (letters, digits, . _ - and spaces; no .. and no wildcards)."
    [ -d "$root/$rel/$folder" ] || fail "$(t "There is no folder '%s' in the share '%s'." "$folder" "$share")"
    if parity_skipped "$rel" | cut -f2 | grep -qxF -- "$folder"; then ok "$(t "'%s' is left out of the parity already." "$folder")"; exit 0; fi
    n=$(count_files "$rel" "$folder")
    step "$(t "Leave '%s' of '%s' out of the parity" "$folder" "$share")"
    note "$(t 'SnapRAID skips the folder from the next sync on: /%s/%s/ (%s files)' "$rel" "$folder" "$n")"
    note "The next sync drops these files from the parity, and removed files in the folder no longer count towards the limit."
    danger "The files in this folder lose their protection: a failed disk cannot bring them back from the parity."
    $dry && exit 0
    if ! $yes; then
      confirm_name "$folder" "the folder name" || fail "Not confirmed. Nothing was changed."
    fi
    parity_skip_add "$rel" "$folder"
    write_conf
    ok "$(t "'%s' is left out of the parity from the next sync." "$folder")"
    exit 0 ;;

  keep)
    [ $# -eq 2 ] || usage
    folder=${2%/}
    parity_skipped "$rel" | cut -f2 | grep -qxF -- "$folder" || { ok "$(t "'%s' is not left out of the parity." "$folder")"; exit 0; }
    step "$(t "Protect '%s' of '%s' again" "$folder" "$share")"
    note "The next sync adds its files to the parity again (the first sync after this can take a while)."
    $dry && exit 0
    parity_skip_del "$rel" "$folder"
    write_conf
    ok "$(t "'%s' is protected again from the next sync." "$folder")"
    exit 0 ;;

  limit)
    [ $# -eq 2 ] || usage
    v=$2
    [[ "$v" =~ ^[0-9]+$ ]] || [ "$v" = off ] || [ "$v" = default ] || usage
    step "$(t "Limit of removed files for '%s'" "$share")"
    case "$v" in
      off)
        note "The sync of this share never stops for removed files: a mistake or malware that deletes files is made permanent by the next sync."
        danger "Without a limit a sync cannot protect this share from deleted files."
        $dry && exit 0
        if ! $yes; then confirm_name "$share" "the share name" || fail "Not confirmed. Nothing was changed."; fi
        parity_limit_write "$rel" off ;;
      default)
        note "$(t 'Back to the default: the higher of %s and %s %% of the files of the share.' "$(parity_limit_floor)" "$(parity_limit_percent)")"
        $dry && exit 0
        parity_limit_write "$rel" ;;
      *)
        note "$(t 'The sync stops for this share when more than %s files were removed since the last sync.' "$v")"
        $dry && exit 0
        parity_limit_write "$rel" "$v" ;;
    esac
    ok "Done."
    exit 0 ;;
  *) usage ;;
esac
