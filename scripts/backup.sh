#!/usr/bin/env bash
# help: back up shares, chosen containers, the domain controller and the host config with restic to the disk labelled "backup"
# help.de: sichert Freigaben, ausgewählte Container, den Domänencontroller und die Server-Einstellungen mit restic auf die Platte mit dem Etikett "backup"
# args: [--state | --shares | --snapshots | status | now | list | find <name> | restore <snapshot|latest> <path> | restore ct <name> [--recipe <app>] | config [restore [<snapshot|latest>] [--with-state] [--from-disk <device>] [--with-samba]] | browse [--off] | verify | drill [N] | drill ct [<name>] | report | offsite set <repo>|--kind s3|rest|sftp|folder ...|now|off|migrate | restore|find|list|drill ... --repo offsite | init [<device>] | <share> on|off | ct <name> on|off] [--dry-run]
set -euo pipefail
. "$(dirname "$0")/lib/ui.sh"
. "$(dirname "$0")/lib/dc.sh"
. "$(dirname "$0")/lib/bulkpath.sh"   # disks_root: the pool disks are mounted under /var/lib/hs, which is a host path
. "$(dirname "$0")/lib/secret.sh"   # the password and the off-site keys may live in the vault
. "$(dirname "$0")/lib/admin.sh"
adm="$(admin_user)"
. "$(dirname "$0")/lib/backup-dump.sh"   # dump_cmds: the commands of a container's dump descriptor

usage() {
  while IFS= read -r _l; do say "$_l"; done <<'EOF'
usage: hs backup [status]                    what is in the backup, last run, space
       hs backup now [--dry-run]             back up right now (also runs every night)
       hs backup <share> on|off              include a share in the backup or leave it out
       hs backup ct <name> on|off            same for a container (needs to be running) or a virtual machine
                                             (the whole machine as one export file every night, needs that much
                                             free space in /var/tmp or HS_VM_EXPORT_DIR)
       hs backup ct <name> paths             which parts of the instance are in the backup (in and out, with sizes)
       hs backup ct <name> include <path>    back up only chosen parts of the instance: add a path inside it
       hs backup ct <name> exclude <glob>    leave a part out (restic pattern, a leading / is the instance root)
       hs backup ct <name> reset [<path>]    forget one rule, or all of them: the whole instance again
       hs backup list                        snapshots (id, time, tag, size)
       hs backup find <name>                 which snapshots contain a file name
       hs backup restore <snapshot|latest> <path> [--tag T] [--to DIR] [--keep-owner]
                                             restore one file or folder, by default
                                             into /bulk/shares/restored (never over the live copy), owned by the admin account;
                                             --keep-owner keeps the owners of the snapshot, --to / (in place) always does
       hs backup config                      the host snapshots and which settings files each holds
       hs backup config restore [<snapshot|latest>] [--with-state] [--dry-run]
       hs backup config restore --from-disk <device> [<snapshot|latest>] [--with-samba] [--dry-run]
                                             put machine.toml and machine.nix of a host snapshot back on this running
                                             server (plan first, you type the file name, the old file is kept as
                                             <file>.before-restore-<time>); --with-state also /var/lib/hs
                                             --from-disk is for a fresh install: only the backup disk and its passphrase
                                             (typed, never an argument) are needed; the disk is mounted read-only,
                                             /var/lib/hs comes back, the SSH host keys after you type their name,
                                             the Samba secrets only with --with-samba
       hs backup browse [--off]              show the whole backup read-only as share "backup-browse"
       hs backup verify                      check part of the stored data
       hs backup restore ct <name> [--recipe <app>] [--dry-run]
                                             a partial container (only some parts in the backup): run its recipe again, then put
                                             the backed-up parts back while the app is stopped (plan first, you type the name)
       hs backup prune [--dry-run]         give space back now: delete leftovers of a run that ran out of space, apply the
                                             retention (7 daily, 4 weekly, 6 monthly) and prune
       hs backup drill [N]                   restore N random files (default 5) into a temp folder and compare them
       hs backup drill ct [<name>]           restore a container (the one drilled longest ago, smallest first) into a
                                             throwaway instance without a network, boot it, delete it; also checks the
                                             domain controller backup file and the export file of one virtual machine
       hs backup report [--dry-run]          the report of the restore drills as a push message (it goes out
                                             every month by itself, on the 25th)
       hs backup offsite set [<repo> | --kind s3|rest|sftp|folder ...]
                                             also copy every backup to a second repository. By kind it asks the fields
                                             (s3: --endpoint --bucket [--prefix], keys asked; rest: --url [--user], password
                                             asked; sftp: --host --user [--port] --path; folder: --path) and writes the restic
                                             address itself; a typed <repo> (b2:bucket:path ...) stays possible. Secrets are asked
                                             for or read from stdin, never taken as arguments. offsite now / off / migrate
       hs backup restore|find|list|drill --repo offsite
                                             the same on the off-site repository instead of the backup disk
       hs backup init [<device>] [--dry-run] FORMAT a disk as the backup disk (erases it) and create the repository;
                                             without a device the free disks are listed to pick from

  A share is in the backup once you switch it on (new ones start out; machine.toml
  backupNewShares = true; changes that). The domain controller and the
  host files (machine.toml, /var/lib/hs, the domain join, SSH host keys) are always included.
EOF
  exit 1
}

die() { fail "$@" >&2; }   # the same red line as everywhere, on stderr

# Paths and overrides (the HS_* variables exist for tests)
STATE=${HS_STATE_DIR:-/var/lib/hs}
MNT=${HS_BACKUP_MOUNT:-/mnt/backup}
REPO=${HS_BACKUP_REPO:-$MNT/restic}
DEV=${HS_BACKUP_DEV:-/dev/disk/by-label/backup}
BULK=${HS_BULK:-/bulk}
FAST=${HS_FAST:-/fast}
PASSFILE=$STATE/restic-password
VAULT_SECRETS=${HS_VAULT_DIR:-/var/lib/hs-vault}/secrets
OFF=$STATE/backup-off            # shares left out, one per line
ON=$STATE/backup-on              # shares included on purpose, one per line (only used while new shares start off)
# machine.toml `backupNewShares` (written to /etc/hs/backup-new-shares by configuration.nix):
# "off" = a share is in the backup only when it was switched on; "on" = in unless switched off.
# Without the file (a server that was not rebuilt yet) nothing changes: "on".
. "$(dirname "$0")/lib/sharepath.sh"
. "$(dirname "$0")/lib/backup-rules.sh"   # rule file per instance: which parts of it are backed up (hs backup ct <ct> paths)
. "$(dirname "$0")/lib/event.sh"   # event_emit: backup.ok, backup.failed, backup.report (best effort)
. "$(dirname "$0")/lib/setting.sh"   # backupNewShares is a runtime setting now (true|false); the old /etc/hs file (on|off) is its fallback
NEW_SHARES=${HS_BACKUP_NEW_SHARES:-$(case "$(setting_get backupNewShares 2>/dev/null)" in false|off) echo off ;; *) echo on ;; esac)}
CTS=$STATE/backup-instances      # containers included, one per line
DUMPS=$STATE/backup-dump         # one file per container: the command that writes its database dump
OFFSITE=$STATE/backup-offsite.repo          # second repository: the restic address (may carry a REST password), 0600, restic --repository-file
OFFSITE_OLD=$STATE/backup-offsite           # the address before 0.7: moved to $OFFSITE once
OFFSITE_PASS=$STATE/restic-offsite-password # its own password (absent: an older off-site repository that shares the backup disk's)
OFFSITE_CRED=$STATE/backup-offsite.credentials   # S3 keys as an AWS credentials file; restic reads it by path (AWS_SHARED_CREDENTIALS_FILE)
OFFSITE_ENV=$STATE/backup-offsite.env       # old way: KEY=VALUE lines for restic's environment; parsed, never sourced, until migrated
RESULT=$STATE/backup.state       # read by hs health
DC=$(dc_name)
INCUS_ROOT=${HS_INCUS_ROOT:-/var/lib/incus/storage-pools/default/containers}
BROWSE=/mnt/backup-browse
OFFDEV=${HS_BACKUP_OFFSITE_DEV:-/dev/disk/by-label/backup-offsite}   # the rotating off-site disk (step 14, D18): a folder repository on it
OFFMNT=${HS_BACKUP_OFFSITE_MOUNT:-/mnt/backup-offsite}                # mounted only while a command needs it
EXPIRY_NAME=offline-backup-disk
export RESTIC_CACHE_DIR=${HS_BACKUP_CACHE:-/var/cache/restic}

dry=false
want_off=false   # --repo offsite: every restic call of this command goes to the off-site repository
machine=false    # offsite set --machine: plain key<TAB>value lines for the web interface
args=()
prev=""
for a in "$@"; do
  if [ "$prev" = --repo ]; then
    prev=""
    case "$a" in offsite) want_off=true ;; local) ;; *) usage ;; esac
    continue
  fi
  case "$a" in
    --repo) prev=--repo ;;
    --machine) machine=true ;;
    --dry-run) dry=true ;;
    --yes)     export HS_BACKUP_YES=1 ;;   # init: the typed confirmation was asked before (the interface's review)
    -h|--help) usage ;;
    *) args+=("$a") ;;
  esac
done
[ -z "$prev" ] || usage
set -- "${args[@]+"${args[@]}"}"
cmd=${1:-status}
[ $# -gt 0 ] && shift

# --from-disk (config restore on a fresh install): the typed passphrase is in a private temp file and the disk is read-only, so no lock is taken
R_PASSFILE=$PASSFILE
R_EXTRA=()
R() {
  if $want_off; then R_off "$@"; else restic -r "$REPO" --password-file "$R_PASSFILE" "${R_EXTRA[@]}" "$@"; fi
}

# Remove locks a dead run left behind. `restic unlock` only removes a lock whose process is gone, and a reused PID (or a
# reboot) keeps it for days ("already locked by PID ... 85h ago"); when no restic runs on this host any more nothing can
# hold a lock, so the rest goes too. Callers hold the backup flock.
clear_locks() {
  R unlock >/dev/null 2>&1 || true
  if R list locks 2>/dev/null | grep -q . && ! pgrep -x restic >/dev/null 2>&1; then
    R unlock --remove-all >/dev/null 2>&1 || true
  fi
}
# Is the backup set up? ok | locked (the password is in the vault and the vault is closed) | missing.
# A dangling link must never read as "not set up".
pass_state() { secret_state "$PASSFILE"; }
set_up() { [ "$(pass_state)" != missing ]; }

# ── The backup disk: mounted only while something needs it ──
mounted_by_us=false
off_mounted=false
cleanup() {
  if declare -F drill_cleanup >/dev/null; then drill_cleanup || true; fi   # the throwaway instance of `drill ct`
  if $mounted_by_us; then
    sync
    umount "$MNT" 2>/dev/null || warn "$(t 'Could not unmount %s (still in use)' "$MNT")" >&2
  fi
  if $off_mounted; then
    sync
    umount "$OFFMNT" 2>/dev/null || warn "$(t 'Could not unmount %s (still in use)' "$OFFMNT")" >&2
  fi
}
trap cleanup EXIT

mount_disk() {
  [ -z "${HS_BACKUP_NO_MOUNT:-}" ] || return 0
  mountpoint -q "$MNT" && return 0
  [ -b "$DEV" ] || die "Backup disk not found (no disk with the label 'backup'). Plug it in, or set it up with: hs backup init <device>"
  mkdir -p "$MNT"
  mount -o noatime "$DEV" "$MNT"
  mounted_by_us=true
}

need_repo() {
  if $want_off; then offsite_ready; return; fi
  [ "$(pass_state)" != locked ] || secret_locked_exit
  [ -f "$PASSFILE" ] || die "Not set up yet. Run: hs backup init <device>"
  mount_disk
  [ -f "$REPO/config" ] || die "$(t 'No backup repository in %s. Run: hs backup init <device>' "$REPO")"
}

# ── What is included ──
# Share folders: "kind name path" per line, for /bulk and /fast (shares, sensitive); path is the folder (lib/sharepath.sh share_dir)
share_names() {
  local tier kind root
  for tier in $(share_tiers); do
    root=$(share_root "$tier")
    for kind in shares sensitive; do
      [ -d "$root/$kind" ] || continue
      find "$root/$kind" -mindepth 1 -maxdepth 1 -type d ! -name 'lost+found' -printf "$kind %f $root/$kind/%f\n" | sort -k2
    done
  done
}
# The first time the default is "off", the shares that are in the backup today are written to
# the "on" list, so switching the default does not silently drop anything; shares that appear
# later start off. (Not writable, e.g. without root: the old rule stays in effect.)
migrate_on() {
  [ -z "${migrated:-}" ] || return 0
  migrated=1
  [ ! -f "$ON" ] || return 0
  local kind name tmp="$ON.new"
  { mkdir -p "$STATE" && : > "$tmp"; } 2>/dev/null || return 0
  while read -r kind name _; do
    [ -n "$name" ] || continue
    grep -qxF "$name" "$OFF" 2>/dev/null || printf '%s
' "$name" >> "$tmp"
  done < <(share_names)
  sort -u "$tmp" > "$ON" && rm -f "$tmp"
}
is_off() {
  if [ "$NEW_SHARES" = off ]; then
    migrate_on
    if [ -f "$ON" ]; then grep -qxF "$1" "$ON" && return 1; return 0; fi
  fi
  [ -f "$OFF" ] && grep -qxF "$1" "$OFF"
}
is_ct_on() { [ -f "$CTS" ] && grep -qxF "$1" "$CTS"; }

set_line() {  # set_line <file> <line> add|remove
  local f=$1 line=$2 mode=$3 tmp
  mkdir -p "$(dirname "$f")"; touch "$f"
  tmp=$(grep -vxF "$line" "$f" || true)
  if [ "$mode" = add ]; then tmp+=$'\n'"$line"; fi
  printf '%s\n' "$tmp" | sed '/^$/d' | sort -u > "$f"
}

cmd_toggle_share() {
  local name=$1 mode=$2 found
  found=$(share_names | awk -v n="$name" '$2 == n')
  [ -n "$found" ] || die "$(t 'No share called %s under %s or %s' "$name" "$BULK/shares" "$BULK/sensitive")"
  case "$mode" in
    on)  [ "$NEW_SHARES" != off ] || migrate_on
         set_line "$OFF" "$name" remove; [ "$NEW_SHARES" != off ] || set_line "$ON" "$name" add
         ok "$(t '%s: included in the backup' "$name")" ;;
    off) [ "$NEW_SHARES" != off ] || migrate_on
         set_line "$OFF" "$name" add;    [ "$NEW_SHARES" != off ] || set_line "$ON" "$name" remove
         ok "$(t '%s: left out of the backup' "$name")" ;;
    *) usage ;;
  esac
}

cmd_toggle_ct() {
  local name=$1 mode=$2
  incus info "$name" >/dev/null 2>&1 </dev/null || die "$(t 'No instance called %s' "$name")"
  case "$mode" in
    on)  if [ "$name" = "$DC" ]; then
           ok "$(t '%s: the domain controller is always in the backup, as samba backup file (the machine itself is not exported)' "$name")"
           return 0
         fi
         set_line "$CTS" "$name" add
         if [ "$(ct_kind "$name")" = virtual-machine ]; then
           ok "$(t '%s: included in the backup (the whole virtual machine as one export file, every night)' "$name")"
         else
           ok "$(t '%s: included in the backup (its files, while it runs)' "$name")"
         fi ;;
    off) set_line "$CTS" "$name" remove; ok "$(t '%s: left out of the backup' "$name")" ;;
    *) usage ;;
  esac
}

# ── Which parts of an instance are backed up (hs backup ct <ct> paths|include|exclude|reset, hs sys backup rules <ct>) ──
rules_size() {   # rules_size <ct> <path inside the instance>: bytes on the SSD (rootfs), or - when it is not mounted or not there
  local f=$INCUS_ROOT/$1/rootfs$2 n
  if [ -e "$f" ] && n=$(du -sb -- "$f" 2>/dev/null | cut -f1) && [ -n "$n" ]; then echo "$n"; else echo -; fi
}
cmd_rules_kv() {   # --rules <ct>: partial<TAB>yes|no, include<TAB>path<TAB>bytes, exclude<TAB>glob<TAB>-, dump<TAB>path<TAB>bytes
  local ct=${1:-} p
  [[ "$ct" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { echo "usage: backup.sh --rules <instance>" >&2; exit 1; }
  if rules_has "$ct"; then printf 'partial\tyes\n'; else printf 'partial\tno\n'; fi
  while IFS= read -r p; do if [ -n "$p" ]; then printf 'include\t%s\t%s\n' "$p" "$(rules_size "$ct" "$p")"; fi; done < <(rules_list "$ct" include)
  while IFS= read -r p; do if [ -n "$p" ]; then printf 'exclude\t%s\t-\n' "$p"; fi; done < <(rules_list "$ct" exclude)
  if rules_has "$ct" && [ -n "$(dump_cmds "$DUMPS/$ct")" ]; then printf 'dump\t/var/backups/hs\t%s\n' "$(rules_size "$ct" /var/backups/hs)"; fi
}
cmd_ct_paths() {   # hs backup ct <ct> paths
  local ct=$1 p b kind sz
  if ! rules_has "$ct"; then
    note "$(t '%s: the whole instance is backed up (no rules). Choose parts: hs backup ct %s include <path>' "$ct" "$ct")"
    return 0
  fi
  step "$(t 'In the backup of %s' "$ct")"
  while IFS=$'\t' read -r kind p b; do
    case "$kind" in include|dump) ;; *) continue ;; esac
    if [ "$b" = - ]; then sz=$(t '(size unknown: the instance is not running)'); else sz=$(human "$b"); fi
    if [ "$kind" = dump ]; then sz="$sz $(t '(dump files, always)')"; fi
    say "  $p  $sz"
  done < <(cmd_rules_kv "$ct")
  step "$(t 'Left out')"
  while IFS= read -r p; do if [ -n "$p" ]; then say "  $p"; fi; done < <(rules_list "$ct" exclude)
  say "  $(t 'everything else in the instance: a restore runs the recipe again and puts these paths back')"
}
cmd_ct_rule_apply() {   # cmd_ct_rule_apply <ct> include|exclude|reset <arg>
  local ct=$1 verb=$2 arg=${3:-}
  case "$verb" in
    include) rules_path_ok "$arg" || die "$(t 'An include is an absolute path inside the instance (no .. in it): %s' "$arg")"
             rules_add "$ct" include "$arg"; ok "$(t '%s: %s is in the backup' "$ct" "$arg")" ;;
    exclude) rules_glob_ok "$arg" || die "$(t 'An exclude is a restic pattern, not empty, no ! in front: %s' "$arg")"
             rules_has "$ct" || die "$(t '%s has no include yet: choose what is in first (hs backup ct %s include <path>)' "$ct" "$ct")"
             rules_add "$ct" exclude "$arg"; ok "$(t '%s: %s is left out' "$ct" "$arg")" ;;
    reset)   if [ -n "$arg" ] && [ "$arg" != all ]; then rules_drop "$ct" "$arg"; ok "$(t '%s: rule %s removed' "$ct" "$arg")"
             else rules_reset "$ct"; ok "$(t '%s: no rules, the whole instance is backed up again' "$ct")"; fi ;;
  esac
}
cmd_ct_rules() {   # hs backup ct <ct> paths|include|exclude|reset|apply ...
  local ct=$1 verb=$2 s
  shift 2
  [[ "$ct" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "$(t 'That is not an instance name: %s' "$ct")"
  case "$verb" in
    paths)   [ $# -eq 0 ] || usage; cmd_ct_paths "$ct" ;;
    include|exclude) [ $# -eq 1 ] || usage
             incus info "$ct" >/dev/null 2>&1 </dev/null || die "$(t 'No instance called %s' "$ct")"
             cmd_ct_rule_apply "$ct" "$verb" "$1" ;;
    reset)   [ $# -le 1 ] || usage; cmd_ct_rule_apply "$ct" reset "${1:-}" ;;
    apply)   # the interface: include=<path> exclude=<glob> reset=<path>|all, in this order
             incus info "$ct" >/dev/null 2>&1 </dev/null || die "$(t 'No instance called %s' "$ct")"
             for s in "$@"; do
               case "$s" in include=*|exclude=*|reset=*) cmd_ct_rule_apply "$ct" "${s%%=*}" "${s#*=}" ;; *) die "$(t 'Unknown rule change: %s' "$s")" ;; esac
             done ;;
    *) usage ;;
  esac
}

host_files() {
  local f
  if [ -n "${HS_BACKUP_HOST_FILES:-}" ]; then
    for f in $HS_BACKUP_HOST_FILES; do [ -e "$f" ] && echo "$f"; done
    return 0
  fi
  for f in /etc/nixos/machine.toml /etc/nixos/machine.nix /etc/nixos/hardware-configuration.nix /etc/nixos/vendor "$STATE" /var/lib/hs-ext /var/lib/private/hs-ext \
           /var/lib/samba/private /etc/ssh/ssh_host_* /var/lib/hs-gateway/acme; do   # acme: the gateway's certificate keys (secret, never printed)
    [ -e "$f" ] && echo "$f"
  done
  # The links in $STATE only point into the vault: with the vault open its secrets go along (the restic
  # password is excluded, like before); closed, they are simply not in this snapshot.
  if vault_is_open && [ -d "$VAULT_SECRETS" ]; then echo "$VAULT_SECRETS"; fi
  return 0
}

# The data and parity disks of the array are mounted under /var/lib/hs/disks (bulkpath.sh), which is inside $STATE: restic follows mounts, so without
# this the "host files" snapshot would copy the whole array (all shares, backup on or off) and fill the backup disk. The shares have their own rule.
host_excludes() {
  printf '%s\n' --exclude "$(disks_root)" --exclude "$STATE/disks"
}

note_state() {  # note_state key=value ...
  mkdir -p "$STATE"
  local kv k tmp
  touch "$RESULT"
  for kv in "$@"; do
    k=${kv%%=*}
    tmp=$(grep -v "^$k=" "$RESULT" || true)
    printf '%s\n' "$tmp" | sed '/^$/d' > "$RESULT.new"
    echo "$kv" >> "$RESULT.new"
    mv "$RESULT.new" "$RESULT"
  done
}

# ── The domain controller: samba's own backup, a small file ──
dc_backup() {
  incus info "$DC" >/dev/null 2>&1 </dev/null || return 0     # no domain controller here
  if [ "$(incus list "$DC" -f csv -c s </dev/null)" != RUNNING ]; then
    warn "$(t '%s is not running, its domain backup was skipped' "$DC")"
    return 1
  fi
  local out=$STATE/backup-dc
  rm -rf "$out"; mkdir -p "$out"
  incus exec "$DC" -- bash -c 'rm -rf /root/hs-dc-backup && samba-tool domain backup offline --targetdir=/root/hs-dc-backup >/dev/null' </dev/null
  incus exec "$DC" -- bash -c 'cat /root/hs-dc-backup/*.tar.bz2 && rm -rf /root/hs-dc-backup' </dev/null > "$out/domain-backup.tar.bz2"
  [ -s "$out/domain-backup.tar.bz2" ] || { echo "empty domain backup from $DC" >&2; return 1; }
  chmod 700 "$out"; chmod 600 "$out/domain-backup.tar.bz2"     # it holds the keys of the domain: root only
}

# ── Incus layout and disks as text, so a lost server can be rebuilt: part of the host files ──
inventory() {
  local out=$STATE/backup-inventory n
  rm -rf "$out"; mkdir -p "$out"
  if command -v incus >/dev/null 2>&1; then
    incus list --format json >"$out/incus-instances.json" 2>/dev/null </dev/null || true
    for n in $(incus list -f csv -c n </dev/null 2>/dev/null); do
      incus config show --expanded "$n" >"$out/instance-$n.yaml" 2>/dev/null </dev/null || true
    done
    for n in $(incus profile list -f csv -c n </dev/null 2>/dev/null); do
      incus profile show "$n" >"$out/profile-$n.yaml" 2>/dev/null </dev/null || true
    done
    incus network list --format json >"$out/incus-networks.json" 2>/dev/null </dev/null || true
    incus storage list --format json >"$out/incus-storage.json" 2>/dev/null </dev/null || true
  fi
  lsblk -f >"$out/lsblk.txt" 2>/dev/null || true
  command -v zpool >/dev/null 2>&1 && zpool status >"$out/zpool-status.txt" 2>/dev/null || true
  command -v zfs >/dev/null 2>&1 && zfs list >"$out/zfs-list.txt" 2>/dev/null || true
  return 0
}

# A database in a container can't be saved by copying its files while it runs. The dump descriptor
# /var/lib/hs/backup-dump/<container> (format and helpers: scripts/lib/backup-dump.sh) lists the commands,
# one per line (mostly `hs-dump ...`, which the recipes install); each runs inside the container right
# before its files are backed up. A failing command does not stop the others; the run counts as failed.
dump_hook() {   # dump_hook <container>
  local f=$DUMPS/$1 cmd n=0 bad=0
  [ -s "$f" ] || return 0
  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    n=$((n + 1))
    incus exec "$1" -- sh -c "$cmd" </dev/null || bad=$((bad + 1))
  done < <(dump_cmds "$f")
  [ "$n" -gt 0 ] || return 0
  if [ "$bad" -eq 0 ]; then ok "$(t '%s: dump written' "$1")"; else warn "$(t '%s: the dump command failed' "$1")"; return 1; fi
}

# ── Virtual machines (not the domain controller, which has samba's own backup file) ──
# A container's files can be read from its mounted rootfs; a VM's disk is a block image that restic cannot read consistently
# while the VM runs, and the files inside would need the guest to run and to have an agent. So a VM is backed up as ONE file:
# `incus export` (Incus takes a snapshot of a running VM for it, so the image is consistent as of that moment: crash-consistent,
# like a power cut, plus the dump hook below, which flushes the databases inside first), uncompressed, so restic can deduplicate
# it from night to night. The file lives at a fixed path (HS_VM_EXPORT_DIR, default /var/tmp/hs-vm-export/<name>.tar) so restic finds
# the parent snapshot, is backed up with the tags ct:<name> and vm, and is deleted right after. It needs about the used size of the
# VM as free space there. Restore: `hs backup restore latest <that path> --tag ct:<name>`, then `incus import <file>`.
VMX=${HS_VM_EXPORT_DIR:-/var/tmp}/hs-vm-export
ct_kind() {   # ct_kind <instance>: virtual-machine | container (a container when Incus does not say)
  local k
  k=$("${HS_INCUS:-incus}" query "/1.0/instances/$1" </dev/null 2>/dev/null | jq -r '.type // empty' 2>/dev/null || true)
  [ "$k" = virtual-machine ] && echo virtual-machine || echo container
}
has_ct=false; has_vm=false
ct_kinds() {   # sets has_ct and has_vm: which kinds of instance are in the backup now (the list $CTS)
  local n
  has_ct=false; has_vm=false
  [ -s "$CTS" ] || return 0
  while read -r n; do
    [ -n "$n" ] || continue
    if [ "$(ct_kind "$n")" = virtual-machine ]; then has_vm=true; else has_ct=true; fi
  done < "$CTS"
}
vm_backup() {   # vm_backup <name> <restic backup options...>
  local name=$1 file used avail bad=0 status
  shift
  if [ "$name" = "$DC" ]; then
    note "$(t '%s is the domain controller: its backup is the samba backup file, not an export of the machine' "$name")"
    return 0
  fi
  file=$VMX/$name.tar
  status=$("${HS_INCUS:-incus}" query "/1.0/instances/$name" </dev/null | jq -r '.status // empty')
  # the databases inside are dumped first (needs the guest agent, so only while it runs)
  if [ "$status" = Running ]; then dump_hook "$name" || bad=1; fi
  mkdir -p "$VMX"; rm -f "$file"
  used=$("${HS_INCUS:-incus}" query "/1.0/instances/$name?recursion=1" </dev/null | jq -r '.state.disk.root.usage // 0' 2>/dev/null || echo 0)
  avail=$(df -B1 --output=avail "$VMX" | tail -n1 | tr -d ' ')
  if [[ "$used" =~ ^[0-9]+$ ]] && [ "$used" -gt 0 ] && [ "$avail" -lt $((used + used / 10)) ]; then
    warn "$(t '%s: the export needs about %s free in %s, only %s is free (HS_VM_EXPORT_DIR points it to another disk)' "$name" "$(human $((used + used / 10)))" "$VMX" "$(human "$avail")")"
    return 1
  fi
  step "$(t 'Virtual machine %s' "$name")"
  if ! "${HS_INCUS:-incus}" export "$name" "$file" --instance-only --compression none </dev/null; then
    rm -f "$file"; warn "$(t '%s: incus export failed' "$name")"; return 1
  fi
  [ -s "$file" ] || { rm -f "$file"; warn "$(t '%s: incus export wrote nothing' "$name")"; return 1; }
  R backup "$@" --tag "ct:$name" --tag vm "$file" || bad=1
  rm -f "$file"
  return "$bad"
}

ct_excludes() {  # ct_excludes <rootfs>
  local d
  for d in proc sys dev run tmp var/tmp var/cache var/lib/apt/lists var/log/journal \
           var/lib/docker/overlay2 var/lib/docker/image lost+found; do
    printf -- '--exclude\n%s/%s\n' "$1" "$d"
  done
}

# An instance with backup rules (scripts/lib/backup-rules.sh): only the included paths below its rootfs, tagged partial, with the
# usual excludes and the rule excludes. The dump files (/var/backups/hs) are always part of it when the instance has a dump descriptor.
# ct_partial_backup <name> <rootfs> <restic backup options...> -- <ct_excludes...>
ct_partial_backup() {
  local name=$1 root=$2 inc=() ex=() opts=() paths=() p g
  shift 2
  while [ $# -gt 0 ] && [ "$1" != -- ]; do opts+=("$1"); shift; done
  shift
  ex=("$@")
  while IFS= read -r p; do if [ -n "$p" ]; then inc+=("$p"); fi; done < <(rules_list "$name" include)
  if [ -n "$(dump_cmds "$DUMPS/$name")" ]; then inc+=(/var/backups/hs); fi
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    case "$g" in /*) ex+=(--exclude "$root$g") ;; *) ex+=(--exclude "$g") ;; esac
  done < <(rules_list "$name" exclude)
  for p in "${inc[@]}"; do
    if [ -e "$root$p" ]; then paths+=("$root$p"); else warn "$(t '%s: %s is not in the instance, skipped' "$name" "$p")"; fi
  done
  if [ ${#paths[@]} -eq 0 ]; then warn "$(t '%s: none of its backup paths exist, nothing backed up' "$name")"; return 1; fi
  note "$(t '%s: only the chosen parts are backed up (hs backup ct %s paths)' "$name" "$name")"
  R backup "${opts[@]}" --tag "ct:$name" --tag partial "${ex[@]}" "${paths[@]}"
}

cmd_now() {
  local scheduled=false
  [ "${1:-}" = --scheduled ] && scheduled=true
  if [ "$(pass_state)" = locked ] && ! $dry; then
    # the nightly run does not fail because of a closed vault (the storage-locked marker already says it)
    if $scheduled; then vault_locked_note >&2; return 0; fi
    secret_locked_exit
  fi
  if [ ! -f "$PASSFILE" ] && ! $dry; then
    $scheduled && { line "Backup is not set up (hs backup init), nothing to do."; return 0; }
    die "Not set up yet. Run: hs backup init <device>"
  fi

  local paths=() on=() offn=() cts=() kind name spath
  while read -r kind name spath; do
    [ -n "$name" ] || continue
    if is_off "$name"; then offn+=("$name"); else on+=("$name"); paths+=("$spath"); fi
  done < <(share_names)
  [ -f "$CTS" ] && while read -r name; do [ -n "$name" ] && cts+=("$name"); done < "$CTS"

  if $dry; then
    echo "Shares in the backup:   ${on[*]:-(none)}"
    echo "Shares left out:        ${offn[*]:-(none)}"
    echo "Containers:             ${cts[*]:-(none)}"
    echo "Domain controller:      $DC (samba-tool domain backup)"
    echo "Host files:"; host_files | sed 's/^/  /'
    say "(dry run, nothing changed)"
    return 0
  fi

  local lock=/run/hs-backup.lock
  [ -w /run ] || lock=$STATE/.backup.lock
  exec 9>"$lock"
  if ! flock -n 9; then
    # a second start is not a failure: as a job it ends skipped (exit 0), at a terminal it says so
    if [ -n "${HS_JOB_ID:-}" ]; then . "$(dirname "$0")/lib/job.sh"; hs_job_skip "Already running" || true; fi
    note "$(t 'Already running')"
    return 0
  fi
  note_state "last_try=$(date +%s)"
  # restic shows its own progress line on a terminal; in a job or a log (no terminal) one line a minute
  [ -t 1 ] || export RESTIC_PROGRESS_FPS=${RESTIC_PROGRESS_FPS:-0.0167}
  local fail=0 b=(--host "$(hostname)" --exclude-caches)
  # the file manager's trash is not backed up (names from scripts/lib/fm.sh, read in a subshell so nothing of it leaks into this script)
  mapfile -t tx < <(. "$(dirname "$0")/lib/fm.sh" && fm_trash_excludes)
  b+=("${tx[@]}")
  mount_disk
  [ -f "$REPO/config" ] || die "$(t 'No backup repository in %s. Run: hs backup init <device>' "$REPO")"
  clear_locks

  # the steps the job shows ("step n of m"): shares, domain controller and host files, each container or VM, the off-site copy
  steps $(( (${#paths[@]} > 0 ? 1 : 0) + 1 + ${#cts[@]} ))
  if [ -s "$OFFSITE" ]; then export HS_STEP_TOTAL=$((HS_STEP_TOTAL + 1)); fi
  if [ ${#paths[@]} -gt 0 ]; then
    step "$(t 'Shares: %s' "${on[*]}")"
    if R backup "${b[@]}" --tag shares "${paths[@]}"; then cat_event shares 0; else fail=1; cat_event shares 1; fi
  fi

  step "Domain controller and host files"
  local hfail=0
  dc_backup || hfail=1
  inventory
  mapfile -t hf < <(host_files)
  if [ ${#hf[@]} -gt 0 ]; then
    mapfile -t hx < <(host_excludes)
    R backup "${b[@]}" --tag host "${hx[@]}" --exclude "$PASSFILE" --exclude "$VAULT_SECRETS/restic-password" --exclude "$OFFSITE_PASS" --exclude "$OFFSITE_CRED" --exclude "$OFFSITE" --exclude "$VAULT_SECRETS/${OFFSITE_PASS##*/}" --exclude "$VAULT_SECRETS/${OFFSITE_CRED##*/}" --exclude "$VAULT_SECRETS/${OFFSITE##*/}" "${hf[@]}" || hfail=1   # none of the off-site secrets goes into a backup (least of all into the off-site repository it protects) || fail=1
  fi

  [ "$hfail" = 0 ] || fail=1
  cat_event host "$hfail"

  local cfail
  for name in "${cts[@]+"${cts[@]}"}"; do
    cfail=0
    if [ "$(ct_kind "$name")" = virtual-machine ]; then
      vm_backup "$name" "${b[@]}" || cfail=1
      [ "$cfail" = 0 ] || fail=1
      cat_event "ct:$name" "$cfail"
      continue
    fi
    local root=$INCUS_ROOT/$name/rootfs
    if [ ! -d "$root" ]; then
      warn "$(t '%s: not running (its files are not mounted), skipped' "$name")"
      export HS_STEP_TOTAL=$((HS_STEP_TOTAL - 1))   # no step for it: the count stays true
      fail=1; cat_event "ct:$name" 1; continue
    fi
    step "$(t 'Container %s' "$name")"
    dump_hook "$name" || cfail=1
    mapfile -t ex < <(ct_excludes "$root")
    if rules_has "$name"; then
      ct_partial_backup "$name" "$root" "${b[@]}" -- "${ex[@]}" || cfail=1
    else
      R backup "${b[@]}" --tag "ct:$name" "${ex[@]}" "$root" || cfail=1
    fi
    [ "$cfail" = 0 ] || fail=1
    cat_event "ct:$name" "$cfail"
  done

  # Keep 7 daily, 4 weekly, 6 monthly per kind of snapshot. Space is only
  # given back by prune, which is slow, so that runs on Sundays.
  local forget=(--group-by tags --keep-daily 7 --keep-weekly 4 --keep-monthly 6)
  [ "$(date +%u)" = 7 ] && forget+=(--prune)
  R forget --quiet "${forget[@]}" || fail=1
  if [ "$(date +%u)" = 7 ]; then
    R check --read-data-subset=5% >/dev/null || { warn "restic check found a problem"; fail=1; }
  fi

  offsite_adopt_old
  if [ -s "$OFFSITE" ] && offsite_is_disk; then
    note "The off-site disk is copied by hand, not by the nightly run: hs backup offsite now"
  elif [ -s "$OFFSITE" ]; then
    step "Off-site copy"
    if offsite_copy; then
      note_state "offsite_ok=$(date +%s)"
      # the same 7/4/6 rule there; REST targets run append-only and prune themselves (offsite_retention skips them)
      if [ "$(date +%u)" = 7 ]; then offsite_retention prune || warn "The off-site prune failed (the copy itself is fine)"
      else offsite_retention || warn "The off-site retention failed (the copy itself is fine)"; fi
    else warn "The off-site copy failed (the backup itself is fine)"; fi
  fi

  local used
  used=$(df --output=pcent "$MNT" | tail -n1 | tr -dc 0-9)
  note_state "used_pct=${used:-0}"
  # bytes too, for the forecast of the backup disk (lib/capacity.sh)
  local ub sb
  read -r ub sb < <(df -B1 --output=used,size "$MNT" | tail -n1) || true
  if [[ "${ub:-}" =~ ^[0-9]+$ ]] && [[ "${sb:-}" =~ ^[0-9]+$ ]]; then note_state "used_bytes=$ub" "size_bytes=$sb"; fi
  # for the interface (--state reads them without mounting the disk)
  note_state "snapshots=$(R snapshots --json 2>/dev/null | jq length 2>/dev/null || echo '?')" \
             "repo_size=$(du -sh "$REPO" 2>/dev/null | cut -f1 || echo '?')"
  if [ "$fail" = 0 ]; then
    note_state "last_ok=$(date +%s)" "status=ok"
    event_emit backup.ok backup "Backup finished"
    grep -q '^first_ok=' "$RESULT" 2>/dev/null || note_state "first_ok=$(date +%s)"
    ok "Backup finished."
    note "See what is in it: hs backup status"
  else
    note_state "status=failed"
    event_emit backup.failed backup "Backup finished with errors"
    note "Details: journalctl -u hs-backup. Try again: hs backup now"
    die "Backup finished with errors (see above)."
  fi
}

human() { numfmt --to=iec "$1"; }
ago() {
  local t=$1 d
  [ -n "$t" ] || { t 'never'; echo; return; }
  d=$(( $(date +%s) - t ))
  if [ "$d" -lt 3600 ]; then t '%s min ago' "$((d / 60))"; echo
  elif [ "$d" -lt 172800 ]; then t '%s h ago' "$((d / 3600))"; echo
  else t '%s days ago' "$((d / 86400))"; echo; fi
}

cmd_status() {
  local kind name last_ok last_try st drill inc unk dsize
  last_ok=$(sed -n 's/^last_ok=//p' "$RESULT" 2>/dev/null || true)
  last_try=$(sed -n 's/^last_try=//p' "$RESULT" 2>/dev/null || true)
  st=$(sed -n 's/^status=//p' "$RESULT" 2>/dev/null || true)
  if [ "$(pass_state)" = locked ]; then status_line "Backup" "vault closed (hs unlock)" warn
  elif [ ! -f "$PASSFILE" ]; then status_line "Backup" "not set up" warn
  elif [ -z "$last_ok" ]; then status_line "Last backup" "never" warn
  elif [ "$st" = failed ]; then status_line "Last backup" "$(ago "$last_ok"), $(t 'the last try failed')" bad
  else status_line "Last backup" "$(ago "$last_ok")" ok; fi

  step "Shares"
  { thead 'Share' 'Backup'
    while read -r kind name _; do
      [ -n "$name" ] || continue
      printf '%s\t%s\n' "$name" "$(is_off "$name" && t 'left out' || t 'in the backup')"
    done < <(share_names); } | table
  step "Containers (opt in with: hs backup ct <name> on)"
  if [ -f "$CTS" ] && [ -s "$CTS" ]; then while read -r name; do [ -z "$name" ] || line "$name"; done < "$CTS"; else line "$(t '(none)')"; fi
  line "$(t 'Always: domain controller %s, host files' "$DC")"
  if [ "$(pass_state)" = locked ]; then vault_locked_note; return 0; fi
  if [ ! -f "$PASSFILE" ]; then line "Not set up yet: hs backup init <device>"; return 0; fi

  step "Backup"
  kv "Last try" "$(ago "$last_try"), $st"
  kv "Disk used" "$(sed -n 's/^used_pct=//p' "$RESULT" 2>/dev/null || echo '?')% $(t '(as of the last run)')"
  drill=$(sed -n 's/^last_drill=//p' "$RESULT" 2>/dev/null || true)
  kv "Restore drill" "$(ago "$drill")$([ -n "$drill" ] || echo "   $(t '(try: hs backup drill)')")"
  ct_kinds
  drill=$(sed -n 's/^drill_ct_ok=//p' "$RESULT" 2>/dev/null || true)
  if [ -n "$drill" ] || $has_ct; then
    kv "Container drill" "$(ago "$drill")$([ -n "$drill" ] || echo "   $(t '(try: hs backup drill ct)')")"
  fi
  drill=$(sed -n 's/^drill_vm_ok=//p' "$RESULT" 2>/dev/null || true)
  if [ -n "$drill" ] || $has_vm; then
    kv "Virtual machine drill" "$(ago "$drill")$([ -n "$drill" ] || echo "   $(t '(try: hs backup drill ct)')")"
  fi
  read -r inc unk <<<"$(included_bytes)"
  if [ "$inc" -gt 0 ] || [ "$unk" -gt 0 ]; then
    kv "Shares size" "$(t 'about %s' "$(human "$inc")")$([ "$unk" -eq 0 ] || echo " $(t 'plus %s share(s) of unknown size (measured overnight)' "$unk")")"
    if mountpoint -q "$MNT" || [ -n "${HS_BACKUP_NO_MOUNT:-}" ] || [ -b "$DEV" ]; then
      mount_disk
      dsize=$(df -B1 --output=size "$MNT" | tail -n1 | tr -d ' ')
      if [ $((inc + inc / 5)) -gt "$dsize" ]; then
        warn "$(t 'That is more than fits on the backup disk (%s): leave shares out (hs backup <share> off) or use a bigger disk' "$(human "$dsize")")"
      else
        kv "Backup disk" "$(t '%s in total, the backup needs about 1.2x the data' "$(human "$dsize")")"
      fi
    fi
  fi
  if [ -s "$OFFSITE" ]; then
    kv "Off-site copy" "$(t '%s, last copied %s' "$(offsite_masked)" "$(ago "$(sed -n 's/^offsite_ok=//p' "$RESULT" 2>/dev/null || true)")")"
  fi
  if [ -n "${HS_BACKUP_NO_MOUNT:-}" ] || [ -b "$DEV" ] || mountpoint -q "$MNT"; then
    mount_disk
    kv "Snapshots" "$(R snapshots --json | jq length)"
    kv "Repository" "$(human "$(R stats --mode raw-data --json | jq .total_size)")"
  else
    warn "The backup disk is not plugged in."
  fi
}

# ── Second copy: another restic repository (own password, secrets in files restic reads by path) ──
# What restic gets, per kind of target (restic 0.18 docs; each backend checked, none of them takes a secret on argv):
#   s3      address s3:https://host/bucket/prefix; keys in an AWS credentials file, restic (minio-go) reads the file named
#           by AWS_SHARED_CREDENTIALS_FILE. The environment carries only that PATH, not a key.
#   rest    address rest:https://user:password@host:port/path/ inside the repository file (--repository-file).
#   sftp    address sftp:user@host:/path; restic runs ssh, which logs in with the key of root (a password cannot be given
#           to ssh without a helper, so SFTP is key-only).
#   folder  a path. No secret.
#   typed   any address (b2:, azure:, gs:, swift:, rclone:): keys that restic reads ONLY from the environment stay in the old
#           /var/lib/hs/backup-offsite.env. It is parsed as KEY=VALUE (never sourced) and its variables are set in restic's own
#           child process only (off_env runs in a subshell that exec's restic): not in this script's environment, not on argv.
secret_write() {   # secret_write <path>: the content comes on stdin; created through secret_prepare (vault), mode 0600
  local p=$1
  secret_prepare "${p##*/}" "$STATE" || return 1
  ( umask 077; cat > "$p" ) && chmod 600 "$p" 2>/dev/null || true
}
secret_rm() {      # secret_rm <path>: also the file in the vault the link points to
  local p=$1 t=""
  secret_in_vault "$p" && t=$(readlink "$p") || true
  rm -f "$p"
  [ -z "$t" ] || rm -f "$t"
}
off_env() {   # runs in the subshell of the restic call: the variables of the old env file, read strictly as KEY=VALUE
  local line k v
  [ ! -e "$OFFSITE_CRED" ] || export AWS_SHARED_CREDENTIALS_FILE=$OFFSITE_CRED
  [ -s "$OFFSITE_ENV" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}
    [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || continue
    k=${BASH_REMATCH[2]}; v=${BASH_REMATCH[3]}
    case "$k" in AWS_*|AZURE_*|B2_*|GOOGLE_*|OS_*|ST_*|SWIFT_*|OSS_*|RCLONE_*|RESTIC_*) ;; *) continue ;; esac
    case "$v" in \"*\") v=${v#\"}; v=${v%\"} ;; \'*\') v=${v#\'}; v=${v%\'} ;; esac
    export "$k=$v"
  done < "$OFFSITE_ENV"
}
offsite_adopt_old() {   # the address of before: into the repository file, once
  [ -s "$OFFSITE_OLD" ] && [ ! -e "$OFFSITE" ] || return 0
  [ "$(secret_state "$OFFSITE")" != locked ] || return 0
  secret_write "$OFFSITE" < "$OFFSITE_OLD" && rm -f "$OFFSITE_OLD" || true
}
offsite_pass_file() { if [ -e "$OFFSITE_PASS" ]; then echo "$OFFSITE_PASS"; else echo "$PASSFILE"; fi; }
R_off() {   # restic on the off-site repository
  local s
  for s in "$OFFSITE" "$OFFSITE_PASS" "$OFFSITE_CRED" "$OFFSITE_ENV"; do
    [ "$(secret_state "$s")" != locked ] || { vault_locked_note >&2; return 1; }
  done
  offsite_adopt_old
  [ -s "$OFFSITE" ] || { echo "No off-site repository" >&2; return 1; }
  ( off_env; exec restic --repository-file "$OFFSITE" --password-file "$(offsite_pass_file)" "$@" )
}
offsite_ready() {   # for --repo offsite: set, unlocked and openable
  [ "$(secret_state "$OFFSITE")" != locked ] || secret_locked_exit
  offsite_adopt_old
  [ -s "$OFFSITE" ] || die "No off-site repository. Set one: hs backup offsite set --kind s3|rest|sftp|folder"
  ! offsite_is_disk || offsite_disk_mount
  R_off cat config >/dev/null 2>&1 || die "$(t 'The off-site repository cannot be opened (not reachable, or wrong credentials or password).')"
}
# The rotating disk: a folder target under $OFFMNT. Only a person copies to it (hs backup offsite now); the nightly run skips it.
offsite_is_disk() { local a; a=$(cat "$OFFSITE" 2>/dev/null || true); [ "$a" = "$OFFMNT" ] || [[ "$a" == "$OFFMNT"/* ]]; }
offsite_disk_mount() {   # mount the disk labelled backup-offsite for this command (no-op for another target)
  [ -z "${HS_BACKUP_NO_MOUNT:-}" ] || return 0
  mountpoint -q "$OFFMNT" && return 0
  [ -e "$OFFDEV" ] || die "$(t "The off-site disk is not plugged in (no disk with the label 'backup-offsite'). Plug it in and run again.")"
  mkdir -p "$OFFMNT"
  mount -o noatime "$OFFDEV" "$OFFMNT" || die "Could not mount the off-site disk."
  off_mounted=true
}
offsite_renew_expiry() {   # after a copy to the rotating disk: the swap reminder moves to today + offsiteDiskDays (hs expiry)
  local days base until
  days=$(setting_get offsiteDiskDays 2>/dev/null || true)
  [[ "$days" =~ ^[0-9]+$ ]] && [ "$days" -ge 1 ] || days=30
  base=${HS_EXPIRY_TODAY:-$(date +%F)}
  until=$(date -u -d "$base +$days days" +%F 2>/dev/null) || { warn "Could not work out the new date of the swap reminder."; return 0; }
  bash "$(dirname "$0")/expiry.sh" add "$EXPIRY_NAME" "$until" "plug in the disk labelled backup-offsite and run: hs backup offsite now" >/dev/null ||
    warn "The swap reminder could not be renewed (hs expiry add $EXPIRY_NAME $until)."
  note_state "offsite_disk_until=$until"
  note "$(t 'Swap reminder renewed: %s' "$until")"
}
offsite_copy() {
  R_off copy --from-repo "$REPO" --from-password-file "$PASSFILE" >/dev/null
}
# Retention on the off-site repository: the same 7/4/6 rule. REST targets run `rest-server --append-only` (this server may
# not delete there), so forget and prune are the target's job; the other kinds prune from here on Sundays.
offsite_is_rest() { case "$(cat "$OFFSITE" 2>/dev/null || true)" in rest:*) return 0 ;; *) return 1 ;; esac; }
offsite_retention() {   # offsite_retention [prune]
  offsite_is_rest && return 0
  local f=(--group-by tags --keep-daily 7 --keep-weekly 4 --keep-monthly 6)
  [ "${1:-}" = prune ] && f+=(--prune)
  R_off forget --quiet "${f[@]}"
}
offsite_enc() { printf '%s' "$1" | jq -sRr @uri; }
offsite_read() {   # offsite_read <question> secret|plain: one line, from the terminal when there is one, else from stdin
  local v
  if [ -t 0 ]; then
    if [ "$2" = secret ]; then v=$(ask_secret "$1"); else v=$(ask "$1"); fi
  else
    IFS= read -r v || true
  fi
  printf '%s' "$v"
}
cmd_offsite() {
  local sub=${1:-}
  [ $# -gt 0 ] && shift
  case "$sub" in
    set)
      offsite_set "$@" ;;
    now)
      offsite_adopt_old
      [ -s "$OFFSITE" ] || die "No off-site repository. Set one: hs backup offsite set --kind s3|rest|sftp|folder"
      need_repo
      step "$(t 'Off-site copy to %s' "$(offsite_masked)")"
      ! offsite_is_disk || offsite_disk_mount
      offsite_copy || die "The off-site copy failed."
      note_state "offsite_ok=$(date +%s)"
      ! offsite_is_disk || offsite_renew_expiry
      ok "Copied." ;;
    off)
      rm -f "$OFFSITE_OLD"; secret_rm "$OFFSITE"; secret_rm "$OFFSITE_CRED"
      note_state "offsite=0"; ok "Off-site copy switched off (what is there stays there; its password file stays: $OFFSITE_PASS)." ;;
    migrate)
      offsite_migrate ;;
    retention)   # what the nightly run does after the copy: forget (7/4/6), with `prune` also prune; nothing for a REST target
      offsite_ready; offsite_retention "${1:-}" ;;
    *) usage ;;
  esac
}
offsite_masked() { sed -E 's#(://[^/@]*):[^/@]*@#\1:***@#' "$OFFSITE" 2>/dev/null || true; }
offsite_migrate() {   # the old env file: AWS keys become a credentials file; anything else stays, and says so
  local k id="" sec="" other=0 line
  [ -s "$OFFSITE_ENV" ] || { note "Nothing to migrate: there is no $OFFSITE_ENV."; return 0; }
  offsite_adopt_old
  while IFS= read -r line || [ -n "$line" ]; do
    [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || continue
    k=${BASH_REMATCH[2]}
    case "$k" in
      AWS_ACCESS_KEY_ID) id=${BASH_REMATCH[3]} ;;
      AWS_SECRET_ACCESS_KEY) sec=${BASH_REMATCH[3]} ;;
      *) other=1 ;;
    esac
  done < "$OFFSITE_ENV"
  id=${id#[\"\']}; id=${id%[\"\']}; sec=${sec#[\"\']}; sec=${sec%[\"\']}
  if [ -n "$id" ] && [ -n "$sec" ]; then
    printf '[default]\naws_access_key_id = %s\naws_secret_access_key = %s\n' "$id" "$sec" | secret_write "$OFFSITE_CRED" ||
      die "Could not write the credentials file."
    ok "S3 keys moved to $OFFSITE_CRED"
  fi
  if [ "$other" -eq 0 ]; then
    secret_rm "$OFFSITE_ENV"; ok "The old env file is gone."
  else
    note "$OFFSITE_ENV keeps variables that restic reads only from the environment (b2, azure, ...): they are set in restic's own process only."
  fi
}
offsite_set() {   # offsite set <repo> | --kind s3|rest|sftp|folder [fields]
  local kind="" endpoint="" bucket="" prefix="" url="" user="" host="" port="" path="" typed="" addr="" id="" sec="" pw="" new=false pass_new=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --kind) kind=${2:-}; shift 2 || usage ;;
      --endpoint) endpoint=${2:-}; shift 2 || usage ;;
      --bucket) bucket=${2:-}; shift 2 || usage ;;
      --prefix) prefix=${2:-}; shift 2 || usage ;;
      --url) url=${2:-}; shift 2 || usage ;;
      --user) user=${2:-}; shift 2 || usage ;;
      --host) host=${2:-}; shift 2 || usage ;;
      --port) port=${2:-}; shift 2 || usage ;;
      --path) path=${2:-}; shift 2 || usage ;;
      -*) usage ;;
      *) [ -z "$typed" ] || usage; typed=$1; shift ;;
    esac
  done
  [ -n "$typed" ] && [ -z "$kind" ] && kind=typed
  if [ -z "$kind" ]; then
    if [ -t 0 ] && [ -z "${HS_BACKUP_YES:-}" ]; then
      kind=$(choose "Where does the copy go?" s3 rest sftp folder typed)
    else usage; fi
  fi
  need_repo
  local re_host='^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$' re_path='^/[A-Za-z0-9/._+=,~%@:-]*$'
  case "$kind" in
    s3)
      [ -n "$endpoint" ] || endpoint=$(ask "S3 endpoint (host[:port], for example s3.eu-central-1.amazonaws.com)")
      [ -n "$bucket" ] || bucket=$(ask "Bucket")
      [[ "$endpoint" =~ ^(https?://)?[A-Za-z0-9.-]+(:[0-9]+)?$ ]] || die "That is not an S3 endpoint (host or host:port)."
      [[ "$bucket" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{1,62}$ ]] || die "That is not a bucket name."
      [[ "$prefix" =~ ^[A-Za-z0-9/._-]*$ ]] && [[ "$prefix" != *..* ]] || die "That is not a prefix (letters, digits, / . _ -)."
      case "$endpoint" in http*) ;; *) endpoint=https://$endpoint ;; esac
      addr="s3:$endpoint/$bucket${prefix:+/${prefix#/}}"
      id=$(offsite_read "Access key id" plain); sec=$(offsite_read "Secret access key" secret)
      [ -n "$id" ] && [ -n "$sec" ] || die "The access key id and the secret key are needed (stdin: two lines)."
      ;;
    rest)
      [ -n "$url" ] || url=$(ask "REST server address (https://host:8000/path)")
      [[ "$url" =~ ^(https?)://([A-Za-z0-9.-]+(:[0-9]+)?)(/[A-Za-z0-9/._-]*)?$ ]] || die "That is not a REST server address (https://host[:port]/path)."
      [[ "$url" != *..* ]] || die "No .. in the path."
      local scheme=${BASH_REMATCH[1]} hp=${BASH_REMATCH[2]} rp=${BASH_REMATCH[4]:-/}
      if [ -n "$user" ]; then
        [[ "$user" =~ ^[A-Za-z0-9._@+-]{1,64}$ ]] || die "That is not a user name."
        pw=$(offsite_read "Password of the REST server" secret)
        [ -n "$pw" ] || die "The password is needed (stdin: one line)."
        addr="rest:$scheme://$(offsite_enc "$user"):$(offsite_enc "$pw")@$hp$rp"
      else
        addr="rest:$scheme://$hp$rp"
      fi ;;
    sftp)
      [ -n "$host" ] || host=$(ask "SFTP host")
      [ -n "$user" ] || user=$(ask "SFTP user")
      [ -n "$path" ] || path=$(ask "Path on the host (absolute)")
      [[ "$host" =~ $re_host ]] || die "That is not a host name."
      [[ "$user" =~ ^[A-Za-z0-9._-]{1,64}$ ]] || die "That is not a user name."
      [[ "$path" =~ $re_path ]] && [[ "$path" != *..* ]] || die "That is not an absolute path."
      if [ -n "$port" ]; then
        [[ "$port" =~ ^[0-9]{1,5}$ ]] || die "That is not a port."
        addr="sftp://$user@$host:$port/$path"   # restic: sftp://user@host:port//abs/path
      else
        addr="sftp:$user@$host:$path"
      fi
      note "SFTP uses the ssh key of root on this server (no password): ssh-copy-id $user@$host first." ;;
    folder)
      [ -n "$path" ] || path=$(ask "Folder (absolute path, for example the mounted offsite disk)")
      [[ "$path" =~ $re_path ]] && [[ "$path" != *..* ]] || die "That is not an absolute path."
      addr=$path ;;
    typed)
      [ -n "$typed" ] || typed=$(ask "restic repository address")
      [[ "$typed" =~ ^[A-Za-z0-9/@:._+=,~%-]+$ ]] && [[ "$typed" != -* ]] && [[ "$typed" != *..* ]] || die "That is not a restic repository address."
      addr=$typed ;;
    *) usage ;;
  esac

  # Everything is written through secret_prepare (vault when there is one), mode 0600; a failure takes it all away again.
  # The same address again keeps the password it has; replacing another address starts without one.
  local old_addr=""
  [ ! -s "$OFFSITE" ] || old_addr=$(cat "$OFFSITE")
  fail_cleanup() { secret_rm "$OFFSITE"; secret_rm "$OFFSITE_CRED"; [ -z "$pass_new" ] || secret_rm "$OFFSITE_PASS"; }
  [ -z "$old_addr" ] || [ "$old_addr" = "$addr" ] || secret_rm "$OFFSITE_PASS"   # no old address: a password put there by hand (Case C) stays
  secret_rm "$OFFSITE_CRED"; rm -f "$OFFSITE_OLD"
  printf '%s\n' "$addr" | secret_write "$OFFSITE" || { fail_cleanup; die "Could not store the address (is the vault open?)."; }
  if [ "$kind" = s3 ]; then
    printf '[default]\naws_access_key_id = %s\naws_secret_access_key = %s\n' "$id" "$sec" | secret_write "$OFFSITE_CRED" ||
      { fail_cleanup; die "Could not store the S3 keys."; }
  fi
  ! offsite_is_disk || offsite_disk_mount
  if R_off cat config >/dev/null 2>&1; then
    # an existing repository keeps the password it has (the backup disk's)
    $machine || ok "$(t 'Using the existing repository %s (it keeps its password)' "$(offsite_masked)")"
  else
    pass_new=$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')
    printf '%s\n' "$pass_new" | secret_write "$OFFSITE_PASS" || { fail_cleanup; die "Could not store the off-site password."; }
    if ! R_off init --from-repo "$REPO" --from-password-file "$PASSFILE" --copy-chunker-params >/dev/null 2>&1; then
      fail_cleanup
      die "$(t 'Could not create the repository %s (reachable? credentials right? does one with another password exist there?)' "$(printf '%s' "$addr" | sed -E 's#(://[^/@]*):[^/@]*@#\1:***@#')")"
    fi
    new=true
  fi
  note_state "offsite=1"
  if $machine; then
    printf 'status\tdone\naddress\t%s\n' "$(offsite_masked)"
    # `secret<TAB>password<TAB>...` is the line the web interface shows once (parse_change); `created` says whether the repository is new
    if $new; then printf 'created\tyes\nsecret\tpassword\t%s\n' "$pass_new"; else printf 'created\tno\n'; fi
    return 0
  fi
  if $new; then
    ok "$(t 'Created the repository %s' "$(offsite_masked)")"
    if [ -t 1 ] && ! secret_batch; then
      warn "This repository has its OWN password. Write it down now; it is not shown again."
      kv "Off-site password" "$pass_new"
    else
      note "The off-site password is in $OFFSITE_PASS (root only). Read it once and write it down."
    fi
  fi
  if offsite_is_disk; then note "This is the rotating disk: plug it in and copy by hand with hs backup offsite now (never by the nightly run)."
  else note "Every nightly run copies new backups there. Now: hs backup offsite now"; fi
}

# ── Does a restore really work? Random files out of the newest backup, compared with the originals ──
cmd_drill() {
  [ "${1:-}" != ct ] || { shift; cmd_drill_ct "$@"; return; }
  local n=${1:-5} tmp picked f live size ok_n=0 bad=0 args=()
  [[ "$n" =~ ^[0-9]+$ ]] || die "$(t "'%s' is not a number of files. To try a container or virtual machine: hs backup drill ct %s" "$n" "$n")"
  [ "$n" -ge 1 ] || usage
  steps 3   # a background job shows "step n of m" (#389): choose, restore, compare
  step "$(t 'Choosing files from the newest backup')"
  need_repo
  mapfile -t picked < <(R ls --json latest --tag shares 2>/dev/null | jq -r 'select(.type == "file" and .size > 0) | .path' | shuf -n "$n")
  [ ${#picked[@]} -gt 0 ] || die "No file in the newest shares backup to try."
  tmp=$(mktemp -d)
  for f in "${picked[@]}"; do args+=(--include "$f"); done
  step "$(t 'Restoring the files into a temporary folder')"
  R restore latest --tag shares --target "$tmp" "${args[@]}" >/dev/null || { rm -rf "$tmp"; die "The restore itself failed."; }
  step "$(t 'Restore drill: %s file(s)' "${#picked[@]}")"
  for f in "${picked[@]}"; do
    live=$f; size=$(stat -c %s "$tmp$f" 2>/dev/null || echo missing)
    if [ "$size" = missing ]; then warn "$(t '%s: not restored' "$f")"; bad=$((bad + 1)); continue; fi
    if [ -f "$live" ] && cmp -s "$tmp$f" "$live"; then ok "$(t '%s: identical to the original' "$f")"; ok_n=$((ok_n + 1))
    elif [ -f "$live" ]; then note "$(t '%s: restored, the original has changed since (not compared)' "$f")"; ok_n=$((ok_n + 1))
    else note "$(t '%s: restored (%s bytes), the original is gone' "$f" "$size")"; ok_n=$((ok_n + 1)); fi
  done
  rm -rf "$tmp"
  note_state "last_drill=$(date +%s)"
  [ "$bad" -ne 0 ] || note_state "drill_ok=$(date +%s)"
  [ "$bad" -eq 0 ] || die "$(t '%s file(s) could not be restored.' "$bad")"
  ok "$(t '%s of %s restored.' "$ok_n" "${#picked[@]}")"
}

# ── Does a CONTAINER come back? Its newest snapshot becomes a throwaway Incus instance that boots without a network ──
# restic holds the files of the running container (the shifted ids of the host, under $INCUS_ROOT/<name>/rootfs).
# They are restored into a temp folder, packed as an Incus image with the ids brought back (lib/ct-image.py), imported,
# and started from `incus init --no-profiles` with only a root disk: no NIC, so no MAC or address can clash with the
# real container. Then everything is deleted, also on an error and on Ctrl-C (drill_cleanup, called from cleanup()).
CTDRILL=$STATE/backup-drill-ct        # one line per try: <container> <epoch> ok|failed (the rotation)
CTNEWEST=$STATE/backup-ct-newest      # epoch of the newest container snapshot in the repository, written by the container drill (0 = none)
CTIMG=$(dirname "$0")/lib/ct-image.py
drill_tmp=""; drill_inst=""; drill_img=""; dc_checked=false
inc() { "${HS_INCUS:-incus}" "$@"; }
drill_cleanup() {
  [ -z "$drill_inst" ] || inc delete -f "$drill_inst" >/dev/null 2>&1 </dev/null || true
  [ -z "$drill_img" ] || inc image delete "$drill_img" >/dev/null 2>&1 </dev/null || true
  [ -z "$drill_tmp" ] || rm -rf "$drill_tmp"
  drill_inst=""; drill_img=""; drill_tmp=""
}

# The container drilled longest ago (never drilled first, the smaller one first), or the one asked for.
# Prints "<name> <snapshot id> <bytes> <snapshot epoch>", nothing when there is none.
# A pick of all containers also records the time of the newest container snapshot (backup-ct-newest, 0 = none) for the report.
drill_pick() {   # drill_pick [<name>] [ct|vm]
  local want=${1:-} kind=${2:-ct} name id size last when newest=0 rows=""
  while IFS=$'\t' read -r name id when; do
    [ -n "$name" ] || continue
    [[ "$when" =~ ^[0-9]+$ ]] || when=0
    [ "$when" -le "$newest" ] || newest=$when
    if [ -n "$want" ] && [ "$name" != "$want" ]; then continue; fi
    # without a name only containers that are in the backup now (switching one off is a choice); virtual machines are not switched this way
    if [ "$kind" = ct ] && [ -z "$want" ] && ! is_ct_on "$name"; then continue; fi
    size=$(R stats --mode restore-size --json "$id" 2>/dev/null | python3 "$CTIMG" field total_size 2>/dev/null | tr -d '\r' || true)
    last=$(awk -v n="$name" '$1 == n { t = $2 } END { print t + 0 }' "$CTDRILL" 2>/dev/null || true)
    rows+="${last:-0}"$'\t'"${size:-0}"$'\t'"$name"$'\t'"$id"$'\t'"$when"$'\n'
  done < <(R snapshots --json 2>/dev/null | python3 "$CTIMG" newest "$kind" --time | tr -d '\r')
  if [ "$kind" = ct ] && [ -z "$want" ]; then echo "$newest" > "$CTNEWEST" 2>/dev/null || true; fi
  [ -n "$rows" ] || return 0
  printf '%s' "$rows" | sort -t$'\t' -k1,1n -k2,2n | awk -F'\t' 'NR == 1 { print $3, $4, $2, $5 }'
}

# A partial container (backup rules) cannot boot: each included path and each dump file must have come back, non-empty.
# The paths are the ones in the rule file now (a rule changed since the snapshot shows up as missing: the next backup fixes it).
drill_ct_partial() {   # drill_ct_partial <name> <restored rootfs>
  local name=$1 root=$2 p bad=0 n=0 what=""
  note "$(t '%s is a partial backup (only chosen parts): checking the paths and the dumps, not booting' "$name")"
  ok "$(t '%s: files restored' "$name")"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    n=$((n + 1))
    if [ -f "$root$p" ]; then
      if [ ! -s "$root$p" ]; then warn "$(t '%s: %s came back empty' "$name" "$p")"; bad=$((bad + 1)); fi
    elif [ -d "$root$p" ]; then
      if [ -z "$(find "$root$p" -type f -size +0 -print -quit 2>/dev/null)" ]; then warn "$(t '%s: %s came back with no file that holds data' "$name" "$p")"; bad=$((bad + 1)); fi
    else
      warn "$(t '%s: %s is not in the backup' "$name" "$p")"; bad=$((bad + 1))
    fi
  done < <(rules_list "$name" include)
  if [ -n "$(dump_cmds "$DUMPS/$name")" ]; then
    what=" and dump"
    if [ -z "$(find "$root/var/backups/hs" -type f -print -quit 2>/dev/null)" ]; then warn "$(t '%s: the backup holds no dump file' "$name")"; bad=$((bad + 1))
    elif [ -n "$(find "$root/var/backups/hs" -type f -size 0 -print -quit 2>/dev/null)" ]; then warn "$(t '%s: a dump file came back empty' "$name")"; bad=$((bad + 1)); fi
  fi
  if [ "$n" -eq 0 ]; then warn "$(t '%s: no backup rules now, nothing to check' "$name")"; bad=$((bad + 1)); fi
  drill_cleanup
  [ "$bad" -eq 0 ] || return 1
  ok "$(t '%s: every backed-up path%s is back and holds data' "$name" "$what")"
  note_state "drill_ct_partial=$name"
}

# One container. Returns 1 with a warning (never exits), so the domain controller check still runs.
drill_ct_one() {   # drill_ct_one <name> <snapshot id> <bytes> <snapshot epoch>
  local name=$1 id=$2 size=$3 when=${4:-0} root avail i st="" wait=${HS_DRILL_WAIT:-90} age
  local inst="hs-drill-$name" img="hs-drill-img-$name"
  inst=${inst:0:63}
  drill_cleanup
  # leftovers of a run that was killed
  inc list -f csv -c n </dev/null 2>/dev/null | grep -E '^hs-drill-' | while read -r i; do inc delete -f "$i" >/dev/null 2>&1 </dev/null || true; done
  inc image delete "$img" >/dev/null 2>&1 </dev/null || true
  mkdir -p "${HS_DRILL_TMP:-/var/tmp}"
  drill_tmp=$(mktemp -d "${HS_DRILL_TMP:-/var/tmp}/hs-drill.XXXXXX") || { warn "Could not make a temporary folder"; return 1; }
  avail=$(df -B1 --output=avail "$drill_tmp" | tail -n1 | tr -d ' ')
  if [ "${size:-0}" -gt 0 ] && [ "$avail" -lt $((size * 2)) ]; then
    warn "$(t '%s: needs about %s free in %s, only %s is free (HS_DRILL_TMP points the drill to another folder)' "$name" "$(human $((size * 2)))" "$(dirname "$drill_tmp")" "$(human "$avail")")"
    drill_cleanup; return 1
  fi
  step "$(t 'Container restore drill: %s' "$name")"
  if [ "$when" -gt 0 ]; then
    age=$(( ($(date +%s) - when) / 86400 ))
    if [ "$age" -le 3 ]; then
      note "$(t 'Snapshot from %s (%s days old)' "$(date -d "@$when" +%F)" "$age")"
    elif grep -qxF "$name" "$CTS" 2>/dev/null; then
      warn "$(t 'Snapshot from %s (%s days old); this container is still in the backup, so its backup has not run for days' "$(date -d "@$when" +%F)" "$age")"
    else
      warn "$(t 'Snapshot from %s (%s days old); this container is no longer in the backup (hs backup ct %s on)' "$(date -d "@$when" +%F)" "$age" "$name")"
    fi
  fi
  R restore "$id" --target "$drill_tmp/restore" >/dev/null || { warn "$(t '%s: the restore itself failed' "$name")"; drill_cleanup; return 1; }
  root=$drill_tmp/restore$INCUS_ROOT/$name/rootfs
  if [ "$(R snapshots --json 2>/dev/null | python3 "$CTIMG" partial "$id" 2>/dev/null | tr -d '\r' || true)" = yes ]; then
    drill_ct_partial "$name" "$root"; return
  fi
  if [ ! -d "$root/etc" ]; then warn "$(t '%s: the snapshot holds no root file system (no etc folder)' "$name")"; drill_cleanup; return 1; fi
  ok "$(t '%s: files restored' "$name")"
  python3 "$CTIMG" build "$root" "$drill_tmp/image.tar.gz" "$name" || { warn "$(t '%s: could not pack the image' "$name")"; drill_cleanup; return 1; }
  rm -rf "$drill_tmp/restore"
  drill_img=$img
  inc image import "$drill_tmp/image.tar.gz" --alias "$img" >/dev/null </dev/null || { warn "$(t '%s: could not import the image' "$name")"; drill_img=""; drill_cleanup; return 1; }
  rm -f "$drill_tmp/image.tar.gz"
  drill_inst=$inst
  # no profiles = no network card, no GPU, no shares, no autostart; only a root disk (--storage adds it: Incus 7 refuses
  # an init without a root disk, so it cannot be added afterwards)
  if ! inc init "$img" "$inst" --no-profiles --storage "${HS_DRILL_POOL:-default}" -c user.hs-drill=1 -c boot.autostart=false </dev/null >/dev/null; then
    warn "$(t '%s: could not create the throwaway instance' "$name")"; drill_cleanup; return 1
  fi
  inc start "$inst" </dev/null >/dev/null || { warn "$(t '%s: the throwaway instance did not start' "$name")"; drill_cleanup; return 1; }
  for ((i = 0; i < wait; i += 2)); do
    inc exec "$inst" -- true </dev/null >/dev/null 2>&1 && break
    sleep 2
  done
  if ! inc exec "$inst" -- true </dev/null >/dev/null 2>&1; then
    warn "$(t '%s: the restored container did not come up within %s s' "$name" "$wait")"; drill_cleanup; return 1
  fi
  ok "$(t '%s: booted, commands run inside it' "$name")"
  # systemd's own verdict (running, or degraded because a service failed without its network); only reported
  for ((i = 0; i < 20; i += 2)); do
    st=$(inc exec "$inst" -- systemctl is-system-running </dev/null 2>/dev/null || true)
    case "$st" in starting|initializing) sleep 2 ;; *) break ;; esac
  done
  [ -z "$st" ] || note "$(t 'systemd says: %s' "$st")"
  drill_cleanup
  ok "$(t '%s: throwaway instance deleted' "$name")"
  return 0
}

# The domain controller is a VM: what restic holds of it is samba's offline backup file. Restore it, list it, unpack it,
# look for sam.ldb. Putting it into a new domain controller stays manual.
drill_dc() {
  inc info "$DC" >/dev/null 2>&1 </dev/null || { note "$(t 'No domain controller %s here, nothing to check' "$DC")"; return 0; }
  local dcfile listing
  drill_tmp=$(mktemp -d "${HS_DRILL_TMP:-/var/tmp}/hs-drill.XXXXXX") || { warn "Could not make a temporary folder"; return 1; }
  step "$(t 'Domain controller backup file (%s)' "$DC")"
  R restore latest --tag host --target "$drill_tmp/restore" --include "$STATE/backup-dc" >/dev/null 2>&1 || { warn "The restore of the domain backup failed"; drill_cleanup; return 1; }
  dcfile=$drill_tmp/restore$STATE/backup-dc/domain-backup.tar.bz2
  [ -s "$dcfile" ] || { warn "The host backup holds no domain backup file (run hs backup now while the domain controller runs)"; drill_cleanup; return 1; }
  mkdir -p "$drill_tmp/x"
  # read the whole listing first: grep -q would close the pipe early and pipefail would count tar's SIGPIPE as a miss
  listing=$(tar -tjf "$dcfile" 2>/dev/null || true)
  grep -q 'sam\.ldb' <<<"$listing" || { warn "The domain backup does not list a sam.ldb"; drill_cleanup; return 1; }
  tar -xjf "$dcfile" -C "$drill_tmp/x" 2>/dev/null || { warn "The domain backup could not be unpacked"; drill_cleanup; return 1; }
  if [ -z "$(find "$drill_tmp/x" -name 'sam.ldb*' -size +0 -print -quit)" ]; then warn "The unpacked domain backup has no sam.ldb"; drill_cleanup; return 1; fi
  drill_cleanup
  dc_checked=true
  ok "Domain backup: it unpacks and holds sam.ldb"
}

# A virtual machine is in the backup as the file `incus export` wrote (vm_backup). The drill streams it out of restic (no free space needed)
# and lists the tar: it must hold Incus's backup/index.yaml and a disk image. Booting it needs the machine's whole size again, so that stays manual.
drill_vm_one() {   # drill_vm_one <name> <snapshot id> <bytes>
  local name=$1 id=$2 listing
  step "$(t 'Virtual machine restore drill: %s' "$name")"
  listing=$(R dump "$id" "$VMX/$name.tar" 2>/dev/null | tar -t 2>/dev/null) || { warn "$(t '%s: the export file could not be read from the backup' "$name")"; return 1; }
  if ! grep -q 'backup/index.yaml' <<<"$listing"; then warn "$(t '%s: the export file has no index.yaml' "$name")"; return 1; fi
  if ! grep -Eq '\.img$|\.qcow2$' <<<"$listing"; then warn "$(t '%s: the export file holds no disk image' "$name")"; return 1; fi
  ok "$(t '%s: the export file comes out of the backup and lists as an Incus export' "$name")"
}

cmd_drill_ct() {   # hs backup drill ct [<name>]
  local want=${1:-} pick name id size when rc=0 vmpick
  [ $# -le 1 ] || usage
  need_repo
  trap 'exit 130' INT TERM
  if [ -n "$want" ] && [ "$want" != "$DC" ]; then vmpick=$(drill_pick "$want" vm); fi
  if [ -z "$want" ]; then
    # the virtual machine drilled longest ago goes along with the container drill (one of each kind per run)
    vmpick=$(drill_pick "" vm)
  fi
  if [ -n "${vmpick:-}" ]; then
    read -r name id size _ <<<"$vmpick"
    if drill_vm_one "$name" "$id" "$size"; then
      printf '%s %s ok\n' "$name" "$(date +%s)" >> "$CTDRILL"
      note_state "drill_vm_ok=$(date +%s)" "drill_vm_name=$name"
    else
      printf '%s %s failed\n' "$name" "$(date +%s)" >> "$CTDRILL"
      rc=1
    fi
    [ -z "$want" ] || { [ "$rc" -eq 0 ] || die "The virtual machine drill failed (see above)."; ok "Virtual machine restore drill done."; return 0; }
  fi
  if [ "$want" != "$DC" ]; then
    pick=$(drill_pick "$want")
    if [ -z "$pick" ]; then
      [ -z "$want" ] || die "$(t 'No backup of a container called %s (see: hs backup list)' "$want")"
      [ -n "${vmpick:-}" ] || note "No container is in the backup, nothing to restore (hs backup ct <name> on)"
    else
      read -r name id size when <<<"$pick"
      if drill_ct_one "$name" "$id" "$size" "$when"; then
        printf '%s %s ok\n' "$name" "$(date +%s)" >> "$CTDRILL"
        note_state "drill_ct_ok=$(date +%s)" "drill_ct_name=$name" "drill_ct_snap=${when:-0}"
      else
        printf '%s %s failed\n' "$name" "$(date +%s)" >> "$CTDRILL"
        rc=1
      fi
    fi
  fi
  drill_dc || rc=1
  ! $dc_checked || note_state "drill_dc_ok=$(date +%s)"
  [ "$rc" -eq 0 ] || die "The container drill failed (see above)."
  ok "Container restore drill done."
}

# ── The monthly report: what the restore drills found, as one push message ──
# The drills (hs backup drill, drill ct) run on the 15th and the 22nd (timers in configuration.nix) and write their results to backup.state;
# on the 25th hs-backup-report sends the picture: when each kind of check last worked, which tries failed in the last 35 days, the age of the
# off-site copy, and how many guides were checked against the server (hs docs verified). It reads the state files only: no restic, no disk.
# Priority "high" and category problem when something is overdue or failed, otherwise a quiet "info". --dry-run prints instead of sending.
# HS_BACKUP_NOTIFY: another program for sending (tests); gets the same arguments as notify.sh.
cmd_report() {
  local scheduled=false now d lines="" problems=0 k v when limit title prio cat msg cname csnap cok cage cnew
  [ "${1:-}" = --scheduled ] && scheduled=true
  if [ ! -f "$PASSFILE" ] && [ "$(pass_state)" != locked ]; then
    $scheduled && return 0
    die "Not set up yet. Run: hs backup init <device>"
  fi
  now=$(date +%s)
  get() { sed -n "s/^$1=//p" "$RESULT" 2>/dev/null | tail -n1 || true; }
  add() { lines+="$1"$'\n'; }
  check_age() {   # check_age <label> <state key> <days allowed> [extra text]
    local label=$1 key=$2 allow=$3 extra=${4:-} stamp days
    stamp=$(get "$key")
    if [[ "$stamp" =~ ^[0-9]+$ ]]; then
      days=$(( (now - stamp) / 86400 ))
      if [ "$days" -gt "$allow" ]; then add "$(t '! %s: %s days ago (more than %s)' "$label" "$days" "$allow")${extra:+ $extra}"; problems=$((problems + 1))
      else add "$(t '%s: %s days ago' "$label" "$days")${extra:+ $extra}"; fi
    else
      add "$(t '! %s: never' "$label")"; problems=$((problems + 1))
    fi
  }
  if [ "$(get status)" = failed ]; then add "$(t '! The last backup failed')"; problems=$((problems + 1)); fi
  check_age "$(t 'Backup')" last_ok 2
  check_age "$(t 'File restore drill')" drill_ok 45
  # the container drill is only expected when containers are in the backup
  ct_kinds
  if $has_ct || [ -n "$(get drill_ct_ok)" ]; then
    # the age of the snapshot the drill restored (at the time of the drill), only when it was old
    cname=$(get drill_ct_name); csnap=$(get drill_ct_snap); cok=$(get drill_ct_ok); cage=""
    if [[ "$csnap" =~ ^[0-9]+$ && "$cok" =~ ^[0-9]+$ && "$csnap" -gt 0 && "$cok" -ge "$csnap" ]]; then
      cage=$(( (cok - csnap) / 86400 ))
      [ "$cage" -gt 3 ] || cage=""
    fi
    if [ -n "$cage" ]; then cname="${cname:+$cname, }$(t 'snapshot %s days old' "$cage")"; fi
    if [ -n "$cname" ] && [ "$(get drill_ct_partial)" = "$(get drill_ct_name)" ]; then cname="$cname, $(t 'partial: paths and dumps')"; fi
    check_age "$(t 'Container restore drill')" drill_ct_ok 90 "$([ -z "$cname" ] || echo "($cname)")"
  fi
  # containers were backed up once, none is in the backup now (the newest container snapshot was noted by the container drill)
  cnew=$(cat "$CTNEWEST" 2>/dev/null || true)
  if [ ! -s "$CTS" ] && [[ "$cnew" =~ ^[0-9]+$ ]] && [ "$cnew" -gt 0 ]; then
    add "$(t 'No container is in the backup (chosen); the newest container snapshot is %s days old' "$(( (now - cnew) / 86400 ))")"
  fi
  if $has_vm && [ -z "$(get drill_vm_ok)" ]; then add "$(t '! Virtual machine drill: never')"; problems=$((problems + 1))
  elif [ -n "$(get drill_vm_ok)" ]; then check_age "$(t 'Virtual machine drill')" drill_vm_ok 90 "($(get drill_vm_name))"; fi
  if incus info "$DC" >/dev/null 2>&1 </dev/null || [ -n "$(get drill_dc_ok)" ]; then check_age "$(t 'Domain controller backup file')" drill_dc_ok 90; fi
  if [ -s "$OFFSITE" ] && ! offsite_is_disk; then check_age "$(t 'Off-site copy')" offsite_ok 3; fi   # the rotating disk is warned about by its expiry entry
  # tries that failed lately (the container drills keep a list)
  if [ -s "$CTDRILL" ]; then
    # only containers that are in the backup now (switching one off is a choice; its old failures do not count)
    # (the list holds virtual machines too: the one the VM drill used last always counts)
    k=$(awk -v lim=$((now - 35 * 86400)) -v cts="$CTS" -v vm="$(get drill_vm_name)" 'BEGIN { while ((getline l < cts) > 0) on[l] = 1 } $3 == "failed" && $2 >= lim && (($1 in on) || $1 == vm) { n[$1]++ } END { for (c in n) printf "%s%s", (s++ ? ", " : ""), c }' "$CTDRILL")
    if [ -n "$k" ]; then add "$(t '! Drills that failed in the last 35 days: %s' "$k")"; problems=$((problems + 1)); fi
  fi
  v=$(get used_pct)
  if [[ "$v" =~ ^[0-9]+$ ]]; then
    if [ "$v" -ge 90 ]; then add "$(t '! Backup disk: %s%% full' "$v")"; problems=$((problems + 1)); else add "$(t 'Backup disk: %s%% full' "$v")"; fi
  fi
  # the guides: how many were worked through on the server (no problem: it is information)
  if [ -f "$(dirname "$0")/docs-verified.sh" ]; then
    d=$(bash "$(dirname "$0")/docs-verified.sh" --summary 2>/dev/null || true)
    if [ -n "$d" ]; then
      add "$(t 'Guides checked on the server: %s of %s%s' "$(sed -n 's/^verified=//p' <<<"$d")" "$(sed -n 's/^total=//p' <<<"$d")" \
        "$(w=$(sed -n 's/^oldest=//p' <<<"$d"); [ -z "$w" ] || t ' (the oldest check: %s)' "$w")")"
    fi
  fi
  if [ "$problems" -eq 0 ]; then
    title="$(hostname): $(t 'restore drills are fine')"; prio=low; cat=info
  else
    title="$(hostname): $(t 'restore drills: %s thing(s) to look at' "$problems")"; prio=high; cat=problem
  fi
  msg=${lines%$'\n'}
  if $dry; then
    say "$title ($prio)"
    printf '%s\n' "$msg"
    say "(dry run, nothing sent)"
    return 0
  fi
  line "$title"
  printf '%s\n' "$msg"
  event_emit backup.report "$cat" "Restore drill report" --level "$([ "$problems" -eq 0 ] && echo info || echo warn)" --payload "{\"problems\":$problems}"
  if [ -n "${HS_BACKUP_NOTIFY:-}" ]; then
    "$HS_BACKUP_NOTIFY" --category "$cat" "$title" "$msg" "$prio"
  else
    bash "$(dirname "$0")/notify.sh" --category "$cat" "$title" "$msg" "$prio"
  fi
}

# ── How big is what goes into the backup? (sizes measured overnight, or ZFS) ──
share_bytes() {   # share_bytes <path>
  local path=$1 b
  b=$(awk -F'\t' -v p="$path" '$1 == p { print $2; exit }' "$STATE/share-sizes" 2>/dev/null || true)
  if [[ "$b" =~ ^[0-9]+$ ]]; then echo "$b"; return; fi
  # a fast share is a dataset whatever the bulk layout is
  local ds=""
  case "$path" in
    "$FAST"/*) ds="fast/${path#"$FAST"/}" ;;
    *) [ "$(cat /etc/hs/bulk-type 2>/dev/null || echo zfs)" != zfs ] || ds="bulk/${path#"$BULK"/}" ;;
  esac
  if [ -n "$ds" ] && command -v zfs >/dev/null 2>&1; then
    b=$(zfs list -Hp -o used "$ds" 2>/dev/null || true)
    if [[ "$b" =~ ^[0-9]+$ ]]; then echo "$b"; return; fi
  fi
  echo "-"
}
included_bytes() {   # prints "bytes unknown-count"
  local kind name spath total=0 unknown=0 b
  while read -r kind name spath; do
    [ -n "$name" ] || continue
    is_off "$name" && continue
    b=$(share_bytes "$spath")
    if [ "$b" = "-" ]; then unknown=$((unknown + 1)); else total=$((total + b)); fi
  done < <(share_names)
  echo "$total $unknown"
}

# One event per part of a run (the subject is the part: shares, host, ct:<name>), next to the overall backup.ok / backup.failed of the run.
cat_event() {   # cat_event <category> <failed: 0|1>
  if [ "$2" = 0 ]; then event_emit backup.ok "$1" "Backup of $1 finished"
  else event_emit backup.failed "$1" "Backup of $1 finished with errors"; fi
}

cmd_list() {
  need_repo
  step "Snapshots"
  R snapshots --group-by tags --compact | sed 's/^/  /'
}

cmd_find() {
  [ $# -eq 1 ] || usage
  need_repo
  step "$(t "Snapshots that contain '%s'" "$1")"
  R find "*$1*" | sed 's/^/  /'
}

# In-place restore of shares on the ZFS layout: every share is its own dataset (hs share add), but restic brings folders back as
# plain folders of the parent dataset. Create the datasets that are missing first, so restic writes into them (hs share repair
# publishes them afterwards). Only creates; nothing is destroyed or overwritten.
restore_make_datasets() {   # restore_make_datasets <snapshot> <tag> <path>
  local snap=$1 tag=$2 path=${3%/} parent name names="" listed d want=() skipped=()
  case "$path" in
    "$BULK/shares"|"$BULK/sensitive") parent=${path##*/} ;;
    "$BULK/shares/"*|"$BULK/sensitive/"*)
      name=${path#"$BULK"/*/}
      case "$name" in */*) return 0 ;; esac
      parent=${path#"$BULK"/}; parent=${parent%%/*} ;;
    *) return 0 ;;
  esac
  [ "$tag" = shares ] || return 0
  [ "$(cat "${HS_BULK_TYPE_FILE:-/etc/hs/bulk-type}" 2>/dev/null || echo zfs)" != snapraid ] || return 0
  command -v zfs >/dev/null 2>&1 || return 0
  if [ -n "${name:-}" ]; then
    names=$name
  else
    # one level below the parent: the share names of the snapshot
    listed=$(R ls "$snap" --tag "$tag" "$path") || die "$(t 'Could not list %s in the snapshot.' "$path")"
    names=$(awk -v p="$path/" 'index($0, p) == 1 { n = substr($0, length(p) + 1); if (n != "" && index(n, "/") == 0) print n }' <<<"$listed")
  fi
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    case "$name" in *.deleted-*|lost+found) continue ;; esac
    case "${name,,}" in shares|sensitive|global|homes|printers) continue ;; esac
    if zfs list -H -o name "bulk/$parent/$name" >/dev/null 2>&1; then continue; fi
    d=$BULK/$parent/$name
    if [ -d "$d" ] && [ -n "$(ls -A "$d" 2>/dev/null)" ]; then skipped+=("$d"); continue; fi
    want+=("$name")
  done <<<"$names"
  for d in "${skipped[@]}"; do note "$(t '%s is a plain folder with files, left as it is.' "$d")"; done
  [ "${#want[@]}" -gt 0 ] || return 0
  note "$(t 'Share datasets that are missing and will be created first:')"
  for name in "${want[@]}"; do note "bulk/$parent/$name"; done
  for name in "${want[@]}"; do
    zfs create -p "bulk/$parent/$name" || die "$(t 'Could not create the dataset %s. Nothing was restored.' "bulk/$parent/$name")"
    # as hs share add: shares are written as adminuser, sensitive folders keep the owner of the snapshot
    if [ "$parent" = shares ]; then
      chown "$adm":users "$BULK/$parent/$name" 2>/dev/null || true
      chmod 2775 "$BULK/$parent/$name" 2>/dev/null || true
    fi
  done
  ok "$(t 'Created %s share datasets. After the restore: sudo hs share repair' "${#want[@]}")"
}

# A partial container (backup rules, D12/D13) cannot boot from its snapshot: the snapshot holds only the chosen paths and the dump files.
# Its restore = run the recipe again from its package (container, app, wiring), then put the paths back while the app is stopped.
# HS_BACKUP_RECIPE_CMD replaces `bash recipe.sh` and HS_BACKUP_RESTORE_TARGET the target "/" (tests/backup-drill-ct.sh).
cmd_restore_ct() {   # hs backup restore ct <ct> [--recipe <app>] [--dry-run] [--yes]
  local ct="" recipe="" id size p target=${HS_BACKUP_RESTORE_TARGET:-/} root rc=0 here unit
  local recipe_cmd=() rargs=()
  here=$(dirname "$0")
  while [ $# -gt 0 ]; do
    case "$1" in
      --recipe) [ $# -ge 2 ] || usage; recipe=$2; shift 2 ;;
      -*)       usage ;;
      *)        [ -z "$ct" ] || usage; ct=$1; shift ;;
    esac
  done
  [[ "$ct" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || usage
  recipe=${recipe:-$ct}
  [[ "$recipe" =~ ^[a-z0-9][a-z0-9-]{0,40}$ ]] || die "$(t "'%s' is not the name of an app (recipe)." "$recipe")"
  if [ -n "${HS_BACKUP_RECIPE_CMD:-}" ]; then recipe_cmd=("$HS_BACKUP_RECIPE_CMD"); else recipe_cmd=(bash "$here/recipe.sh"); fi
  rargs=("$recipe"); [ "$recipe" = "$ct" ] || rargs+=(--name "$ct")
  need_repo
  id=$(R snapshots --tag "ct:$ct" --json | jq -r 'sort_by(.time) | last // empty | select((.tags // []) | index("partial")) | .id')
  [ -n "$id" ] || die "$(t '%s has no partial backup (only some parts). A whole container: hs backup restore latest <path> --tag ct:%s' "$ct" "$ct")"
  root=$INCUS_ROOT/$ct/rootfs
  size=$(R stats --mode restore-size --json "$id" 2>/dev/null | python3 "$CTIMG" field total_size 2>/dev/null | tr -d '\r' || true)
  step "$(t 'Restore of the partial container %s' "$ct")"
  note "$(t 'The backup holds only the chosen parts, not the whole container; it cannot boot from them.')"
  say "  1. $(t 'run the recipe %s again (container, app, connection to this server)' "$recipe")"
  say "  2. $(t 'stop %s' "$ct")"
  say "  3. $(t 'put these back from the newest backup (%s):' "$(human "${size:-0}")")"
  if rules_has "$ct"; then
    while IFS= read -r p; do if [ -n "$p" ]; then say "       $p"; fi; done < <(rules_list "$ct" include)
  fi
  if [ -n "$(dump_cmds "$DUMPS/$ct")" ]; then say "       /var/backups/hs   $(t '(the database dumps)')"; fi
  say "  4. $(t 'start %s again' "$ct")"
  warn "$(t 'Files of these paths that are newer than the backup are overwritten; files that are not in the backup stay as the recipe made them.')"
  if $dry; then note "$(t 'Dry run: nothing was changed.')"; return 0; fi
  if [ -z "${HS_BACKUP_YES:-}" ]; then
    confirm_name "$ct" "$(t 'the name of the instance')" || die "cancelled"
    if [ -t 0 ] && [ -t 1 ] && [ -z "${HS_CALLER:-}" ] && confirm "$(t 'Run the work as a background job? (recommended: it keeps going if the terminal closes; follow it with: hs job follow)')"; then
      . "$here/lib/job.sh"
      unit=$(hs_job "backup-restore-$ct" "hs backup restore ct $ct" -- bash "$here/backup.sh" restore ct "$ct" --recipe "$recipe" --yes) || exit 1
      ok "$(t 'Started as job %s. Follow it: hs job follow %s' "$unit" "$unit")"
      return 0
    fi
  fi
  step "$(t 'Running the recipe %s' "$recipe")"
  "${recipe_cmd[@]}" "${rargs[@]}" || die "$(t 'The recipe failed: nothing was put back. Fix that first, then run this command again.')"
  step "$(t 'Putting the backed-up parts back')"
  inc stop "$ct" </dev/null >/dev/null 2>&1 || true
  R restore "$id" --target "$target" --include "$root" || rc=1
  if [ "$rc" -eq 0 ] && rules_has "$ct"; then
    while IFS= read -r p; do
      if [ -n "$p" ] && [ ! -e "$target$root$p" ]; then warn "$(t '%s: not in the backup' "$p")"; rc=1; fi
    done < <(rules_list "$ct" include)
  fi
  inc start "$ct" </dev/null >/dev/null 2>&1 || warn "$(t '%s did not start: hs instance start %s' "$ct" "$ct")"
  [ "$rc" -eq 0 ] || die "$(t 'Not everything came back (see above). The container runs the recipe version of the app.')"
  ok "$(t '%s: recipe run, backed-up parts put back.' "$ct")"
  if [ -n "$(dump_cmds "$DUMPS/$ct")" ]; then note "$(t 'The database dumps are in /var/backups/hs inside the container; load them with the import of the app (see its guide).')"; fi
}

cmd_restore() {
  local snap="" path="" tag=shares to=$BULK/shares/restored keep=false
  if [ "${1:-}" = ct ]; then shift; cmd_restore_ct "$@"; return; fi
  while [ $# -gt 0 ]; do
    case "$1" in
      --keep-owner) keep=true; shift ;;
      --tag) [ $# -ge 2 ] || usage; tag=$2; shift 2 ;;
      --to)  [ $# -ge 2 ] || usage; to=$2; shift 2 ;;
      -*)    usage ;;
      *)     if [ -z "$snap" ]; then snap=$1; elif [ -z "$path" ]; then path=$1; else usage; fi; shift ;;
    esac
  done
  [ -n "$snap" ] && [ -n "$path" ] || usage
  [ -d "$to" ] || die "$(t '%s does not exist. For the default: hs share add restored' "$to")"
  steps 2   # a background job shows "step n of m" (#389)
  step "$(t 'Preparing the target')"
  need_repo
  [ -n "${to%/}" ] || restore_make_datasets "$snap" "$tag" "$path"
  # "latest" means the newest snapshot with that tag (shares, host, ct:<name>)
  step "$(t 'Restoring %s' "$path")"
  R restore "$snap" --tag "$tag" --target "$to" --include "$path"
  # restic is happy to restore nothing when the path is not in the snapshot
  [ -e "$to/${path#/}" ] || die "$(t "Nothing restored: '%s' is not in that snapshot. Use the full original path (for example %s/shares/<share>/<file>); look it up with: hs backup find <name>" "$path" "$BULK")"
  # --to / is a restore in place: restic as root already put the owners of the snapshot back (container-owned folders
  # of sensitive/ must stay 1000000:1000000), and the target is the whole system. --keep-owner asks for the same elsewhere.
  [ -n "${to%/}" ] || keep=true
  # only what was restored, and only for a folder meant for a person or for incus file push
  $keep || chown -R "$adm":users "$to/${path#/}" 2>/dev/null || true
  ok "$(t 'Restored into %s (the full original path is recreated below it).' "$to")"
  if $keep; then note "$(t 'Owners kept as in the snapshot.')"; fi
}

# ── The settings only: hs backup config [restore] ──
# vendor/ (the vendored Nix modules of capability packages and their lock, docs/PLAN-capabilities-repo.md, ADR 0017 decision 10) belongs to the
# settings: machine.toml may switch such a package on, and a rebuild on a clean install needs the code and the lock without reaching GitHub.
# What the host snapshot holds of the settings: the files under $NIXOS_DIR (the paths are the original ones in the snapshot).
# hardware-configuration.nix, SSH host keys, Samba secrets, disks and networks are never put back by this command.
NIXOS_DIR=${HS_NIXOS_DIR:-/etc/nixos}
CONFIG_FILES=(machine.toml machine.nix)
SSH_DIR=${HS_SSH_DIR:-/etc/ssh}
SAMBA_DIR=${HS_SAMBA_DIR:-/var/lib/samba/private}
# Files of $STATE that describe THIS disk set or the backup itself: never restored, even with --with-state.
state_skip() {  # state_skip <path relative to $STATE>
  case "$1" in
    restic-password|restic-offsite-password|backup-offsite.credentials|backup-offsite.repo|vault-uuid|luks-uuids|disks|disks/*|.config-restore.*|*.before-restore-*) return 0 ;;
  esac
  return 1
}

cmd_config_list() {
  need_repo
  local snaps id time f held
  snaps=$(R snapshots --tag host --json) || die "$(t 'Could not read the snapshots.')"
  step "$(t 'Host snapshots (the settings of this server)')"
  {
    thead 'Snapshot' 'When' 'Settings files'
    while IFS=$'\t' read -r id time; do
      [ -n "$id" ] || continue
      held=""
      for f in "${CONFIG_FILES[@]}"; do
        if R ls "$id" "$NIXOS_DIR/$f" 2>/dev/null | grep -qxF "$NIXOS_DIR/$f"; then held+="${held:+, }$f"; fi
      done
      if R ls "$id" "$NIXOS_DIR/vendor/capabilities.lock" 2>/dev/null | grep -qxF "$NIXOS_DIR/vendor/capabilities.lock"; then held+="${held:+, }vendor/"; fi
      printf '%s\t%s\t%s\n' "$id" "$time" "${held:--}"
    done < <(jq -r '.[] | [.id[0:8], (.time[0:16] | sub("T"; " "))] | @tsv' <<<"$snaps")
  } | table
  note "$(t 'Put them back with: hs backup config restore --dry-run')"
}

# --from-disk: mount the backup disk read-only and open the repository with a typed passphrase (a fresh install has neither
# /var/lib/hs/restic-password nor the mounted disk). Sets REPO, R_PASSFILE, R_EXTRA; cleanup() unmounts, the trap removes the temp files.
open_repo_from_disk() {   # open_repo_from_disk <device>
  local dev=$1 pass
  [ -t 0 ] || [ -n "${HS_BACKUP_NO_MOUNT:-}" ] || die "$(t 'The passphrase is typed: run this in a terminal.')"
  if [ -z "${HS_BACKUP_NO_MOUNT:-}" ]; then
    [ -b "$dev" ] || die "$(t '%s is not a disk or partition.' "$dev")"
    MNT=$(mktemp -d "${HS_RUN_DIR:-/run}/hs-config-restore-mnt.XXXX")
    mount -o ro,noatime "$dev" "$MNT" || die "$(t 'Could not mount %s read-only. Is it the backup disk (ext4)?' "$dev")"
    mounted_by_us=true
    REPO=$MNT/restic
  fi
  [ -f "$REPO/config" ] || die "$(t 'No restic repository on %s. Is it the backup disk?' "$dev")"
  CFG_PASSDIR=$(umask 077; mktemp -d "${HS_RUN_DIR:-/run}/hs-config-restore-pw.XXXX")
  pass=$(ask_secret "$(t 'Backup passphrase (the restic password from your password manager):')") || die "cancelled"
  [ -n "$pass" ] || die "$(t 'No passphrase given.')"
  (umask 077; printf '%s' "$pass" >"$CFG_PASSDIR/pass")   # printf is a builtin: nothing on argv
  pass=""
  R_PASSFILE=$CFG_PASSDIR/pass
  R_EXTRA=(--no-lock --no-cache)
  R snapshots --tag host --json >/dev/null 2>&1 || die "$(t 'Could not open the repository: wrong passphrase, or not the backup disk of this server.')"
}

cmd_config_restore() {
  local snap=latest with_state=false a with_samba=false
  from_disk=""   # global: the EXIT trap reads it after this function ends
  while [ $# -gt 0 ]; do
    a=$1; shift
    case "$a" in
      --with-state) with_state=true ;;
      --with-samba) with_samba=true ;;
      --from-disk) [ $# -gt 0 ] || usage; from_disk=$1; shift ;;
      -*) usage ;;
      *)  snap=$a ;;
    esac
  done
  if $with_samba && [ -z "$from_disk" ]; then die "$(t '--with-samba belongs to --from-disk.')"; fi
  local tmp
  CFG_TMP="" CFG_PASSDIR=""
  trap '[ -z "$CFG_TMP" ] || rm -rf "$CFG_TMP"; [ -z "$CFG_PASSDIR" ] || rm -rf "$CFG_PASSDIR"; cleanup; if [ -n "$from_disk" ] && [ -z "${HS_BACKUP_NO_MOUNT:-}" ]; then rmdir "$MNT" 2>/dev/null || true; fi' EXIT
  if [ -n "$from_disk" ]; then
    with_state=true
    open_repo_from_disk "$from_disk"
  else
    need_repo
  fi
  mkdir -p "$STATE"
  tmp=$(mktemp -d "$STATE/.config-restore.XXXX")
  CFG_TMP=$tmp
  local inc=() f
  for f in "${CONFIG_FILES[@]}"; do inc+=(--include "$NIXOS_DIR/$f"); done
  inc+=(--include "$NIXOS_DIR/vendor")
  $with_state && inc+=(--include "$STATE")
  if [ -n "$from_disk" ]; then
    inc+=(--include "$SSH_DIR/ssh_host_*")
    $with_samba && inc+=(--include "$SAMBA_DIR")
  fi
  step "$(t 'Reading the host snapshot %s' "$snap")"
  R restore "$snap" --tag host --target "$tmp" "${inc[@]}" >/dev/null || die "$(t 'Could not restore the settings from snapshot %s. Is there a host snapshot? (hs backup config)' "$snap")"
  [ -f "$tmp$NIXOS_DIR/machine.toml" ] || die "$(t 'That snapshot holds no machine.toml. Look at the list: hs backup config')"

  # The plan: per file new | changed | same. Only names, never contents.
  local rows=() live rel state same=0 changed=0 skipped=()
  for f in "${CONFIG_FILES[@]}"; do
    [ -f "$tmp$NIXOS_DIR/$f" ] || continue
    rows+=("$NIXOS_DIR/$f")
  done
  if [ -d "$tmp$NIXOS_DIR/vendor" ]; then
    while IFS= read -r -d '' f; do rows+=("${f#"$tmp"}"); done < <(find "$tmp$NIXOS_DIR/vendor" -type f -print0 | sort -z)
  fi
  if $with_state && [ -d "$tmp$STATE" ]; then
    while IFS= read -r -d '' f; do
      rel=${f#"$tmp$STATE/"}
      if state_skip "$rel"; then skipped+=("$rel"); continue; fi
      rows+=("$STATE/$rel")
    done < <(find "$tmp$STATE" -type f -print0 | sort -z)
  fi
  local ssh_rows=()
  if [ -n "$from_disk" ]; then
    while IFS= read -r -d '' f; do ssh_rows+=("${f#"$tmp"}"); done < <(find "$tmp$SSH_DIR" -maxdepth 1 -name 'ssh_host_*' -type f -print0 2>/dev/null | sort -z)
    rows+=("${ssh_rows[@]}")
    if $with_samba && [ -d "$tmp$SAMBA_DIR" ]; then
      while IFS= read -r -d '' f; do rows+=("${f#"$tmp"}"); done < <(find "$tmp$SAMBA_DIR" -type f -print0 | sort -z)
    fi
  fi
  local plan=()
  for f in "${rows[@]}"; do
    live=$f
    if [ ! -e "$live" ]; then state=new
    elif cmp -s "$tmp$f" "$live"; then state=same
    else state=changed; fi
    case "$state" in same) same=$((same + 1)) ;; *) plan+=("$state"$'\t'"$f"); changed=$((changed + 1)) ;; esac
  done
  step "$(t 'Plan')"
  if [ "$changed" -eq 0 ]; then
    ok "$(t 'Already identical: nothing to put back (%s file(s) compared).' "$same")"
    return 0
  fi
  { thead 'State' 'File'; printf '%s\n' "${plan[@]}"; } | table
  kv "Identical" "$same"
  if [ "${#skipped[@]}" -gt 0 ]; then
    note "$(t 'Not restored on purpose (they describe this disk set or the backup itself): %s' "$(IFS=,; echo "${skipped[*]}")")"
  fi
  if [ -n "$from_disk" ]; then
    $with_samba || note "$(t 'Samba secrets are not restored (add --with-samba to include them).')"
    note "$(t 'Never touched: hardware-configuration.nix, disks, pools, network.')"
  else
    note "$(t 'Never touched: hardware-configuration.nix, SSH host keys, Samba, disks, pools, network.')"
  fi
  if $dry; then note "(dry run, nothing changed)"; return 0; fi

  if [ -z "${HS_BACKUP_YES:-}" ]; then
    [ -t 0 ] || { [ -n "$from_disk" ] && [ -n "${HS_BACKUP_NO_MOUNT:-}" ]; } || die "$(t 'This replaces settings files. Run it in a terminal, or add --yes after looking at --dry-run.')"
    confirm_name "machine.toml" "the file" || die "cancelled"
  fi
  if [ "${#ssh_rows[@]}" -gt 0 ]; then
    # the old SSH host keys replace this install's own: other computers stop warning about a new server, but they are secrets,
    # so they come back only after a typed line (never with --yes)
    local keep=() r ssh_ok=false
    if [ -z "${HS_BACKUP_YES:-}" ]; then
      note "$(t 'The SSH host keys of the old server are in the backup. Putting them back keeps your computers from warning about a new server.')"
      confirm_name "ssh host keys" "the SSH host keys" && ssh_ok=true
    fi
    if ! $ssh_ok; then
      for r in "${rows[@]}"; do case " ${ssh_rows[*]} " in *" $r "*) ;; *) keep+=("$r") ;; esac; done
      rows=("${keep[@]}")
      warn "$(t 'SSH host keys not restored (this server keeps its own). Run the command again to put them back.')"
    fi
  fi

  local stamp
  stamp=$(date +%Y%m%d-%H%M%S)
  for f in "${rows[@]}"; do
    cmp -s "$tmp$f" "$f" 2>/dev/null && continue
    # a link into the vault: writing through it would overwrite the secret itself
    if [ -L "$f" ]; then warn "$(t '%s is a link into the vault, skipped' "$f")"; continue; fi
    if [ -e "$f" ]; then cp -a "$f" "$f.before-restore-$stamp"; fi
    mkdir -p "$(dirname "$f")"
    cp -a "$tmp$f" "$f"
    ok "$(t 'Restored %s' "$f")"
  done
  note "$(t 'The old files were kept as <file>.before-restore-%s.' "$stamp")"
  note "$(t 'Apply the settings with: hs rebuild')"
}

cmd_config() {
  case "${1:-}" in
    "")      cmd_config_list ;;
    restore) shift; cmd_config_restore "$@" ;;
    *)       usage ;;
  esac
}

cmd_browse() {
  need_repo
  if [ "${1:-}" = --off ]; then
    systemctl stop hs-backup-browse 2>/dev/null || true
    net conf delshare backup-browse 2>/dev/null || true
    mountpoint -q "$BROWSE" && umount "$BROWSE" 2>/dev/null || true
    mounted_by_us=true       # the disk goes back to being unmounted when this call ends
    mountpoint -q "$MNT" || mounted_by_us=false
    ok "Browsing is off."
    return 0
  fi
  mounted_by_us=false      # stays mounted until: hs backup browse --off
  local admins="" admins_sid=""
  if [ "$(testparm -s --parameter-name=security 2>/dev/null)" = "ADS" ]; then
    admins="$(testparm -s --parameter-name=workgroup 2>/dev/null)\Domain Admins"
    admins_sid=$(wbinfo -n "$admins" 2>/dev/null | cut -d" " -f1 || true)
    [ -n "$admins_sid" ] || die "$(t "Can't look up %s (is winbind running?)." "$admins")"
  fi
  mkdir -p "$BROWSE"
  systemctl stop hs-backup-browse 2>/dev/null || true
  # restic looks for "fusermount"; NixOS only has fusermount3, and the service has a bare PATH
  local fuse_bin=/run/hs/fuse-bin fm
  fm=$(command -v fusermount3 || true)
  [ -n "$fm" ] || fm=/run/wrappers/bin/fusermount3
  mkdir -p "$fuse_bin"
  ln -sf "$fm" "$fuse_bin/fusermount"
  ln -sf "$fm" "$fuse_bin/fusermount3"
  systemd-run --quiet --unit=hs-backup-browse --collect \
    --setenv=RESTIC_CACHE_DIR="$RESTIC_CACHE_DIR" \
    --setenv=PATH="$fuse_bin:/run/current-system/sw/bin:/run/wrappers/bin" \
    restic -r "$REPO" --password-file "$PASSFILE" mount "$BROWSE"
  local i
  for i in $(seq 1 30); do mountpoint -q "$BROWSE" && break; sleep 1; done
  mountpoint -q "$BROWSE" || die "Could not mount the backup (journalctl -u hs-backup-browse)."
  if ! net conf listshares | grep -qix backup-browse; then
    net conf addshare backup-browse "$BROWSE" writeable=n guest_ok=n
    net conf setparm backup-browse "force user" root
    [ -z "$admins" ] || sharesec backup-browse --replace "$admins_sid:ALLOWED/0x0/FULL" || true
  fi
  ok "$(t 'Open %s: snapshots/<time>/ ... (read-only, only %s)' "\\\\$(hostname)\\backup-browse" "$admins")"
  note "When you are done: hs backup browse --off"
}

cmd_verify() {
  steps 2   # a background job shows "step n of m" (#389)
  step "$(t 'Opening the backup repository')"
  need_repo
  step "$(t 'Reading a tenth of the stored data')"
  R check --read-data-subset=10%
}

# Give space back now (the nightly run only does it on Sundays, and a full backup disk cannot even get that far): remove the temporary files a run that
# died of "no space left" leaves in the repository, remove stale locks, apply the retention and prune what no snapshot uses any more.
cmd_prune() {
  need_repo
  local lock=/run/hs-backup.lock
  [ -w /run ] || lock=$STATE/.backup.lock
  exec 9>"$lock"
  flock -n 9 || die "Another backup is running."     # nothing else writes to the repository while this runs
  local free_before tmpn
  free_before=$(df -B1 --output=avail "$MNT" | tail -n1 | tr -d ' ')
  step "$(t 'Space on the backup disk')"
  kv "Free" "$(human "$free_before")"
  tmpn=$(find "$REPO/data" -type f -name '*-tmp-*' 2>/dev/null | wc -l | tr -d ' ')
  if [ "$tmpn" -gt 0 ]; then
    if $dry; then note "$(t '%s leftover temporary file(s) from a run that ran out of space would be deleted' "$tmpn")"
    else
      find "$REPO/data" -type f -name '*-tmp-*' -delete 2>/dev/null || true
      ok "$(t '%s leftover temporary file(s) from a run that ran out of space deleted' "$tmpn")"
    fi
  fi
  # a lock of a process that is gone (restic only removes those); a running backup holds the flock above, so none is
  $dry || clear_locks
  local forget=(--group-by tags --keep-daily 7 --keep-weekly 4 --keep-monthly 6)
  step "$(t 'Retention: 7 daily, 4 weekly, 6 monthly per kind, then prune')"
  [ -t 1 ] || export RESTIC_PROGRESS_FPS=${RESTIC_PROGRESS_FPS:-0.0167}
  if $dry; then
    R forget --dry-run "${forget[@]}" || die "$(t 'Could not work out what to forget.')"
    say "(dry run, nothing changed)"
    return 0
  fi
  R forget "${forget[@]}" --prune || die "$(t 'Pruning failed. Is the disk too full even to prune? Delete a large snapshot with: restic forget <id> (hs backup list shows them), then run this again.')"
  local free_after
  free_after=$(df -B1 --output=avail "$MNT" | tail -n1 | tr -d ' ')
  ok "$(t 'Free space on the backup disk: %s (was %s)' "$(human "$free_after")" "$(human "$free_before")")"
  note_state "pruned=$(date +%s)"
}

# ── Setting up a disk ──
cmd_init() {
  local dev bad pass tool missing=()
  # the password is created inside the vault: with a closed vault nothing is asked and nothing is erased
  if vault_configured && ! vault_is_open && [ ! -e "$PASSFILE" ]; then secret_locked_exit; fi
  [ "$(pass_state)" != locked ] || secret_locked_exit
  # the tools first: a missing restic must not be found out after the disk is erased
  for tool in restic mkfs.ext4 wipefs; do command -v "$tool" >/dev/null 2>&1 || missing+=("$tool"); done
  [ ${#missing[@]} -eq 0 ] || die "$(t 'Missing on this system: %s. Nothing was changed.' "${missing[*]}")"
  if [ $# -eq 0 ]; then
    # no device given: offer the free disks (the same list hs pool bulk uses), nothing is erased yet
    local list line id size kind rest options=() picked
    list=$(bash "${HS_MANAGE_POOL:-$(dirname "$0")/manage-pool.sh}" --list-disks 2>/dev/null || true)
    while IFS=$'\t' read -r id size kind rest; do
      [ -n "$id" ] || continue
      options+=("$id  $(numfmt --to=si "$size")B  $kind  $rest")
    done <<<"$list"
    [ ${#options[@]} -gt 0 ] || die "No free disk found. Plug it in, or give the device: hs backup init /dev/sdX"
    picked=$(choose "Which disk becomes the backup disk? (it is erased in the next step)" "${options[@]}") || die "cancelled"
    dev="/dev/disk/by-id/${picked%% *}"
  elif [ $# -eq 1 ]; then
    dev=$1
  else
    usage
  fi
  [ -b "$dev" ] || die "$(t '%s is not a block device' "$dev")"
  # Never touch a disk that is in use or belongs to a pool
  bad=$(lsblk -J -o PATH,FSTYPE,LABEL,MOUNTPOINTS "$dev" | jq -r '
    [.blockdevices[] | recurse(.children[]?)]
    | map(select(((.mountpoints // [] | map(select(. != null)) | length) > 0)
                 or ((.fstype // "") | test("^(zfs_member|linux_raid_member|swap|LVM2_member)$"))
                 or ((.label // "") | test("^bulk-(data|parity)-"))))
    | map(.path) | join(" ")')
  [ -z "$bad" ] || die "$(t 'Refusing: %s is mounted, swap, or part of a pool.' "$bad")"
  step "Backup disk"
  kv "Disk" "$dev ($(lsblk -dno SIZE,MODEL "$dev"))"
  lsblk -no PATH,FSTYPE,LABEL "$dev" | sed 's/^/      /'
  danger "$(t "This ERASES everything on %s and makes it the backup disk (ext4, label 'backup')." "$dev")"
  if $dry; then note "(dry run, nothing changed)"; return 0; fi
  if [ -z "${HS_BACKUP_YES:-}" ]; then
    confirm_name "$(basename "$(readlink -f "$dev")")" "the disk" || die "cancelled"
  fi
  wipefs -a "$dev" >/dev/null
  mkfs.ext4 -q -m 1 -L backup "$dev"
  udevadm settle 2>/dev/null || true
  DEV=$dev
  mount_disk
  mkdir -p "$STATE"
  if [ ! -f "$PASSFILE" ]; then
    secret_prepare restic-password "$STATE" || exit 1   # with a vault: created inside it, linked at the old path
    ( umask 077; head -c 24 /dev/urandom | base64 > "$PASSFILE" )
    if [ "${HS_CALLER:-}" = job ]; then
      # a job's output goes to the journal: the password is not printed there, only where to read it
      warn "$(t 'The backup password is in %s (root only). Read it once with: sudo cat %s, and SAVE IT in your password manager: without it a backup cannot be opened.' "$PASSFILE" "$PASSFILE")"
    else
      pass=$(cat "$PASSFILE")
      box <<TEXT
Backup password (also in $PASSFILE, root only):

    $pass

SAVE IT IN YOUR PASSWORD MANAGER NOW. Without it a backup can't be opened,
also not after the OS disk dies.
TEXT
    fi
  else
    note "$(t 'Using the existing backup password (%s).' "$PASSFILE")"
  fi
  R init >/dev/null
  # Game server backups are backups already; "restored" is where restores land
  if [ ! -f "$OFF" ]; then printf '%s\n' pelican-backups restored > "$OFF"; fi
  note_state "status=new"
  ok "Backup disk ready. First run: hs backup now   (then nightly at 04:00)"
}

# ── Machine-readable modes for the web interface (Backup page) ──
# --state: key<TAB>value, never mounts the disk and never fails (before init: configured=no).
# Everything comes from the last run (backup.state); snapshots/repo_size are shown once cmd_now records them.
cmd_state_kv() {
  local v
  get() { sed -n "s/^$1=//p" "$RESULT" 2>/dev/null | tail -n1 || true; }
  printf 'configured\t%s\n' "$(set_up && echo yes || echo no)"
  if [ "$(pass_state)" = locked ]; then printf 'vault\tclosed\n'; fi   # an unknown key: the interface ignores it
  printf 'last_ok\t%s\n' "$(get last_ok)"
  printf 'last_try\t%s\n' "$(get last_try)"
  v=$(get status); printf 'status\t%s\n' "${v:-empty}"
  printf 'used_pct\t%s\n' "$(get used_pct)"
  printf 'snapshots\t%s\n' "$(get snapshots)"
  printf 'repo_size\t%s\n' "$(get repo_size)"
  if [ -n "${HS_BACKUP_NO_MOUNT:-}" ] || [ -b "$DEV" ] || mountpoint -q "$MNT" 2>/dev/null; then
    printf 'disk\tpresent\n'
  else
    printf 'disk\tabsent\n'
  fi
  if mountpoint -q "$BROWSE" 2>/dev/null; then printf 'browse\ton\n'; else printf 'browse\toff\n'; fi
  # the address may carry user:password (rest:https://u:pw@host/); this output lands in the live state, so the password is masked
  offsite_adopt_old
  printf 'offsite\t%s\n' "$({ cat "$OFFSITE" 2>/dev/null || true; } | sed -E 's#(://[^/@]*):[^/@]*@#\1:***@#')"
  printf 'offsite_ok\t%s\n' "$(get offsite_ok)"
  printf 'last_drill\t%s\n' "$(get last_drill)"
  printf 'drill_ok\t%s\n' "$(get drill_ok)"
  printf 'drill_ct_ok\t%s\n' "$(get drill_ct_ok)"
  printf 'drill_ct_name\t%s\n' "$(get drill_ct_name)"
  v=$(systemctl show hs-backup.timer -p NextElapseUSecRealtime --value 2>/dev/null || true)
  printf 'next\t%s\n' "$([ -n "$v" ] && date -d "$v" +%s 2>/dev/null || true)"
  # appended last: readers go by key and ignore keys they do not know
  printf 'used_bytes\t%s\n' "$(get used_bytes)"
  printf 'size_bytes\t%s\n' "$(get size_bytes)"
  printf 'drill_ct_partial\t%s\n' "$(get drill_ct_partial)"   # the container of the last partial drill (paths and dumps, no boot)
}

# --overview: kind<TAB>name<TAB>on|off<TAB>bytes or -  (kind = shares | sensitive | ct | always)
cmd_overview_kv() {
  local kind name spath state b
  while read -r kind name spath; do
    [ -n "$name" ] || continue
    if is_off "$name"; then state=off; else state=on; fi
    printf '%s\t%s\t%s\t%s\n' "$kind" "$name" "$state" "$(share_bytes "$spath")"
  done < <(share_names)
  if [ -f "$CTS" ]; then
    while read -r name; do
      if [ -n "$name" ]; then printf 'ct\t%s\ton\t-\n' "$name"; fi
    done < "$CTS"
  fi
  printf 'always\tdomain controller\ton\t-\nalways\thost files\ton\t-\n'
}

# --shares: kind<TAB>name<TAB>on|off  (kind = share | ct | always)
cmd_shares_kv() {
  local kind name _
  while read -r kind name _; do
    [ -n "$name" ] || continue
    if is_off "$name"; then printf 'share\t%s\toff\n' "$name"; else printf 'share\t%s\ton\n' "$name"; fi
  done < <(share_names)
  if [ -f "$CTS" ]; then
    while read -r name; do
      if [ -n "$name" ]; then printf 'ct\t%s\ton\n' "$name"; fi
    done < "$CTS"
  fi
  printf 'always\tdomain controller %s\ton\n' "$DC"
  printf 'always\thost files\ton\n'
}

# The snapshots of the shares, oldest first, for the interface: id, time (UTC), tags. Mounts the backup disk while it reads.
cmd_snapshots_kv() {
  local tag=${1:-shares}
  [[ "$tag" =~ ^(shares|host|ct:[A-Za-z0-9._-]+)$ ]] || die "unknown tag (shares, host or ct:<name>)"
  need_repo
  R snapshots --tag "$tag" --json | jq -r 'sort_by(.time) | .[] | [.short_id, (.time[0:16] | sub("T"; " ")), (.tags | join(","))] | @tsv'
}

# Files whose name contains a word, in every snapshot, for the interface: snapshot id, time (UTC), path, type, bytes. At most 200 rows.
# Mounts the backup disk while it reads; can take a while on a big repository.
cmd_find_kv() {
  [ $# -eq 1 ] && [ -n "$1" ] || die "usage: hs sys backup find <word>"
  [[ "$1" != *[[:cntrl:]]* ]] || die "the word has a control character"
  need_repo
  local snaps
  snaps=$(R snapshots --json)
  R find --json "*$1*" | jq -r --argjson s "$snaps" '($s | map({(.id): .time[0:16]}) | add // {}) as $t
    | .[] | .snapshot as $id | .matches[] | [$id[0:8], (($t[$id] // "") | sub("T"; " ")), .path, .type, (.size // 0)] | @tsv' | awk 'NR <= 200'
}

case "$cmd" in
  --find)  cmd_find_kv "$@" ;;
  --snapshots) cmd_snapshots_kv "$@" ;;
  --overview)  cmd_overview_kv ;;
  --rules)  cmd_rules_kv "$@" ;;
  --state)  cmd_state_kv ;;
  --shares) cmd_shares_kv ;;
  status)  cmd_status ;;
  now)     cmd_now "$@" ;;
  list)    cmd_list ;;
  find)    cmd_find "$@" ;;
  restore) cmd_restore "$@" ;;
  config)  cmd_config "$@" ;;
  browse)  cmd_browse "$@" ;;
  verify)  cmd_verify ;;
  prune)   cmd_prune ;;
  report)  cmd_report "$@" ;;
  drill)  cmd_drill "$@" ;;
  offsite) cmd_offsite "$@" ;;
  init)    cmd_init "$@" ;;
  ct)      if [ $# -eq 2 ] && { [ "$2" = on ] || [ "$2" = off ]; }; then cmd_toggle_ct "$@"
           elif [ $# -ge 2 ]; then cmd_ct_rules "$@"
           else usage; fi ;;
  *)
    # hs backup <share> on|off
    if [ $# -eq 1 ] && { [ "$1" = on ] || [ "$1" = off ]; }; then
      cmd_toggle_share "$cmd" "$1"
    else
      usage
    fi ;;
esac
