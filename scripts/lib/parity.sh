# shellcheck shell=bash
# Per-share settings of the SnapRAID parity sync (hobnix/server#952). Sourced, not run.
#
#   /var/lib/hs/parity-skip     <rel><TAB><folder>   folders SnapRAID leaves out (bulk-mount.sh writes `exclude /<rel>/<folder>/`)
#   /var/lib/hs/parity-limits   <rel><TAB><N|off>    removed files that stop the sync for that share (no line = the default)
#   /var/lib/hs/sync-refused    share<TAB>folder<TAB>removed<TAB>limit<TAB>share_total   written by bulk-sync.sh, empty/absent = nothing refused
#
# <rel> is shares/<name> or sensitive/<name>. Default limit = max(syncMaxRemoved, syncMaxRemovedPercent % of the share's files).
# Test knobs: HS_PARITY_SKIP, HS_PARITY_LIMITS, HS_SYNC_REFUSED.

parity_skip_file()    { printf '%s\n' "${HS_PARITY_SKIP:-/var/lib/hs/parity-skip}"; }
parity_limits_file()  { printf '%s\n' "${HS_PARITY_LIMITS:-/var/lib/hs/parity-limits}"; }
parity_refused_file() { printf '%s\n' "${HS_SYNC_REFUSED:-/var/lib/hs/sync-refused}"; }

parity_skipped() {   # parity_skipped [rel]: "rel<TAB>folder" lines (only that share's when given)
  local f; f=$(parity_skip_file)
  [ -r "$f" ] || return 0
  awk -F'\t' -v r="${1-}" 'NF >= 2 && (r == "" || $1 == r) { print $1 "\t" $2 }' "$f"
}

parity_limit_mode() {   # parity_limit_mode <rel>: "default" | "off" | a number
  local f v; f=$(parity_limits_file)
  v=""
  [ ! -r "$f" ] || v=$(awk -F'\t' -v r="$1" '$1 == r { v = $2 } END { print v }' "$f")
  printf '%s\n' "${v:-default}"
}

parity_limit_floor() {
  local v; v=$(. "${BASH_SOURCE[0]%/*}/setting.sh"; setting_get syncMaxRemoved 2>/dev/null || true)
  [[ "$v" =~ ^[0-9]+$ ]] || v=100
  printf '%s\n' "$v"
}
parity_limit_percent() {
  local v; v=$(. "${BASH_SOURCE[0]%/*}/setting.sh"; setting_get syncMaxRemovedPercent 2>/dev/null || true)
  [[ "$v" =~ ^[0-9]+$ ]] || v=1
  printf '%s\n' "$v"
}

parity_limit_default() {   # parity_limit_default <files in the share>
  local floor pct n
  floor=$(parity_limit_floor); pct=$(parity_limit_percent)
  n=$(( ${1:-0} * pct / 100 ))
  [ "$n" -gt "$floor" ] || n=$floor
  printf '%s\n' "$n"
}

parity_edit() {   # parity_edit <file> <rel> [<value>]: drop the lines of <rel> (limits) or write rel<TAB>value; skip uses parity_add/del
  local f=$1 rel=$2 tmp
  mkdir -p "$(dirname "$f")"
  tmp=$f.tmp-$$
  { [ ! -r "$f" ] || awk -F'\t' -v r="$rel" '$1 != r' "$f"; [ $# -lt 3 ] || printf '%s\t%s\n' "$rel" "$3"; } > "$tmp"
  mv -f "$tmp" "$f"
}
parity_limit_write() { parity_edit "$(parity_limits_file)" "$1" ${2:+"$2"}; }   # no value = back to the default

parity_skip_add() {
  local f tmp; f=$(parity_skip_file)
  mkdir -p "$(dirname "$f")"
  tmp=$f.tmp-$$
  { [ ! -r "$f" ] || awk -F'\t' -v r="$1" -v d="$2" '!($1 == r && $2 == d)' "$f"; printf '%s\t%s\n' "$1" "$2"; } > "$tmp"
  mv -f "$tmp" "$f"
}
parity_skip_del() {
  local f tmp; f=$(parity_skip_file)
  [ -r "$f" ] || return 0
  tmp=$f.tmp-$$
  awk -F'\t' -v r="$1" -v d="$2" '!($1 == r && $2 == d)' "$f" > "$tmp"
  mv -f "$tmp" "$f"
}
