#!/usr/bin/env bash
# help: after the installation: web interface language, notifications, what the server is for, and a checklist of what is still to set up
# help.de: nach der Installation: Sprache der Weboberfläche, Benachrichtigungen, wofür der Server da ist und eine Checkliste, was noch einzurichten ist
# args: [--language en|de] [--notify <url|none>] [--blueprint <name> | --parts <a,b|none> | --core-only] [--yes]
# Asks the two things that can be answered right away and shows the rest as a checklist with the command
# for each open item. HS_BIN points tests at a stand-in for the hs dispatcher.
# What the server is for is one of: only the core, one blueprint, or parts one by one. The default is what hs-install recorded in
# <HS_STATE_DIR or /var/lib/hs>/setup-choice; once a choice is carried out the record says done. Nothing is installed without a plan.
set -euo pipefail
here=$(dirname "$0")
. "$here/lib/ui.sh"
. "$here/lib/machine.sh"
. "$here/lib/vault.sh"
. "$here/lib/pools.sh"
. "$here/lib/setup-choice.sh"
hsbin=${HS_BIN:-$here/lib/hs.sh}
cfg() { HS_CALLER="" bash "$hsbin" config "$@"; }

lang=""; notify=""; parts=""; yes=false; mode=""; blueprint=""; choices=0
while [ $# -gt 0 ]; do
  case "$1" in
    --language) [ $# -ge 2 ] || exit 1; lang=$2; shift 2 ;;
    --notify)   [ $# -ge 2 ] || exit 1; notify=$2; shift 2 ;;
    --parts)    [ $# -ge 2 ] || exit 1; parts=$2; mode=parts; choices=$((choices + 1)); shift 2 ;;
    --blueprint) [ $# -ge 2 ] || exit 1; blueprint=$2; mode=blueprint; choices=$((choices + 1)); shift 2 ;;
    --core-only) mode=core; choices=$((choices + 1)); shift ;;
    --yes)      yes=true; shift ;;
    *) say "usage: hs first-run [--language en|de] [--notify <url|none>] [--blueprint <name> | --parts <a,b|none> | --core-only] [--yes]"; exit 1 ;;
  esac
done
[ "$choices" -le 1 ] || fail "Give only one of --blueprint, --parts and --core-only."
[ "$mode" != blueprint ] || setup_name_ok "$blueprint" || fail "That is not a blueprint name (lowercase letters, digits and dashes)."

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

step "What is this server for"
choice_file=${HS_STATE_DIR:-/var/lib/hs}/setup-choice
tty=false; if [ -t 0 ] && [ -t 1 ]; then tty=true; fi
clean() { LC_ALL=C tr -d '\000-\010\013-\037\177'; }   # a blueprint is untrusted: no control character reaches the terminal (tab and newline stay)
reason_of() { awk -F'\t' '$1 == "reason" { print $2; exit }' <<<"$1"; }
choice_done() {   # the recorded choice was carried out: it is not offered as the default again
  [ -e "$choice_file" ] || return 0
  { setup_choice_write "$choice_file" "done" -; } 2>/dev/null || warn "The setup choice could not be marked as done (run with sudo)."
}

blueprints() {   # the names of the blueprints offered for the role of this server (no role = homeserver)
  local role=""
  if machine_has role; then role=$(machine_get role 2>/dev/null || true); fi
  bash "$hsbin" sys blueprint list 2>/dev/null </dev/null | clean |
    awk -F'\t' -v r="${role:-homeserver}" '$6 != "waits" && $1 ~ /^[a-z0-9][a-z0-9-]*$/ && index("," $4 ",", "," r ",") { print $1 }' || true
}

apply_blueprint() {   # the plan, the typed name or one question, then ONE background job; never stops the checklist
  local name=$1 plan rc=0 kind text c out unit
  local names=() args=()
  plan=$(bash "$hsbin" sys blueprint plan apply "$name" 2>/dev/null </dev/null | clean) || rc=$?
  if [ "$rc" != 0 ] || ! grep -q $'^status\tok' <<<"$plan"; then
    c=$(reason_of "$plan"); warn "${c:-The blueprint could not be planned.}"
    note "$(t 'Later: hs blueprint apply %s' "$name")"; return 0
  fi
  { thead 'Step' 'What' 'Here'
    awk -F'\t' '$1 == "part" { printf "%s\t%s\t%s\n", $3, ($4 == "-" ? "" : $4), $6 }' <<<"$plan"
  } | table
  while IFS=$'\t' read -r kind text; do
    case "$kind" in step|note) note "$text" ;; warn) warn "$text" ;; esac
  done <<<"$plan"
  while IFS= read -r c; do [ -z "$c" ] || names+=("$c"); done < <(awk -F'\t' '$1 == "confirm_name" { print $2 }' <<<"$plan")
  if $yes; then   # --yes never types a name for the person
    if [ ${#names[@]} -gt 0 ]; then warn "$(t 'This blueprint asks for a typed name: run hs blueprint apply %s in a terminal.' "$name")"; return 0; fi
  elif ! $tty; then
    note "$(t 'Applying a blueprint asks first: run hs blueprint apply %s in a terminal.' "$name")"; return 0
  else
    for c in ${names[@]+"${names[@]}"}; do confirm_name "$c" "$(t 'the blueprint or Docker')" || { note "Nothing changed."; return 0; }; done
    [ ${#names[@]} -gt 0 ] || confirm "$(t 'Apply the blueprint %s now?' "$name")" || { note "Nothing changed."; return 0; }
  fi
  for c in ${names[@]+"${names[@]}"}; do args+=(--confirm "$c"); done
  out=$(bash "$hsbin" sys blueprint start apply "$name" ${args[@]+"${args[@]}"} 2>/dev/null </dev/null | clean) || true
  unit=$(awk -F'\t' '$1 == "unit" { print $2; exit }' <<<"$out")
  if [ -n "$unit" ]; then ok "$(t 'Started as a job: hs job follow %s' "$unit")"; choice_done
  else c=$(reason_of "$out"); warn "${c:-The blueprint could not be started.}"; fi
}

add_parts() {   # single capability packages, installed with what they require in one job
  local offer plan out unit k v
  offer=$(bash "$hsbin" sys pkg capabilities 2>/dev/null | awk -F'\t' '$4 == "-"' || true)
  if [ "$parts" = none ]; then note "No optional parts added; later: hs pkg install <name>."; choice_done; return 0; fi
  if [ -z "$offer" ]; then note "No optional parts are offered (reading the repositories needs the network)."; return 0; fi
  if [ -z "$parts" ] && $tty && ! $yes; then
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
           if [ -n "$unit" ]; then ok "$(t 'Started as a job: hs job follow %s' "$unit")"; choice_done
           else warn "$(awk -F'\t' '$1 == "reason" { print $2 }' <<<"$out")"; fi
         fi
       fi ;;
  esac
}

if [ -z "$mode" ]; then
  recorded=$(setup_choice_read "$choice_file")
  rec_kind=${recorded%% *}; rec_name=${recorded#* }
  case "$rec_kind" in blueprint|parts|core) ;; *) rec_kind=""; rec_name="" ;; esac
  case "$rec_kind" in
    blueprint) note "$(t 'Chosen at the installation: the blueprint %s' "$rec_name")" ;;
    parts) note "$(t 'Chosen at the installation: the parts %s' "$rec_name")" ;;
    core) note "Chosen at the installation: only the core." ;;
  esac
  if $tty && ! $yes; then
    options=()   # the recorded choice comes first
    case "$rec_kind" in blueprint) options+=("blueprint $rec_name") ;; parts) options+=("choose parts") ;; esac
    options+=("core only")
    while IFS= read -r b; do
      if [ -n "$b" ] && { [ "$rec_kind" != blueprint ] || [ "$b" != "$rec_name" ]; }; then options+=("blueprint $b"); fi
    done < <(blueprints)
    [ "$rec_kind" = parts ] || options+=("choose parts")
    pick=$(choose "What should this server be set up for?" "${options[@]}") || pick=""
    case "$pick" in
      "core only") mode=core ;;
      "choose parts") mode=parts; [ "$rec_kind" != parts ] || parts=$rec_name ;;
      "blueprint "*) mode=blueprint; blueprint=${pick#blueprint } ;;
    esac
  elif $yes && [ -n "$rec_kind" ]; then
    mode=$rec_kind
    case "$mode" in blueprint) blueprint=$rec_name ;; parts) parts=$rec_name ;; esac
  fi
fi
case "$mode" in
  blueprint) apply_blueprint "$blueprint" ;;
  parts) add_parts ;;
  core) note "Only the core: nothing else is installed."; choice_done ;;
  *) note "Nothing chosen; later: hs blueprint list, or hs pkg install <name>." ;;
esac

step "What is still to do"
# i18n: Set up notifications|Storage pool|A first share|Setup finished|Vault (secrets)|Optional parts (capabilities)|Wildcard DNS for the gateway proxy
# the same list as the Setup page and `hs sys setup list` (one source: setup-list.sh); "finished" is the person's own decision
rows=$(bash "$here/setup-list.sh" --list | awk -F'\t' '$1 != "finished" { print $3 "\t" $2 "\t" $4 }' | while IFS=$'\t' read -r label state cmd; do
  printf '%s\t%s\t%s\n' "$(_tr "$label")" "$(_tr "$state")" "$cmd"
done)
open=$(awk -F'	' '$3 != "-"' <<<"$rows" | grep -c . || true)
if [ "$open" -eq 0 ]; then status_line "Setup" "Complete" ok; else status_line "Setup" "$(t '%s item(s) still open' "$open")" warn; fi
{ thead 'What' 'State' 'Command'; printf '%s
' "$rows"; } | table
note "Problems at any time: hs doctor"
