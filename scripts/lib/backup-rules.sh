# shellcheck shell=bash
# Backup rules of one instance: which parts of it go into the nightly backup (docs/PLAN-storage-nas.md, Q4, D12).
# File: $STATE/backup-rules/<instance> (STATE = /var/lib/hs). One rule per line:
#   include <absolute path inside the instance>
#   exclude <restic glob>        (restic's pattern rules; a glob that starts with / is read from the instance's root; no "!")
# No file = the whole instance (the backup of every instance before this existed). Blank lines and lines starting with # are ignored.
# The recipe seeds the file once from [app.backup] mode = "paths" (rules_seed); a person's edit always wins, so seeding never overwrites.

rules_file() { printf '%s/backup-rules/%s\n' "${STATE:-${HS_STATE_DIR:-/var/lib/hs}}" "$1"; }
rules_has() { [ -s "$(rules_file "$1")" ] && grep -qE '^include ' "$(rules_file "$1")"; }
rules_list() {   # rules_list <instance> include|exclude: the arguments, one per line
  local f; f=$(rules_file "$1")
  [ -s "$f" ] || return 0
  sed -n "s/^$2 //p" "$f"
}

rules_path_ok() {   # an absolute path inside the instance: no .., no control characters, not just /
  case "$1" in
    /?*) ;;
    *) return 1 ;;
  esac
  case "$1" in *$'\n'*|*$'\t'*|*$'\r'*) return 1 ;; esac
  case "/$1/" in */../*|*/./*) return 1 ;; esac
  return 0
}
rules_glob_ok() {   # a restic glob: not empty, no "!" negation, no control characters
  [ -n "$1" ] || return 1
  case "$1" in '!'*|'#'*) return 1 ;; esac
  case "$1" in *$'\n'*|*$'\t'*|*$'\r'*) return 1 ;; esac
  case "/$1/" in */../*) return 1 ;; esac
  return 0
}

rules_add() {   # rules_add <instance> include|exclude <argument>: add the line once
  local ct=$1 kind=$2 arg=$3 f tmp
  f=$(rules_file "$ct")
  mkdir -p "$(dirname "$f")"; touch "$f"
  if [ "$kind" = include ]; then arg=${arg%/}; fi
  grep -qxF "$kind $arg" "$f" && return 0
  tmp=$(mktemp "$f.XXXXXX")
  { cat "$f"; printf '%s %s\n' "$kind" "$arg"; } > "$tmp" && chmod 0644 "$tmp" && mv "$tmp" "$f"
}

rules_drop() {   # rules_drop <instance> <argument>: remove the include or exclude line with this argument; no lines left = no file
  local f tmp
  f=$(rules_file "$1")
  [ -f "$f" ] || return 0
  tmp=$(mktemp "$f.XXXXXX")
  grep -vxF -e "include $2" -e "include ${2%/}" -e "exclude $2" "$f" > "$tmp" || true
  if grep -qE '^(include|exclude) ' "$tmp"; then chmod 0644 "$tmp"; mv "$tmp" "$f"; else rm -f "$tmp" "$f"; fi
}

rules_reset() { rm -f "$(rules_file "$1")"; }   # the whole instance again

rules_seed() {   # rules_seed <instance> <path>...: write the include lines unless the file exists (never overwrites)
  local ct=$1 p f
  shift
  f=$(rules_file "$ct")
  [ ! -e "$f" ] || return 0
  [ $# -gt 0 ] || return 0
  for p in "$@"; do rules_path_ok "$p" || return 1; done
  for p in "$@"; do rules_add "$ct" include "$p"; done
}
