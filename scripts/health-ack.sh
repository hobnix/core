#!/usr/bin/env bash
# help: silence a health problem until it clears (acknowledge), and lift a pause the health check set
# help.de: ein Gesundheitsproblem stummschalten, bis es verschwindet (quittieren), und eine Pause aufheben, die der Health-Check gesetzt hat
# args: ack [<id> [--for <time>] [--note <text>]] | unack <id> | list-acks | resume
# ack            list the active problems with their ids (the id is the key the health check works with)
# ack <id>       acknowledge: the problem is no longer sent or counted. It stays silent until the problem has cleared (the
#                health check drops the entry then, and a later return is reported again). Only active ids are accepted.
#                --for 7d (m, h, d, w): the acknowledgement ends by itself after that time even if the problem stays. --note: why.
#                An acknowledgement also ends when the problem gets worse: the key changes (disk:sda:smart -> disk:sda:smart-failing),
#                so the worse problem is a new one and is sent.
# unack <id>     take the acknowledgement back
# list-acks      the acknowledgements: id, time, until (- = until it clears), who, note (- when empty); machine-readable when not on a terminal
# resume         lift the pause of the parity sync, scrub and cache mover (setting autoMitigate) and
#                acknowledge the problems that caused it, so the next health run does not pause again. Fix the cause first.
# The list is /var/lib/hs/health-ack (id TAB time TAB until TAB who TAB note, columns are only added at the end, - = empty; rows of two columns are older ones); the health check reads it. Test knobs: HS_ACK_FILE, HS_HEALTH_CHECK, HS_BULK_PAUSE.
set -uo pipefail
here=$(dirname "$0")
. "$here/lib/ui.sh"
. "$here/lib/bulklock.sh"
. "$here/lib/event.sh"
ack_file=${HS_ACK_FILE:-/var/lib/hs/health-ack}
hc=${HS_HEALTH_CHECK:-$here/health-check.sh}

usage() { say "usage: hs health ack [<id> [--for 7d] [--note <text>]] | hs health unack <id> | hs health list-acks | hs health resume"; exit 1; }
can_write() { mkdir -p "$(dirname "$ack_file")" 2>/dev/null && { [ -w "$ack_file" ] || { [ ! -e "$ack_file" ] && [ -w "$(dirname "$ack_file")" ]; }; }; }
is_acked() { [ -r "$ack_file" ] && awk -F'	' -v k="$1" -v now="$(date +%s)" '$1 == k && !($3 ~ /^[0-9]+$/ && $3 + 0 < now) { f = 1 } END { exit !f }' "$ack_file"; }
active() { bash "$hc" --list 2>/dev/null || true; }   # id TAB text TAB acked|- (then since, channels: ignored here)

who_am_i() { local w=${HS_ACTOR:-${SUDO_USER:-$(id -un 2>/dev/null || echo root)}}; w=$(printf '%s' "$w" | tr -c 'A-Za-z0-9._@ -' '_' | cut -c1-80); echo "${w:--}"; }
clean_note() { local n; n=$(printf '%s' "$1" | tr '\t\r\n' '   ' | cut -c1-200); echo "${n:--}"; }
json_str() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }

add_ack() {   # <id> [until-epoch|-] [note]
  can_write || fail "Cannot write $ack_file: run it with sudo."
  is_acked "$1" && return 0
  local who note; who=$(who_am_i); note=$(clean_note "${3:-}")
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$(date +%s)" "${2:--}" "$who" "$note" >> "$ack_file"
  event_emit health.acked "$1" "Acknowledged by $who" --payload "{\"who\":\"$(json_str "$who")\",\"until\":\"${2:--}\"}"
}

cmd=${1:-ack}; [ $# -eq 0 ] || shift
case "$cmd" in
  ack)
    id=${1:-}; [ $# -eq 0 ] || shift
    until_at=- ; note_txt=
    while [ $# -gt 0 ]; do
      case "$1" in
        --for) [ $# -ge 2 ] || usage
               [[ "$2" =~ ^([0-9]{1,4})([mhdw])$ ]] || fail "--for needs a time such as 90m, 12h, 7d or 2w."
               case "${BASH_REMATCH[2]}" in m) mul=60 ;; h) mul=3600 ;; d) mul=86400 ;; w) mul=604800 ;; esac
               [ "${BASH_REMATCH[1]}" -gt 0 ] || fail "--for needs a time above zero."
               until_at=$(( $(date +%s) + ${BASH_REMATCH[1]} * mul )); shift 2 ;;
        --note) [ $# -ge 2 ] || usage; note_txt=$2; shift 2 ;;
        *) usage ;;
      esac
    done
    if [ -z "$id" ]; then
      out=$(active)
      if [ -z "$out" ]; then ok "No problems found."; exit 0; fi
      if [ -t 1 ] && [ -z "${HS_CALLER:-}" ] && [ -z "${HS_PLAIN:-}" ]; then
        { thead 'Id' 'Problem' 'State'
          awk -F'\t' -v OFS='\t' '{ print $1, $2, ($3 == "acked" ? "acknowledged" : "open") }' <<<"$out"
        } | table
        note "Silence one until it clears: hs health ack <id>"
      else
        printf '%s\n' "$out"
      fi
      exit 0
    fi
    if ! awk -F'\t' -v k="$id" '$1 == k { f = 1 } END { exit !f }' <<<"$(active)"; then
      is_acked "$id" || fail "$id is not an active problem. List the ids: hs health ack"
    fi
    add_ack "$id" "$until_at" "$note_txt"
    if [ "$until_at" = - ]; then ok "Acknowledged $id: silent until it clears."; else ok "Acknowledged $id: silent until $(date -d "@$until_at" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "$until_at") or until it clears."; fi
    ;;
  unack)
    id=${1:-}; [ -n "$id" ] || usage
    can_write || fail "Cannot write $ack_file: run it with sudo."
    is_acked "$id" || fail "$id is not acknowledged."
    awk -F'\t' -v k="$id" '$1 != k' "$ack_file" > "$ack_file.tmp" && mv "$ack_file.tmp" "$ack_file"
    event_emit health.unacked "$id" "Acknowledgement taken back by $(who_am_i)" --payload '{"reason":"taken back"}'
    ok "Back in the reports: $id"
    ;;
  list-acks)
    [ $# -eq 0 ] || usage
    tty_out=false; { [ -t 1 ] && [ -z "${HS_CALLER:-}" ] && [ -z "${HS_PLAIN:-}" ]; } && tty_out=true
    rows=$(awk -F'\t' -v now="$(date +%s)" -v OFS='\t' 'NF && $1 != "" && !($3 ~ /^[0-9]+$/ && $3 + 0 < now) { print $1, ($2 == "" ? "-" : $2), ($3 == "" ? "-" : $3), ($4 == "" ? "-" : $4), ($5 == "" ? "-" : $5) }' "$ack_file" 2>/dev/null || true)
    if [ -z "$rows" ]; then $tty_out && note "Nothing is acknowledged."; exit 0; fi
    if $tty_out; then
      { thead 'Id' 'Since' 'Until' 'By' 'Note'
        while IFS=$'\t' read -r i t u w n; do
          [ "$t" = - ] || t=$(date -d "@$t" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "$t")
          if [ "$u" = - ]; then u="it clears"; else u=$(date -d "@$u" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "$u"); fi
          printf '%s\t%s\t%s\t%s\t%s\n' "$i" "$t" "$u" "$w" "$n"
        done <<<"$rows"
      } | table
    else
      printf '%s\n' "$rows"
    fi
    ;;
  resume)
    if [ ! -e "$bulk_pause" ]; then note "Nothing is paused."; exit 0; fi
    keys=$(sed -n 's/^keys=//p' "$bulk_pause" | head -n1)
    can_write || fail "Cannot write $ack_file: run it with sudo."
    IFS=, read -r -a ks <<<"$keys"
    for k in "${ks[@]}"; do [ -z "$k" ] || add_ack "$k"; done
    rm -f "$bulk_pause"
    ok "Lifted: the parity sync, the scrub and the cache mover run again."
    [ -z "$keys" ] || note "Acknowledged: ${keys//,/, }. Unsilence with: hs health unack <id>"
    ;;
  *) usage ;;
esac
