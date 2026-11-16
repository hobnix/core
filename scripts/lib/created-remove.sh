# shellcheck shell=bash
# Remove what the created ledger lists (docs/PLAN-app-lifecycle.md Q3). Sourced by scripts/apps-recover.sh (a failed install, step 9) and, later, by
# Remove (step 11). Needs lib/created.sh and lib/ui.sh already sourced. The ledger lists ONLY what a run itself created; this never touches
# anything else, and an app without a ledger is refused, never guessed at.
#
#   created_plan <instance> [yes]            tab lines, one per ledger line, in the order they are removed (the ledger in reverse):
#                                            kind id detail state action text      state = there|gone|unknown (re-checked now),
#                                            action = remove|forget|keep|skip      (data kinds are `keep` unless the caller says yes = delete)
#   created_remove_all <instance> [yes]      do it (yes = also delete the data, default no); each line is checked again first.
#                                            Returns 0 when nothing the ledger lists is left (kept data does not count), 1 otherwise.
# Kinds: service (descriptor), reservation (UniFi fixed address, detail = mac), container (instance; its own disk goes with it), share and volume
# (DATA: kept unless asked). Test knobs: HS_INCUS, HS_SERVICES (services.sh), HS_UNIFI (unifi.sh), HS_STATE_DIR.
_cr_here=$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)

_cr_data() { case "$1" in share|volume) return 0 ;; *) return 1 ;; esac; }
_cr_text() {   # what a line is, in words
  case "$1" in
    service)     echo "the service $2 (its description; the route follows with hs services apply)" ;;
    reservation) echo "the fixed address $2 in UniFi" ;;
    container)   echo "the instance $2 with its snapshots" ;;
    share)       echo "the share $2 (data; shares are kept: hs share $2 delete removes one)" ;;
    volume)      echo "the volume $2 (data)" ;;
    *)           echo "$1 $2" ;;
  esac
}

created_plan() {   # created_plan <instance> [yes]
  local inst=$1 del=${2:-no} kind id detail st action rc
  [ -f "$(created_file "$inst")" ] || return 1
  while IFS=$'\t' read -r kind id detail; do
    rc=0; created_check "$kind" "$id" "$detail" || rc=$?
    case "$rc" in 0) st=there ;; 1) st=gone ;; *) st=unknown ;; esac
    case "$st" in
      gone) action=forget ;;
      unknown) action=skip ;;
      *) if [ "$kind" = share ] || { _cr_data "$kind" && [ "$del" != yes ]; }; then action=keep; else action=remove; fi ;;   # a share is never removed here
    esac
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$kind" "$id" "$detail" "$st" "$action" "$(_cr_text "$kind" "$id")"
  done < <(created_list "$inst" | awk -F'	' '{ l[NR] = $0; v[NR] = ($1 == "volume") } END { for (i = NR; i >= 1; i--) if (!v[i]) print l[i]; for (i = NR; i >= 1; i--) if (v[i]) print l[i] }')
}

_cr_one() {   # _cr_one <kind> <id> <detail>: remove one thing, 0 = gone now
  local kind=$1 id=$2 detail=$3
  case "$kind" in
    service)     bash "${HS_SERVICES:-$_cr_here/services.sh}" remove "$id" >/dev/null 2>&1 ;;
    reservation) [ "$detail" != - ] && bash "${HS_UNIFI:-$_cr_here/unifi.sh}" clear-ip "$detail" >/dev/null 2>&1 ;;
    container)   "${HS_INCUS:-incus}" delete -f "$id" >/dev/null 2>&1 ;;
    volume)      [ "$detail" != - ] && "${HS_INCUS:-incus}" storage volume delete "$detail" "$id" >/dev/null 2>&1 ;;
    *)           return 1 ;;
  esac
}

created_remove_all() {   # created_remove_all <instance> [yes]
  local inst=$1 del=${2:-no} kind id detail st action left=0 text
  [ -f "$(created_file "$inst")" ] || { warn "There is no record of what was created for $inst: nothing is removed by guesswork."; return 1; }
  while IFS=$'\t' read -r kind id detail st action text; do
    case "$action" in
      forget) note "Already gone: $text"; created_drop "$kind" "$id" "$inst" ;;
      skip)   warn "Cannot tell whether $text is still there: left alone."; left=$((left + 1)) ;;
      keep)   note "Kept (data): $text"; created_drop "$kind" "$id" "$inst" ;;
      remove)
        if _cr_one "$kind" "$id" "$detail"; then ok "Removed $text"; created_drop "$kind" "$id" "$inst"
        else warn "Could not remove $text."; left=$((left + 1)); fi ;;
    esac
  done < <(created_plan "$inst" "$del")
  [ "$left" -eq 0 ]
}
