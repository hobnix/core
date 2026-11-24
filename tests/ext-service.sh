#!/usr/bin/env bash
# The service-extension lifecycle v1 (docs/adr/0011-extension-service-lifecycle.md): the reference supervisor scripts/lib/ext_service.py against a test
# service (tests/fixtures/ext-service/svc.py): init and ready, delivery of subscribed events with acks and a cursor, health and heartbeat,
# shutdown, SIGTERM/SIGKILL, a start timeout, protocol errors, and the schema file. No root, python3 only.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
command -v python3 >/dev/null || { echo "python3 missing: skipped"; exit 0; }
RUN="python3 -I $SCRIPTS/lib/ext_service.py"
SVC=$ROOT/tests/fixtures/ext-service/svc.py
export SVC_LOG=$WORK/svc.log
EV=$WORK/events.jsonl
for r in '1 job failed a' '2 backup done b' '3 job failed c' '4 job done d'; do
  set -- $r
  printf '{"id":%s,"time":1700000000,"source":"%s","kind":"%s","subject":"%s","level":"info","text":"t","payload":null}\n' "$1" "$2" "$3" "$4" >> "$EV"
done

go() {   # go <mode> <run-for> [extra runner options]: out = the runner's lines, rc = its exit status
  local m=$1 f=$2; shift 2
  : > "$SVC_LOG"; rc=0
  out=$($RUN run --name fixsvc --run-for "$f" --grace 1 "$@" -- python3 -I "$SVC" "$m" 2>&1) || rc=$?
}
final() { printf '%s\n' "$out" | tail -n1 | python3 -I -c 'import json,sys; d=json.load(sys.stdin); print(eval(sys.argv[1]))' "$1"; }
states() { printf '%s\n' "$out" | python3 -I -c '
import json,sys
print(" ".join(d["state"] for d in map(json.loads, sys.stdin) if d.get("type") == "state"))'; }

echo "-- start, run, stop"
go good 3 --subscribe 'job.*' --events "$EV" --cursor "$WORK/cur" --health-interval 1
check_eq "a service that is ready and healthy is stopped on request: exit 0" "0 stopped" "$rc $(final 'd["state"]')"
check_eq "the states are starting, running, stopping, stopped" "starting running stopping stopped" "$(states)"
check_eq "init names the package and the subscription" "fixsvc ['job.*']" "$(head -n1 "$SVC_LOG" | python3 -I -c 'import json,sys; d=json.loads(sys.stdin.readline()); print(d["name"], d["subscribe"])')"
check_eq "the service gets shutdown last" shutdown "$(tail -n1 "$SVC_LOG" | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["type"])')"
check_eq "only the subscribed events are delivered (job.failed 1 and 3, job.done 4)" "1 3 4" "$(grep '"type": "event"' "$SVC_LOG" | python3 -I -c 'import json,sys; print(" ".join(str(json.loads(l)["id"]) for l in sys.stdin))')"
check_eq "the cursor is the last acknowledged id" 4 "$(cat "$WORK/cur")"
go good 3 --subscribe 'job.failed' --events "$EV" --cursor "$WORK/cur" --health-interval 1
check_eq "a restart does not repeat what was acknowledged" "0" "$(grep -c '"type": "event"' "$SVC_LOG")"
echo 2 > "$WORK/cur"
go good 3 --subscribe 'job.failed' --events "$EV" --cursor "$WORK/cur" --health-interval 1
check_eq "from cursor 2 only newer matching events arrive" "3" "$(grep '"type": "event"' "$SVC_LOG" | python3 -I -c 'import json,sys; print(" ".join(str(json.loads(l)["id"]) for l in sys.stdin))')"
check_eq "the cursor moves past events the service did not subscribe to" 4 "$(cat "$WORK/cur")"
echo 0 > "$WORK/cur"
go noack 3 --subscribe 'job.*' --events "$EV" --cursor "$WORK/cur" --health-interval 1
check_eq "without acks the cursor stays where it was (at-least-once)" 0 "$(cat "$WORK/cur")"
go emit 1 --health-interval 1
check_out "emit and snapshot messages are passed on" '"type":"snapshot"' printf '%s' "$out"
check_out "emit is passed on" 'pkg.fixsvc.seen' printf '%s' "$out"

echo "-- health"
go unhealthy 1.5 --health-interval 1
check_out "health ok=false makes the state degraded" 'degraded' printf '%s' "$(states)"
go silent 1.5 --health-interval 0.2 --missed 2
check_out "no heartbeat makes the state degraded" 'degraded' printf '%s' "$(states)"

echo "-- failures"
go crash 5 --health-interval 1
check_eq "a service that exits is failed (exit 1)" "1 failed exited" "$rc $(final 'd["state"] + " " + d["code"]')"
go badmsg 5 --health-interval 1
check_eq "a bad line is a protocol error" "1 protocol_error" "$rc $(final 'd["code"]')"
go ackbad 5 --health-interval 1
check_eq "an ack of an id that was not sent is a protocol error" "1 protocol_error" "$rc $(final 'd["code"]')"
go garbagefirst 5 --health-interval 1
check_eq "garbage before ready is a protocol error" "1 protocol_error" "$rc $(final 'd["code"]')"
go earlyack 5 --health-interval 1
check_eq "a message before ready is a protocol error" "1 protocol_error" "$rc $(final 'd["code"]')"
go longline 5 --health-interval 1
check_eq "a line over 1 MiB is a protocol error" "1 protocol_error" "$rc $(final 'd["code"]')"
# a deaf service with many large events must not freeze the supervisor: the stop still comes
BIG=$WORK/big.jsonl; python3 -I -c '
import json
for i in range(1, 301):
    print(json.dumps({"id": i, "time": 1, "source": "job", "kind": "failed", "subject": "s", "level": "info", "text": "t", "payload": {"p": "x" * 4000}}))' > "$BIG"
s=$SECONDS; go deaf 2 --subscribe 'job.*' --events "$BIG" --health-interval 1
check_eq "a service that stops reading does not block the stop" "0 stopped" "$rc $(final 'd["state"]')"
[ $((SECONDS - s)) -le 12 ] && pass "...in time" || fail "the stop took $((SECONDS - s)) s"
rc=0; $RUN run --name fixsvc --cursor /nonexistent/dir/c --subscribe 'job.*' --events "$EV" --health-interval 1 -- python3 -I "$SVC" good >/dev/null 2>&1 || rc=$?
check_eq "an error in the supervisor itself is not silent" 1 "$([ "$rc" -ne 0 ] && echo 1 || echo 0)"
sleep 0.5
if left=$(pgrep -af "^python3 -I $SVC good"); [ -n "$left" ]; then fail "the service is left running after a supervisor error: $left"; else pass "...and the service is not left running"; fi
s=$SECONDS; go slowready 30 --ready-timeout 1
check_eq "no ready in time: exit 75" "75 start_timeout" "$rc $(final 'd["code"]')"
[ $((SECONDS - s)) -le 6 ] && pass "the start timeout stops the process" || fail "start timeout took $((SECONDS - s)) s"
s=$SECONDS; go stubborn 1 --health-interval 1
check_eq "a service that ignores shutdown and SIGTERM is killed, the stop still counts as requested" "0 stopped" "$rc $(final 'd["state"]')"
[ $((SECONDS - s)) -le 8 ] && pass "SIGKILL follows" || fail "kill took $((SECONDS - s)) s"
sleep 0.3
if left=$(pgrep -af "^python3 -I $SVC"); [ -n "$left" ]; then fail "a service process is left behind: $left"; else pass "no process is left behind"; fi
rc=0; $RUN run --name Bad -- true >/dev/null 2>&1 || rc=$?
check_eq "a bad package name is refused" 2 "$rc"

echo "-- schema"
SCHEMA=$ROOT/docs/api/ext-service-v1.schema.json
check "the schema is valid JSON" python3 -I -c "import json; json.load(open('$SCHEMA'))"
check "the schema and the supervisor agree" python3 -I - "$SCHEMA" "$SCRIPTS/lib" <<'PY'
import json, sys
sys.path.insert(0, sys.argv[2])
import ext_service as p
d = json.load(open(sys.argv[1]))["$defs"]
assert {r["$ref"].split("/")[-1] for r in d["fromService"]["oneOf"]} == set(p.FROM_SERVICE)
assert set(d["state"]["enum"]) == set(p.STATES)
assert d["init"]["properties"]["v"]["const"] == p.VERSION
assert {r["$ref"].split("/")[-1] for r in d["fromCore"]["oneOf"]} == {"init", "event", "shutdown"}
PY

echo "-- init.integrations: only the declared ones, no key, sent in init"
LISTING=$(printf 'jellyfin\tmedia\trecipe\thttp://127.0.0.1:8096\tok\ta=1,b=2\tX-Emby-Token\nplex\tmedia\trecipe\t-\tmissing\t-\t-\nsecretapp\tvault\trecipe\thttp://h\tok\t-\t-\n')
: > "$SVC_LOG"
check "the bridge sends the declared rows in init and drops an undeclared integration" python3 -I - "$SCRIPTS/lib" "$SVC" "$SVC_LOG" "$LISTING" <<'PY'
import json, os, sys, threading
sys.path.insert(0, sys.argv[1])
import ext_service as p
rows = p.integration_rows(sys.argv[4], ["integration:media", "events:emit"])
assert [r["package"] for r in rows] == ["jellyfin", "plex"], rows
assert rows[0] == {"package": "jellyfin", "integration": "media", "source": "recipe", "api_url": "http://127.0.0.1:8096",
                   "extras": {"a": "1", "b": "2"}, "key_header": "X-Emby-Token"}
assert rows[1]["api_url"] is None and rows[1]["extras"] == {} and rows[1]["key_header"] is None
assert not any("key_file" in r or "key" in r or "key_state" in r for r in rows)
assert p.integration_rows(sys.argv[4], None) == [] and p.integration_rows(sys.argv[4], ["integration:other"]) == []
os.environ["SVC_LOG"] = sys.argv[3]
stop = threading.Event()
threading.Timer(1.5, stop.set).start()
p.supervise([sys.executable, "-I", sys.argv[2], "good"], "fixsvc", health_interval=1, grace=1, stop=stop, integrations=rows)
init = json.loads(open(sys.argv[3]).readline())
assert init["type"] == "init" and init["v"] == 1 and init["integrations"] == rows
PY
: > "$SVC_LOG"
check "without declared integrations init has no integrations field (older services see the same init)" python3 -I - "$SCRIPTS/lib" "$SVC" "$SVC_LOG" <<'PY'
import json, os, sys, threading
sys.path.insert(0, sys.argv[1])
import ext_service as p
os.environ["SVC_LOG"] = sys.argv[3]
stop = threading.Event()
threading.Timer(1.5, stop.set).start()
p.supervise([sys.executable, "-I", sys.argv[2], "good"], "fixsvc", health_interval=1, grace=1, stop=stop)
assert "integrations" not in json.loads(open(sys.argv[3]).readline())
PY
check "the schema describes init.integrations" python3 -I -c "
import json; d=json.load(open('$SCHEMA'))['\$defs']['init']
assert 'integrations' in d['properties'] and 'integrations' not in d['required']"

echo "-- init.integrations travel in a file, not in argv"
check "ext.sh passes no listing text in argv" sh -c "! grep -q -e 'svc-run.*--integrations ' '$SCRIPTS/ext.sh' && grep -q -e '--integrations-file' '$SCRIPTS/ext.sh'"
printf 'jellyfin\tmedia\trecipe\thttp://x\tok\tsecret=hunter2\t-\n' > "$WORK/listing.tsv"
check "the bridge refuses a listing in argv" sh -c "! python3 -I '$SCRIPTS/lib/ext_service.py' svc-run --name fixsvc --state-dir '$WORK/svcstate' --integrations 'x' 2>/dev/null"
FIX_MODE=good python3 -I "$SCRIPTS/lib/ext_service.py" svc-run --name fixsvc --dir "$WORK" --state-dir "$WORK/svcstate" --integrations-file "$WORK/listing.tsv" >/dev/null 2>&1 &
BRIDGE=$!; sleep 1; kill $BRIDGE 2>/dev/null; wait $BRIDGE 2>/dev/null
check "the bridge removes the listing file after reading it" test ! -e "$WORK/listing.tsv"

echo "-- svc-run: the unit's bridge, five failures in ten minutes (fake supervisor = a loop that restarts like Restart=on-failure)"
PKG=$WORK/pkgs/fixsvc; mkdir -p "$PKG" "$WORK/svcstate"
printf 'name = "fixsvc"\n[service]\nexec = "@/run.sh"\nhealth_interval = 5\n' > "$PKG/package.toml"
printf '#!/usr/bin/env bash\nexec python3 -I "%s" "${FIX_MODE:-crash}"\n' "$SVC" > "$PKG/run.sh"
printf '#!/usr/bin/env bash\nprintf "%%s\n" "$*" >> "%s"\n' "$WORK/emitted" > "$WORK/emit.sh"; chmod +x "$WORK/emit.sh"
export HS_EXT_EMIT=$WORK/emit.sh
# the bridge starts the service through systemd-run (a confined transient unit): a fake that runs what follows `--` and a fake systemctl
fake_service_systemd
SR="python3 -I $SCRIPTS/lib/ext_service.py svc-run --name fixsvc --dir $PKG --state-dir $WORK/svcstate"
check "has-service sees the [service] table" python3 -I "$SCRIPTS/lib/ext_service.py" has-service "$PKG"
check_eq "a folder without [service] has none" 1 "$(python3 -I "$SCRIPTS/lib/ext_service.py" has-service "$WORK" >/dev/null 2>&1; echo $?)"
fake_systemd() {   # fake_systemd <start-time> <gap-seconds>: starts the unit until it is refused (5 starts per 10 minutes), like systemd
  local t=$1 gap=$2 starts=0 first=$1
  while [ "$starts" -lt 5 ]; do
    HS_NOW=$t $SR >/dev/null 2>&1 || true
    starts=$((starts + 1)); t=$((t + gap))
  done
}
rm -f "$WORK/emitted"
HS_NOW=1000 $SR >/dev/null 2>&1; rc=$?
check_eq "a crashing service makes the bridge exit 1" 1 "$rc"
check_eq "one failure sends no event" 0 "$(cat "$WORK/emitted" 2>/dev/null | wc -l | tr -d ' ')"
rm -f "$WORK/svcstate/fixsvc.json" "$WORK/emitted"
fake_systemd 2000 20
check_eq "five failures within ten minutes send exactly one event" 1 "$(wc -l < "$WORK/emitted" | tr -d ' ')"
check "the event is ext.service-failed for the package at level error" grep -q '^ext.service-failed fixsvc .* --level error --payload' "$WORK/emitted"
check_eq "the payload names package and code" '{"package":"fixsvc","code":"exited"}' "$(sed -n 's/.*--payload //p' "$WORK/emitted")"
HS_NOW=2200 $SR >/dev/null 2>&1 || true
check_eq "a further failure does not send it again" 1 "$(wc -l < "$WORK/emitted" | tr -d ' ')"
check_eq "the status after the failure is failed" "failed" "$(python3 -I "$SCRIPTS/lib/ext_service.py" status --name fixsvc --state-dir "$WORK/svcstate" --active no | cut -f1)"
python3 -I "$SCRIPTS/lib/ext_service.py" reset --name fixsvc --state-dir "$WORK/svcstate"
check_eq "reset (hs ext start) forgets the failure" "stopped	-	-" "$(python3 -I "$SCRIPTS/lib/ext_service.py" status --name fixsvc --state-dir "$WORK/svcstate" --active no)"
rm -f "$WORK/emitted"
fake_systemd 5000 200
check_eq "five failures spread over more than ten minutes send nothing" 0 "$(cat "$WORK/emitted" 2>/dev/null | wc -l | tr -d ' ')"
check_eq "a stop by hand shows as stopped with its reason" "stopped	stopped by hand	-" "$(python3 -I "$SCRIPTS/lib/ext_service.py" status --name nox --state-dir "$WORK/svcstate" --stopped yes)"

echo "-- svc-run: a healthy service stops on SIGTERM with exit 0 and shows running"
rm -f "$WORK/svcstate/fixsvc.json" "$WORK/emitted"
FIX_MODE=good $SR >/dev/null 2>&1 & pid=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do grep -q '"state": *"running"' "$WORK/svcstate/fixsvc.json" 2>/dev/null && break; sleep 0.5; done
check_eq "while it runs: running" running "$(python3 -I "$SCRIPTS/lib/ext_service.py" status --name fixsvc --state-dir "$WORK/svcstate" --active yes | cut -f1)"
check_eq "without a unit behind it the same file says stopped" stopped "$(python3 -I "$SCRIPTS/lib/ext_service.py" status --name fixsvc --state-dir "$WORK/svcstate" --active no | cut -f1)"
kill -TERM "$pid"; wait "$pid"; rc=$?
check_eq "SIGTERM: exit 0" 0 "$rc"
check_eq "no event for a requested stop" 0 "$(cat "$WORK/emitted" 2>/dev/null | wc -l | tr -d ' ')"

echo "-- svc-run: a hostile provider name in a credential means no run (fail closed, #1135)"
rm -f "$WORK/svcstate/fixsvc.json"
FIX_MODE=good $SR --credential "integration-media-evil=../x=/etc/shadow" --credential "integration-media-jellyfin=jellyfin=/etc/shadow" >/dev/null 2>&1; rc=$?
check_eq "a provider ../x: exit 69, the service is not started" 69 "$rc"
check "the failure is counted in the state file" grep -q '"failures"' "$WORK/svcstate/fixsvc.json"
check_eq "no key copy stays" 0 "$(find "$WORK/cred" -type f 2>/dev/null | wc -l | tr -d ' ')"
FIX_MODE=good $SR --credential "integration-media-jellyfin=jellyfin=/etc/shadow" --credential "integration-media-evil=../x=/etc/shadow" >/dev/null 2>&1; rc=$?
check_eq "the bad credential last: exit 69 as well" 69 "$rc"
check_eq "and no key copy stays (the copies of the cases with a good first credential are in ext-service-reach.sh)" 0 "$(find "$WORK/cred" -type f 2>/dev/null | wc -l | tr -d ' ')"

echo "-- hs ext status|start|stop with a fake systemctl"
EXT=$WORK/ext; mkdir -p "$EXT/pk/svcpkg" "$EXT/state"
printf 'name = "svcpkg"\ntitle = "t"\nkind = "feature"\nrequires = []\nprovides = []\nneeds = []\nextension = true\n[service]\nexec = "@/run.sh"\n' > "$EXT/pk/svcpkg/capability.toml"
printf '#!/usr/bin/env bash\nexit 0\n' > "$EXT/pk/svcpkg/run.sh"
printf '#!/usr/bin/env bash\necho "$*" >> "%s"\n[ "$1" = is-active ] && [ -e "%s" ]\nexit 0\n' "$EXT/ctl.log" "$EXT/active" > "$EXT/systemctl"; chmod +x "$EXT/systemctl"
printf 'hostName = "t"\n' > "$EXT/machine.toml"; : > "$EXT/caps"
xe() { HS_LANG=en HS_PLAIN=1 HS_CALLER=test HS_STATE_DIR=$EXT/state HS_PACKAGES_DIR=$EXT/pk HS_CAPABILITIES_FILE=$EXT/caps HS_MACHINE_FILE=$EXT/machine.toml HS_SYSTEMCTL=$EXT/systemctl HS_CONFINE_DIR=$EXT/dropin bash "$SCRIPTS/ext.sh" "$@"; }
check_eq "a package that is off has no status row" "" "$(xe --status)"
echo svcpkg > "$EXT/caps"
check_eq "on, never ran: stopped" "svcpkg	stopped	-	-" "$(xe --status)"
xe start svcpkg >/dev/null; check "start asks systemd for the unit" grep -q '^start hs-ext-svc@svcpkg.service' "$EXT/ctl.log"
xe stop svcpkg >/dev/null
check "stop asks systemd to stop the unit" grep -q '^stop hs-ext-svc@svcpkg.service' "$EXT/ctl.log"
check_eq "a stop by hand is shown" "svcpkg	stopped	stopped by hand	-" "$(xe --status)"
xe start svcpkg >/dev/null; check_eq "start removes the stop by hand" "svcpkg	stopped	-	-" "$(xe --status)"
check_out "boot starts the service of a package that is on" "^svcpkg	service ok" xe boot
xe stop svcpkg >/dev/null; : > "$EXT/ctl.log"; xe boot >/dev/null
check_eq "boot leaves a service stopped by hand alone" 0 "$(grep -c '^start' "$EXT/ctl.log")"
check_out "start of an unknown package is refused" "No extension called" xe start nope || true
finish
