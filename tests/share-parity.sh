#!/usr/bin/env bash
# hs share <share> parity skip|keep|limit (scripts/share-parity.sh), the plan and job of hs sys shares plan|start, the schema keys and the web allowlist (#952).
# No root: a stand-in for bulk-mount.sh, a fake systemd-run, files in a temp folder.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
export HS_PLAIN=1 HS_LANG=en
unset HS_CALLER HS_GUIDED_TTY
T=$'\t'
export HS_STATE_DIR=$WORK/state HS_SETTINGS_DIR=$WORK/settings HS_LOCK=$WORK/lock
export HS_PARITY_SKIP=$WORK/parity-skip HS_PARITY_LIMITS=$WORK/parity-limits HS_SYNC_REFUSED=$WORK/sync-refused
export HS_BULK=$WORK/bulk HS_BULK_TYPE_FILE=$WORK/bulk-type
mkdir -p "$HS_BULK/shares/media/downloads/a" "$HS_BULK/shares/media/series" "$HS_SETTINGS_DIR" "$WORK/bin"
echo snapraid > "$WORK/bulk-type"
for i in 1 2 3; do : > "$HS_BULK/shares/media/downloads/a/f$i"; done
: > "$HS_BULK/shares/media/series/s1"
printf '#!/usr/bin/env bash\necho x >> "%s/mounted"\n' "$WORK" > "$WORK/bulk-mount"; chmod +x "$WORK/bulk-mount"
export HS_BULK_MOUNT=$WORK/bulk-mount
command -v flock >/dev/null 2>&1 || { printf '#!/bin/sh\nexit 0\n' > "$WORK/bin/flock"; chmod +x "$WORK/bin/flock"; }
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/jobcalls"\n' "$WORK" > "$WORK/bin/systemd-run"; chmod +x "$WORK/bin/systemd-run"
export PATH=$WORK/bin:$PATH
P="bash $SCRIPTS/share-parity.sh"

echo "-- state and status of a fresh share"
out=$($P --state media)
check_eq "default limit, no skip" "limit${T}default${T}-
default${T}100${T}1" "$out"
out=$($P media parity 2>&1)
grep -q "No folder is left out" <<<"$out" && grep -q "Limit: 100 removed files" <<<"$out" && pass "status: nothing skipped, limit 100" || fail "status: $out"

echo "-- skip: plan, warning, typing the folder name"
out=$($P media parity skip downloads --dry-run 2>&1)
grep -q "(3 files)" <<<"$out" && grep -q "lose their protection" <<<"$out" && pass "the plan shows the file count and the warning" || fail "plan: $out"
[ ! -s "$HS_PARITY_SKIP" ] && pass "a dry run changes nothing" || fail "dry run wrote the file"
rc=0; out=$(echo wrong | $P media parity skip downloads 2>&1) || rc=$?
[ "$rc" -ne 0 ] && [ ! -s "$HS_PARITY_SKIP" ] && pass "a wrong name changes nothing" || fail "wrong name accepted: $out"
rc=0; out=$(echo downloads | $P media parity skip downloads 2>&1) || rc=$?
check_eq "typing the folder name works" 0 "$rc"
check_eq "stored as <rel><TAB><folder>" "shares/media${T}downloads" "$(cat "$HS_PARITY_SKIP")"
[ -e "$WORK/mounted" ] && pass "the SnapRAID config is written again" || fail "bulk-mount was not called"
check_eq "--state lists it" "skip${T}downloads" "$($P --state media | grep '^skip')"
rc=0; $P media parity skip ../etc --yes >/dev/null 2>&1 || rc=$?
[ "$rc" -ne 0 ] && pass "a path with .. is refused" || fail ".. accepted"
rc=0; $P media parity skip nothere --yes >/dev/null 2>&1 || rc=$?
[ "$rc" -ne 0 ] && pass "a folder that does not exist is refused" || fail "missing folder accepted"
rc=0; $P media parity skip 'a*' --yes >/dev/null 2>&1 || rc=$?
[ "$rc" -ne 0 ] && pass "a wildcard is refused" || fail "wildcard accepted"

echo "-- bulk-mount writes the exclude line"
# the real script needs disks; check the generating loop only
grep -q 'echo "exclude /$prel/$pfolder/"' "$SCRIPTS/bulk-mount.sh" && pass "bulk-mount.sh writes exclude /<rel>/<folder>/" || fail "no exclude loop"

echo "-- keep"
$P media parity keep downloads >/dev/null 2>&1
[ ! -s "$HS_PARITY_SKIP" ] && pass "keep removes the line" || fail "keep: $(cat "$HS_PARITY_SKIP")"

echo "-- limit"
$P media parity limit 250 >/dev/null 2>&1
check_eq "a number is stored" "shares/media${T}250" "$(cat "$HS_PARITY_LIMITS")"
check_eq "--state says custom" "limit${T}custom${T}250" "$($P --state media | head -n1)"
rc=0; out=$(echo nope | $P media parity limit off 2>&1) || rc=$?
[ "$rc" -ne 0 ] && grep -q "shares/media${T}250" "$HS_PARITY_LIMITS" && pass "off needs the share name" || fail "off without name: $out"
echo media | $P media parity limit off >/dev/null 2>&1
check_eq "off is stored" "shares/media${T}off" "$(cat "$HS_PARITY_LIMITS")"
check_eq "--state says off" "limit${T}off${T}-" "$($P --state media | head -n1)"
$P media parity limit default >/dev/null 2>&1
[ ! -s "$HS_PARITY_LIMITS" ] && pass "default removes the line" || fail "default: $(cat "$HS_PARITY_LIMITS")"
rc=0; $P media parity limit lots >/dev/null 2>&1 || rc=$?
[ "$rc" -ne 0 ] && pass "limit takes a number, off or default" || fail "limit lots accepted"
echo 40 > "$HS_SETTINGS_DIR/syncMaxRemoved"; echo 10 > "$HS_SETTINGS_DIR/syncMaxRemovedPercent"
check_eq "the settings change the default" "default${T}40${T}10" "$($P --state media | sed -n 2p)"
rm -f "$HS_SETTINGS_DIR"/*

echo "-- other layouts and unknown shares"
rc=0; out=$($P nosuch parity 2>&1) || rc=$?
[ "$rc" -ne 0 ] && grep -q "No share called" <<<"$out" && pass "unknown share" || fail "unknown share: $out"
echo zfs > "$WORK/bulk-type"
rc=0; out=$($P media parity 2>&1) || rc=$?
[ "$rc" -ne 0 ] && grep -q "only on the snapraid layout" <<<"$out" && pass "ZFS: refused with the reason" || fail "zfs: $out"
echo snapraid > "$WORK/bulk-type"

echo "-- sys bulk sync-refused"
[ -z "$($P --refused)" ] && pass "empty when nothing was refused" || fail "refused not empty"
printf 'shares/media\tdownloads\t12\t10\t15\n' > "$HS_SYNC_REFUSED"
check_eq "prints the file" "shares/media${T}downloads${T}12${T}10${T}15" "$($P --refused)"

echo "-- hs sys shares plan|start (share-change.sh)"
C="bash $SCRIPTS/share-change.sh"
export HS_SHARE_PARITY=$SCRIPTS/share-parity.sh
out=$($C plan media parity-skip --folder downloads)
check_match "skip plan: ok, heading, danger" "^status${T}ok" "$out"
grep -q "^danger${T}" <<<"$out" && grep -q "^confirm_name${T}downloads$" <<<"$out" && pass "the folder name is the confirm word" || fail "confirm_name: $out"
rc=0; out=$($C start media parity-skip --folder downloads 2>&1) || rc=$?
[ "$rc" -ne 0 ] && grep -q "type the name to confirm: downloads" <<<"$out" && pass "start without the name is refused" || fail "start: $out"
out=$($C start media parity-skip --folder downloads --confirm downloads 2>&1)
grep -q "^status${T}started" <<<"$out" && pass "start with the folder name runs a job" || fail "start: $out"
out=$($C plan media parity-limit --to 50)
grep -q "^danger" <<<"$out" && fail "a number needs no confirmation" || pass "limit N: no danger line"
out=$($C plan media parity-limit --to off)
grep -q "^confirm_name${T}media$" <<<"$out" && pass "limit off: the share name is typed" || fail "limit off: $out"
rc=0; $C plan media parity-limit --to lots >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] && pass "a bad limit is refused" || fail "bad limit rc=$rc"
rc=0; out=$($C plan media parity-skip 2>&1) || rc=$?
[ "$rc" -eq 2 ] && grep -q "^needs${T}folder" <<<"$out" && pass "skip without a folder: needs folder" || fail "needs: rc=$rc $out"

echo "-- sys system plan sync --force"
echo snapraid > "$WORK/bulk-type"
out=$(HS_BULK_TYPE_FILE=$WORK/bulk-type bash "$SCRIPTS/system-change.sh" plan sync --force)
grep -q "^warn${T}Forced" <<<"$out" && grep -q -- "bulk-sync.sh --force" <<<"$out" && pass "forced sync: warning and --force in the command" || fail "forced plan: $out"
rc=0; HS_BULK_TYPE_FILE=$WORK/bulk-type bash "$SCRIPTS/system-change.sh" plan update --force >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] && pass "--force is only for sync" || fail "--force on update rc=$rc"

echo "-- schema keys, registry, web allowlist"
grep -q '^  syncMaxRemoved = 100;' "$ROOT/config/defaults.nix" && grep -q '^  syncMaxRemovedPercent = 1;' "$ROOT/config/defaults.nix" && pass "defaults.nix has both keys (generated)" || fail "defaults.nix"
grep -q "^sys${T}sys share parity state <share>${T}share-parity.sh" "$SCRIPTS/lib/registry.tsv" && grep -q "^sys${T}sys bulk sync-refused${T}share-parity.sh" "$SCRIPTS/lib/registry.tsv" && grep -q "^user${T}share <share> parity${T}share-parity.sh" "$SCRIPTS/lib/registry.tsv" && pass "registry rows" || fail "registry rows"
grep -q '("share", "parity", "state")' "$SCRIPTS/web-serve.py" && grep -q '("bulk", "sync-refused")' "$SCRIPTS/web-serve.py" && grep -q 'parity-(skip|keep)' "$SCRIPTS/web-serve.py" && grep -q 'parity-limit' "$SCRIPTS/web-serve.py" && pass "web-serve.py allows the reads and the changes" || fail "web-serve.py"

finish
