#!/usr/bin/env bash
# help: file manager on the command line: places, folder lists, folder sizes, and copy, move, delete as plan + typed confirmation + background job
# help.de: Dateimanager auf der Kommandozeile: Orte, Ordnerlisten, Ordnergrößen, und Kopieren, Verschieben, Löschen als Plan + getippte Bestätigung + Hintergrundjob
# args: locations | ls <loc> [--path P] | du <loc> [--path P] [--no-wait] | copy <from> <to> <name>... [--path P] [--to-path Q] | move <from> <to> <name>... | delete <loc> <name>... [--permanent]
# Thin wrapper over `hs sys fm ...` (scripts/fm.sh, docs/PLAN-storage-nas.md D4): every rule is enforced there. The reads print for people; the changes show the plan first,
# ask for the typed confirmation and start a background job. Names are inside --path (default: the top of the place), never paths with a slash.
#   --conflict skip|rename|newer|overwrite   --verify size|checksum   (copy and move)    --confirm TEXT: the typed text, for a script (no terminal to ask on)
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib/ui.sh"
fmsh() { bash "$here/fm.sh" "$@"; }

usage() {
  line "usage: hs fm locations                                  the places a pane of the web file manager can show"
  line "       hs fm ls <place> [--path P]                      one folder (first 500 entries)"
  line "       hs fm du <place> [--path P] [--no-wait]          the size of a folder (it may wake disks: a background job, the answer is kept)"
  line "       hs fm copy <from> <to> <name>... [--path P] [--to-path Q] [--conflict skip|rename|newer|overwrite] [--verify size|checksum]"
  line "       hs fm move <from> <to> <name>...                 the same, and the source is removed once a file is checked"
  line "       hs fm delete <place> <name>... [--path P] [--permanent]   into the trash (14 days); --permanent = for good"
  line "A place is an id from 'hs fm locations', e.g. disk:data-04, pool:tank, share:media."
  exit 1
}

# val <key> <<< output: the first value of a key
val() { awk -F'\t' -v k="$1" '$1 == k { print $2; exit }'; }
# asked: the answer of a sys fm call; a refusal ends the command with its reason
need_ok() {   # need_ok <output>
  case "$(printf '%s\n' "$1" | val status)" in ok|done) ;; *) fail "$(printf '%s\n' "$1" | val reason)" ;; esac
}
human() { numfmt --to=iec --suffix=B "$1" 2>/dev/null || echo "$1 B"; }

cmd_locations() {
  local out; out=$(fmsh locations 2>&1) || true
  need_ok "$out"
  if [ "$(printf '%s\n' "$out" | val locked)" = yes ]; then warn "The storage is locked. Unlock it first (hs unlock)."; return 0; fi
  [ "$(printf '%s\n' "$out" | val write)" = yes ] || note "The file manager is read only until you allow it: hs config set fileManagerWrite true"
  { printf 'Place\tKind\tName\tFilesystem\tSize\tFree\tWritable\n'
    printf '%s\n' "$out" | awk -F'\t' '$1 == "loc" { printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n", $2, $3, $4, $5, $6, $7, $8 }' \
      | while IFS=$'\t' read -r id kind label fs size free w; do
          printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$kind" "$label" "$fs" "$(human "$size")" "$( [ "$free" = - ] && echo - || human "$free")" "$w"
        done
  } | table
}

cmd_ls() {
  [ $# -ge 1 ] || usage
  local out; out=$(fmsh ls "$@" 2>&1) || true
  need_ok "$out"
  { printf 'Type\tSize\tModified\tName\tFlags\n'
    printf '%s\n' "$out" | awk -F'\t' '$1 == "row" { printf "%s\t%s\t%s\t%s\t%s\n", $2, $3, $4, $5, $7 }' \
      | while IFS=$'\t' read -r ty by mt nm fl; do
          printf '%s\t%s\t%s\t%s\t%s\n' "$ty" "$( [ "$ty" = d ] && echo - || human "$by")" "$(date -d "@$mt" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "$mt")" "$nm" "$fl"
        done
  } | table
  [ "$(printf '%s\n' "$out" | awk -F'\t' '$1 == "cursor" { print "more" }')" != more ] || note "The folder has more entries than shown."
}

cmd_du() {
  [ $# -ge 1 ] || usage
  local wait=yes a args=() out i
  for a in "$@"; do if [ "$a" = --no-wait ]; then wait=no; else args+=("$a"); fi; done
  for ((i = 0; i < 300; i++)); do
    out=$(fmsh du "${args[@]}" 2>&1) || true
    need_ok "$out"
    [ "$(printf '%s\n' "$out" | val pending)" = yes ] || break
    if [ "$wait" = no ]; then ok "Measuring in the background ($(printf '%s\n' "$out" | val unit)). Ask again with the same command."; return 0; fi
    [ "$i" -gt 0 ] || note "Measuring in the background: this reads every file entry and can wake sleeping disks."
    sleep 2
  done
  [ "$(printf '%s\n' "$out" | val pending)" != yes ] || fail "Still measuring. Ask again later."
  kv "Files" "$(printf '%s\n' "$out" | val files)"
  kv "Folders" "$(printf '%s\n' "$out" | val folders)"
  kv "Size" "$(human "$(printf '%s\n' "$out" | val bytes)")"
  [ "$(printf '%s\n' "$out" | val partial)" != yes ] || warn "The folder is very big: these numbers are a first part only."
  [ "$(printf '%s\n' "$out" | val cached)" != yes ] || note "From the saved answer: the folder has not changed since."
}

# change <op> <args...>: names and options -> plan, typed confirmation, job
change() {
  local op=$1; shift
  local from="" to="" path="" topath="" conflict="" verify="" permanent=no typed="" names=() pos=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --path)      [ $# -ge 2 ] || usage; path=$2; shift 2 ;;
      --to-path)   [ $# -ge 2 ] || usage; topath=$2; shift 2 ;;
      --conflict)  [ $# -ge 2 ] || usage; conflict=$2; shift 2 ;;
      --verify)    [ $# -ge 2 ] || usage; verify=$2; shift 2 ;;
      --confirm)   [ $# -ge 2 ] || usage; typed=$2; shift 2 ;;
      --permanent) permanent=yes; shift ;;
      -*) usage ;;
      *) pos+=("$1"); shift ;;
    esac
  done
  if [ "$op" = delete ]; then [ "${#pos[@]}" -ge 2 ] || usage; from=${pos[0]}; names=("${pos[@]:1}")
  else [ "${#pos[@]}" -ge 3 ] || usage; from=${pos[0]}; to=${pos[1]}; names=("${pos[@]:2}"); fi
  [ "$permanent" = no ] || [ "$op" = delete ] || fail "--permanent belongs to delete only"
  local -a a=("$op" --from "$from" --path "$path")
  [ -z "$to" ] || a+=(--to "$to" --to-path "$topath")
  [ -z "$conflict" ] || a+=(--conflict "$conflict")
  [ -z "$verify" ] || a+=(--verify "$verify")
  [ "$permanent" = no ] || a+=(--permanent)
  local out
  out=$(printf '%s\0' "${names[@]}" | fmsh plan "${a[@]}" 2>&1) || true
  need_ok "$out"
  step "$(printf '%s\n' "$out" | val heading)"
  local k v
  while IFS=$'\t' read -r k v; do
    case "$k" in
      step) line "$v" ;;
      note) note "$v" ;;
      warn) warn "$v" ;;
    esac
  done <<<"$out"
  kv "Files" "$(printf '%s\n' "$out" | val files)"
  kv "Folders" "$(printf '%s\n' "$out" | val folders)"
  kv "Size" "$(human "$(printf '%s\n' "$out" | val bytes)")"
  local need; need=$(printf '%s\n' "$out" | val confirm_name)
  if [ -z "$need" ] && [ "$op" = delete ]; then need="delete ${#names[@]} item(s)"; fi
  local -a s=("${a[@]}")
  if [ -n "$need" ]; then
    if [ -z "$typed" ]; then
      [ -t 0 ] && [ -t 1 ] || fail "This needs a typed confirmation, and there is no terminal: pass --confirm \"$need\"."
      confirm_name "$need" "this change" || fail "Nothing was changed."
    elif [ "$typed" != "$need" ]; then fail "The confirmation does not match: type \"$need\"."; fi
    # the backend asks for its own confirm_name only when the plan has one
    [ -z "$(printf '%s\n' "$out" | val confirm_name)" ] || s+=(--confirm "$need")
  elif [ -z "$typed" ]; then
    [ -t 0 ] && [ -t 1 ] || fail "This needs a confirmation, and there is no terminal: pass --confirm yes."
    confirm "Start it now?" || fail "Nothing was changed."
  fi
  local res
  res=$(printf '%s\0' "${names[@]}" | fmsh start "${s[@]}" 2>&1) || true
  need_ok "$res"
  ok "Started as a background job: $(printf '%s\n' "$res" | val unit)"
  note "Watch it: hs job log $(printf '%s\n' "$res" | val unit)"
}

cmd=${1:-}; [ $# -eq 0 ] || shift
case "$cmd" in
  locations) cmd_locations ;;
  ls) cmd_ls "$@" ;;
  du) cmd_du "$@" ;;
  copy|move|delete) change "$cmd" "$@" ;;
  *) usage ;;
esac
