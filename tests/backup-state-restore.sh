#!/usr/bin/env bash
# The state of an extension service is the service's: restic never writes it in place (however the include is spelled), a restore puts it back only
# through scripts/lib/state_put.py (no link, FIFO or huge file the service made is followed or read), and the installer restore does the same.
# Uses a REAL restic in a temporary repository (skipped without restic); no root.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
export HS_PLAIN=1 HS_LANG=en HS_BACKUP_NO_MOUNT=1
unset HS_CALLER HS_BACKUP_YES
SP=$SCRIPTS/lib/state_put.py

echo "-- state_put.py: a FIFO or a huge file the service made is never read, a link is never followed"
T=$WORK/top; mkdir -p "$T/sub"; echo new > "$WORK/src"; echo victim > "$WORK/victim"
mkfifo "$T/f"
rc=0; timeout 20 python3 -I "$SP" same "$WORK/src" "$T" f || rc=$?
check_eq "same: a FIFO is different, and it does not hang" 1 "$rc"
rc=0; timeout 20 python3 -I "$SP" put "$WORK/src" "$T" f s1 || rc=$?
check_eq "put over a FIFO does not hang" 0 "$rc"
check_eq "and the file is the new one, the FIFO moved aside" "new yes" "$(cat "$T/f") $([ -p "$T/f.before-restore-s1" ] && echo yes || echo no)"
truncate -s 1T "$T/big" 2>/dev/null || : > "$T/big"
rc=0; timeout 20 python3 -I "$SP" same "$WORK/src" "$T" big || rc=$?
check_eq "same: a file of another size is different without being read" 1 "$rc"
rc=0; timeout 60 python3 -I "$SP" put "$WORK/src" "$T" big s2 || rc=$?
check_eq "put over a huge file does not copy it" "0 new" "$rc $(cat "$T/big")"
ln -s "$WORK/victim" "$T/l"; ln -s "$WORK" "$T/sub/up"
python3 -I "$SP" put "$WORK/src" "$T" l s3 && python3 -I "$SP" put "$WORK/src" "$T" sub/up/x s4 2>/dev/null; rc=$?
check_eq "a link at the file is replaced, one in the way of a folder is refused (exit 2)" "victim 2" "$(cat "$WORK/victim") $rc"
check "nothing was written through the folder link" test ! -e "$WORK/x"

echo "-- the installer restore (scripts/lib/restore.sh) puts service state back through state_put.py, never with cp"
. "$SCRIPTS/lib/ui.sh"
. "$SCRIPTS/lib/restore.sh"
D=$WORK/fetched; R2=$WORK/newroot
mkdir -p "$D/var/lib/private/hs-ext/svc/sub" "$D/var/lib/private/hs-ext/BadName" "$D/var/lib/hs" "$R2"
echo state > "$D/var/lib/private/hs-ext/svc/sub/f"; echo bad > "$D/var/lib/private/hs-ext/BadName/f"; echo cfg > "$D/var/lib/hs/setting"
check_eq "restore_files lists the service state" "/var/lib/private/hs-ext/svc/sub/f" "$(restore_files "$D" | grep hs-ext/svc)"
restore_apply "$D" "$R2" >/dev/null 2>&1
check_eq "the state is below /var/lib/hs-ext of the new system, closed (0700)" "state 700" "$(cat "$R2/var/lib/hs-ext/svc/sub/f" 2>/dev/null) $(stat -c %a "$R2/var/lib/hs-ext/svc/sub" 2>/dev/null)"
check "a name that is no package name is skipped, not copied" test ! -e "$R2/var/lib/hs-ext/BadName" -a ! -e "$R2/var/lib/private/hs-ext/BadName"
check_eq "the other settings are still copied" "cfg" "$(cat "$R2/var/lib/hs/setting" 2>/dev/null)"

echo "-- restic never writes service state in place (real restic)"
if ! have restic; then skip "restic missing"; finish; exit 0; fi
ST=$WORK/state PRIV=$WORK/priv EXTD=$WORK/ext REPO=$WORK/repo
mkdir -p "$ST" "$PRIV/hs-ext/svc" "$EXTD" "$WORK/other/hs-ext"
echo live-pass > "$ST/restic-password"
export HS_STATE_DIR=$ST HS_PRIVATE_DIR=$PRIV HS_EXT_STATE_DIR=$EXTD HS_BACKUP_REPO=$REPO
export RESTIC_PASSWORD=live-pass
restic -r "$REPO" --password-file "$ST/restic-password" init >/dev/null 2>&1 || { fail "restic init failed"; finish; exit 1; }
echo from-snapshot > "$PRIV/hs-ext/svc/f"; echo plain > "$ST/plain"
restic -r "$REPO" --password-file "$ST/restic-password" backup --tag host "$PRIV/hs-ext" "$ST/plain" >/dev/null 2>&1 || { fail "restic backup failed"; finish; exit 1; }
b() { bash "$SCRIPTS/backup.sh" "$@" </dev/null 2>&1; }
for spec in "hs-ext" "$PRIV/hs-ext" "$PRIV/hs-e*" "$PRIV/hs-ext/**" "$PRIV/hs-ex[t]" "hs-ext/svc/f" "$PRIV" "$WORK" "/" "$PRIV/hs-ext/../hs-ext" "$PRIV/hs-ext/"; do
  echo live-edit > "$PRIV/hs-ext/svc/f"
  out=$(b restore latest "$spec" --tag host --to / || true)
  check_eq "restore latest '$spec' --to /: the live service file is untouched" "live-edit" "$(cat "$PRIV/hs-ext/svc/f")"
  case $out in *"Not restored"*) pass "...and it was refused, not left to restic" ;; *) fail "'$spec' was not refused: $(echo "$out" | tail -2)" ;; esac
done
echo live-edit > "$PRIV/hs-ext/svc/f"
for to in // /. /./; do
  out=$(b restore latest "$PRIV/hs-ext" --tag host --to "$to" || true)
  check_eq "--to $to: the live service file is untouched" "live-edit" "$(cat "$PRIV/hs-ext/svc/f")"
  case $out in *"Not restored"*) pass "...and it was refused" ;; *) fail "--to $to was not refused: $(echo "$out" | tail -2)" ;; esac
done
echo "-- what reaches restic is checked: the snapshot is latest or a hex id (no <snapshot>:<subfolder>), the path is exact for every --to"
mkdir -p "$WORK/out"
echo live-edit > "$PRIV/hs-ext/svc/f"
for snap in "latest:/var/lib" "latest:/" "abc:def" "-x" "ABCDEF12" "" "latest/" "deadbee" "latest:$WORK" "0123456789abcdef:/"; do
  out=$(b restore "$snap" "$PRIV/hs-ext/svc" --tag host --to / || true)
  case $out in *"is not a snapshot"*|*usage*|*Usage*) pass "restore '$snap' is refused" ;; *) fail "restore '$snap' was not refused: $(echo "$out" | tail -2)" ;; esac
  check_eq "...the live service file is untouched" "live-edit" "$(cat "$PRIV/hs-ext/svc/f")"
  out=$(b config restore "$snap" --with-state --yes --dry-run || true)
  case $out in *"is not a snapshot"*|*usage*|*Usage*|*"not a"*) pass "config restore '$snap' is refused" ;; *) fail "config restore '$snap' was not refused: $(echo "$out" | tail -2)" ;; esac
done
out=$(b restore latest svc --tag host --to "$WORK/out" || true)
case $out in *"not a full path"*) pass "a relative path is refused for any --to" ;; *) fail "relative path accepted: $(echo "$out" | tail -2)" ;; esac
out=$(b restore latest "$PRIV/hs-e*" --tag host --to "$WORK/out" || true)
case $out in *"pattern or a dot part"*) pass "a glob is refused for any --to" ;; *) fail "glob accepted: $(echo "$out" | tail -2)" ;; esac
out=$(b restore latest "$ST/plain" --tag 'x;y' --to "$WORK/out" || true)
case $out in *"not a snapshot tag"*) pass "an odd tag is refused" ;; *) fail "odd tag accepted: $(echo "$out" | tail -2)" ;; esac
ID=$(restic -r "$REPO" --password-file "$ST/restic-password" snapshots --json | python3 -I -c 'import json,sys; print(json.load(sys.stdin)[0]["short_id"])')
out=$(b restore "$ID" "$ST/plain" --tag host --to "$WORK/out" || true)
check_eq "a real snapshot id works" "plain" "$(cat "$WORK/out$ST/plain" 2>/dev/null)"
echo "-- state_put copies in chunks (a big source is not held in memory)"
head -c 5000000 /dev/zero > "$WORK/bigsrc"
python3 -I "$SP" put "$WORK/bigsrc" "$T" bigcopy s9 && check_eq "the copy is complete" "5000000" "$(stat -c %s "$T/bigcopy")"

echo plain-live > "$ST/plain"
out=$(b restore latest "$ST/plain" --tag host --to / || true)
check_eq "a file that is not service state is still restored in place" "plain" "$(cat "$ST/plain")"

finish
