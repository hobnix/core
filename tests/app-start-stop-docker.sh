#!/usr/bin/env bash
# What starting and stopping an app in the container docker does TODAY (hobnix/core#1335): a characterization test, the second half of
# tests/app-start-stop.sh. The list of every path by which an app is started or stopped is in the header of that file. A line "LOOKS WRONG"
# marks behaviour that looks like a bug: it is asserted because it is what happens now. Not compared with a real server yet.
#
# Recorded here: hs sys docker-app plan|start <app> start|stop|restart, the job (hs_job -> docker-app-change.sh), the cancel of that job.
# The program under test is the hs of tests/lib-appfakes.sh (HS_UNDER_TEST); scripts/docker.sh (status and list of the apps) runs as it
# is, in front of the fake incus. NOT recorded: that a compose start, stop or restart longer than 30 s counts as failed (`timeout 30` in
# run_action; the up -d of a stopped app has 600 s), and the other actions of the row (pull, recreate, rebuild, app-save, app-write,
# delete; tests/docker-app-change.sh).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
trap 'rm -rf "${WORK:?}"' EXIT   # not the cleanup of lib.sh: run as root it closes every /dev/mapper/hs-*, also those of a real server
[ "$(uname -s)" = Linux ] || { echo "  skip  needs Linux (WSL): process groups, setsid"; exit 77; }
for tool in jq python3 setsid; do have "$tool" || { skip "needs $tool"; finish; exit; }; done
# shellcheck source=tests/lib-appfakes.sh
. "$(dirname "$0")/lib-appfakes.sh"
export HS_VAULT_DIR=$WORK/vault
echo arcane > "$HS_SETTINGS_DIR/dockerManager"

# zz-hstest-arr = an app with a running container; zz-hstest-kept = an app with a folder and no container (state stopped); arcane = the manager
setup() { reset_fakes; instance docker RUNNING docker; }
started_unit() {   # started_unit <app> <action>: the web starts the job; sets UNIT and ID
  as_web sys docker-app start "$1" "$2"
  UNIT=$(unit_of_output)
  ID=$(job_id_of "$UNIT")
}
audit() {   # audit <ok|failed> <plan|start> <words> [actor]: the audit line the dispatcher writes for these rows
  local level=info rc=0
  [ "$1" = ok ] || { level=warn; rc=1; }
  printf 'audit.%s|sys docker-app %s %s|%s|-|{"actor":"%s","exit":%s}' "$1" "$2" "$3" "$level" "${4:-anna}" "$rc"
}

echo "== hs sys docker-app plan"
setup
for action in start stop restart; do
  case "$action" in start) text=Start ;; stop) text=Stop ;; restart) text=Restart ;; esac
  mark
  as_web sys docker-app plan zz-hstest-arr "$action"
  check_run "plan $action" 0 "$(lines "status|ok" "heading|$action zz-hstest-arr" "step|$text the containers of zz-hstest-arr" "long|no")"
  check_eq "plan $action: stderr" "" "$ERR"
  # LOOKS WRONG: both rows have the flag changes (the plan row too), so a plan, which changes nothing, is written to the audit log as a
  # change and reads the area system again (the rows name no topic, so it is not the area of the apps)
  check_events "LOOKS WRONG: plan $action is audited" "$(audit ok plan "zz-hstest-arr $action")"
  check_signals "LOOKS WRONG: plan $action refreshes" event:area.system
done
check_eq "a plan changes nothing" "" "$(changes)"
check_eq "a plan makes no job" 0 "$(job_files)"

echo "== refusals of plan and start (no job)"
refused() {   # refused "what" "<stdout>" <app> <action> [word...]
  local what=$1 want=$2 verb
  shift 2
  for verb in plan start; do
    mark
    as_web sys docker-app "$verb" "$@"
    check_run "$verb: $what" 1 "$want"
    check_events "$verb: $what" "$(audit failed "$verb" "$1 $2")"
    check_signals "$verb: $what" event:area.system
  done
}
setup
refused "a name that is not one" "$(lines 'status|refused' 'reason|The app name is not valid.' 'code|name.invalid')" Bad.Name start
refused "an unknown action" "$(lines 'status|refused' 'reason|Action must be start, stop, restart, pull, app-save, app-write, rebuild, recreate or delete.' 'code|action.unknown')" zz-hstest-arr halt
refused "a word too many" "$(lines 'status|refused' 'reason|Unexpected arguments.' 'code|args.unexpected')" zz-hstest-arr stop --force
refused "no such app" "$(lines 'status|refused' "reason|No app called 'zz-hstest-ghost' was found." 'code|app.unknown')" zz-hstest-ghost start
# the list of the apps leaves the manager out, so the check for the manager (app.is-manager) is never reached
refused "the Docker manager reads as unknown" "$(lines 'status|refused' "reason|No app called 'arcane' was found." 'code|app.unknown')" arcane stop
OFF=$(lines 'status|refused' 'reason|Docker is not on or not running.' 'code|docker.off')
echo STOPPED > "$FAKE/ct/docker/state"
refused "the container docker is stopped" "$OFF" zz-hstest-arr start
echo RUNNING > "$FAKE/ct/docker/state"; echo docker > "$HS_STATE_DIR/capabilities-off"
refused "the capability docker is off" "$OFF" zz-hstest-arr start
rm -f "$HS_STATE_DIR/capabilities-off"
touch "$FAKE/down"
refused "Incus does not answer" "$OFF" zz-hstest-arr stop
rm -f "$FAKE/down"
check_eq "refusals change nothing" "" "$(changes)"
check_eq "refusals make no job" 0 "$(job_files)"
check_no_surprise "plans and refusals"

echo "== start, then the job (success)"
# <action> <app> <what docker is told>: a stopped app without containers is brought up from its folder for start and restart
for row in "start|zz-hstest-arr|compose start zz-hstest-arr" "stop|zz-hstest-arr|compose stop zz-hstest-arr" "restart|zz-hstest-arr|compose restart zz-hstest-arr" \
  "start|zz-hstest-kept|compose up -d zz-hstest-kept (in /shares/apps/stacks/zz-hstest-kept)" "restart|zz-hstest-kept|compose up -d zz-hstest-kept (in /shares/apps/stacks/zz-hstest-kept)" \
  "stop|zz-hstest-kept|compose stop zz-hstest-kept"; do
  IFS='|' read -r action app told <<<"$row"
  case "$action" in start) text="Start $app" ;; stop) text="Stop $app" ;; restart) text="Restart $app" ;; esac
  what="$action $app"
  setup; mark
  started_unit "$app" "$action"
  check_eq "$what: exit 0" 0 "$RC"
  check_eq "$what: stdout" "$(lines "status|started" "unit|hs-job-docker-app-$action-$app-HHMMSS")" "$(norm <<<"$OUT")"
  check_eq "$what: the answer comes before anything changed" "" "$(changes)"
  # LOOKS WRONG: key is null. The description does not start with "hs ", so hs_job derives no row key, and the script sets none.
  # web/src/pages/docker/DockerApp.svelte lists the jobs of an app by a key that starts with "docker-app <app> ", and a browser that did
  # not start the job cannot match it to a row. (A job of an instance has the key, tests/app-start-stop.sh.)
  queued=$(record "$ID")
  check_eq "$what: the record while queued" "$(printf '%s\n' "id=\"ID-docker-app-$action-$app\"" "slug=\"docker-app-$action-$app\"" \
    "description=\"$text\"" 'source="web"' 'initiator="root"' "unit=\"hs-job-docker-app-$action-$app-HHMMSS\"" 'queued="T"' 'started=null' \
    'ended=null' 'state="queued"' 'exit=null' 'step=null' 'progress=null' 'error=null' 'result=null' 'cancel=null' 'version=1' \
    'parent=null' 'kind=null' 'waiting=null' 'key=null')" "$queued"
  # LOOKS WRONG: the audit line says the command ended with exit 0 while the work has not run yet (the job writes no audit line)
  check_events "$what: before the job runs" "job.queued|ID-docker-app-$action-$app|info|job queued|-" "$(audit ok start "$app $action")"
  # LOOKS WRONG: after the start the area system is read again, not the area instances (web-serve.py adds @instances itself)
  check_signals "$what: before the job runs" event:area.jobs event:area.system
  unitdir=$FAKE/units/$UNIT.service
  check_eq "$what: the description of the unit" "$text" "$(cat "$unitdir/description")"
  check_eq "$what: the unit properties" "OnFailure=hs-notify-failure@$UNIT.service" "$(cat "$unitdir/props")"
  check_eq "$what: what the unit is told (no HS_JOB_KEY)" "HS_CALLER HS_JOBS_DIR HS_JOB_ID HS_JOB_UNIT HS_LANG PATH" \
    "$(sed 's/=.*//' "$unitdir/env.txt" | grep -v '^HOBNIX_BIN$\|^HS_JOB_RECORD$' | LC_ALL=C sort | paste -sd' ' -)"

  mark
  run_unit "$UNIT"
  check_eq "$what: the job ends well" 0 "$JOB_RC"
  check_eq "$what: what docker is told" "$told" "$(changes)"
  check_eq "$what: the record after" \
    "$(sed -e 's/^started=null/started="T"/' -e 's/^ended=null/ended="T"/' -e 's/^state="queued"/state="ok"/' -e 's/^exit=null/exit=0/' <<<"$queued")" "$(record "$ID")"
  check_events "$what: the job" "job.running|ID-docker-app-$action-$app|info|job started|-" \
    "job.ok|ID-docker-app-$action-$app|info|job finished|-" "notify.sent|main|info|hs|-"
  check_signals "$what: the job" --all
  check_eq "$what: one push" 1 "$(pushes)"
  check_match "$what: the push says the job finished" "$text finished" "$(cat "$FAKE/pushes")"
  as_web sys jobs tail "$UNIT"
  check_run "$what: sys jobs tail after" 0 "$(lines "state|ok" "exit|0" "line|Started $text." "line|" "line|── $text ──" \
    "line|  ✓ Done: $action $app" "next|4")"
  check_no_surprise "$what"
done

echo "-- the same row typed by a person"
setup; mark
as_person sys docker-app start zz-hstest-arr stop
ID=$(job_id_of "$(unit_of_output)")
# a job of an instance started the same way is recorded as source web (tests/app-start-stop.sh)
check_eq "typed by a person: source and initiator" '"cli" "tester"' "$(field "$(record "$ID")" source) $(field "$(record "$ID")" initiator)"
check_events "typed by a person" "job.queued|ID-docker-app-stop-zz-hstest-arr|info|job queued|-" "$(audit ok start "zz-hstest-arr stop" tester)"

echo "== the job fails"
setup; echo 5 > "$FAKE/fail-compose"; mark
started_unit zz-hstest-arr stop
check_eq "a start that will fail still answers started: exit 0" 0 "$RC"
run_unit "$UNIT"
# the exit status of compose is lost: the job ends with 1
check_eq "failed job: exit status" 1 "$JOB_RC"
failed=$(record "$ID")
check_eq "failed job: state, exit" '"failed" 1' "$(field "$failed" state) $(field "$failed" exit)"
check_eq "failed job: error" '{"category":"exit","message":"exit status 1"}' "$(field "$failed" error)"
check_events "failed job" "job.queued|ID-docker-app-stop-zz-hstest-arr|info|job queued|-" "$(audit ok start "zz-hstest-arr stop")" \
  "job.running|ID-docker-app-stop-zz-hstest-arr|info|job started|-" 'job.failed|ID-docker-app-stop-zz-hstest-arr|error|job failed (exit 1)|{"exit":1}'
check_signals "start and failed job" event:area.jobs event:area.system --all
check_eq "failed job: the wrapper sends no push (OnFailure of the unit does)" 0 "$(pushes)"
as_web sys jobs tail "$UNIT"
check_run "failed job: sys jobs tail" 0 "$(lines "state|failed" "exit|1" "line|Started Stop zz-hstest-arr." "line|" "line|── Stop zz-hstest-arr ──" \
  "line|Error: stand-in failure of compose" "line|  ✗ The stop of zz-hstest-arr failed." "next|5")"

echo "-- the job checks again: the app, or docker, went away after the answer"
setup
started_unit zz-hstest-arr start; touch "$FAKE/no-zz-hstest-arr"
run_unit "$UNIT"
check_eq "app gone: the job fails" '1 "failed"' "$JOB_RC $(field "$(record "$ID")" state)"
check_match "app gone: the journal says why" "No app called 'zz-hstest-arr' was found." "$(cat "$FAKE/units/$UNIT.service/journal")"
check_eq "app gone: compose does not run" "" "$(changes)"
setup
started_unit zz-hstest-arr start; echo STOPPED > "$FAKE/ct/docker/state"
run_unit "$UNIT"
check_eq "docker stopped: the job fails" '1 "failed"' "$JOB_RC $(field "$(record "$ID")" state)"
check_match "docker stopped: the journal says why" "Docker is not on or not running." "$(cat "$FAKE/units/$UNIT.service/journal")"

echo "-- systemd does not start the unit"
setup; touch "$FAKE/run-fail"; mark
as_web sys docker-app start zz-hstest-arr start
check_run "unit refused" 1 "$(lines 'status|refused' 'reason|The background job could not be started.' 'code|job.start-failed')"
check_events "unit refused" "job.queued|ID-docker-app-start-zz-hstest-arr|info|job queued|-" \
  'job.failed|ID-docker-app-start-zz-hstest-arr|error|job failed (exit 1)|{"exit":1}' "$(audit failed start "zz-hstest-arr start")"
check_signals "unit refused" event:area.system
check_no_surprise "failure"

echo "-- a closed vault and an app that needs a private image"
setup
printf 'ghcr.io\tanna\n' > "$HS_STATE_DIR/docker-registries.tsv"
echo 0000-stand-in > "$HS_STATE_DIR/vault-uuid"
ln -sfn "$WORK/vault/secrets/docker-registry-ghcr.io" "$HS_STATE_DIR/docker-registry-ghcr.io"
LOCKED=$(lines 'status|refused' 'reason|The vault is closed: the token for ghcr.io is in it.' 'fix|hs vault open' 'code|vault.locked')
as_web sys docker-app plan zz-hstest-kept start
check_run "plan start of a stopped app: refused" 1 "$LOCKED"
as_web sys docker-app plan zz-hstest-kept restart
check_run "plan restart of a stopped app: refused" 1 "$LOCKED"
for pair in "zz-hstest-kept stop" "zz-hstest-arr start" "zz-hstest-arr restart" "zz-hstest-arr stop"; do
  read -r app action <<<"$pair"
  as_web sys docker-app plan "$app" "$action"
  check_eq "plan $action $app: not refused (no image is pulled)" 0 "$RC"
done
# LOOKS WRONG: the header of docker-app-change.sh says every check is repeated at start and that start, stop and restart never need the
# token. The plan of a stopped app checks it, the start does not: it answers started and the job fails.
started_unit zz-hstest-kept start
check_eq "LOOKS WRONG: start does not repeat the vault check" "0 started" "$RC $(awk -F'\t' '$1 == "status" { print $2 }' <<<"$OUT")"
run_unit "$UNIT"
check_eq "...and the job fails" 1 "$JOB_RC"
check_match "...with the reason in the journal only" "The vault is closed: the token for ghcr.io is in it." "$(cat "$FAKE/units/$UNIT.service/journal")"
check_eq "...before compose runs" "" "$(changes)"
rm -f "$HS_STATE_DIR/docker-registries.tsv" "$HS_STATE_DIR/vault-uuid" "$HS_STATE_DIR/docker-registry-ghcr.io"
check_no_surprise "vault"

echo "== cancel"
setup; : > "$FAKE/hang-compose"
started_unit zz-hstest-arr stop
run_unit_bg "$UNIT"
mark
as_web sys jobs plan stop "$UNIT"
check_eq "cancel plan" "$(lines "status|ok" "heading|stop Stop zz-hstest-arr" "step|stop the unit hs-job-docker-app-stop-zz-hstest-arr-HHMMSS.service" \
  "note|What the job did already stays done." "note|The job record will say cancelled by root" \
  "command|systemctl stop hs-job-docker-app-stop-zz-hstest-arr-HHMMSS.service" "long|no")" "$(norm <<<"$OUT")"
as_web sys jobs start stop "$UNIT"
check_run "cancel" 0 "$(lines "status|done")"
wait_unit
check_eq "cancel: the job ended by SIGTERM" 143 "$JOB_RC"
cancelled=$(record "$ID")
check_eq "cancel: state, exit" '"cancelled" null' "$(field "$cancelled" state) $(field "$cancelled" exit)"
check_eq "cancel: the cancel block" '{"requested_by":"root","at":"T","safe":true}' "$(field "$cancelled" cancel)"
check_events "cancel" "job.cancelled|ID-docker-app-stop-zz-hstest-arr|info|job stopped by root|-"
# LOOKS WRONG: nothing is refreshed after a cancel (see tests/app-start-stop.sh); what compose already does inside docker goes on or not,
# nothing looks
check_signals "cancel"
check_eq "cancel: no push" 0 "$(pushes)"
as_web sys jobs tail "$UNIT"
check_match "LOOKS WRONG: sys jobs tail calls the cancelled job ok" "^state${T}ok" "$OUT"
check_no_surprise "cancel"

echo "== the web server around these rows (scripts/web-serve.py)"
web=$(timeout 60 python3 - "$SCRIPTS" <<'PY' 2>&1
import importlib.util, sys
sys.path.insert(0, sys.argv[1])
spec = importlib.util.spec_from_file_location("web_serve", sys.argv[1] + "/web-serve.py")
ws = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ws)
for action in ("start", "stop", "restart"):
    got = ws.validate_change({"area": "docker-app", "args": ["zz-hstest-arr", action]})
    print("allowed" if got else "refused", "docker-app zz-hstest-arr", action, "->", ws.area_refresh("docker-app"))
PY
)
check_eq "web-serve: what it lets through and what it refreshes after a start" "$(printf '%s\n' 'allowed docker-app zz-hstest-arr start -> @instances' \
  'allowed docker-app zz-hstest-arr stop -> @instances' 'allowed docker-app zz-hstest-arr restart -> @instances')" "$web"
finish
