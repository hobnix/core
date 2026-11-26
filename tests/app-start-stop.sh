#!/usr/bin/env bash
# What starting and stopping an app does TODAY (hobnix/core#1335, docs/adr/0001-rust-strangler.md, docs/PLAN-core-daemon.md step P4): a
# characterization test. It records behaviour, it does not say the behaviour is right. A line "LOOKS WRONG" marks behaviour that looks like
# a bug: it is asserted because it is what happens now. Whoever changes it, changes the assertion in the same commit, on purpose.
# Not compared with a real server yet (the "Hardware test" box of #1335).
#
# This file: an app that is an Incus instance (also a recipe app: the Apps page starts and stops the instances of the app one by one).
# tests/app-start-stop-docker.sh: an app in the container docker. Stand-ins and the knob HS_UNDER_TEST: tests/lib-appfakes.sh.
#
# Every path by which an app is started or stopped today:
#   A person       hs ct <ct> start|stop|restart       scripts/manage-ct.sh --start|--stop|--restart, in the foreground, no job
#                  hs job stop <unit>                  ends a running job (scripts/jobs.sh stop)
#                  (an app in docker has no `hs` command for a person)
#   Web interface  hs sys ct plan|start <ct> start|stop|restart [--autostart off, stop only]    scripts/ct-change.sh, start = a job
#                    callers: web/src/pages/Apps.svelte, Workloads.svelte, instances/Instance.svelte
#                  hs sys docker-app plan|start <app> start|stop|restart    scripts/docker-app-change.sh, start = a job
#                    callers: web/src/pages/Workloads.svelte, docker/DockerApp.svelte
#                  hs sys jobs plan|start stop <unit>  cancel (scripts/jobs-change.sh; web/src/files/api.js and the job views)
#                  reads while and after a job: sys jobs tail|show|running|records|record
#                  scripts/web-serve.py: allowlist (CHANGES), HS_ACTOR, parse_change, and after every start a refresh of the area of its own
#   Other rows     hs sys jobs stop <unit>             scripts/jobs.sh stop (no caller in web/src, named in the help of sys fm progress)
#   Job wrapper    scripts/lib/job.sh hs_job: a transient unit, the job record (scripts/job-record.py or hobnix job-record, ADR 0004),
#                  notify.sh after success, OnFailure=hs-notify-failure@ for the push after a failure
#   Events         job.queued|running|ok|failed|cancelled, notify.sent, audit.ok|failed (dispatcher, rows with the flag `changes`).
#                  ct.started and ct.stopped do NOT come from these commands but from the Incus watcher of hs-live
#                  (scripts/live-collect.py IncusWatch; recorded by tests/live-state-test.py, not here).
#   Refresh        dispatcher (rows `changes`: event:area.<topic>), hs_job after the start (event:area.jobs), the job wrapper at its end
#                  (--all, any exit status), the counter reads:jobs-records (job steps only), jobs.sh stop (event:job.stopped), web-serve
#                  after a start (the area), outside these commands scripts/unit-watch.py (hs-job-*.service -> jobs-running,
#                  tests/unit-watch.sh), the Incus watcher (event:ct.*) and the Docker watcher (event:docker.changed)
#
# Also starts or stops instances, as a side effect of another operation; NOT recorded here: hs sys apps (install, retry, cleanup, remove),
# hs ct add / create / delete / restore / ip / update / update-all, the app auto update, share changes and share-cache --restart, hs mac,
# the recipes (scripts/recipes/_lib.sh), hs docker enable|disable|mount|gpu, the other docker-app actions (pull, recreate, rebuild,
# app-save, delete), hs storage incident pause|resume (incus pause, a freeze; tests/storage-incident.sh), autostart at boot, shutdown and
# reboot, the reconcile of a job after a reboot (tests/job-reconcile.sh), hs ext start|stop (services of extensions, not apps), and what
# happens outside hobnix (the pages of Incus or Arcane, inside the instance).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
[ "$(uname -s)" = Linux ] || { echo "  skip  needs Linux (WSL): process groups, setsid"; exit 77; }
for tool in jq python3 setsid; do have "$tool" || { skip "needs $tool"; finish; exit; }; done
# shellcheck source=tests/lib-appfakes.sh
. "$(dirname "$0")/lib-appfakes.sh"

setup() {   # a fresh system with the app in the given state
  reset_fakes
  instance app "${1:-RUNNING}"
}
started_unit() {   # started_unit <action> [option...]: the web starts the job; sets UNIT and ID
  as_web sys ct start app "$@"
  UNIT=$(unit_of_output)
  ID=$(job_id_of "$UNIT")
}
state_of() { cat "$FAKE/ct/$1/state"; }
autostart_kept() { [ -e "$FAKE/ct/$1/autostart" ] && echo yes || echo no; }

echo "== a person: hs ct <ct> start|stop|restart (foreground, no job)"
for row in "start STOPPED RUNNING" "stop RUNNING STOPPED" "restart RUNNING RUNNING"; do
  read -r action before after <<<"$row"
  setup "$before"; mark
  as_person ct app "$action"
  check_run "hs ct app $action" 0 ""
  check_eq "hs ct app $action: stderr" "" "$ERR"
  check_eq "hs ct app $action: what Incus was told" "incus $action app" "$(changes)"
  check_eq "hs ct app $action: the state after" "$after" "$(state_of app)"
  check_eq "hs ct app $action: no job record" 0 "$(job_files)"
  check_events "hs ct app $action" "audit.ok|ct app $action|info|-|{\"actor\":\"tester\",\"exit\":0}"
  check_signals "hs ct app $action" event:area.instances
  check_eq "hs ct app $action: no push" 0 "$(pushes)"
done

echo "-- a failure: the exit status and the message of incus come through; audit and refresh also then"
setup STOPPED; echo 3 > "$FAKE/fail-start"; mark
as_person ct app start
check_run "hs ct app start fails" 3 ""
check_eq "hs ct app start fails: stderr" "Error: stand-in failure of start" "$ERR"
check_events "hs ct app start fails" 'audit.failed|ct app start|warn|-|{"actor":"tester","exit":3}'
check_signals "hs ct app start fails" event:area.instances

echo "-- nothing checks the state first: start of a running instance and stop of a stopped one fail in Incus"
setup RUNNING; as_person ct app start
check_run "start of a running instance" 1 ""
check_eq "start of a running instance: stderr" "Error: The instance is already running" "$ERR"
setup STOPPED; as_person ct app stop
check_run "stop of a stopped instance" 1 ""

echo "-- refused: no such instance"
setup; mark
as_person ct ghost start
check_run "hs ct ghost start" 1 ""
check_eq "hs ct ghost start: stderr" "$(printf "  ✗ 'ghost' does not exist.\n    Fix: hs ct list")" "$ERR"
check_eq "hs ct ghost start: Incus is not told to change anything" "" "$(changes)"
check_events "hs ct ghost start" 'audit.failed|ct ghost start|warn|-|{"actor":"tester","exit":1}'
check_signals "hs ct ghost start" event:area.instances

echo "-- LOOKS WRONG: the rows have fixed arguments without {rest}, so every further word is dropped without a message"
# scripts/manage-ct.sh documents --dry-run for any change and --keep-off for --stop. Through `hs ct <ct> stop` neither arrives.
setup RUNNING
as_person ct app stop --dry-run
check_run "LOOKS WRONG: hs ct app stop --dry-run exits 0 and prints nothing" 0 ""
check_eq "LOOKS WRONG: hs ct app stop --dry-run really stops the app" "incus stop app" "$(changes)"
check_eq "LOOKS WRONG: hs ct app stop --dry-run, the state after" STOPPED "$(state_of app)"
setup RUNNING
as_person ct app stop --keep-off
check_run "LOOKS WRONG: hs ct app stop --keep-off" 0 ""
check_eq "LOOKS WRONG: --keep-off is dropped, the instance still starts at boot" "incus stop app" "$(changes)"

echo "-- the locked container docker (every app in it) can be stopped and started by hand: only delete and device changes are locked"
reset_fakes; instance docker RUNNING docker
as_person ct docker stop
check_run "hs ct docker stop" 0 ""
check_eq "hs ct docker stop: what Incus was told" "incus stop docker" "$(changes)"
check_no_surprise "a person"

echo "== web: hs sys ct plan"
plan_of() {   # plan_of <action>
  case "$1" in
    start) lines "status|ok" "heading|start app" "step|start the instance" "command|incus start app" "long|no" ;;
    stop) lines "status|ok" "heading|stop app" "step|stop the instance" "note|Services that go down: immich, postgres" "command|incus stop app" "long|no" ;;
    keepoff) lines "status|ok" "heading|stop app" "step|stop the instance" "step|keep it off at boot" "note|Services that go down: immich, postgres" \
      "command|incus stop app" "command|incus config unset app boot.autostart" "long|no" ;;
    restart) lines "status|ok" "heading|restart app" "step|stop and start the instance" "note|Services that go down: immich, postgres" "command|incus restart app" "long|no" ;;
  esac
}
setup RUNNING; mark
for action in start stop restart; do   # also `start` of an app that runs: the plan does not look at the state
  as_web sys ct plan app "$action"
  check_run "plan $action" 0 "$(plan_of "$action")"
done
as_web sys ct plan app stop --autostart off
check_run "plan stop --autostart off" 0 "$(plan_of keepoff)"
as_web sys ct plan app stop --autostart no
check_run "plan stop --autostart no (the same)" 0 "$(plan_of keepoff)"
as_web sys ct plan app start --confirm something
check_run "plan start with a --confirm nobody asked for: taken and ignored" 0 "$(plan_of start)"
check_eq "a plan changes nothing" "" "$(changes)"
check_eq "a plan makes no job" 0 "$(job_files)"
check_events "plans (no audit line: the rows have no flag changes)"
check_signals "plans"

echo "== web: refusals of plan and start (the same answer, no job, no event, no refresh)"
refused() {   # refused "what" "<stdout>" <ct> <action> [option...]
  local what=$1 want=$2 verb
  shift 2
  for verb in plan start; do
    mark
    as_web sys ct "$verb" "$@"
    check_run "$verb: $what" 1 "$want"
    check_events "$verb: $what"
    check_signals "$verb: $what"
  done
}
setup RUNNING
refused "a name that is not one" "$(lines 'status|refused' 'reason|invalid instance name' 'code|name.invalid')" App_1 start
refused "an unknown action" "$(lines 'status|refused' 'reason|unknown action' 'code|action.unknown')" app halt
refused "an unknown option" "$(lines 'status|refused' 'reason|unknown option --force' 'code|option.unknown')" app stop --force
refused "stop --autostart on" "$(lines 'status|refused' "reason|a stop can only keep the instance off at boot: --autostart off" 'code|ct.value-invalid')" app stop --autostart on
refused "start --autostart off" "$(lines 'status|refused' 'reason|--autostart belongs to set and stop' 'code|ct.option-misplaced')" app start --autostart off
refused "restart --autostart off" "$(lines 'status|refused' 'reason|--autostart belongs to set and stop' 'code|ct.option-misplaced')" app restart --autostart off
# LOOKS WRONG: two `reason` lines, no `code` and no `fix` line (ADR 0028); the web keeps only the last reason (checked below)
GONE=$(lines "status|refused" "reason|'ghost' does not exist." "reason|Fix: hs ct list")
refused "no such instance" "$GONE" ghost start
touch "$FAKE/down"
# LOOKS WRONG: an Incus daemon that does not answer reads as "the instance does not exist"
refused "Incus does not answer" "$(lines "status|refused" "reason|'app' does not exist." "reason|Fix: hs ct list")" app start
rm -f "$FAKE/down"
check_eq "refusals change nothing" "" "$(changes)"
check_eq "refusals make no job" 0 "$(job_files)"
as_web sys ct start app
check_eq "without an action there is no row: exit 1" 1 "$RC"
check_eq "without an action there is no row: nothing on stdout" "" "$OUT"
check_match "without an action there is no row: stderr" "unknown command 'sys ct start app'" "$ERR"

echo "== web: hs sys ct start, then the job (success)"
for row in "start STOPPED RUNNING" "stop RUNNING STOPPED" "restart RUNNING RUNNING"; do
  read -r action before after <<<"$row"
  setup "$before"; mark
  started_unit "$action"
  check_eq "start $action: exit 0" 0 "$RC"
  check_eq "start $action: stdout" "$(lines "status|started" "unit|hs-job-ct-$action-app-HHMMSS")" "$(norm <<<"$OUT")"
  check_eq "start $action: stderr" "" "$ERR"
  check_eq "start $action: the answer comes before anything changed" "" "$(changes)"
  # LOOKS WRONG: initiator is not the signed-in person: hs_job reads HS_JOB_INITIATOR, SUDO_USER, USER, never HS_ACTOR. The "root" here is
  # the USER that as_web gives the web process; see "who and where in the record" for a process without one.
  # LOOKS WRONG: sys ct rows have no flag changes, so a start or stop from the web writes no audit line (hs ct <ct> stop and the
  # docker-app rows do)
  queued=$(record "$ID")
  check_eq "start $action: the record while queued" "$(printf '%s\n' 'id="ID-ct-'"$action"'-app"' "slug=\"ct-$action-app\"" \
    "description=\"hs ct app $action\"" 'source="web"' 'initiator="root"' "unit=\"hs-job-ct-$action-app-HHMMSS\"" 'queued="T"' 'started=null' \
    'ended=null' 'state="queued"' 'exit=null' 'step=null' 'progress=null' 'error=null' 'result=null' 'cancel=null' 'version=1' 'parent=null' \
    'kind=null' 'waiting=null' "key=\"ct app $action\"")" "$queued"
  check_events "start $action: before the job runs" "job.queued|ID-ct-$action-app|info|job queued|-"
  check_signals "start $action: before the job runs" event:area.jobs

  unitdir=$FAKE/units/$UNIT.service
  check_eq "start $action: the description of the unit" "hs ct app $action" "$(cat "$unitdir/description")"
  check_eq "start $action: the unit properties" "OnFailure=hs-notify-failure@$UNIT.service" "$(cat "$unitdir/props")"
  # the names that reach the unit; the HS_JOBS_DIR of the test is handed on because it is set
  check_eq "start $action: what the unit is told" "HS_CALLER HS_JOBS_DIR HS_JOB_ID HS_JOB_KEY HS_JOB_UNIT HS_LANG PATH" \
    "$(sed 's/=.*//' "$unitdir/env.txt" | grep -v '^HOBNIX_BIN$\|^HS_JOB_RECORD$' | LC_ALL=C sort | paste -sd' ' -)"
  check_match "start $action: HS_CALLER of the unit is job" '(^| )HS_CALLER=job( |$)' "$(paste -sd' ' "$unitdir/env.txt")"
  check_match "start $action: the row key of the unit" "HS_JOB_KEY=ct app $action" "$(cat "$unitdir/env.txt")"

  as_web sys jobs running
  check_eq "start $action: sys jobs running" "$(lines "hs-job-ct-$action-app-HHMMSS.service|hs ct app $action|-")" "$(norm <<<"$OUT")"
  as_web sys jobs tail "$UNIT"
  check_run "start $action: sys jobs tail while it runs" 0 "$(lines "state|running" "line|Started hs ct app $action." "next|1")"
  as_web sys jobs records
  check_eq "start $action: sys jobs records while queued" \
    "$(lines "ID-ct-$action-app|ct-$action-app|hs ct app $action|queued|T|-|-|-|-|-|-|-|-|-|ct app $action")" \
    "$(norm <<<"$OUT" | sed -E 's/[0-9-]{10}T[0-9:]{8}Z/T/g')"

  mark
  run_unit "$UNIT"
  check_eq "job $action: exit 0" 0 "$JOB_RC"
  check_eq "job $action: what Incus was told" "incus $action app" "$(changes)"
  check_eq "job $action: the state after" "$after" "$(state_of app)"
  done_record=$(record "$ID")
  check_eq "job $action: the record after" \
    "$(sed -e 's/^started=null/started="T"/' -e 's/^ended=null/ended="T"/' -e 's/^state="queued"/state="ok"/' -e 's/^exit=null/exit=0/' <<<"$queued")" "$done_record"
  check_events "job $action" "job.running|ID-ct-$action-app|info|job started|{\"key\":\"ct app $action\"}" \
    "job.ok|ID-ct-$action-app|info|job finished|{\"key\":\"ct app $action\"}" "notify.sent|main|info|hs|-"
  # no counter of its own for the record: only the full refresh at the end of the job
  check_signals "job $action" --all
  check_eq "job $action: one push" 1 "$(pushes)"
  check_match "job $action: the push says the job finished" "hs ct app $action finished" "$(cat "$FAKE/pushes")"
  as_web sys jobs tail "$UNIT"
  check_run "job $action: sys jobs tail after" 0 "$(lines "state|ok" "exit|0" "line|Started hs ct app $action." "next|1")"
  as_web sys jobs tail "$UNIT" 1
  check_run "job $action: sys jobs tail from line 1" 0 "$(lines "state|ok" "exit|0" "next|1")"
  check_no_surprise "job $action"
done

echo "-- stop and keep it off at boot"
setup RUNNING
started_unit stop --autostart off
run_unit "$UNIT"
check_eq "keep off: the job ends well" 0 "$JOB_RC"
check_eq "keep off: what Incus was told, in order" "$(printf 'incus stop app\nincus config unset app boot.autostart')" "$(changes)"
check_eq "keep off: no longer started at boot" no "$(autostart_kept app)"
kept=$(record "$ID")
# LOOKS WRONG: the key drops --autostart off; web/src/pages/instances/pending.js waits for "ct app stop --autostart off", the key a
# browser builds from the arguments of its plan. A page that only knows the record cannot match that one.
check_eq "keep off: the row key" '"ct app stop"' "$(field "$kept" key)"
check_eq "keep off: the description" '"hs ct app stop"' "$(field "$kept" description)"

echo "-- who and where in the record"
setup STOPPED
as_person sys ct start app start
ID=$(job_id_of "$(unit_of_output)")
person=$(record "$ID")
# LOOKS WRONG: ct-change.sh sets HS_CALLER=ui when it is not set, so a start typed at the command line is recorded as from the web
check_eq "sys ct start typed by a person: source" '"web"' "$(field "$person" source)"
check_eq "sys ct start typed by a person: initiator" '"tester"' "$(field "$person" initiator)"
setup STOPPED
_hs -u USER HS_CALLER=web HS_ACTOR=anna timeout 60 "${HS_CMD[@]}" sys ct start app start
check_eq "from the web by anna, the web process without USER: initiator" null "$(field "$(record "$(job_id_of "$(unit_of_output)")")" initiator)"
check_no_surprise "success"

echo "== web: the job fails"
setup RUNNING; echo 7 > "$FAKE/fail-stop"; mark
started_unit stop --autostart off
check_eq "a start that will fail still answers started: exit 0" 0 "$RC"
check_match "a start that will fail still answers started" "^status${T}started" "$OUT"
run_unit "$UNIT"
check_eq "failed job: the exit status of incus" 7 "$JOB_RC"
check_eq "failed job: the autostart setting is not touched after a failed stop" "incus stop app" "$(changes)"
check_eq "failed job: still started at boot" yes "$(autostart_kept app)"
failed=$(record "$ID")
check_eq "failed job: state" '"failed"' "$(field "$failed" state)"
check_eq "failed job: exit" 7 "$(field "$failed" exit)"
check_eq "failed job: error (no word of what incus said)" '{"category":"exit","message":"exit status 7"}' "$(field "$failed" error)"
check_eq "failed job: ended" '"T"' "$(field "$failed" ended)"
check_events "failed job" "job.queued|ID-ct-stop-app|info|job queued|-" 'job.running|ID-ct-stop-app|info|job started|{"key":"ct app stop"}' \
  'job.failed|ID-ct-stop-app|error|job failed (exit 7)|{"exit":7,"key":"ct app stop"}'
check_signals "start and failed job" event:area.jobs --all
check_eq "failed job: the wrapper sends no push (OnFailure of the unit does)" 0 "$(pushes)"
as_web sys jobs tail "$UNIT"
check_run "failed job: sys jobs tail" 0 "$(lines "state|failed" "exit|7" "line|Started hs ct app stop." "line|Error: stand-in failure of stop" "next|2")"
as_web sys jobs show "$UNIT"
check_eq "failed job: sys jobs show" "$(lines "unit|hs-job-ct-stop-app-HHMMSS.service" "description|hs ct app stop" "state|failed" "exit|7" \
  "started|T" "last|T" "next|-" "command|")" "$(norm <<<"$OUT" | sed -E "s/^(started|last)${T}[0-9]{2}\.[0-9]{2}\. [0-9:]{5}\$/\1${T}T/")"

echo "-- a job for an instance that went away between the answer and the job"
setup STOPPED
started_unit start
rm -rf "$FAKE/ct/app"
run_unit "$UNIT"
check_eq "gone: the job fails" 1 "$JOB_RC"
check_eq "gone: the record" '"failed"' "$(field "$(record "$ID")" state)"
check_eq "gone: Incus is not told to start" "" "$(changes)"

echo "-- systemd does not start the unit"
setup STOPPED; touch "$FAKE/run-fail"; mark
as_web sys ct start app start
check_run "unit refused" 1 "$(lines 'status|refused' 'reason|the job could not be started' 'code|job.start-failed')"
check_eq "unit refused: stderr is the one of systemd-run" "Failed to start transient service unit: stand-in" "$ERR"
ID=$(basename "$(find "$HS_JOBS_DIR" -name '*.json' | head -n 1)" .json)
broken=$(record "$ID")
check_eq "unit refused: a record stays, failed" '"failed"' "$(field "$broken" state)"
check_eq "unit refused: exit 1, never started" "1 null" "$(field "$broken" exit) $(field "$broken" started)"
# LOOKS WRONG: this job.failed has no row key (HS_JOB_KEY is set for the unit only), and nothing is refreshed for the new record
check_events "unit refused" "job.queued|ID-ct-start-app|info|job queued|-" 'job.failed|ID-ct-start-app|error|job failed (exit 1)|{"exit":1}'
check_signals "unit refused"

echo "-- no lock and no check for a job that already works on the app"
setup RUNNING
started_unit stop; first=$UNIT
as_web sys ct start app restart
check_eq "a restart while a stop is queued: accepted" "0 started" "$RC $(awk -F'\t' '$1 == "status" { print $2 }' <<<"$OUT")"
check_eq "two records for the same app" 2 "$(job_files)"
run_unit "$first"; run_unit "$(unit_of_output)"
check_eq "the second job fails in Incus: it finds the instance stopped" 1 "$JOB_RC"
check_no_surprise "failure"

echo "== cancel: hs sys jobs plan|start stop <unit>"
cancel_setup() {   # a stop of the app that hangs in Incus
  setup RUNNING; : > "$FAKE/hang-stop"
  started_unit stop --autostart off
  run_unit_bg "$UNIT"
}
cancel_setup
check_eq "running: the record" '"running"' "$(field "$(record "$ID")" state)"
mark
as_web sys jobs plan stop "$UNIT"
check_eq "cancel plan: exit 0" 0 "$RC"
check_eq "cancel plan: stdout" "$(lines "status|ok" "heading|stop hs ct app stop" "step|stop the unit hs-job-ct-stop-app-HHMMSS.service" \
  "note|What the job did already stays done." "note|The job record will say cancelled by root" \
  "command|systemctl stop hs-job-ct-stop-app-HHMMSS.service" "long|no")" "$(norm <<<"$OUT")"
check_events "cancel plan"
check_signals "cancel plan"
as_web sys jobs start stop "$UNIT"
check_run "cancel" 0 "$(lines "status|done")"
wait_unit
check_eq "cancel: the job ended by SIGTERM" 143 "$JOB_RC"
check_eq "cancel: systemd was told to stop the unit" "stop $UNIT.service" "$(cat "$FAKE/systemctl.log")"
cancelled=$(record "$ID")
check_eq "cancel: state" '"cancelled"' "$(field "$cancelled" state)"
check_eq "cancel: no exit status" null "$(field "$cancelled" exit)"
check_eq "cancel: ended" '"T"' "$(field "$cancelled" ended)"
# LOOKS WRONG: requested_by is SUDO_USER or USER of the calling process (here the stand-in root), not the signed-in person (HS_ACTOR)
check_eq "cancel: the cancel block" '{"requested_by":"root","at":"T","safe":true}' "$(field "$cancelled" cancel)"
check_eq "cancel: no error" null "$(field "$cancelled" error)"
check_events "cancel" "job.cancelled|ID-ct-stop-app|info|job stopped by root|-"
# LOOKS WRONG: a cancel refreshes nothing, although ADR 0005 rule 8 asks for a refresh on every end: the wrapper is killed before its
# --all, and the rows have no flag changes. web-serve adds the area jobs (below); the instance lists wait for a watcher or their interval.
check_signals "cancel"
check_eq "cancel: no push" 0 "$(pushes)"
check_eq "cancel: what was asked of Incus stays asked; the rest of the job does not run" "incus stop app" "$(changes)"
check_eq "cancel: still started at boot" yes "$(autostart_kept app)"
as_web sys jobs tail "$UNIT"
# LOOKS WRONG: the progress view's read calls a cancelled job ok with exit 0 (a stopped transient unit is gone, and systemd answers
# Result=success for a unit it does not know; only the journal is left). Depends on the stand-in: check on a real server.
check_run "LOOKS WRONG: sys jobs tail after a cancel" 0 "$(lines "state|ok" "exit|0" "line|Started hs ct app stop." "line|Stopped hs ct app stop." "next|2")"
as_web sys jobs show "$UNIT"
check_match "cancel: sys jobs show says unknown" "^state${T}unknown\$" "$OUT"

echo "-- cancel a job that does not run"
mark
as_web sys jobs plan stop "$UNIT"
check_eq "stop again: plan is refused" "1 $(lines 'status|refused' "reason|$UNIT.service is not running." 'code|job.not-running')" "$RC $OUT"
as_web sys jobs start stop "$UNIT"
check_eq "stop again: start is refused the same way" "1 $(lines 'status|refused' "reason|$UNIT.service is not running." 'code|job.not-running')" "$RC $OUT"
check_events "stop again"
check_signals "stop again"
check_eq "stop again: the record stays cancelled" '"cancelled"' "$(field "$(record "$ID")" state)"

echo "-- systemd cannot stop the unit"
cancel_setup; touch "$FAKE/stop-fail"; mark
as_web sys jobs start stop "$UNIT"
check_run "stop fails" 1 "$(lines 'status|refused' 'reason|systemctl failed' 'code|job.systemctl-failed')"
still=$(record "$ID")
check_eq "stop fails: the record runs again" '"running" null null' "$(field "$still" state) $(field "$still" ended) $(field "$still" cancel)"
check_events "stop fails"
check_signals "stop fails"
rm -f "$FAKE/stop-fail"; : > "$FAKE/release"
wait_unit
check_eq "stop fails: the job goes on and ends well" "0 \"ok\"" "$JOB_RC $(field "$(record "$ID")" state)"
check_no_surprise "cancel"

echo "== the other way to stop a job: jobs.sh stop"
cancel_setup; mark
as_web sys jobs stop "$UNIT"
check_run "sys jobs stop" 0 "  ✓ Stopped $UNIT"
wait_unit
# LOOKS WRONG: no cancel in the record and no job.cancelled event: the record says running until a reboot reconciles it
check_eq "LOOKS WRONG: sys jobs stop leaves the record running" '"running" null' "$(field "$(record "$ID")" state) $(field "$(record "$ID")" ended)"
check_events "sys jobs stop"
check_signals "sys jobs stop" event:job.stopped

cancel_setup; mark
as_person job stop "$UNIT"
check_run "hs job stop (a person)" 0 "  ✓ Stopped $UNIT"
wait_unit
check_eq "LOOKS WRONG: hs job stop leaves the record running" '"running"' "$(field "$(record "$ID")" state)"
# LOOKS WRONG: no audit line either: the row has the flag nohelp, which also switches the audit off (scripts/lib/audit.sh)
check_events "hs job stop"
check_signals "hs job stop" event:job.stopped event:area.jobs

reset_fakes
as_web sys jobs stop sshd
# LOOKS WRONG: no check that the unit is a job of hobnix (sys jobs start stop has one). No page calls this row.
check_run "LOOKS WRONG: sys jobs stop takes any unit" 0 "  ✓ Stopped sshd"
check_eq "LOOKS WRONG: sys jobs stop sshd reaches systemd" "stop sshd" "$(cat "$FAKE/systemctl.log")"
as_web sys jobs start stop sshd
check_run "sys jobs start stop refuses a unit that is no job" 1 "$(lines 'status|refused' 'reason|that is not a job of this server (hs-*)' 'code|job.unit-invalid')"

echo "== the web server around these rows (scripts/web-serve.py, stays in Python until P6)"
setup RUNNING
as_web sys ct plan ghost stop
printf '%s\n' "$OUT" > "$WORK/gone.out"
web=$(timeout 60 python3 - "$SCRIPTS" "$WORK/gone.out" <<'PY' 2>&1
import importlib.util, sys
sys.path.insert(0, sys.argv[1])
spec = importlib.util.spec_from_file_location("web_serve", sys.argv[1] + "/web-serve.py")
ws = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ws)
for area, args in (("ct", ["app", "start"]), ("ct", ["app", "stop"]), ("ct", ["app", "stop", "--autostart", "off"]), ("ct", ["app", "restart"]),
                   ("jobs", ["stop", "hs-job-ct-stop-app-101010"])):
    got = ws.validate_change({"area": area, "args": args})
    print("allowed" if got else "refused", area, " ".join(args), "->", ws.area_refresh(area))
print("reason shown:", ws.parse_change(open(sys.argv[2]).read(), 1)["reason"])
PY
)
check_eq "web-serve: what it lets through and what it refreshes after a start; the reason it shows for a missing instance" \
  "$(printf '%s\n' 'allowed ct app start -> @instances' 'allowed ct app stop -> @instances' 'allowed ct app stop --autostart off -> @instances' \
    'allowed ct app restart -> @instances' 'allowed jobs stop hs-job-ct-stop-app-101010 -> @jobs' \
    'reason shown: Fix: hs ct list')" "$web"
finish
