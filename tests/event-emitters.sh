#!/usr/bin/env bash
# The event kinds the scripts emit (docs/events.md, #617 b): backup.ok / backup.failed (the run and each part of it), unlock.needed / unlock.done,
# lock.done. A fake restic, zfs, umount and cryptsetup; no root, no real disk. update.started / update.stopped are in tests/machine-toml.sh.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
export HS_PLAIN=1 HS_LANG=en HS_CALLER=test HS_EVENT_NOROOT=1 HS_STATE_DB=$WORK/ev.db
export HS_STATE_DIR=$WORK/state HS_RUN_DIR=$WORK/run
BIN=$WORK/bin; mkdir -p "$BIN" "$HS_STATE_DIR" "$HS_RUN_DIR" "$WORK/mnt/restic"
export PATH="$BIN:$PATH"
evs() { python3 "$SCRIPTS/state-db.py" event-list 100 | cut -f3-6 | tr '\t' ' ' | sort; }   # source kind subject level
reset() { rm -f "$HS_STATE_DB"; }

echo "-- backup: the run and its parts"
export HS_BACKUP_NO_MOUNT=1 HS_BACKUP_MOUNT=$WORK/mnt HS_BACKUP_CACHE=$WORK/cache
echo x > "$WORK/mnt/restic/config"; echo pw > "$HS_STATE_DIR/restic-password"
printf '#!/bin/sh\nexit 0\n' > "$BIN/restic"; chmod +x "$BIN/restic"
reset
check "a backup without errors" bash "$SCRIPTS/backup.sh" now
check_out "backup.ok for the host part" "backup ok host info" evs
check_out "backup.ok for the whole run" "backup ok backup info" evs
check_eq "and no failure" 0 "$(evs | grep -c 'backup failed')"
reset
printf '#!/bin/sh\ncase "$*" in *"--tag host"*) exit 1 ;; esac\nexit 0\n' > "$BIN/restic"
check "a backup with an error exits 1" bash -c "! bash $SCRIPTS/backup.sh now"
check_out "backup.failed for the host part" "backup failed host error" evs
check_out "backup.failed for the whole run" "backup failed backup error" evs
check_eq "and the host part is not reported as ok" 0 "$(evs | grep -c 'backup ok host')"
rm -f "$BIN/restic"

echo "-- unlock: needed at boot, done after the passphrase"
printf 'uuid-1\n' > "$HS_STATE_DIR/vault-uuid"
reset
check "a closed vault at boot" bash "$SCRIPTS/unlock.sh" --boot
check_out "unlock.needed" "unlock needed storage warn" evs
check "the marker is there" test -e "$HS_RUN_DIR/storage-locked"
rm -f "$HS_STATE_DIR/vault-uuid" "$HS_RUN_DIR/storage-locked"
cat > "$BIN/zfs" <<'FAKE'
#!/usr/bin/env bash
case "$1" in
  list) [ -e "$HS_RUN_DIR/zfs-open" ] || printf 'tank\ttank\tunavailable\n' ;;
  load-key) cat >/dev/null; : > "$HS_RUN_DIR/zfs-open" ;;
esac
exit 0
FAKE
chmod +x "$BIN/zfs"
reset
HS_DISK_PASSPHRASE=secret check "an encrypted pool is unlocked" bash "$SCRIPTS/unlock.sh"
check_out "unlock.done" "unlock done storage info" evs
rm -f "$BIN/zfs"

echo "-- lock: closing the vault"
printf 'uuid-1\n' > "$HS_STATE_DIR/vault-uuid"
printf '#!/bin/sh\nexit 0\n' > "$BIN/umount"; cp "$BIN/umount" "$BIN/cryptsetup"; chmod +x "$BIN/umount" "$BIN/cryptsetup"
reset
HS_VAULT_OPEN=1 HS_VAULT_DIR=$WORK/vault check "hs vault close --yes" bash "$SCRIPTS/vault.sh" close --yes
check_out "lock.done" "lock done storage info" evs
finish
