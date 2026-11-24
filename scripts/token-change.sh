#!/usr/bin/env bash
# help: create or revoke an API token without asking anything: what would happen (plan), then do it (start)
# help.de: einen API-Token anlegen oder widerrufen, ohne etwas zu fragen: was passieren würde (plan), dann ausführen (start)
# args: plan|start <create <name> [--role R] [--days N] | revoke <name> [--confirm <name>]> --by <user> --cap <role>
# System command (hs sys token plan|start): for the interface and tests. It never asks and prints key<TAB>value lines like ssh-key-change.sh.
# --by is the person who asks (the web interface adds it, with --cap = that person's role; a client never sends them). A token belongs to
# --by and has at most the role --cap. An app-manager or viewer sees and revokes only their own tokens, an admin all.
#   create <name>   --role viewer|app-manager|admin (default viewer), --days 1..365 (default 90). start prints `secret<TAB>token<TAB><token>`: the
#                   one and only time the token is visible; the id and the expiry follow as `id` and `note` lines. The token is made by token_store.py.
#   revoke <name>   RED: the name of the token must be typed (confirm_name = the name). The token stops working at once.
# plan: exit 0 = allowed, 1 = refused. Output: status ok|refused, reason | heading|step|note|warn|danger|command, confirm_name, long<TAB>no.
# Test knobs: HS_TOKEN_FILE, HS_STATE_DIR, HS_ADMIN_USER_FILE, HS_PYTHON.
set -uo pipefail
here=$(dirname "$0")
. "$here/lib/admin.sh"
py=${HS_PYTHON:-python3}
export HS_PLAIN=1

refuse() { printf 'status\trefused\nreason\t%s\n' "$1"; exit 1; }
. "$here/lib/refuse-code.sh"   # refuse_code (ADR 0028)

verb=${1:-}; action=${2:-}; name=${3:-}
case "$verb" in plan|start) ;; *) echo "usage: token-change.sh plan|start <create <name>|revoke <name>> --by <user> --cap <role>" >&2; exit 1 ;; esac
case "$action" in create|revoke) ;; *) refuse_code action.unknown "unknown action (create or revoke)" ;; esac
[ $# -ge 3 ] || refuse_code token.name-missing "give the name of the token"
shift 3
role=viewer; days=90; by=""; cap=""; confirm=""
while [ $# -gt 0 ]; do
  case "$1" in
    --role) role=${2:-}; shift 2 || refuse_code token.value-missing "an option needs a value" ;;
    --days) days=${2:-}; shift 2 || refuse_code token.value-missing "an option needs a value" ;;
    --by) by=${2:-}; shift 2 || refuse_code token.value-missing "an option needs a value" ;;
    --cap) cap=${2:-}; shift 2 || refuse_code token.value-missing "an option needs a value" ;;
    --confirm) confirm=${2:-}; shift 2 || refuse_code token.value-missing "an option needs a value" ;;
    *) refuse_code option.unknown "unknown option" ;;
  esac
done
[ -n "$by" ] && [ -n "$cap" ] || refuse_code token.caller-missing "who asks is missing"
case "$cap" in viewer|app-manager|admin) ;; *) refuse_code token.role-unknown "unknown role of the person who asks" ;; esac
case "$days" in ''|*[!0-9]*) refuse_code token.days-invalid "the days are a number (1 to 365)" ;; esac
store=("$py" "$here/token_store.py")
adm=$(admin_user)
realm=domain; [ "$by" != "$adm" ] || realm=local

case "$action" in
  create)
    if ! msg=$("${store[@]}" validate --name "$name" --owner "$by" --realm "$realm" --role "$role" --days "$days" --cap "$cap" 2>&1); then refuse_code token.invalid "${msg:-the token cannot be created}"; fi
    danger="" ;;
  revoke)
    line=$("${store[@]}" find "$name" 2>/dev/null) || refuse_code token.not-found "there is no token with this name"
    owner=$(cut -f3 <<<"$line")
    { [ "$cap" = admin ] || [ "$owner" = "$by" ]; } || refuse_code token.not-found "there is no token with this name"
    danger="Every program that uses the token '$name' stops working at once. This cannot be undone: create a new token for it." ;;
esac

if [ "$verb" = start ]; then
  case "$action" in
    create)
      out=$(HS_CALLER=${HS_CALLER:-ui} "${store[@]}" create --name "$name" --owner "$by" --realm "$realm" --role "$role" --days "$days" --cap "$cap" 2>&1) || refuse_code token.invalid "${out:-the token cannot be created}"
      IFS=$'\t' read -r _ token tid exp <<<"$out"
      printf 'status\tdone\nsecret\ttoken\t%s\nid\t%s\nnote\tCopy the token now: it is shown only once and only its hash is kept. It ends on %s.\n' "$token" "$tid" "$(date -d "@$exp" +%F 2>/dev/null || echo "$exp")" ;;
    revoke)
      [ "$confirm" = "$name" ] || refuse_code confirm.missing "type the name of the token to confirm: $name"
      if [ "$cap" = admin ]; then "${store[@]}" revoke "$name" >/dev/null || refuse_code token.not-found "there is no token with this name"
      else "${store[@]}" revoke "$name" --owner "$by" >/dev/null || refuse_code token.not-found "there is no token with this name"; fi
      printf 'status\tdone\nnote\tThe token %s no longer works.\n' "$name" ;;
  esac
  exit 0
fi

echo "status	ok"
case "$action" in
  create)
    printf 'heading\tcreate the API token %s\n' "$name"
    printf 'step\tmake a token for %s with the role %s that ends in %s days; only its hash is stored in /var/lib/hs/api-tokens.json\n' "$by" "$role" "$days"
    printf 'note\tThe token is shown once, right after this step. A token cannot create tokens or use users, secrets or unlock.\n'
    printf 'command\ths token create %s --role %s --days %s\n' "$name" "$role" "$days"
    printf 'long\tno\n' ;;
  revoke)
    printf 'heading\trevoke the API token %s\n' "$name"
    printf 'step\tremove the token %s (owner %s) from /var/lib/hs/api-tokens.json\n' "$name" "$owner"
    printf 'command\ths token revoke %s\n' "$name"
    printf 'danger\t%s\nconfirm_name\t%s\nlong\tno\n' "$danger" "$name" ;;
esac
exit 0
