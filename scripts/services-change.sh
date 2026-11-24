#!/usr/bin/env bash
# help: change the services and their routes on the reverse proxy without asking anything: what would happen (plan), then do it (start)
# help.de: die Dienste und ihre Routen am Reverse-Proxy ändern, ohne etwas zu fragen: was passieren würde (plan), dann ausführen (start)
# args: plan|start apply | adopt | import | remove <service> | add <name> --port N (--container C | --host H) [--title T] [--names a,b] [--exposure E] [--public-path P]... [--want w,w] | set <name> [--local yes|no] [--public yes|no] [--public-name FQDN] | edit <name> [the options of add] [--clear title|icon|group|description|names|public-path|auth-skip]...
# System command (hs sys routes plan|start): for the interface and tests. It never asks and prints plain key<TAB>value lines like
# backup-change.sh. The work is services.sh's (no logic is repeated here). The reads are `hs sys services list|plan|tiles`.
#   apply          do what `hs services plan` says: add, publish (confirm), change and remove routes. The plan lists every route; when one goes on
#                  the internet, changes a live route or removes one it is red: confirm_name = apply, and start passes --confirm for each host.
#                  Runs as a background job. Blocked services, violations and routes not made by hs are never touched.
#   adopt          routes made by hand that match a service become ones hs may change and remove (writes a list, nothing is sent to the proxy)
#   import         one service description per route the proxy has and no service describes yet (writes service files)
#   add <name>     describe a new service (a file in the services folder; nothing is sent to the proxy: `apply` does that). public-ok is red: the
#                  typed word is the service name. The options go to `hs services add` as they are; services.py checks them.
#   set <name>     change an existing service: local name, public yes/no (+ public name). public yes is red (typed word: the service name).
#                  Routes are not touched: `apply` does that.
#   edit <name>    change the description of a service: only the options given change (`hs services edit`, merge); nothing is sent to the proxy
#                  (`apply` does that). Going to public-ok is red like add (the typed word is the service name).
#   remove <name>  forget the description of a service; its routes on the proxy stay
# plan: exit 0 = allowed, 1 = refused (no proxy, nothing to do). Output: status ok|refused, reason<TAB><text>,
#   heading|step|note|warn|danger|command<TAB><line>, confirm_name<TAB>apply, long<TAB>yes|no.
# start: the same checks (and the typed word for a red plan), then apply is a background job (status started, unit); the others answer status done.
# Test knobs: HS_SERVICES (stand-in for services.sh).
set -euo pipefail
here=$(dirname "$0")
svc=${HS_SERVICES:-$here/services.sh}

refuse() { printf 'status\trefused\nreason\t%s\n' "$1"; exit 1; }
. "$here/lib/refuse-code.sh"   # refuse_code (ADR 0028)

verb=${1:-}; action=${2:-}
case "$verb" in plan|start) ;; *) echo "usage: services-change.sh plan|start apply|adopt|import|remove <service>" >&2; exit 1 ;; esac
shift 2 || true
confirm=""
name=""
case "$action" in
  apply|adopt|import) ;;
  remove) name=${1:-}; shift || true; [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,60}$ ]] || refuse_code name.invalid "that is not a service name" ;;
  add) name=${1:-}; shift || true; [[ "$name" =~ ^[a-z0-9][a-z0-9-]{0,40}$ ]] || refuse_code name.invalid "A service name is lower case letters, digits and - (at most 41)." ;;
  edit) name=${1:-}; shift || true; [[ "$name" =~ ^[a-z0-9][a-z0-9-]{0,40}$ ]] || refuse_code name.invalid "That is not a service name." ;;
  set) name=${1:-}; shift || true; [[ "$name" =~ ^[a-z0-9][a-z0-9-]{0,40}$ ]] || refuse_code name.invalid "A service name is lower case letters, digits and - (at most 41)." ;;
  *) refuse_code action.unknown "unknown action (apply, adopt, import, add, edit, set or remove)" ;;
esac
pargs=() addargs=() exposure=private-ok port="" container="" host="" title="" setargs=() set_public="" set_pname="" set_local=""
[ "$action" != edit ] || exposure=   # an edit changes the exposure only when it is given
while [ $# -gt 0 ]; do
  case "$1" in
    --proxy) [ $# -ge 2 ] || refuse_code service.value-missing "--proxy needs a value"
      case "$action" in apply|import|adopt) ;; *) refuse_code option.unknown "unknown option $1" ;; esac
      case "$2" in public) ;; local) pargs=(--proxy local) ;; *) refuse_code service.proxy-invalid "--proxy is public or local" ;; esac
      shift 2 ;;
    --confirm) [ $# -ge 2 ] || refuse_code confirm.missing "--confirm needs a value"; confirm=$2; shift 2 ;;
    --local|--public|--public-name)
      [ "$action" = set ] || refuse_code option.unknown "unknown option $1"
      [ $# -ge 2 ] || refuse_code service.value-missing "$1 needs a value"
      case "$1" in
        --local|--public) case "$2" in yes|no) ;; *) refuse_code service.value-invalid "$1 is yes or no" ;; esac ;;
        --public-name) [[ "$2" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$ ]] || refuse_code service.public-name-invalid "The public name is a full name like app.example.org." ;;
      esac
      case "$1" in --local) set_local=$2 ;; --public) set_public=$2 ;; --public-name) set_pname=$2 ;; esac
      setargs+=("$1" "$2"); shift 2 ;;
    --port|--container|--host|--title|--names|--exposure|--public-path|--blocked-path|--auth|--auth-skip|--request-header|--response-header|--want|--group|--icon|--description|--clear)
      case "$action" in add|edit) ;; *) refuse_code option.unknown "unknown option $1" ;; esac
      [ "$1" != --clear ] || [ "$action" = edit ] || refuse_code option.unknown "unknown option $1"
      [ $# -ge 2 ] || refuse_code service.value-missing "$1 needs a value"
      case "$1" in --port) port=$2 ;; --container) container=$2 ;; --host) host=$2 ;; --exposure) exposure=$2 ;; --title) title=$2 ;; esac
      addargs+=("$1" "$2"); shift 2 ;;
    *) refuse_code option.unknown "unknown option $1" ;;
  esac
done

export HS_PLAIN=1 HS_LANG=en HS_CALLER=${HS_CALLER:-ui}
unset HS_GUIDED_TTY

# the plan of the proxy against the services into $plan_out: act host path target service note (tab separated)
load_plan() {
  plan_out=$(bash "$svc" plan --plain ${pargs[@]+"${pargs[@]}"} </dev/null 2>/dev/null || true)
  case "$plan_out" in
    "status"*none*) refuse_code service.no-proxy "No reverse proxy is set up (hs recipe zoraxy, then: hs config set reverseProxy zoraxy)." ;;
  esac
}

case "$action" in
  add)
    list=$(bash "$svc" list --plain </dev/null 2>/dev/null || true)
    if awk -F'\t' -v n="$name" '$1 == n { f = 1 } END { exit !f }' <<<"$list"; then refuse_code service.exists "There is a service called '$name' already."; fi
    [[ "$port" =~ ^[0-9]{1,5}$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || refuse_code service.port-invalid "The port is a number from 1 to 65535."
    if [ -n "$container" ] && [ -n "$host" ]; then refuse_code service.target-both "Give a container or a host, not both."; fi
    if [ -z "$container" ] && [ -z "$host" ]; then refuse_code service.target-missing "Give the container or the host the service runs on."; fi
    case "$exposure" in never-public|private-ok|public-ok) ;; *) refuse_code service.exposure-invalid "The exposure is never-public, private-ok or public-ok." ;; esac
    if [ "$verb" = start ]; then
      if [ "$exposure" = public-ok ] && [ "$confirm" != "$name" ]; then refuse_code confirm.missing "type the word to confirm: $name"; fi
      err=$(bash "$svc" add "$name" "${addargs[@]}" </dev/null 2>&1 >/dev/null) || refuse_code service.failed "$(tail -n 1 <<<"$err" | tr -d '\t')"
      printf 'status\tdone\n'
      exit 0
    fi
    where=${container:+container $container}${host:+host $host}
    printf 'status\tok\nheading\tdescribe the service %s\n' "${title:-$name}"
    printf 'step\twrite the description of %s (%s, port %s, %s)\n' "$name" "$where" "$port" "$exposure"
    printf 'note\tNothing is sent to the reverse proxy yet: the route is made by Apply.\n'
    if [ "$exposure" = public-ok ]; then
      printf 'danger\t%s may be put on the internet by the next Apply.\nconfirm_name\t%s\n' "$name" "$name"
    fi
    printf 'command\ths services add %s %s\nlong\tno\n' "$name" "${addargs[*]}"
    exit 0 ;;
  edit)
    cur=$(bash "$svc" show "$name" </dev/null 2>/dev/null) || refuse_code service.unknown "There is no service called '$name'."
    [ "${#addargs[@]}" -gt 0 ] || refuse_code service.nothing-to-change "Nothing to change."
    [ -z "$port" ] || { [[ "$port" =~ ^[0-9]{1,5}$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || refuse_code service.port-invalid "The port is a number from 1 to 65535."; }
    if [ -n "$container" ] && [ -n "$host" ]; then refuse_code service.target-both "Give a container or a host, not both."; fi
    case "$exposure" in ''|never-public|private-ok|public-ok) ;; *) refuse_code service.exposure-invalid "The exposure is never-public, private-ok or public-ok." ;; esac
    was=$(awk -F'\t' '$1 == "exposure" { print $2; exit }' <<<"$cur")
    going_public=""
    if [ "$exposure" = public-ok ] && [ "$was" != public-ok ]; then going_public=yes; fi
    if [ "$verb" = start ]; then
      if [ -n "$going_public" ] && [ "$confirm" != "$name" ]; then refuse_code confirm.missing "type the word to confirm: $name"; fi
      err=$(bash "$svc" edit "$name" "${addargs[@]}" </dev/null 2>&1 >/dev/null) || refuse_code service.failed "$(tail -n 1 <<<"$err" | tr -d '\t')"
      printf 'status\tdone\n'
      exit 0
    fi
    printf 'status\tok\nheading\tchange the service %s\n' "$name"
    printf 'step\trewrite the description of %s (only what you changed)\n' "$name"
    printf 'note\tNothing is sent to the reverse proxy yet: Apply makes the change there.\n'
    printf 'note\tIf a recipe declared this service, running the recipe again refreshes its container, port and title.\n'
    if [ "$was" = public-ok ] && [ -n "$exposure" ] && [ "$exposure" != public-ok ]; then
      printf 'warn\t%s is public-ok today: the next Apply takes its route off the internet.\n' "$name"
    fi
    if [ -n "$going_public" ]; then
      printf 'danger\t%s may be put on the internet by the next Apply.\nconfirm_name\t%s\n' "$name" "$name"
    fi
    printf 'command\ths services edit %s %s\nlong\tno\n' "$name" "${addargs[*]}"
    exit 0 ;;
  set)
    list=$(bash "$svc" list --plain </dev/null 2>/dev/null || true)
    awk -F'\t' -v n="$name" '$1 == n { f = 1 } END { exit !f }' <<<"$list" || refuse_code service.unknown "There is no service called '$name'."
    [ ${#setargs[@]} -gt 0 ] || refuse_code service.nothing-to-change "Nothing to change: give --local, --public or --public-name."
    if [ "$set_public" = yes ] && [ -z "$set_pname" ]; then refuse_code service.public-name-missing "A public service needs its public name."; fi
    if [ "$verb" = start ]; then
      if [ "$set_public" = yes ] && [ "$confirm" != "$name" ]; then refuse_code confirm.missing "type the word to confirm: $name"; fi
      err=$(bash "$svc" set "$name" "${setargs[@]}" </dev/null 2>&1 >/dev/null) || refuse_code service.failed "$(tail -n 1 <<<"$err" | tr -d '\t')"
      printf 'status\tdone\n'
      exit 0
    fi
    printf 'status\tok\nheading\tchange the service %s\n' "$name"
    [ -z "$set_local" ] || printf 'step\t%s a local name for %s\n' "$([ "$set_local" = yes ] && echo give || echo take away)" "$name"
    [ "$set_public" != yes ] || printf 'step\tpublish %s as %s\n' "$name" "$set_pname"
    [ "$set_public" != no ] || printf 'step\tstop publishing %s\n' "$name"
    [ "$set_public" != "" ] || [ -z "$set_pname" ] || printf 'step\trename the public name of %s to %s\n' "$name" "$set_pname"
    printf 'note\tNothing is sent to the proxy yet: Apply makes the route.\n'
    if [ "$set_public" = yes ]; then
      printf 'danger\t%s may be put on the internet by the next Apply.\nconfirm_name\t%s\n' "$name" "$name"
    fi
    printf 'command\ths services set %s %s\nlong\tno\n' "$name" "${setargs[*]}"
    exit 0 ;;
  remove)
    list=$(bash "$svc" list --plain </dev/null 2>/dev/null || true)
    awk -F'\t' -v n="$name" '$1 == n { f = 1 } END { exit !f }' <<<"$list" || refuse_code service.unknown "There is no service called '$name'."
    if [ "$verb" = start ]; then
      bash "$svc" remove "$name" >/dev/null 2>&1 || refuse_code service.failed "the service could not be removed"
      printf 'status\tdone\n'
      exit 0
    fi
    printf 'status\tok\nheading\tforget the service %s\n' "$name"
    printf 'step\tremove its description (the file in the services folder)\n'
    printf 'note\tIts routes on the reverse proxy stay; the plan then shows them as unmanaged.\n'
    printf 'command\ths services remove %s\nlong\tno\n' "$name"
    exit 0 ;;
  adopt)
    load_plan
    rows=$(awk -F'\t' '$1 == "ok" && $6 ~ /^not adopted/' <<<"$plan_out")
    [ -n "$rows" ] || refuse_code service.nothing-to-do "Nothing to adopt."
    if [ "$verb" = start ]; then
      bash "$svc" adopt --yes ${pargs[@]+"${pargs[@]}"} >/dev/null 2>&1 || refuse_code service.failed "the routes could not be adopted"
      printf 'status\tdone\n'
      exit 0
    fi
    printf 'status\tok\nheading\tadopt routes made by hand\n'
    while IFS=$'\t' read -r _ host path target service _; do
      printf 'step\t%s%s -> %s (%s)\n' "$host" "$path" "$target" "$service"
    done <<<"$rows"
    printf 'note\tFrom now on hs may change and remove these routes when a service no longer wants them. Nothing is sent to the proxy.\n'
    printf 'command\ths services adopt --yes\nlong\tno\n'
    exit 0 ;;
  import)
    out=$(bash "$svc" import --dry-run ${pargs[@]+"${pargs[@]}"} </dev/null 2>&1 || true)
    if grep -qiE 'nothing new|no routes|already says' <<<"$out"; then
      refuse_code service.nothing-to-do "Nothing new to describe: every route of the proxy has a service already (or the proxy has no routes)."
    fi
    if [ "$verb" = start ]; then
      bash "$svc" import --yes ${pargs[@]+"${pargs[@]}"} >/dev/null 2>&1 || refuse_code service.failed "the services could not be described"
      printf 'status\tdone\n'
      exit 0
    fi
    if [ "${#pargs[@]}" -gt 0 ]; then
      printf 'status\tok\nheading\tgive the services a local name\n'
      printf 'step\tset local-proxy = true on every service that does not say yet whether it wants a local name\n'
      printf 'note\tOnly the service files change; the routes are made by Apply. A service with local-proxy = false stays out.\n'
    else
      printf 'status\tok\nheading\tdescribe the routes of the proxy as services\n'
      printf 'step\tmake one service file for every route that no service describes yet\n'
      printf 'warn\tCheck the exposure of each afterwards: public-ok means the service is reachable from the internet today.\n'
    fi
    printf 'command\ths services import --yes%s\nlong\tno\n' "${pargs[*]:+ ${pargs[*]}}"
    exit 0 ;;
  apply)
    load_plan
    rows=$plan_out
    todo=$(awk -F'\t' '$1 == "add" || $1 == "confirm" || $1 == "remove" || ($1 == "change" && $6 !~ /adopt it first/)' <<<"$rows")
    [ -n "$todo" ] || refuse_code service.nothing-to-do "Nothing to do: the routes of the proxy match the services."
    red=$(awk -F'\t' '$1 == "confirm" || $1 == "change" || $1 == "remove"' <<<"$todo")
    hosts=$(awk -F'\t' '$1 == "confirm" || $1 == "change" || $1 == "remove" { print $2 }' <<<"$todo" | sort -u)
    if [ "$verb" = start ]; then
      if [ -n "$red" ] && [ "$confirm" != apply ]; then refuse_code confirm.missing "type the word to confirm: apply"; fi
      args=(apply --yes ${pargs[@]+"${pargs[@]}"})
      while IFS= read -r h; do
        [ -z "$h" ] || args+=(--confirm "$h")
      done <<<"$hosts"
      . "$here/lib/job.sh"
      unit=$(hs_job services-apply "hs services apply" -- bash "$svc" "${args[@]}") || refuse_code job.start-failed "the job could not be started"
      printf 'status\tstarted\nunit\t%s\n' "$unit"
      exit 0
    fi
    printf 'status\tok\nheading\tmake the routes of the services on the reverse proxy\n'
    while IFS=$'\t' read -r act host path target service _; do
      [ -n "$act" ] || continue
      case "$act" in
        add)     printf 'step\tadd %s%s -> %s\n' "$host" "$path" "$target" ;;
        confirm) printf 'step\tpublish %s%s -> %s (%s)\ndanger\t%s goes on the internet.\n' "$host" "$path" "$target" "$service" "$host" ;;
        change)  printf 'step\tchange the live route %s%s to %s\nwarn\t%s%s is a live route.\n' "$host" "$path" "$target" "$host" "$path" ;;
        remove)  printf 'step\tremove the route %s%s\nwarn\t%s%s is removed from the proxy.\n' "$host" "$path" "$host" "$path" ;;
      esac
    done <<<"$todo"
    left=$(awk -F'\t' '$1 == "blocked" || $1 == "violation" || $1 == "conflict" || $1 == "invalid" || $1 == "unresolved" || $1 == "manual"' <<<"$rows" | grep -c . || true)
    if [ "$left" -gt 0 ]; then printf 'note\t%s more row(s) are left alone (blocked, violations, conflicts, headers or logins to set by hand): see the list.\n' "$left"; fi
    printf 'command\ths services apply --yes%s\n' "${pargs[*]:+ ${pargs[*]}}"
    if [ -n "$red" ]; then printf 'confirm_name\tapply\n'; fi
    printf 'long\tyes\n'
    exit 0 ;;
esac
