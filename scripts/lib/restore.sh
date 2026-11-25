# shellcheck shell=bash
# Helpers of the disaster-recovery installer (scripts/install-restore.sh, scripts/install-wizard.sh --restore-from).
# UNVERIFIED: not tested on hardware. Tests (tests/install-restore.sh) use a fake restic and a temporary folder, no disk.
#
# The restored files come from the "host" snapshot of the backup, one folder per original path (like `hs backup config restore`).

# What of /var/lib/hs a fresh machine does NOT get back. restic-password: a secret that belongs into the new vault by hand; disks/: describes
# the old disk mounts; the temp and safety-copy leftovers. vault-uuid and luks-uuids are kept (docs/backup-and-recovery.md Case A step 4:
# the data disks are the same ones). Differs from scripts/backup.sh state_skip, which protects a RUNNING server.
restore_skip() {   # restore_skip <path relative to the state folder>
  case "$1" in
    restic-password|disks|disks/*|.config-restore.*|*.before-restore-*) return 0 ;;
  esac
  return 1
}

restore_snapshots() {   # restore_snapshots <repo> <passfile>: id<TAB>time of the host snapshots, newest last
  # --no-lock: the installer mounts the backup disk read-only, restic could not write its lock there (and would retry for minutes)
  local json
  json=$(restic -r "$1" --password-file "$2" --no-lock snapshots --tag host --json 2>/dev/null) || return 1
  [ -n "$json" ] || return 1   # nothing to parse: no traceback, the caller says what is wrong
  python3 -I -c 'import json,sys
for s in sorted(json.load(sys.stdin), key=lambda s: s["time"]):
    print(s["id"][:8] + "\t" + s["time"][:16].replace("T", " "))' <<<"$json" 2>/dev/null
}

restore_fetch() {   # restore_fetch <repo> <passfile> <snapshot|latest> <dir>: the settings of the host snapshot below <dir>
  # `<snapshot>:<subfolder>` would move everything: only latest or a hex id goes to restic
  [[ "$3" =~ ^(latest|[0-9a-f]{8,64})$ ]] || return 1
  restic -r "$1" --password-file "$2" --no-lock restore "$3" --tag host --target "$4" \
    --include /etc/nixos/machine.toml --include /etc/nixos/machine.nix \
    --include /var/lib/hs --include /var/lib/private/hs-ext --include /var/lib/hs-ext --include '/etc/ssh/ssh_host_*' >/dev/null 2>&1
}

restore_files() {   # restore_files <dir>: the files restore_apply would put in place, one per line (path as on the new system)
  local d=$1 f rel
  for f in /etc/nixos/machine.toml /etc/nixos/machine.nix; do [ -f "$d$f" ] && echo "$f"; done
  if [ -d "$d/var/lib/hs" ]; then
    while IFS= read -r -d '' f; do   # files only: a link into the vault must not be copied
      rel=${f#"$d/var/lib/hs/"}
      restore_skip "$rel" || echo "/var/lib/hs/$rel"
    done < <(find "$d/var/lib/hs" -type f -print0 | sort -z)
  fi
  # the state of extension services (ext_state.py): below the private root since the move, below /var/lib/hs-ext before the first start
  for f in /var/lib/private/hs-ext /var/lib/hs-ext; do
    [ -d "$d$f" ] || continue
    while IFS= read -r -d '' rel; do echo "${rel#"$d"}"; done < <(find "$d$f" -type f -print0 | sort -z)
  done
  for f in "$d"/etc/ssh/ssh_host_*; do [ -f "$f" ] && echo "/etc/ssh/${f##*/}"; done
  return 0
}

restore_apply() {   # restore_apply <dir> <target root>: copy the files of restore_files into the new system, keeping modes
  local d=$1 t=$2 f p c rel name put
  put=$(dirname "${BASH_SOURCE[0]}")/state_put.py
  while IFS= read -r f; do
    case "$f" in
      /var/lib/private/hs-ext/*|/var/lib/hs-ext/*)    # service state: never cp (it follows links); state_put.py opens every folder with O_NOFOLLOW
        rel=${f#/var/lib/private/hs-ext/}; [ "$rel" != "$f" ] || rel=${f#/var/lib/hs-ext/}
        name=${rel%%/*}
        if [ "$name" != "$rel" ] && [[ "$name" =~ ^[a-z][a-z0-9-]{0,40}$ ]]; then
          python3 -I "$put" put "$d$f" "$t/var/lib/hs-ext/$name" "${rel#*/}" restore || warn "$f was not restored"
        else
          warn "$f is not the state of a package, skipped"
        fi
        continue ;;
    esac
    # parent folders get explicit modes: the result must not depend on the caller's umask (sshd needs a readable /etc/ssh)
    p=""
    for c in $(dirname "$f" | tr / ' '); do   # top down, one folder at a time
      p=$p/$c
      [ -d "$t$p" ] || install -d -m 755 "$t$p"
    done
    cp -a "$d$f" "$t$f"
  done < <(restore_files "$d")
}
