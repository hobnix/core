#!/usr/bin/env bash
# The parity sync stops per share (hs share <share> parity limit), leaves skipped folders out, and prints SnapRAID's complaints (#952).
# No root: a fake `snapraid` prints a prepared diff and records that a sync ran.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
export HS_PLAIN=1 HS_LANG=en HS_CALLER=ui
unset HS_GUIDED_TTY
T=$'\t'
export HS_STATE_DIR=$WORK/state HS_SETTINGS_DIR=$WORK/settings HS_LOCK=$WORK/lock HS_LOCK_ADMIN=$WORK/admin
export HS_DETACHED_DIR=$WORK/state/detached HS_RECOVER_DIR=$WORK/state/recovering
export HS_PARITY_SKIP=$WORK/parity-skip HS_PARITY_LIMITS=$WORK/parity-limits HS_SYNC_REFUSED=$WORK/sync-refused
export HS_BULK=$WORK/bulk HS_SPIN_PLAIN=1
mkdir -p "$HS_DETACHED_DIR" "$HS_RECOVER_DIR" "$HS_SETTINGS_DIR" "$HS_BULK/shares/media/downloads" "$HS_BULK/shares/media/series" "$HS_BULK/shares/docs"
echo snapraid > "$WORK/bulk-type"; echo "parity /nonexistent/snapraid.parity" > "$WORK/snapraid.conf"
export HS_BULK_TYPE_FILE=$WORK/bulk-type HS_SNAPRAID_CONF=$WORK/snapraid.conf
mkdir -p "$WORK/bin"
cat > "$WORK/bin/snapraid" <<'FAKE'
#!/usr/bin/env bash
# fake: diff prints $FAKE_DIFF, sync records itself (and fails with $FAKE_SYNC_OUT when FAKE_SYNC_FAIL is set)
for a in "$@"; do
  case "$a" in
    diff) cat "$FAKE_DIFF"; exit 2 ;;
    sync) echo ran >> "$FAKE_RAN"
          if [ -n "${FAKE_SYNC_FAIL:-}" ]; then cat "$FAKE_SYNC_OUT"; exit 1; fi
          echo "Everything OK"; exit 0 ;;
  esac
done
exit 0
FAKE
chmod +x "$WORK/bin/snapraid"
# Git Bash on Windows has no flock: a stand-in that always gets the lock (CI and Linux use the real one)
command -v flock >/dev/null 2>&1 || { printf '#!/bin/sh
exit 0
' > "$WORK/bin/flock"; chmod +x "$WORK/bin/flock"; }
export PATH=$WORK/bin:$PATH FAKE_DIFF=$WORK/diff FAKE_RAN=$WORK/ran FAKE_SYNC_OUT=$WORK/syncout

# diff <share/folder> <count> ...: a SnapRAID diff with that many removed files per folder
mkdiff() {
  local total=0 spec n i
  : > "$FAKE_DIFF"
  while [ $# -gt 0 ]; do
    spec=$1 n=$2; shift 2
    for ((i = 1; i <= n; i++)); do echo "remove $spec/file$i.bin" >> "$FAKE_DIFF"; done
    total=$((total + n))
  done
  printf '\n%d equal\n0 added\n%d removed\n0 updated\n' 5000 "$total" >> "$FAKE_DIFF"
}
sync_() { rc=0; rm -f "$FAKE_RAN"; out=$(timeout 60 bash "$SCRIPTS/bulk-sync.sh" --no-mover "$@" 2>&1 </dev/null) || rc=$?; }
ran() { [ -e "$FAKE_RAN" ]; }

echo "-- under the limit: syncs"
mkdiff shares/media/series 40 shares/docs 3
sync_
check_eq "exit 0" 0 "$rc"
ran && pass "the sync ran" || fail "no sync: $out"
[ ! -s "$HS_SYNC_REFUSED" ] && pass "nothing refused" || fail "refused file written"

echo "-- one share over its limit: stops, prints the table, writes the file"
mkdiff shares/media/downloads 1014 shares/media/series 101 shares/docs 3
sync_
check_eq "exit 1" 1 "$rc"
ran && fail "the sync ran although a share is over its limit" || pass "no sync"
grep -q "over their limit" <<<"$out" && grep -q "shares/media" <<<"$out" && grep -q "downloads" <<<"$out" && pass "the table names share and folder" || fail "table: $out"
grep -q "shares/docs" <<<"$out" && fail "a share under its limit is in the table" || pass "docs (3 removed) is not listed"
grep -q "^shares/media${T}downloads${T}1014${T}100${T}1115$" "$HS_SYNC_REFUSED" && pass "sync-refused: share, folder, removed, limit, share total" || fail "refused file: $(cat "$HS_SYNC_REFUSED")"
out2=$(bash "$SCRIPTS/share-parity.sh" --refused)
[ "$out2" = "$(cat "$HS_SYNC_REFUSED")" ] && pass "hs share --refused prints the file" || fail "--refused: $out2"

echo "-- the percentage raises the limit of a big share"
mkdir -p "$HS_BULK/shares/big"; for i in $(seq 1 30); do : > "$HS_BULK/shares/big/f$i"; done
echo 5 > "$HS_SETTINGS_DIR/syncMaxRemoved"; echo 50 > "$HS_SETTINGS_DIR/syncMaxRemovedPercent"
mkdiff shares/big 20
sync_
check_eq "20 removed of 50 files, limit max(5, 50%)=25: syncs" 0 "$rc"
mkdiff shares/big 40
sync_
check_eq "40 removed of 70 files before (limit 35): stops" 1 "$rc"
rm -f "$HS_SETTINGS_DIR/syncMaxRemoved" "$HS_SETTINGS_DIR/syncMaxRemovedPercent"

echo "-- a skipped folder does not count"
printf 'shares/media\tdownloads\n' > "$HS_PARITY_SKIP"
mkdiff shares/media/downloads 1014 shares/media/series 40
sync_
check_eq "1014 removed in a skipped folder: exit 0" 0 "$rc"
ran && pass "synced" || fail "not synced: $out"
: > "$HS_PARITY_SKIP"

echo "-- limit N, off, default; --force"
printf 'shares/media\t2000\n' > "$HS_PARITY_LIMITS"
mkdiff shares/media/downloads 1500
sync_
check_eq "limit 2000 and 1500 removed: syncs" 0 "$rc"
printf 'shares/media\t10\n' > "$HS_PARITY_LIMITS"
mkdiff shares/media/series 11
sync_
check_eq "limit 10 and 11 removed: stops" 1 "$rc"
sync_ --force
check_eq "--force syncs anyway" 0 "$rc"
ran && pass "ran with --force" || fail "no sync with --force"
[ ! -e "$HS_SYNC_REFUSED" ] && pass "a finished sync clears sync-refused" || fail "sync-refused is still there"
printf 'shares/media\toff\n' > "$HS_PARITY_LIMITS"
mkdiff shares/media/downloads 5000
sync_
check_eq "limit off: syncs" 0 "$rc"
: > "$HS_PARITY_LIMITS"

echo "-- removals only in the summary (no per-file lines) are held to the floor"
printf '\n5000 equal\n0 added\n500 removed\n' > "$FAKE_DIFF"
sync_
check_eq "500 removed, no lines: stops" 1 "$rc"

echo "-- after a failed sync SnapRAID's Unexpected / WARNING lines are printed once each, at most 30"
mkdiff shares/docs 1
{ for i in 1 2 3; do echo "WARNING! You cannot modify files while running"; done
  for i in $(seq 1 45); do echo "Unexpected time change at file '/x/file$i' from 1 to 2."; done; } > "$FAKE_SYNC_OUT"
FAKE_SYNC_FAIL=1 sync_
check_eq "the sync failed" 1 "$rc"
mine=$(sed -n '/What SnapRAID complained about/,$p' <<<"$out")
n=$(grep -c "Unexpected time change" <<<"$mine" || true)
check_eq "30 different lines are listed (1 WARNING + 29 Unexpected)" 29 "$n"
check_eq "a repeated WARNING is listed once" 1 "$(grep -c "cannot modify files while running" <<<"$mine" || true)"
[ "$(grep -c "cannot modify files while running" <<<"$mine" || true)" -le 1 ] && pass "a repeated WARNING is not repeated" || fail "WARNING repeated"
grep -q "more different lines" <<<"$out" && pass "says how many more there are" || fail "no 'and more' line"

finish
