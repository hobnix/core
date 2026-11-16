#!/usr/bin/env bash
# help: after the installation: web interface language, notifications, optional parts, and a checklist of what is still to set up
# help.de: nach der Installation: Sprache der Weboberfläche, Benachrichtigungen, optionale Teile und eine Checkliste, was noch einzurichten ist
# args: [--language en|de] [--notify <url|none>] [--parts <a,b|none>] [--yes]
# Asks the two things that can be answered right away and shows the rest as a checklist with the command
# for each open item. HS_BIN points tests at a stand-in for the hs dispatcher.
set -euo pipefail
here=$(dirname "$0")
. "$here/lib/ui.sh"
. "$here/lib/machine.sh"
. "$here/lib/vault.sh"
. "$here/lib/pools.sh"
hsbin=${HS_BIN:-$here/lib/hs.sh}
cfg() { HS_CALLER="" bash "$hsbin" config "$@"; }

lang=""; notify=""; parts=""; yes=false
while [ $# -gt 0 ]; do
  case "$1" in
    --language) [ $# -ge 2 ] || exit 1; lang=$2; shift 2 ;;
    --notify)   [ $# -ge 2 ] || exit 1; notify=$2; shift 2 ;;
    --parts)    [ $# -ge 2 ] || exit 1; parts=$2; shift 2 ;;
    --yes)      yes=true; shift ;;
    *) say "usage: hs first-run [--language en|de] [--notify <url|none>] [--parts <a,b|none>] [--yes]"; exit 1 ;;
  esac
done

step "Web interface language"
if [ -z "$lang" ] && [ -t 0 ] && ! $yes; then
  lang=$(choose "Default language of the web interface" en de) || lang=""
fi
if [ -n "$lang" ]; then cfg set language "$lang"; else note "Web interface language unchanged."; fi

step "Notifications"
if [ -z "$notify" ] && [ -t 0 ] && ! $yes; then
  note "A push message tells you when a disk or a backup needs attention (ntfy.sh style address)."
  notify=$(ask "Address (empty to skip):" "")
fi
if [ -n "$notify" ]; then cfg set notifyUrl "$notify"; else note "Notifications unchanged."; fi

step "Core packages"
if bash "$hsbin" pkg install --core; then :; else warn "Some core packages could not be fetched; try again with: hs pkg install --core"; fi

step "Optional parts"
offer=$(bash "$hsbin" sys pkg capabilities 2>/dev/null | awk -F'\t' '$4 == "-"' || true)
if [ -z "$offer" ]; then note "No optional parts are offered (reading the repositories needs the network)."
else
  if [ -z "$parts" ] && [ -t 0 ] && ! $yes; then
    { thead 'Name' 'Needs' 'What'; awk -F'\t' '{ print $1 "\t" $6 "\t" $8 }' <<<"$offer"; } | table
    parts=$(ask "Parts to add (names separated by commas, empty to skip):" "")
  fi
  case "$parts" in
    ""|none) note "No optional parts added; later: hs pkg install <name>." ;;
    *) plan=$(bash "$hsbin" sys pkg bundle plan "$parts" 2>/dev/null) || true
       if ! grep -q $'^status\tok' <<<"$plan"; then warn "$(awk -F'\t' '$1 == "reason" { print $2 }' <<<"$plan")"
       else
         while IFS=$'\t' read -r k v; do case "$k" in step|note) note "$v" ;; warn|danger) warn "$v" ;; esac; done <<<"$plan"
         if $yes || confirm "Install, switch on and rebuild now?"; then
           out=$(bash "$hsbin" sys pkg bundle start "$parts" 2>/dev/null) || true
           unit=$(awk -F'\t' '$1 == "unit" { print $2 }' <<<"$out")
           if [ -n "$unit" ]; then ok "$(t 'Started as a job: hs job follow %s' "$unit")"; else warn "$(awk -F'\t' '$1 == "reason" { print $2 }' <<<"$out")"; fi
         fi
       fi ;;
  esac
fi

step "What is still to do"
check() {   # check <label> <command to run when open> <test...>
  local label=$1 cmd=$2; shift 2
  if "$@" >/dev/null 2>&1; then printf '%s\t%s\t%s\n' "$label" "$(_tr 'done')" "-"; else printf '%s\t%s\t%s\n' "$label" "$(_tr 'open')" "$cmd"; fi
}
main_pool=$(pool_default data 2>/dev/null || pool_default apps 2>/dev/null || true)
pools_ready() {
  local set n
  set=$(pool_names data); [ -n "$set" ] || set=$(pool_names)
  [ -n "$set" ] || return 1
  while IFS= read -r n; do pool_mounted "$n" || return 1; done <<<"$set"
}
has_share() {
  local n
  for n in $(pool_names data); do ls "$(pool_root "$n")/shares" 2>/dev/null | grep -q . && return 0; done
  return 1
}
rows=$(
  check "Storage pools"        "hs pool ${main_pool:-<name>} add" pools_ready
  check "A first share"        "hs share add <name>"         has_share
  check "Domain users"         "hs recipe domain"            machine_has adDomain
  check "Backup disk"          "hs backup init <device>"     bash -c '[ -s "$1" ] || [ -L "$1" ]' _ "${HS_STATE_DIR:-/var/lib/hs}/restic-password"
  # with a vault (secrets of this server) it has to be open for backup, UniFi and the like
  if vault_configured; then check "Vault (secrets)"  "hs unlock"                      vault_is_open; fi
  check "Notifications"       "hs config set notifyUrl <url>" test -s "${HS_STATE_DIR:-/var/lib/hs}/notify-url" -o -s /etc/hs/notify-url
)
open=$(awk -F'	' '$3 != "-"' <<<"$rows" | grep -c . || true)
if [ "$open" -eq 0 ]; then status_line "Setup" "Complete" ok; else status_line "Setup" "$(t '%s item(s) still open' "$open")" warn; fi
{ thead 'What' 'State' 'Command'; printf '%s
' "$rows"; } | table
note "Problems at any time: hs doctor"
