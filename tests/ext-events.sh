#!/usr/bin/env bash
# Event delivery to a service extension (#197 d, docs/PLAN-extensions-access.md step 5): the real event log (state.db) as the source, the cursor file in
# ext-cursors/<name> (D12), a kill and restart redelivers what was not acknowledged exactly once, emit goes to `hs event emit` at 50 a minute, and
# a snapshot is stored as a file that the live collector serves as the topic ext-<name>-<topic>. Fakes only: a fake emitter, sqlite in a temp dir.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
command -v python3 >/dev/null || { echo "python3 missing: skipped"; exit 0; }
SVC=$ROOT/tests/fixtures/ext-service/svc.py
export SVC_LOG=$WORK/svc.log
export HS_STATE_DIR=$WORK/st HS_STATE_DB=$WORK/st/state.db
mkdir -p "$HS_STATE_DIR"
PKG=$WORK/pk/fixsvc; mkdir -p "$PKG" "$WORK/svcstate"
printf 'name = "fixsvc"\n[service]\nexec = "@/run.sh"\nsubscribe = ["job.*"]\nhealth_interval = 5\n' > "$PKG/package.toml"
printf '#!/usr/bin/env bash\nexec python3 -I "%s" "${FIX_MODE:-good}"\n' "$SVC" > "$PKG/run.sh"
printf '#!/usr/bin/env bash\nprintf "%%s\n" "$*" >> "%s"\n' "$WORK/emitted" > "$WORK/emit.sh"; chmod +x "$WORK/emit.sh"
export HS_EXT_EMIT=$WORK/emit.sh
CUR=$HS_STATE_DIR/ext-cursors/fixsvc
SR="python3 -I $SCRIPTS/lib/ext_service.py svc-run --name fixsvc --dir $PKG --state-dir $WORK/svcstate"
python3 -I - "$HS_STATE_DB" <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.execute("CREATE TABLE events (id INTEGER PRIMARY KEY AUTOINCREMENT, time INTEGER NOT NULL, kind TEXT NOT NULL, subject TEXT, text TEXT, source TEXT NOT NULL DEFAULT 'storage', level TEXT NOT NULL DEFAULT 'info', payload TEXT, v INTEGER NOT NULL DEFAULT 1)")
c.commit()
PY
addev() { python3 -I - "$HS_STATE_DB" "$1" "$2" <<'PY'   # addev <kind> <source>
import sqlite3, sys
c = sqlite3.connect(sys.argv[1]); c.execute("INSERT INTO events (time, kind, subject, text, source, payload) VALUES (1700000000, ?, 's', 't', ?, '{\"a\":1}')", (sys.argv[2], sys.argv[3])); c.commit()
PY
}
ids() { grep '"type": "event"' "$SVC_LOG" | python3 -I -c 'import json,sys; print(" ".join(str(json.loads(l)["id"]) for l in sys.stdin))'; }
runfor() {   # runfor <mode> <seconds>: run the bridge, then stop it with SIGTERM
  : > "$SVC_LOG"; FIX_MODE=$1 $SR >/dev/null 2>"$WORK/err" & local pid=$!
  sleep "$2"; kill -TERM "$pid" 2>/dev/null; wait "$pid" 2>/dev/null || true
}

echo "-- the cursor starts at the end of the log"
addev failed job; addev done job
runfor good 2
check_eq "a first start does not replay the log" "" "$(ids)"
check_eq "the cursor file is ext-cursors/<name> with the newest id" 2 "$(cat "$CUR")"

echo "-- kill and restart: the unacknowledged event comes again, exactly once"
addev failed job; addev failed job; addev failed other
: > "$SVC_LOG"; FIX_MODE=ackfirst $SR >/dev/null 2>&1 & pid=$!
sleep 2.5
check_eq "the first run gets the subscribed events 3 and 4 (5 is not job.*)" "3 4" "$(ids)"
kill -KILL "$pid" 2>/dev/null; wait "$pid" 2>/dev/null || true
pkill -f "^python3 -I $SVC ackfirst" 2>/dev/null || true
check_eq "only event 3 was acknowledged: the cursor is 3" 3 "$(cat "$CUR")"
runfor good 2
check_eq "after the kill, event 4 is delivered once and event 3 not again" "4" "$(ids)"
check_eq "and now the cursor is at the end of what matched" 5 "$(cat "$CUR")"
runfor good 2
check_eq "another restart delivers nothing" "" "$(ids)"

echo "-- emit: 50 a minute"
rm -f "$WORK/emitted"
runfor flood 2.5
check_eq "50 of 51 emits reach the event log" 50 "$(grep -c '^pkg.fixsvc.flood ' "$WORK/emitted")"
check_eq "the 51st is dropped with one warning" 1 "$(grep -c 'further ones are dropped' "$WORK/err")"
check "the emit carries the level" grep -q -- '--level info' "$WORK/emitted"
rm -f "$WORK/emitted"
runfor foreign 1.5
check_eq "a service cannot emit another package's kind" "0 1" "$(cat "$WORK/emitted" 2>/dev/null | wc -l | tr -d ' ') $(grep -c 'may only emit pkg.fixsvc' "$WORK/err")"
echo "-- emit: the events.emit permission is checked on every emit (step 9)"
check "an undeclared package keeps the prefix check; declared kinds pass, others are dropped once per kind, the rate limit still applies" python3 -I - "$SCRIPTS/lib" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import ext_service as p
def run(perms, kinds, limit=None):
    sent, warns = [], []
    p.emit_event = lambda name, m: sent.append(m["kind"])
    h = p.make_handler("fixsvc", limit=limit, warn=warns.append, perms=perms)
    for k in kinds:
        h({"type": "emit", "kind": k, "subject": "s"})
    return sent, warns
ok, other = "pkg.fixsvc.seen", "pkg.fixsvc.secret"
s, w = run(None, [ok, other])
assert s == [ok, other] and not w, (s, w)
s, w = run(["host:incus"], [ok])
assert s == [] and len(w) == 1, (s, w)
perms = ["events.emit:pkg.fixsvc.seen", "host:incus"]
s, w = run(perms, [ok, other, other, other, ok])
assert s == [ok, ok] and len(w) == 1 and other in w[0], (s, w)
s, w = run(["events.emit:pkg.fixsvc.*"], ["pkg.fixsvc.a.b", "pkg.other.x", "pkg.other.x"])
assert s == ["pkg.fixsvc.a.b"] and len(w) == 1, (s, w)
t = [0.0]
s, w = run(["events.emit:pkg.fixsvc.*"], [ok] * 52, limit=p.RateLimit(clock=lambda: t[0]))
assert len(s) == 50 and len(w) == 1 and "further ones" in w[0], (len(s), w)
PY
EC="python3 -I $SCRIPTS/lib/ext_service.py emit-check --name fixsvc --state-dir $WORK/ecstate"
rc=0; $EC --kind pkg.fixsvc.seen -- events.emit:pkg.fixsvc.seen >/dev/null 2>&1 || rc=$?
check_eq "emit-check: a declared kind passes (exit 0)" 0 "$rc"
rc=0; $EC --kind pkg.fixsvc.x -- - >/dev/null 2>&1 || rc=$?
check_eq "emit-check: no permissions declared keeps today's behaviour" 0 "$rc"
rc=0; e1=$($EC --kind pkg.fixsvc.other -- events.emit:pkg.fixsvc.seen 2>&1) || rc=$?
e2=$($EC --kind pkg.fixsvc.other -- events.emit:pkg.fixsvc.seen 2>&1) || true
check_eq "emit-check: an uncovered kind is dropped (exit 3), warned once per kind" "3 1 0" "$rc $(printf '%s' "$e1" | grep -c 'dropped') $(printf '%s' "$e2" | grep -c .)"
rc=0; $EC --kind pkg.fixsvc.third -- events.emit:pkg.fixsvc.seen >/dev/null 2>&1 || rc=$?
check_eq "emit-check: another kind is warned on its own" "3" "$rc"
rc=0; $EC --kind pkg.other.x -- - >/dev/null 2>&1 || rc=$?
check_eq "emit-check: another package's kind is dropped even without permissions" 3 "$rc"
rc=0; HS_EVENT_NOROOT=1 HS_STATE_DIR=$WORK/st bash "$SCRIPTS/event.sh" emit --pkg no-such-pkg pkg.no-such-pkg.x s >/dev/null 2>&1 || rc=$?
check "hs event emit --pkg refuses an unknown package" test "$rc" -ne 0
check "the rate limit is a sliding window" python3 -I - "$SCRIPTS/lib" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import ext_service as p
t = [0.0]
r = p.RateLimit(clock=lambda: t[0])
assert all(r.allow() for _ in range(50)) and not r.allow()
t[0] = 59.0
assert not r.allow()
t[0] = 60.5
assert r.allow()
PY

echo "-- snapshot: a live topic"
runfor snap 2
SNAPF=$HS_STATE_DIR/ext-snapshots/fixsvc/state.json
check_eq "the snapshot is stored under ext-snapshots/<name>/<topic>.json (last one wins)" '{"n":2}' "$(cat "$SNAPF")"
check_eq "the helper names it ext-<name>-<topic>" "ext-fixsvc-state" "$(python3 -I - "$SCRIPTS" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import hs_ext
print(" ".join(t for t, _ in hs_ext.ext_snapshots(["fixsvc", "gone"])))
PY
)"
check_eq "a package that is off has no topic" "" "$(python3 -I - "$SCRIPTS" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import hs_ext
print(" ".join(t for t, _ in hs_ext.ext_snapshots([])))
PY
)"
check "the collector stores a changed snapshot once and deletes it when the package goes" python3 -I - "$SCRIPTS" <<'PY'
import sys, threading, importlib.util
sys.path.insert(0, sys.argv[1])
spec = importlib.util.spec_from_file_location("lc", sys.argv[1] + "/live-collect.py")
lc = importlib.util.module_from_spec(spec); spec.loader.exec_module(lc)

class Store:
    def __init__(self): self.d = {}
    def cmd(self, *a):
        if a[0] == "GET": return self.d.get(a[1])
        if a[0] == "SET": self.d[a[1]] = a[2]
        if a[0] == "DEL": self.d.pop(a[1], None)
        return None
st = Store()
c = lc.Collector(st, topic_rows=[], topic_info={}, ext_rows=lambda log=None: ([], {}), watchers=[], topic_needs={}, snapshots=False)
docs = [[("ext-x-state", '{"n":1}')]]
w = lc.SnapshotWatch(c, threading.Event(), read=lambda: docs[0])
w.once(); w.once()
import json
d = json.loads(st.d["hs:v1:ext-x-state"])
assert d["out"] == '{"n":1}' and d["gen"] == 1, d
docs[0] = [("ext-x-state", '{"n":2}')]
w.once()
assert json.loads(st.d["hs:v1:ext-x-state"])["gen"] == 2
docs[0] = []
w.once()
assert "hs:v1:ext-x-state" not in st.d
PY
finish
