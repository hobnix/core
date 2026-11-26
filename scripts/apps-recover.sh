#!/usr/bin/env bash
# help: after a failed install: retry from the step that failed, or remove what the run created (called by apps-change.sh: hs sys apps plan|start retry|cleanup <job>)
# args: plan|start retry|cleanup <job> [--set KEY=value]... [--delete-data] [--by <user>] [--confirm <name>]
# System command part of hs sys apps (docs/PLAN-app-lifecycle.md Q3, step 9, #466). It never asks and prints plain key<TAB>value lines.
#
# A failed Install job leaves a `result` on its record: status failed, failed_step (read|needs|ask|run:<phase>|check), reason, tail (the last lines
# of the failed phase's log), package, repo, tag, instance. Both actions work from that record.
#
# retry <job>     plan: the install plan of the SAME tag plus failed_step, reason, tail, retry_from; start: a new Install job that begins at the failed
#                 step (apps-change.sh --from); a phase of the recipe runs again as a whole (recipes are idempotent, decision D7). The release is
#                 the one that failed: "the release moved" refuses it. --set answers again; a secret is one line on standard input.
# cleanup <job>   "Remove what was created": plan = the created ledger of the instance in reverse (scripts/lib/created.sh), each line checked against
#                 the real thing now: item <kind> <id> <state> <action> <text>. The data question is separate and kept by default (--delete-data
#                 answers it); confirm_name is the instance name, start needs --confirm <instance>. start = a background job. An app without a ledger
#                 is refused, nothing is guessed. Refused too when a later install of the same app finished (that is Remove, not clean-up).
# Test knobs: HS_JOBS_DIR, HS_STATE_DIR, HS_INCUS, HS_SERVICES, HS_UNIFI, HS_JOB_LIB, HS_APPS_CHANGE.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
change=${HS_APPS_CHANGE:-$here/apps-change.sh}
. "$here/lib/refuse-code.sh"   # refuse_code (ADR 0028)

verb=${1:-}; action=${2:-}; job=${3:-}
case "$verb" in plan|start|run) ;; *) refuse_code apps.usage "usage: plan|start retry|cleanup <job>" ;; esac
case "$action" in retry|cleanup) ;; *) refuse_code action.unknown "unknown action (retry, cleanup)" ;; esac
[ "$verb" != run ] || [ "$action" = cleanup ] || refuse_code apps.job-only "only cleanup runs as a job body"
[[ "$job" =~ ^[0-9A-Za-z][0-9A-Za-z-]{6,100}$ ]] || refuse_code job.id-invalid "not a job id"
shift 3 || true
sets=() confirm="" delete_data=no by=""
while [ $# -gt 0 ]; do
  case "$1" in
    --set)         [ $# -ge 2 ] || refuse_code apps.set-invalid "--set needs KEY=value"; sets+=(--set "$2"); shift 2 ;;
    --confirm)     [ $# -ge 2 ] || refuse_code confirm.missing "--confirm needs a value"; confirm=$2; shift 2 ;;
    --delete-data) delete_data=yes; shift ;;
    --by)          [ $# -ge 2 ] || refuse_code apps.by-invalid "--by needs a user name"; by=$2; shift 2 ;;
    --role)        [ $# -ge 2 ] || refuse_code apps.role-invalid "--role needs a role"; shift 2 ;;
    *) refuse_code option.unknown "unknown option $1" ;;
  esac
done

# ── the failed record: state, the result a failed Install left, and whether a later install of the same app finished ──
rec=$(python3 "$here/job-record.py" get "$job" 2>/dev/null) || refuse_code job.unknown "There is no job $job."
facts=$(python3 -c 'import json,os,sys,glob
r=json.loads(sys.argv[1]); res=r.get("result") or {}
def f(v): return (str(v).replace("\t"," ").replace("\n"," ") or "-")
later="no"
want="hs apps install %s" % res.get("package") + ("" if res.get("instance")==res.get("package") else " --name %s" % res.get("instance"))
for p in glob.glob(os.path.join(os.environ.get("HS_JOBS_DIR","/var/lib/hs/jobs"),"*.json")):
    try: o=json.load(open(p))
    except Exception: continue
    x=o.get("result") or {}
    if o.get("id")==r.get("id") or not str(o.get("slug","")).startswith("app-install-"): continue
    if (o.get("state")=="ok" and x.get("package")==res.get("package") and x.get("instance")==res.get("instance")) or (o.get("state") in ("queued","running","waiting") and o.get("description")==want): later="yes"
print("\t".join(f(v) for v in (r.get("state"),res.get("status"),res.get("failed_step"),res.get("reason"),res.get("tail"),res.get("package"),res.get("repo"),res.get("tag"),res.get("instance"),later)))' "$rec") || refuse_code job.record-unreadable "cannot read the record of $job"
IFS=$'\t' read -r jstate rstatus fstep reason tail pkg repo tag inst later <<<"$facts"
[[ "$jstate" =~ ^(failed|interrupted)$ ]] || refuse_code apps.job-not-failed "The job $job did not fail (it is $jstate): nothing to retry or clean up."
[ "$rstatus" = failed ] && [ "$fstep" != - ] && [ "$pkg" != - ] && [ "$inst" != - ] || refuse_code apps.no-failed-step "The job $job left no failed step (it was an older run or it was interrupted): install again from the start."
[[ "$pkg" =~ ^[a-z0-9][a-z0-9-]{0,40}$ && "$inst" =~ ^[a-z0-9][a-z0-9-]{0,40}$ ]] || refuse_code apps.record-invalid "the record names no usable app"
[[ "$fstep" =~ ^(read|needs|ask|check|run(:[a-z0-9][a-z0-9-]{0,30})?|on|rebuild|done)$ ]] || refuse_code apps.record-invalid "the record names an unknown step"
[ "$later" = no ] || refuse_code apps.other-run "$inst was installed or being installed by another run: use Remove for it, this clean-up could delete the working app."

case "$action" in
retry)
  inst_args=(); [ "$inst" = "$pkg" ] || inst_args=(--name "$inst")
  rep=(); [ "$repo" = - ] || rep=(--repo "$repo")
  if [ "$verb" = plan ]; then
    out=$(bash "$change" plan install "$pkg" ${rep[@]+"${rep[@]}"} --tag "$tag" ${inst_args[@]+"${inst_args[@]}"} ${sets[@]+"${sets[@]}"} 2>&1 </dev/null) || { printf '%s\n' "$out"; exit 1; }
    grep -v $'^command\t' <<<"$out"
    printf 'failed_step\t%s\nreason\t%s\ntail\t%s\n' "$fstep" "$reason" "$tail"
    printf 'retry_from\t%s\n' "$fstep"
    printf 'note\tStarts again at the step that failed (%s); a recipe phase runs again as a whole.\n' "$fstep"
    printf 'command\ths sys apps start retry %s\n' "$job"
    exit 0
  fi
  args=(start install "$pkg" ${rep[@]+"${rep[@]}"} --tag "$tag" ${inst_args[@]+"${inst_args[@]}"} --from "$fstep" ${sets[@]+"${sets[@]}"})
  [ -z "$confirm" ] || args+=(--confirm "$confirm"); [ -z "$by" ] || args+=(--by "$by")
  exec bash "$change" "${args[@]}" ;;
cleanup)
  . "$here/lib/ui.sh"
  . "$here/lib/created.sh"
  . "$here/lib/network.sh"
  . "$here/lib/created-remove.sh"
  led=$(created_file "$inst")
  [ -f "$led" ] || refuse_code apps.no-created-record "There is no record of what the run created for $inst (an app from before the record, or nothing was made): nothing is removed by guesswork."
  if [ "$verb" = run ]; then
    HS_PLAIN=1 step "Remove what was created for $inst"
    rc=0; created_remove_all "$inst" "$delete_data" || rc=$?
    if [ "$rc" -eq 0 ]; then ok "Done: nothing the record lists is left."; else fail "Some of it could not be removed: run the clean-up again (it checks each line first)."; fi
    exit 0
  fi
  lines=$(created_plan "$inst" "$delete_data")
  [ -n "$lines" ] || refuse_code apps.no-created-record "The record of $inst lists nothing."
  if [ "$verb" = start ]; then
    [ "$confirm" = "$inst" ] || refuse_code confirm.missing "type the name ($inst) to confirm"
    . "${HS_JOB_LIB:-$here/lib/job.sh}"
    export HS_JOB_ENV=${HS_JOB_ENV:-} HS_JOB_KIND=orchestration HS_JOB_INITIATOR=${by:-${SUDO_USER:-${USER:-}}}
    dargs=(); [ "$delete_data" = no ] || dargs=(--delete-data)
    unit=$(hs_job "app-cleanup-$inst" "hs apps cleanup $inst" -- bash "$here/apps-recover.sh" run cleanup "$job" ${dargs[@]+"${dargs[@]}"}) || refuse_code job.start-failed "the job could not be started"
    jid=$(hs_job_record find-unit "$unit" 2>/dev/null) || jid=""
    printf 'status\tstarted\nunit\t%s\njob\t%s\n' "$unit" "${jid:--}"
    exit 0
  fi
  printf 'status\tok\nheading\tremove what the failed install of %s created\n' "$pkg"
  printf 'package\t%s\ninstance\t%s\nfailed_step\t%s\n' "$pkg" "$inst" "$fstep"
  while IFS=$'\t' read -r kind id _ st act text; do printf 'item\t%s\t%s\t%s\t%s\t%s\n' "$kind" "$id" "$st" "$act" "$text"; done <<<"$lines"
  if awk -F'\t' '$1=="share" || $1=="volume" { f = 1 } END { exit !f }' <<<"$lines"; then
    printf 'data\tyes\nquestion\tdelete_data\tThe run created storage that may hold data. Keep it?\tkeep\n'
  else printf 'data\tno\n'; fi
  printf 'note\tOnly what the run itself created is removed, and each line is checked again first. What was there before stays.\n'
  printf 'note\tThe instance goes with its own disk and snapshots.\n'
  printf 'danger\t%s and what is listed above are deleted for good.\n' "$inst"
  printf 'confirm_name\t%s\n' "$inst"
  printf 'command\ths sys apps start cleanup %s --confirm %s\nlong\tyes\n' "$job" "$inst"
  exit 0 ;;
esac
