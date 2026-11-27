#!/usr/bin/env bash
# The command-extension protocol v1 (docs/adr/0010-extension-command-protocol.md): the reference runner scripts/lib/ext_proto.py against a test
# extension that speaks it (tests/fixtures/ext-proto/ext.py): result, failure, timeout, cancellation (SIGTERM, grace, SIGKILL), protocol
# violations, and the JSON schema file. No root, python3 only.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
command -v python3 >/dev/null || { echo "python3 missing: skipped"; exit 0; }
RUN="python3 -I $SCRIPTS/lib/ext_proto.py"
EXT=$ROOT/tests/fixtures/ext-proto/ext.py

call() {   # call <timeout> <grace> <command word> [--arg v]...: output is the runner's lines; $rc is its exit status
  local t=$1 g=$2 w=$3; shift 3
  rc=0
  out=$($RUN call --timeout "$t" --grace "$g" --command "$w" "$@" -- python3 -I "$EXT" 2>&1) || rc=$?
}
last() { printf '%s\n' "$out" | tail -n1; }
field() { last | python3 -I -c 'import json,sys; d=json.load(sys.stdin); print(eval(sys.argv[1]))' "$1"; }

echo "-- result"
call 10 2 echo --arg a --arg "b c" --lang de
check_eq "ok exits 0" 0 "$rc"
check_eq "outcome code ok" ok "$(field 'd["code"]')"
check_eq "argv and lang arrive" "['a', 'b c'] de" "$(field 'str(d["result"]["data"]["argv"]) + " " + d["result"]["data"]["lang"]')"
check_out "progress is passed on" '"type":"progress"' printf '%s' "$out"
check_out "an event is passed on" 'pkg.fixproto.said' printf '%s' "$out"
call 10 2 fail
check_eq "ok=false with exit 1 exits 1" 1 "$rc"
check_eq "the error message is the reason" "it broke" "$(field 'd["reason"]')"
call 10 2 nosuch
check_eq "an unknown command is a failure, not a protocol error" "1 failed" "$rc $(field 'd["code"]')"

echo "-- timeout and cancellation"
s=$SECONDS; call 1 1 slow
check_eq "timeout exits 124" "124 timeout" "$rc $(field 'd["code"]')"
[ $((SECONDS - s)) -le 5 ] && pass "the timeout stops the process quickly" || fail "the timeout took $((SECONDS - s)) s"
s=$SECONDS; call 1 1 stubborn
check_eq "a process that ignores SIGTERM is killed after the grace time" "124 timeout" "$rc $(field 'd["code"]')"
[ $((SECONDS - s)) -le 6 ] && pass "SIGKILL follows the grace time" || fail "the kill took $((SECONDS - s)) s"
# cancel: SIGTERM to the runner is forwarded; a polite extension answers inside the grace time, the outcome is cancelled either way
$RUN call --timeout 20 --grace 3 --command polite -- python3 -I "$EXT" > "$WORK/cancel.out" 2>&1 &
pid=$!
for _ in $(seq 1 50); do grep -q started "$WORK/cancel.out" 2>/dev/null && break; sleep 0.1; done
kill -TERM "$pid"; rc=0; wait "$pid" || rc=$?
check_eq "SIGTERM to the runner cancels: exit 130" 130 "$rc"
check_out "the cancelled outcome carries the extension's own answer" 'stopped by the core' cat "$WORK/cancel.out"
$RUN call --timeout 20 --grace 1 --command stubborn -- python3 -I "$EXT" > "$WORK/cancel2.out" 2>&1 &
pid=$!
for _ in $(seq 1 50); do grep -q started "$WORK/cancel2.out" 2>/dev/null && break; sleep 0.1; done
s=$SECONDS; kill -TERM "$pid"; rc=0; wait "$pid" || rc=$?
check_eq "a cancelled call that ignores SIGTERM is killed" 130 "$rc"
[ $((SECONDS - s)) -le 5 ] && pass "cancel ends within the grace time" || fail "cancel took $((SECONDS - s)) s"
sleep 0.2
if left=$(pgrep -af "^python3 -I $EXT"); [ -n "$left" ]; then fail "a process of the extension is left behind: $left"; else pass "no process is left behind"; fi

echo "-- protocol violations"
for w in garbage noresult after badexit huge two okexit1 failexit0 badfield badcode partial; do
  call 10 1 "$w"
  check_eq "$w is a protocol error (exit 70)" "70 protocol_error" "$rc $(field 'd["code"]')"
done
rc=0; out=$($RUN call --timeout 5 --command echo -- /nonexistent/prog 2>&1) || rc=$?
check_eq "a program that does not start exits 69" "69 spawn_failed" "$rc $(field 'd["code"]')"

echo "-- blocking edges"
big=$(head -c 100000 /dev/zero | tr '\0' a)
s=$SECONDS; rc=0
out=$($RUN call --timeout 2 --grace 1 --command echo --arg "$big" --arg "$big" --arg "$big" -- python3 -I "$EXT" noread 2>&1) || rc=$?
check_eq "a 300 KB request to an extension that never reads it still times out" "124 timeout" "$rc $(field 'd["code"]')"
[ $((SECONDS - s)) -le 8 ] && pass "...in time" || fail "it took $((SECONDS - s)) s"
call 2 1 linger
check_eq "an extension that answers but does not exit times out" "124 timeout" "$rc $(field 'd["code"]')"
$RUN call --timeout 30 --grace 1 --command linger -- python3 -I "$EXT" > "$WORK/c3.out" 2>&1 &
pid=$!; sleep 1; s=$SECONDS; kill -TERM "$pid"; rc=0; wait "$pid" || rc=$?
check_eq "a cancel after the result is still honoured" 130 "$rc"
[ $((SECONDS - s)) -le 5 ] && pass "...in time" || fail "it took $((SECONDS - s)) s"
rc=0; out=$($RUN call --lang xx --command echo -- true 2>&1) || rc=$?
check_eq "a bad --lang is refused, not sent" 1 "$([ "$rc" -ne 0 ] && echo 1 || echo 0)"
rc=0; out=$($RUN call --command Bad -- true 2>&1) || rc=$?
check_eq "a bad command word is refused" 1 "$([ "$rc" -ne 0 ] && echo 1 || echo 0)"

echo "-- the dispatcher: hs ext / hs sys ext run a protocol row"
export HS_LANG=en HS_PLAIN=1 HS_CALLER=test HS_STATE_DIR=$WORK/state HS_CAPABILITIES_FILE=$WORK/caps HS_MACHINE_FILE=$WORK/machine.toml
mkdir -p "$HS_STATE_DIR"; echo fixproto > "$HS_CAPABILITIES_FILE"; printf 'hostName = "t"
' > "$HS_MACHINE_FILE"
tab=$'	'; PK=$WORK/packages; mkdir -p "$PK/fixproto"
cp "$EXT" "$PK/fixproto/ext.py"; cp "$ROOT/tests/fixtures/ext-proto/rows.sh" "$PK/fixproto/rows.sh"
cat > "$PK/fixproto/capability.toml" <<'TOML'
name = "fixproto"
title = "Fixture"
title_de = "Fixture"
kind = "feature"
requires = []
provides = []
needs = []
extension = true
TOML
printf 'name = "fixproto"
version = "1.0.0"
kind = "capability"
requires_core = ">=10"
protocol = [1]
' > "$PK/fixproto/package.toml"
row() {   # row <kind> <words> <script> <fixed args> <flags>
  printf '%s	%s	%s	%s	x	x	%s
' "$@"
}
{
  row user "ext fixproto rows" @/ext.py "-" "topic:system,reads"
  row sys "sys ext fixproto rows" @/ext.py "-" "-"
  row sys "sys ext fixproto kv <x>" @/ext.py "{1}" "-"
  row sys "sys ext fixproto slow" @/ext.py "-" "timeout:1"
  row sys "sys ext fixproto spawn" @/ext.py "$WORK/childpid" "timeout:1"
  row sys "sys ext fixproto fail" @/ext.py "-" "-"
  row sys "sys ext fixproto own" @/ext.py "-" "reads,proto"
} > "$PK/fixproto/commands.tsv"
HS="bash $SCRIPTS/lib/hs.sh"
export HS_PACKAGES_DIR=$PK
check "a protocol package's rows carry the flag proto" bash -c ". $SCRIPTS/lib/registry-load.sh; registry_rows | grep -q \"^sys.sys ext fixproto rows.*proto\$\""
check_eq "a row that has the flag proto itself (the command macro writes it) does not get it twice" "reads,proto" \
  "$(bash -c ". $SCRIPTS/lib/registry-load.sh; registry_rows" | awk -F'\t' '$2 == "sys ext fixproto own" { print $7 }')"
$HS sys ext fixproto rows > "$WORK/proto.out" 2> "$WORK/proto.err"; rc=$?
bash "$PK/fixproto/rows.sh" > "$WORK/twin.out" 2>&1
check_eq "the protocol row exits 0" 0 "$rc"
check "the protocol row prints the same bytes as its shell twin" cmp "$WORK/proto.out" "$WORK/twin.out"
check_eq "a sys row prints no progress text" "" "$(cat "$WORK/proto.err")"
check_eq "a user row prints the extension's text" "two rows" "$($HS ext fixproto rows 2>/dev/null)"
check_eq "a user row shows progress on stderr" "working" "$($HS ext fixproto rows 2>&1 >/dev/null)"
check_eq "an object is key TAB value, empty is -" "name${tab}demo
args${tab}[\"one\"]
empty${tab}-" "$($HS sys ext fixproto kv one)"
rc=0; err=$($HS sys ext fixproto fail 2>&1 >/dev/null) || rc=$?
check_eq "ok=false: exit 1 and the message on stderr" "1 it broke" "$rc $err"
s=$SECONDS; rc=0; $HS sys ext fixproto slow >/dev/null 2>&1 || rc=$?
check_eq "the row's timeout flag applies" 124 "$rc"
[ $((SECONDS - s)) -le 6 ] && pass "the timeout is quick" || fail "the timeout took $((SECONDS - s)) s"
rc=0; $HS sys ext fixproto spawn >/dev/null 2>&1 || rc=$?
check_eq "a timeout exits 124" 124 "$rc"
cp_pid=$(cat "$WORK/childpid" 2>/dev/null || echo 0)
sleep 0.3
if [ "$cp_pid" -gt 1 ] && ! kill -0 "$cp_pid" 2>/dev/null; then pass "a timeout stops the whole process group"; else fail "the child $cp_pid of the extension still runs"; [ "$cp_pid" -gt 1 ] && kill -9 "$cp_pid" 2>/dev/null; fi

echo "-- version and schema"
rc=0
out=$(printf '{"v":2,"type":"request","id":"x","command":["echo"],"argv":[],"lang":"en","caller":"cli","timeout_ms":1000}\n' | python3 -I "$EXT") || rc=$?
check_eq "an unknown request version is answered unsupported_version" "1 unsupported_version" "$rc $(printf '%s' "$out" | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["error"]["code"])')"
SCHEMA=$ROOT/docs/api/ext-protocol-v1.schema.json
check "the schema is valid JSON" python3 -I -c "import json; json.load(open('$SCHEMA'))"
# every type and error code the runner and the fixture know is in the schema, and the schema names the same version
check "the schema and the runner agree" python3 -I - "$SCHEMA" "$SCRIPTS/lib" <<'PY'
import json, sys
sys.path.insert(0, sys.argv[2])
import ext_proto as p
s = json.load(open(sys.argv[1]))
defs = s["$defs"]
assert set(defs["fromExtension"]["oneOf"][i]["$ref"].split("/")[-1] for i in range(4)) == {"progress", "log", "event", "result"}
assert defs["request"]["properties"]["v"]["const"] == p.VERSION
assert defs["log"]["properties"]["level"]["enum"] == list(p.LEVELS)
req = p.make_request(["x"], ["a"])
assert set(req) == set(defs["request"]["required"]) == set(defs["request"]["properties"]), (set(req), defs["request"]["required"])
assert {"timeout", "cancelled", "protocol_error"} <= set(defs["errorCode"]["enum"])
PY
check "the runner file passes a syntax check" python3 -I -m py_compile "$SCRIPTS/lib/ext_proto.py"
finish
