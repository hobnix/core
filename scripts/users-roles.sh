#!/usr/bin/env bash
# help: create the three groups of the web interface roles (viewer, app manager, admin) in the domain, after a plan and the typed domain name
# help.de: die Gruppen der Rollen der Weboberfläche (Betrachter, App-Verwalter, Admin) in der Domäne anlegen, nach Plan und getipptem Domänennamen
# args: [--confirm <domain>] [--dry-run]
# ADR 0012 and D2 of docs/PLAN-extensions-access.md: people get a role from the groups hn-viewers and hn-app-managers (names: the settings
# webViewerGroup and webAppManagerGroup) and Domain Admins. This command makes the two missing groups. It never creates anything on its own:
# it shows what is missing, and only the typed name of the domain (or --confirm <domain> for a script) lets it go on, also when the domain
# is brand new. Without a domain (no adDomain) the local account is the admin and there is nothing to create.
# HS_MANAGE_USERS points tests at a stand-in for manage-users.sh; HS_USERS_BACKEND and HS_MACHINE_FILE are the usual knobs.
set -euo pipefail
here=$(dirname "$0")
. "$here/lib/ui.sh"
. "$here/lib/machine.sh"
. "$here/lib/setting.sh"
. "$here/lib/users-backend.sh"
mu=${HS_MANAGE_USERS:-$here/manage-users.sh}

usage() {
  say "usage: hs group roles [--dry-run] [--confirm <domain>]"
  exit 1
}
dry=false; confirm_with=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry=true; shift ;;
    --confirm) [ $# -ge 2 ] || usage; confirm_with=$2; shift 2 ;;
    *) usage ;;
  esac
done

if [ "$(users_backend)" != ad ]; then
  note "$(t 'This server has no domain: the local account is the admin of the web interface. Nothing to create.')"
  exit 0
fi

viewers=$(setting_get webViewerGroup 2>/dev/null || true); viewers=${viewers:-hn-viewers}
managers=$(setting_get webAppManagerGroup 2>/dev/null || true); managers=${managers:-hn-app-managers}
for g in "$viewers" "$managers"; do
  [[ "$g" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,62}$ ]] || fail "$(t "Invalid group name '%s': letters, digits, . _ -" "$g")"
done
domain=$(machine_get adDomain.realm 2>/dev/null | tr -d ' \r\n' || true)
[ -n "$domain" ] || fail "$(t 'No domain name found (adDomain.realm in machine.toml).')"

existing=$(bash "$mu" --groups | cut -f1)
missing=(); rows=""
for pair in "app-manager:$managers" "viewer:$viewers"; do
  role=${pair%%:*}; g=${pair#*:}
  if grep -qixF -- "$g" <<<"$existing"; then state=$(t 'exists')
  else state=$(t 'will be created'); missing+=("$g"); fi
  rows+=$(printf '%s	%s	%s
' "$role" "$g" "$state")$'
'
done
step "$(t 'Groups for the roles of the web interface')"
{
  thead 'Role' 'Group' 'State'
  printf 'admin	Domain Admins	%s
' "$(t 'the domain needs it')"
  printf '%s' "$rows"
} | table

if [ ${#missing[@]} -eq 0 ]; then
  ok "$(t 'All groups exist. Put people into them with: hs user <user> join <group>')"
  exit 0
fi
note "$(t "Created in the domain '%s': %s. They start empty: nobody can sign in through them until you add members." "$domain" "${missing[*]}")"
if $dry; then
  note "$(t 'Dry run: nothing was created.')"
  exit 0
fi
if [ -z "$confirm_with" ]; then
  [ -t 0 ] && [ -t 1 ] || fail "$(t 'Nothing is created without the typed domain name: run this on a terminal or give --confirm <domain>.')"
  confirm_name "$domain" "$(t 'the domain')" || fail "$(t 'cancelled')"
elif [ "$confirm_with" != "$domain" ]; then
  fail "$(t "The name does not match the domain '%s'. Nothing was created." "$domain")"
fi
for g in "${missing[@]}"; do
  bash "$mu" --group-add "$g"
done
ok "$(t 'The role groups are ready.')"
next_step "hs user <user> join $managers"
