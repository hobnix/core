# shellcheck shell=bash
# The created ledger (docs/PLAN-app-lifecycle.md Q3, decision D6): one record per app at $HS_STATE_DIR/apps/<instance>.toml
# (/var/lib/hs/apps) that lists ONLY what a run itself created. Sourced; needs nothing but coreutils and awk.
#
# API (small on purpose; failed-install cleanup and Remove read it, they do not write it):
#   created <kind> <id> [detail]   record one thing this run created. No-op without an app (CREATED_APP empty), and when the same kind+id is
#                                  there already (a re-run writes nothing). The caller calls it ONLY for what it made itself (existed=false),
#                                  never for something that was there before.
#   created_list [instance]        the lines, one per record, tab separated: kind id detail (an empty detail is `-`)
#   created_check <kind> <id> [detail]   re-check one line against the real thing: exit 0 = still there, 1 = gone, 2 = cannot tell
#   created_drop <kind> <id> [instance]  take one line out (after it was removed); the file goes with its last line
#   created_file [instance]        the path of the record
#   created_app                    the instance this run belongs to (CREATED_APP, set by recipes/_lib.sh from ${app:-$ct})
#
# Kinds written today: container (id = instance, detail = vm|container), reservation (id = ip, detail = mac), service (id = descriptor name),
# share (id = share name, detail = directory). An app without a record is never removed by guesswork (a read-only discovered list
# is built by Remove, not here). The record never holds a secret.
# Test knob: HS_STATE_DIR.

created_app() { printf '%s\n' "${CREATED_APP:-}"; }
created_file() { printf '%s/apps/%s.toml\n' "${HS_STATE_DIR:-/var/lib/hs}" "${1:-${CREATED_APP:-}}"; }

# one value of a TOML basic string: no quote, backslash or line break (ids and details are names, paths, addresses)
_created_val() { local v=${1//[$'\n\r\t']/ }; v=${v//\\/}; printf '%s' "${v//\"/}"; }

created() {   # created <kind> <id> [detail]
  local kind=${1:-} id=${2:-} detail=${3:-} f
  [ -n "${CREATED_APP:-}" ] && [ -n "$kind" ] && [ -n "$id" ] || return 0
  [[ "$kind" =~ ^[a-z][a-z-]*$ ]] || return 0
  [[ "$CREATED_APP" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || return 0
  f=$(created_file)
  id=$(_created_val "$id"); detail=$(_created_val "$detail")
  if [ -f "$f" ] && awk -v k="$kind" -v i="$id" '
      /^\[\[created\]\]/ { kk=""; ii="" }
      /^kind = / { kk=$0; sub(/^kind = "/, "", kk); sub(/"$/, "", kk) }
      /^id = /   { ii=$0; sub(/^id = "/, "", ii); sub(/"$/, "", ii); if (kk == k && ii == i) found=1 }
      END { exit found ? 0 : 1 }' "$f"; then
    return 0
  fi
  mkdir -p "$(dirname "$f")" || return 0
  [ -f "$f" ] || printf 'app = "%s"\n' "$CREATED_APP" >"$f"
  printf '\n[[created]]\nkind = "%s"\nid = "%s"\ndetail = "%s"\nat = "%s"\n' "$kind" "$id" "$detail" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"$f"
}

created_list() {   # created_list [instance]
  local f
  f=$(created_file "${1:-}")
  [ -f "$f" ] || return 0
  awk '
    function val(s) { sub(/^[a-z]+ = "/, "", s); sub(/"$/, "", s); return s }
    function out() { if (k != "") printf "%s\t%s\t%s\n", k, i, (d == "" ? "-" : d); k=""; i=""; d="" }
    /^\[\[created\]\]/ { out() }
    /^kind = / { k = val($0) }
    /^id = /   { i = val($0) }
    /^detail = / { d = val($0) }
    END { out() }' "$f"
}

created_check() {   # created_check <kind> <id> [detail]
  local kind=$1 id=$2 detail=${3:--} sd=${HS_STATE_DIR:-/var/lib/hs}
  case "$kind" in
    container) incus info "$id" >/dev/null 2>&1 ;;
    volume)    [ "$detail" != - ] || return 2; incus storage volume show "$detail" "$id" >/dev/null 2>&1 ;;
    service)   [ -f "${HS_SERVICES_DIR:-$sd/services.d}/$id.toml" ] ;;
    share)     [ "$detail" != - ] || return 2; [ -d "$detail" ] ;;
    reservation)
      [ "$detail" != - ] && declare -F network_run >/dev/null 2>&1 || return 2
      local got
      got=$(network_run reserved "$detail" 2>/dev/null) || return 2
      [ "$got" = "$id" ] ;;
    *) return 2 ;;
  esac
}

created_drop() {   # created_drop <kind> <id> [instance]
  local f tmp
  f=$(created_file "${3:-}")
  [ -f "$f" ] || return 0
  tmp=$(mktemp "$f.XXXXXX") || return 1
  awk -v k="$1" -v i="$2" '
    function flush() { if (n > 0 && !(kk == k && ii == i)) printf "%s", buf; buf=""; n=0; kk=""; ii="" }
    /^\[\[created\]\]/ { flush(); n=1; buf=$0 "\n"; next }
    n == 0 { print; next }
    { buf = buf $0 "\n"
      if ($0 ~ /^kind = /) { kk=$0; sub(/^kind = "/, "", kk); sub(/"$/, "", kk) }
      if ($0 ~ /^id = /)   { ii=$0; sub(/^id = "/, "", ii); sub(/"$/, "", ii) } }
    END { flush() }' "$f" >"$tmp"
  if grep -q '^\[\[created\]\]' "$tmp"; then mv "$tmp" "$f"; else rm -f "$tmp" "$f"; fi
}
