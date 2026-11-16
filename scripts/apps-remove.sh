#!/usr/bin/env bash
# help: remove an app instance, keeping its data or deleting it: what goes and what stays (plan), then do it as a background job (start)
# help.de: eine App-Instanz entfernen, Daten behalten oder löschen: was geht und was bleibt (plan), dann als Hintergrundauftrag ausführen (start)
# args: plan|start remove <instance> [--delete-data] [--confirm <instance>] [--confirm-data <instance>] [--by <user>] [--role <role>]
# System command (hs sys apps plan|start remove <instance>; docs/PLAN-app-lifecycle.md Q3, step 11, #466). It never asks and prints plain key<TAB>value lines.
#
# plan    What removing would do. The list is the created ledger of the instance in reverse (scripts/lib/created.sh, scripts/lib/created-remove.sh),
#         each line checked against the real thing now: item <kind> <id> <state> <action> <text> (state there|gone|unknown, action
#         remove|forget|keep|skip). An app without a ledger (installed before it existed) gets a READ-ONLY discovered list instead: the instance and
#         the service description named after it, nothing else (`source discovered`); nothing is guessed beyond that, and --delete-data is refused.
#         `keeps <text>` lines are the manifest's [app.remove] keeps (plain English); data yes|no; the data question is separate and kept by default
#         (`question delete_data ... keep`); confirm_name is the INSTANCE (not the package). With --delete-data the plan also says confirm_data <instance>:
#         the name is typed a second time. Data inside the instance goes with the instance; what lives in a volume or a share is the data question.
# start   Same checks, then a background job (status started, unit, job). Needs --confirm <instance>; with --delete-data also --confirm-data <instance>.
# run     The job body (never called by a person).
# Test knobs: HS_STATE_DIR, HS_INCUS, HS_SERVICES, HS_SERVICES_DIR, HS_UNIFI, HS_SHARE_DELETE, HS_JOB_LIB.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
refuse() { printf 'status\trefused\nreason\t%s\n' "$1"; exit 1; }

verb=${1:-}; action=${2:-}; inst=${3:-}
case "$verb" in plan|start|run) ;; *) refuse "usage: plan|start remove <instance>" ;; esac
[ "$action" = remove ] || refuse "unknown action (remove)"
[[ "$inst" =~ ^[a-z0-9][a-z0-9-]{0,40}$ ]] || refuse "not an instance name (lower case letters, digits and dashes)"
shift 3 || true
confirm="" confirm_data="" delete_data=no by=""
while [ $# -gt 0 ]; do
  case "$1" in
    --delete-data)  delete_data=yes; shift ;;
    --confirm)      [ $# -ge 2 ] || refuse "--confirm needs a value"; confirm=$2; shift 2 ;;
    --confirm-data) [ $# -ge 2 ] || refuse "--confirm-data needs a value"; confirm_data=$2; shift 2 ;;
    --by)           [ $# -ge 2 ] || refuse "--by needs a user name"; by=$2; shift 2 ;;
    --role)         [ $# -ge 2 ] || refuse "--role needs a role"; shift 2 ;;
    *) refuse "unknown option $1" ;;
  esac
done

. "$here/lib/ui.sh"
. "$here/lib/created.sh"
. "$here/lib/network.sh"
. "$here/lib/created-remove.sh"
st=${HS_STATE_DIR:-/var/lib/hs}
incus=${HS_INCUS:-incus}
led=$(created_file "$inst")

# ── what is there: the ledger (written by the install) or, for an older app, what can be told without guessing ──
have_ct=no; "$incus" info "$inst" >/dev/null 2>&1 && have_ct=yes
desc=${HS_SERVICES_DIR:-$st/services.d}/$inst.toml
[ -f "$led" ] || [ "$have_ct" = yes ] || refuse "There is no app called $inst (no instance and no record of one)."
if [ "$have_ct" = yes ]; then
  owner=$("$incus" config get "$inst" user.hs.managed_by 2>/dev/null || true)
  [ -z "$owner" ] || refuse "$inst belongs to the part $owner and is not removed here: switch that part off."
fi
source=ledger; [ -f "$led" ] || source=discovered
[ "$source" = ledger ] || [ "$delete_data" = no ] || refuse "$inst has no record of what its install created: nothing beyond the instance and its service description is known, so there is no data to delete. Remove it with the data kept."

# the package: the instance itself or, for a second instance (<package>-<word>), the package it was made from
pkg=-
cand=$inst
while :; do
  if [ -f "$st/packages/current/$cand/package.toml" ]; then pkg=$cand; break; fi
  case "$cand" in *-*) cand=${cand%-*} ;; *) break ;; esac
done
keeps=() datapaths=()
if [ "$pkg" != - ]; then
  while IFS=$'\t' read -r k v; do
    case "$k" in keeps) keeps+=("$v") ;; data) datapaths+=("$v") ;; esac
  done < <(python3 -I - "$st/packages/current/$pkg/package.toml" <<'PY' 2>/dev/null || true
import sys, tomllib
try:
    t = tomllib.load(open(sys.argv[1], "rb"))
except Exception:
    sys.exit(0)
r = ((t.get("app") or {}).get("remove") or {})
for k in ("keeps", "data"):
    for v in r.get(k) or []:
        print("%s\t%s" % (k, str(v).replace("\t", " ").replace("\n", " ")))
PY
)
fi

if [ "$source" = ledger ]; then
  lines=$(created_plan "$inst" "$delete_data")
else   # discovered: read-only, the instance and the description named after it
  lines=""
  if [ "$have_ct" = yes ]; then lines+=$(printf 'container\t%s\t-\tthere\tremove\t%s' "$inst" "$(_cr_text container "$inst")")$'\n'; fi
  if [ -f "$desc" ]; then lines+=$(printf 'service\t%s\t-\tthere\tremove\t%s' "$inst" "$(_cr_text service "$inst")")$'\n'; fi
  lines=${lines%$'\n'}
fi
[ -n "$lines" ] || refuse "Nothing is listed for $inst: nothing to remove."

if [ "$verb" = run ]; then
  HS_PLAIN=1 step "Remove $inst"
  rc=0
  if [ "$source" = ledger ]; then created_remove_all "$inst" "$delete_data" || rc=$?
  else
    while IFS=$'\t' read -r kind id detail _ act text; do
      [ "$act" = remove ] || continue
      if _cr_one "$kind" "$id" "$detail"; then ok "Removed $text"; else warn "Could not remove $text."; rc=1; fi
    done <<<"$lines"
  fi
  if [ "$rc" -eq 0 ]; then
    if [ "$delete_data" = yes ]; then ok "Done: $inst is removed with its data."; else ok "Done: $inst is removed. Its data is kept, a later install finds it again."; fi
  else fail "Some of it could not be removed: run Remove again (it checks each line first)."; fi
  exit 0
fi

if [ "$verb" = start ]; then
  [ "$confirm" = "$inst" ] || refuse "type the name ($inst) to confirm"
  [ "$delete_data" = no ] || [ "$confirm_data" = "$inst" ] || refuse "deleting the data needs the name again: type $inst a second time"
  . "${HS_JOB_LIB:-$here/lib/job.sh}"
  export HS_JOB_ENV=${HS_JOB_ENV:-} HS_JOB_KIND=orchestration HS_JOB_INITIATOR=${by:-${SUDO_USER:-${USER:-}}}
  dargs=(); [ "$delete_data" = no ] || dargs=(--delete-data)
  unit=$(hs_job "app-remove-$inst" "hs apps remove $inst" -- bash "$here/apps-remove.sh" run remove "$inst" ${dargs[@]+"${dargs[@]}"}) || refuse "the job could not be started"
  jid=$(hs_job_record find-unit "$unit" 2>/dev/null) || jid=""
  printf 'status\tstarted\nunit\t%s\njob\t%s\n' "$unit" "${jid:--}"
  exit 0
fi

# ── plan ──
data=no
awk -F'\t' '$1=="share" || $1=="volume" { f = 1 } END { exit !f }' <<<"$lines" && data=yes
[ "${#datapaths[@]}" -eq 0 ] || data=yes
printf 'status\tok\nheading\tremove %s\n' "$inst"
printf 'package\t%s\ninstance\t%s\nsource\t%s\n' "$pkg" "$inst" "$source"
while IFS=$'\t' read -r kind id _ stt act text; do printf 'item\t%s\t%s\t%s\t%s\t%s\n' "$kind" "$id" "$stt" "$act" "$text"; done <<<"$lines"
for k in ${keeps[@]+"${keeps[@]}"}; do printf 'keeps\t%s\n' "$k"; done
for d in ${datapaths[@]+"${datapaths[@]}"}; do printf 'datapath\t%s\n' "$d"; done
printf 'data\t%s\n' "$data"
if [ "$source" = ledger ]; then
  [ "$data" = no ] || printf 'question\tdelete_data\tKeep the data of %s? A later install finds it again.\tkeep\n' "$inst"
  printf 'note\tOnly what the install itself created is removed, and each line is checked again first. What was there before stays.\n'
else
  printf 'note\t%s was installed before the record of what an install creates: only the instance and its service description are listed (read from what exists now), nothing more is touched.\n' "$inst"
  printf 'note\tA fixed address in UniFi and a Zoraxy rule are not on any record: remove them by hand.\n'
fi
case "$data$source$delete_data" in
  yesledgerno)  printf 'note\tThe data is kept: the shares and volumes listed stay, so installing %s again finds it.\n' "$pkg" ;;
esac
[ "${#datapaths[@]}" -eq 0 ] || printf 'note\tData inside the instance (%s) goes with the instance.\n' "$(IFS=,; echo "${datapaths[*]}")"
printf 'note\tThe instance goes with its own disk and snapshots.\n'
if [ "$delete_data" = yes ]; then
  printf 'danger\t%s is removed and its data is deleted (a share is taken away, its folder is kept as <share>.deleted-<date>).\n' "$inst"
  printf 'confirm_name\t%s\nconfirm_data\t%s\n' "$inst" "$inst"
  printf 'command\ths sys apps start remove %s --delete-data --confirm %s --confirm-data %s\nlong\tyes\n' "$inst" "$inst" "$inst"
else
  printf 'danger\t%s is removed; its data is kept.\n' "$inst"
  printf 'confirm_name\t%s\n' "$inst"
  printf 'command\ths sys apps start remove %s --confirm %s\nlong\tyes\n' "$inst" "$inst"
fi
exit 0
