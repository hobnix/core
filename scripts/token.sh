#!/usr/bin/env bash
# help: API tokens for programs (curl, a dashboard, a script): create one (shown once), list them, revoke one
# help.de: API-Token für Programme (curl, ein Dashboard, ein Skript): eines anlegen (wird nur einmal angezeigt), anzeigen, widerrufen
# args: create <name> [--role viewer|app-manager|admin] [--days N] [--owner <user>] | list | --list | revoke <name> [--yes]
# A token belongs to a person and never has more than that person's role (ADR 0012, docs/PLAN-extensions-access.md step 17). It is sent as
# `Authorization: Bearer hn_...` to the web interface; it cannot create tokens, use users, secrets or unlock, and it ends at its expiry (default 90 days,
# at most 365) and when its owner is disabled (checked at least once an hour). Only the sha256 of a token is stored (/var/lib/hs/api-tokens.json, 0600);
# the token itself is printed once, here, and cannot be shown again. The token never goes through an argument or the environment.
# create: --owner is the person it belongs to (default: the local admin, role admin). --cap <role> is the role of whoever asks (the web interface sets it):
#   the token cannot have more. --list (hs sys token list) is the plain form for the interface, one token per line, tab separated:
#   id, name, owner, realm (domain|local), role, created and expires (epoch seconds), state (active|expired). --owner <user> shows one person's tokens.
# Test knobs: HS_TOKEN_FILE, HS_STATE_DIR, HS_ADMIN_USER_FILE, HS_PYTHON.
set -uo pipefail
here=$(dirname "$0")
. "$here/lib/ui.sh"
. "$here/lib/admin.sh"
py=${HS_PYTHON:-python3}
store=("$py" "$here/token_store.py")

usage() {
  note "usage: hs token create <name> [--role viewer|app-manager|admin] [--days N]"
  note "       hs token list"
  note "       hs token revoke <name> [--yes]"
  exit 1
}
interactive() { [ -t 0 ] && [ -t 1 ] && [ -z "${HS_CALLER:-}" ] || [ -n "${HS_GUIDED_TTY:-}" ]; }

cmd=${1:-}; [ $# -eq 0 ] || shift
case "$cmd" in
  --list)
    owner=""; [ "${1:-}" != --owner ] || owner=${2:-}
    if [ -n "$owner" ]; then "${store[@]}" list --owner "$owner"; else "${store[@]}" list; fi ;;
  list)
    out=$("${store[@]}" list) || fail "$(t 'The token list cannot be read.')"
    if [ -z "$out" ]; then note "$(t 'No tokens yet. Create one: hs token create <name>')"; exit 0; fi
    {
      thead 'Name' 'Id' 'Owner' 'Role' 'Expires' 'State'
      while IFS=$'\t' read -r id name owner _ role _ exp state; do
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$id" "$owner" "$role" "$(date -d "@$exp" +%F 2>/dev/null || echo "$exp")" "$state"
      done <<<"$out"
    } | table ;;
  create)
    name=${1:-}; [ $# -eq 0 ] || shift
    [ -n "$name" ] && [ "${name#-}" = "$name" ] || usage
    role=viewer; days=90; owner=""; cap=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --role) role=${2:-}; shift 2 || usage ;;
        --days) days=${2:-}; shift 2 || usage ;;
        --owner) owner=${2:-}; shift 2 || usage ;;
        --cap) cap=${2:-}; shift 2 || usage ;;
        *) usage ;;
      esac
    done
    case "$days" in ''|*[!0-9]*) fail "$(t 'The days are a number (1 to 365).')" ;; esac
    adm=$(admin_user)
    realm=domain
    if [ -z "$owner" ]; then owner=$adm; cap=${cap:-admin}; fi
    [ "$owner" != "$adm" ] || realm=local
    args=(create --name "$name" --owner "$owner" --realm "$realm" --role "$role" --days "$days")
    [ -z "$cap" ] || args+=(--cap "$cap")
    errf=$(mktemp)
    if ! out=$("${store[@]}" "${args[@]}" 2>"$errf"); then
      msg=$(cat "$errf"); rm -f "$errf"; fail "${msg:-$(t 'The token could not be created.')}"
    fi
    rm -f "$errf"
    IFS=$'\t' read -r _ token tid exp <<<"$out"
    if [ -n "${HS_PLAIN:-}" ]; then printf 'token\t%s\t%s\t%s\n' "$token" "$tid" "$exp"; exit 0; fi
    ok "$(t 'Token %s created for %s (%s).' "$name" "$owner" "$role")"
    kv "$(t 'Token')" "$token"
    note "$(t 'Copy it now: it is shown only once and only its hash is kept.')"
    note "$(t 'Use it like this: curl -H "Authorization: Bearer <token>" http://<server>:8480/api/sys/status')"
    note "$(t 'It ends on %s. Revoke it earlier: hs token revoke %s' "$(date -d "@$exp" +%F 2>/dev/null || echo "$exp")" "$name")" ;;
  revoke)
    name=${1:-}; [ $# -eq 0 ] || shift
    [ -n "$name" ] || usage
    yes=false; owner=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --yes) yes=true; shift ;;
        --owner) owner=${2:-}; shift 2 || usage ;;
        *) usage ;;
      esac
    done
    "${store[@]}" find "$name" >/dev/null || fail "$(t 'There is no token named %s.' "$name")"
    if [ "$yes" != true ]; then
      interactive || fail "$(t 'Nothing is revoked without a terminal unless you type the name: add --yes')"
      warn "$(t 'Every program that uses the token %s stops working at once.' "$name")"
      confirm_name "$name" "$(t 'the token name')" || fail "$(t 'cancelled')"
    fi
    if [ -n "$owner" ]; then "${store[@]}" revoke "$name" --owner "$owner" || fail "$(t 'There is no token named %s.' "$name")"
    else "${store[@]}" revoke "$name" || fail "$(t 'There is no token named %s.' "$name")"; fi
    ok "$(t 'Token %s revoked.' "$name")" ;;
  *) usage ;;
esac
