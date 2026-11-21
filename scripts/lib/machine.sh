# shellcheck shell=bash
# Reading and writing machine.toml. The one place that knows the file:
# scripts call these instead of grep/sed on the text. Needs python3 (stdlib tomllib).
#
#   machine_file                 path of the file (HS_MACHINE_FILE, default /etc/nixos/machine.toml)
#   machine_get <key>            value on stdout (a.b = inside a table; a list one item per line); 1 when not set
#   machine_get_json <key>       the same as JSON ("de", true, 4, ["nvidia","intel"])
#   machine_has <key>            true when the option is set (not commented out)
#   machine_set <key> <toml> [tag]   change one line, comments stay; copy in $HS_STATE_DIR/machine.toml.before-<tag>
#   machine_unset <key> [tag]    comment the line out
#   machine_example              path of machine.toml.example (HS_MACHINE_EXAMPLE), with the sections of installed capability packages when there are some
#   machine_generated_dir, config_keys_extend   the generated overlay folder (HS_GENERATED_DIR); the keys of capability packages for config-change.sh
#   config_overlay_key <key>     succeeds when <key> is an option of an installed capability package that lives in machine.toml
# Test knobs: HS_MACHINE_FILE, HS_MACHINE_EXAMPLE, HS_STATE_DIR, HS_PYTHON.

machine_file() { echo "${HS_MACHINE_FILE:-/etc/nixos/machine.toml}"; }
# The scripts run from a copy in /nix/store (no machine.toml.example next to it): then the example is the one beside machine.toml (the checkout).
machine_example() {
  local e=${HS_MACHINE_EXAMPLE:-}
  [ -n "$e" ] || e=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)/machine.toml.example
  [ -f "$e" ] || [ -n "${HS_MACHINE_EXAMPLE:-}" ] || e=$(dirname "$(machine_file)")/machine.toml.example
  # capability packages with options of their own (`schema-gen.py overlay write`): the layout is the core example followed by their sections;
  # used only while it still starts with the core example as it is now (after a core update the overlay is rewritten, and until then the core wins)
  local m; m=$(machine_generated_dir)/machine.toml.example
  if [ -f "$m" ] && [ -f "$e" ] && cmp -s -n "$(wc -c < "$e")" "$e" "$m"; then e=$m; fi
  echo "$e"
}
# The folder `schema-gen.py overlay write` fills on this machine (root, not in git, not in the checkout).
machine_generated_dir() { echo "${HS_GENERATED_DIR:-${HS_STATE_DIR:-/var/lib/hs}/generated}"; }
# config_keys_extend: adds the settable and secret keys of installed capability packages to CONFIG_SETTABLE / CONFIG_SECRET (scripts/lib/config-keys.sh
# holds only the core ones).
config_keys_extend() {
  local f; f=$(machine_generated_dir)/config-keys.overlay
  [ -r "$f" ] || return 0
  local k st se rest
  while IFS=$'	' read -r k st se rest; do
    case "$k" in ''|'#'*) continue ;; esac
    if [ "$st" = yes ]; then CONFIG_SETTABLE="${CONFIG_SETTABLE:-} $k"; fi
    if [ "$se" = yes ]; then CONFIG_SECRET="${CONFIG_SECRET:-} $k"; fi
  done < "$f"
  return 0
}
machine_tool() {   # machine_tool <args>: the python tool
  local py=${HS_PYTHON:-python3}
  command -v "$py" >/dev/null 2>&1 || py=python
  PYTHONUTF8=1 "$py" "${BASH_SOURCE[0]%/*}/../machine-toml.py" "$@"
}
# The read path of the long-running services (hs-live, hs-web) asks for the same keys again and again (pools, bulkType ...): with
# HS_MACHINE_CACHE=<folder> (set in their units; OFF everywhere else, so the CLI and the tests always read the file) each answer is kept in a file
# there for at most HS_MACHINE_CACHE_TTL seconds (default 30) and only while the file has the same modification time (ns), size and inode.
# A file system stamps a file with a coarse clock, so a rewrite within the same few milliseconds can look unchanged: that is why the answer also
# expires, and machine_set / machine_unset drop every answer.
_machine_cache_dir() {
  local d=${HS_MACHINE_CACHE:-}
  [ -n "$d" ] && [ "$d" != off ] || return 1
  [ -d "$d" ] || (umask 077; mkdir -p "$d") 2>/dev/null || return 1
  [ -w "$d" ] || return 1
  printf '%s' "$d"
}
_machine_cached() {   # _machine_cached <mode> <key> [--json]: print the answer, return its exit code
  local f; f=$(machine_file)
  [ -f "$f" ] || return 1
  local d c rc out sig have
  if d=$(_machine_cache_dir) && [[ $2 =~ ^[A-Za-z0-9_.-]{1,80}$ ]] && sig=$(stat -c '%.9Y %s %i' -- "$f" 2>/dev/null) && [ -n "$sig" ]; then
    local now=${EPOCHSECONDS:-0} ttl=${HS_MACHINE_CACHE_TTL:-30} at
    # exact: the answer is used only while the file has the same modification time (ns), size and inode as when it was read; any writer
    # (machine_set, the python tool, an editor, a copy over it) changes at least one of them
    c=$d/$(printf '%s' "$f" | cksum | tr -c '0-9' _).$2.${3:+json}
    if [ -f "$c" ]; then
      { IFS= read -r have; IFS= read -r at; IFS= read -r rc; out=$(cat); } <"$c" 2>/dev/null || rc=
      if [ "$have" = "$sig" ] && [[ $at =~ ^[0-9]+$ ]] && [ "$now" -gt 0 ] && [ $((now - at)) -ge 0 ] && [ $((now - at)) -lt "$ttl" ] && [[ $rc =~ ^[0-9]+$ ]]; then [ -z "$out" ] || printf '%s
' "$out"; return "$rc"; fi
    fi
    out=$(machine_tool get "$f" "$2" $3); rc=$?
    ( umask 077; { printf '%s
%s
%s
' "$sig" "$now" "$rc"; printf '%s' "$out"; } >"$c.$$" && mv -f "$c.$$" "$c" ) 2>/dev/null || true
    [ -z "$out" ] || printf '%s
' "$out"
    return "$rc"
  fi
  machine_tool get "$f" "$2" $3
}
_machine_cache_clear() { local d; d=$(_machine_cache_dir) && rm -f "$d"/* 2>/dev/null; return 0; }
machine_get() { _machine_cached get "$1"; }
machine_get_json() { _machine_cached get "$1" --json; }
machine_has() { machine_get_json "$1" >/dev/null 2>&1; }
_machine_backup() {   # _machine_backup <tag>: the --backup option for a change, when there is a state folder
  local state=${HS_STATE_DIR:-/var/lib/hs}
  mkdir -p "$state" 2>/dev/null && printf -- '--backup\n%s\n' "$state/machine.toml.before-$1"
}
machine_set() {
  local -a bk=(); mapfile -t bk < <(_machine_backup "${3:-config}")
  machine_tool set "$(machine_file)" "$1" "$2" "${bk[@]}"; local rc=$?
  _machine_cache_clear; return "$rc"
}
machine_unset() {
  local -a bk=(); mapfile -t bk < <(_machine_backup "${2:-config}")
  machine_tool unset "$(machine_file)" "$1" "${bk[@]}"; local rc=$?
  _machine_cache_clear; return "$rc"
}
config_overlay_key() {
  local f; f=$(machine_generated_dir)/config-keys.overlay
  [ -r "$f" ] && awk -F'	' -v k="$1" '$1 == k && $4 == "machine" { f = 1 } END { exit f ? 0 : 1 }' "$f"
}
