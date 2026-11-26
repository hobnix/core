#!/usr/bin/env bash
# A running service extension follows its integration rows (hobnix/core#1328, ADR 0011 rule 6): scripts/lib/ext_watch.py (the event stream, the planned
# checks, the gap between two changes, the slow check) and the restart of the service process inside `ext_service.py svc-run`. The Incus event
# stream and the listing are fakes (HS_EXT_INCUS_EVENTS, HS_EXT_LISTING_CMD). No root, python3 only.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
command -v python3 >/dev/null || { echo "python3 missing: skipped"; exit 0; }
SVC=$ROOT/tests/fixtures/ext-service/svc.py

# the fake of `incus monitor`: notes its pid, prints what is appended to FEED, ends when the file DIE appears
cat > "$WORK/stream.py" <<'PY'
import os
import sys
import time
feed, die, pids = sys.argv[1:4]
with open(pids, "a") as f:
    f.write("%d\n" % os.getpid())
pos = 0
while True:
    if os.path.exists(die):
        os.unlink(die)
        sys.exit(0)
    try:
        with open(feed, "rb") as f:
            f.seek(pos)
            data = f.read()
    except OSError:
        data = b""
    if data:
        pos += len(data)
        sys.stdout.buffer.write(data)
        sys.stdout.flush()
    time.sleep(0.05)
PY

cat > "$WORK/unit.py" <<'PY'
import importlib.util
import io
import json
import os
import sys
import threading
import time

scripts, work = sys.argv[1:3]


def load(mod):
    s = importlib.util.spec_from_file_location(mod, os.path.join(scripts, "lib", mod + ".py"))
    m = importlib.util.module_from_spec(s)
    s.loader.exec_module(m)
    return m


pi, ew, es = load("pkg_integrations"), load("ext_watch"), load("ext_service")


def say(ok, what):
    print("%s\t%s" % ("ok" if ok else "FAIL", what), flush=True)


def ev(action="instance-started", name="jellyfin", **more):
    d = {"type": "lifecycle", "metadata": {"action": action, "source": "/1.0/instances/" + name, "context": {"junk": ["x", 1]}}}
    d.update(more)
    return json.dumps(d).encode() + b"\n"


# parse
say(ew.parse(ev(), pi) == "jellyfin" and ew.parse(ev("instance-stopped"), pi) == "jellyfin", "parse: started and stopped give the instance")
say(ew.parse(ev(project="default"), pi) == "jellyfin", "parse: the project default counts")
say(ew.parse(ev(name="jellyfin?project=default"), pi) == "jellyfin", "parse: the query of the source is cut off")
bad = [ev("image-created"), ev("instance-exec"), ev("instance-snapshot-created"), ev(project="other"), ev(name="../x"), ev(name="-flag"),
       ev(name="jellyfin/snapshots/a"), b"not json\n", b"[1]\n", b'{"type": "lifecycle", "metadata": "x"}\n', b"\xff\xfe\n", b"[" * 100000,
       json.dumps({"type": "logging", "metadata": {"action": "instance-started", "source": "/1.0/instances/jellyfin"}}).encode()]
say(all(ew.parse(x, pi) is None for x in bad), "parse: images, exec, another project, bad names and junk give nothing")

os.environ.pop("HS_EXT_INCUS_EVENTS", None)
os.environ["HS_INCUS"] = "/x/incus"
say(ew.events_cmd() == ["/x/incus", "monitor", "--type=lifecycle", "--format=json"], "events_cmd: the lifecycle stream of HS_INCUS")

# watched_instances
sd = os.path.join(work, "services.d")
os.makedirs(sd, exist_ok=True)
for pkg, c in (("jellyfin", '"jellyfin"'), ("evil", '"../x"'), ("number", "7")):
    with open(os.path.join(sd, pkg + ".toml"), "w") as f:
        f.write("container = %s\n" % c)
got = ew.watched_instances([{"package": p} for p in ("jellyfin", "evil", "number", "norecord", "jellyfin")], sd, pi)
say(got == {"jellyfin"}, "watched_instances: only a good container name of a service record: %r" % got)


def row(url):
    return [{"package": "jellyfin", "integration": "media", "api_url": url}]


A, B, C = row("http://10.0.0.1"), row("http://10.0.0.2"), row(None)
n = [0]


class Run:
    def __init__(self, baseline=A, **kw):
        n[0] += 1
        base = os.path.join(work, "w%d" % n[0])
        self.feed, self.die, self.pidfile = base + ".feed", base + ".die", base + ".pids"
        open(self.feed, "wb").close()
        os.environ["HS_EXT_INCUS_EVENTS"] = " ".join('"%s"' % x for x in (sys.executable, "-I", os.path.join(work, "stream.py"), self.feed, self.die, self.pidfile))
        self.now, self.lists, self.changes, self.logs = baseline, [], [], []
        args = {"delays": (0.1,), "start_delays": (30,), "gap": 0.2, "backoff": (0.2,), "every": 60}
        args.update(kw)
        self.w = ew.IntegrationWatch({"jellyfin"}, baseline, self.list, lambda r: self.changes.append((time.monotonic(), r)), pi,
                                     log=self.logs.append, **args)
        self.w.start()

    def list(self):
        self.lists.append(time.monotonic())
        if isinstance(self.now, Exception):
            raise self.now
        return self.now

    def send(self, data):
        with open(self.feed, "ab") as f:
            f.write(data)

    def pids(self):
        try:
            return open(self.pidfile).read().split()
        except OSError:
            return []


def until(f, limit=8.0):
    end = time.monotonic() + limit
    while time.monotonic() < end:
        if f():
            return True
        time.sleep(0.02)
    return False


# no change; an unwatched instance
r = Run()
say(until(lambda: len(r.lists) == 1), "after the connect there is one check")
r.send(ev(name="radarr") + ev("image-created"))
time.sleep(0.8)
say(len(r.lists) == 1, "an event of an instance that is not watched makes no listing")
r.send(ev())
say(until(lambda: len(r.lists) == 2), "an event of a watched instance makes a listing")
time.sleep(0.3)
say(r.changes == [], "with the same rows nothing changes")
r.now = B
r.send(ev("instance-stopped"))
say(until(lambda: len(r.changes) == 1), "changed rows after an event: on_change")
time.sleep(0.5)
say([c[1] for c in r.changes] == [B] and r.w.baseline == B, "it is called once, with the new rows")
say(any("the rows of an integration changed" in x for x in r.logs) and not any("10.0.0" in x for x in r.logs), "the log says it, without an address")
proc = r.w._proc
r.w.stop()
r.w.stop()
say(proc.poll() is not None, "stop() ends the stream process, and may be called twice")
before = len(r.pids())
time.sleep(0.6)
say(len(r.pids()) == before, "after stop() nothing is connected again")

# a listing that cannot say; one that raises
r = Run()
until(lambda: len(r.lists) == 1)
r.now = None
r.send(ev())
say(until(lambda: len(r.lists) == 2), "a failed listing is asked")
time.sleep(0.2)
say(r.changes == [] and r.w.baseline == A, "a failed listing decides nothing")
r.now = RuntimeError("http://10.9.9.9")
r.send(ev())
until(lambda: len(r.lists) == 3)
time.sleep(0.2)
say(any("failed (RuntimeError)" in x for x in r.logs) and not any("10.9.9.9" in x for x in r.logs), "an exception is logged by its kind only")
r.now = B
time.sleep(0.2)
r.send(ev())
say(until(lambda: len(r.changes) == 1), "and the watcher goes on")
r.w.stop()

# two changes inside the gap
r = Run(gap=2.5)
until(lambda: len(r.lists) == 1)
r.now = B
r.send(ev())
until(lambda: len(r.changes) == 1)
r.now = C
r.send(ev())
time.sleep(1.0)
say(len(r.changes) == 1, "a second change inside the gap waits")
say(until(lambda: len(r.changes) == 2), "and comes after the gap without another event")
say(len(r.changes) == 2 and r.changes[1][1] == C and r.changes[1][0] - r.changes[0][0] >= 2.4, "the gap was kept")
r.w.stop()

# boot: a row without an address is checked without any event
r = Run(baseline=C, delays=(30,), start_delays=(0.2,))
r.now = A
say(until(lambda: len(r.changes) == 1, 4), "a row without an address at the start: checked without an event")
r.w.stop()
r = Run(delays=(30,), start_delays=(0.2,))
time.sleep(0.8)
say(r.lists == [], "with all addresses known there are no start checks")
r.w.stop()

# the slow check
r = Run(delays=(30,), every=0.4)
r.now = None
say(until(lambda: len(r.lists) >= 1, 4), "the slow check comes without any event")
r.now = B      # the same instance with another address, no event
say(until(lambda: len(r.changes) == 1, 4) and r.changes[0][1] == B, "after a failed listing the next slow check finds the new address")
k = len(r.lists)
say(until(lambda: len(r.lists) >= k + 2, 4) and len(r.changes) == 1, "it keeps coming, and unchanged rows change nothing")
r.w.stop()
r = Run(delays=(30,), every=0.3, gap=2.0)
r.now = B
until(lambda: len(r.changes) == 1, 4)
r.now = C
say(until(lambda: len(r.changes) == 2, 6) and r.changes[1][0] - r.changes[0][0] >= 1.9, "the slow check keeps the same gap")
r.w.stop()
say(ew.SLOW_CHECK == 1800.0 and ew.REINIT_GAP == 20.0, "the constants: every 30 minutes, 20 s between two changes")

# the stream ends; a long line is skipped
r = Run()
until(lambda: len(r.pids()) == 1 and len(r.lists) == 1)
open(r.die, "w").close()
say(until(lambda: len(set(r.pids())) == 2), "a stream that ended is connected again")
say(until(lambda: len(r.lists) >= 2), "with a check after the connect")
r.w.stop()
r = Run()
until(lambda: len(r.lists) == 1)
r.send(b"x" * (ew.MAX_LINE + 10) + ev())      # the tail of the long line looks like an event
time.sleep(0.8)
say(len(r.lists) == 1, "a line over the limit is skipped as a whole")
r.send(ev())
say(until(lambda: len(r.lists) == 2), "and the line after it is read")
r.w.stop()

# no monitor program: no busy loop, no crash
w = ew.IntegrationWatch({"jellyfin"}, A, lambda: A, lambda r: None, pi, cmd=lambda: [os.path.join(work, "nosuch")], backoff=(0.3,))
calls = []
real = w._spawn
w._spawn = lambda: (calls.append(1), real())[1]
w.start()
time.sleep(1.0)
w.stop()
say(2 <= len(calls) <= 5, "a monitor that cannot start is tried again with the back-off: %d" % len(calls))

# listing_rows: the same rows as the start, None when one listing fails
lc = os.path.join(work, "list.py")
with open(lc, "w") as f:
    f.write("import sys\nif sys.argv[1] == 'broken': sys.exit(1)\n"
            "print('jellyfin\\t%s\\trecipe\\t-\\tok\\ta=1\\t-' % sys.argv[1])\n")
os.environ["HS_EXT_LISTING_CMD"] = '"%s" -I "%s"' % (sys.executable, lc)
got = es.listing_rows("fixsvc", ["integration:zeta", "events.emit:x", "integration:media"])
say([x["integration"] for x in got] == ["zeta", "media"] and got[0]["api_url"] is None, "listing_rows: one listing per declared integration, in order")
say(got == es.integration_rows("jellyfin\tzeta\trecipe\t-\tok\ta=1\t-\n\njellyfin\tmedia\trecipe\t-\tok\ta=1\t-\n", ["integration:zeta", "integration:media"]),
    "and the same rows as the text ext.sh writes at the start")
say(es.listing_rows("fixsvc", ["integration:media", "integration:broken"]) is None, "one failing listing: None")
os.environ["HS_EXT_LISTING_CMD"] = os.path.join(work, "nosuch")
say(es.listing_rows("fixsvc", ["integration:media"]) is None, "a listing that cannot start: None")
PY

echo "-- ext_watch.py"
rc=0; out=$(python3 -I "$WORK/unit.py" "$SCRIPTS" "$WORK" 2>"$WORK/unit.err") || rc=$?
while IFS=$'\t' read -r st what; do
  case "$st" in ok) pass "$what" ;; FAIL) fail "$what" ;; esac
done <<<"$out"
check_eq "the unit checks ran to the end" 0 "$rc"
[ "$rc" = 0 ] || tail -n 15 "$WORK/unit.err"

echo "-- listing_rows through the real pkg.sh: an Incus that does not answer is a failed listing, not rows without an address"
cat > "$WORK/real.py" <<'PY'
# real.py <lib> <integration> [listing timeout]: what the watcher sees: "None", or "package=api_url" of each row
import importlib.util
import os
import sys
s = importlib.util.spec_from_file_location("es", os.path.join(sys.argv[1], "ext_service.py"))
es = importlib.util.module_from_spec(s)
s.loader.exec_module(es)
if len(sys.argv) > 3:
    es.LISTING_TIMEOUT = float(sys.argv[3])
got = es.listing_rows("fixsvc", ["integration:" + sys.argv[2]])
print("None" if got is None else " ".join("%s=%s" % (r["package"], r["api_url"]) for r in got) or "empty")
PY
R=$WORK/real; mkdir -p "$R/packages/jellyfin" "$R/packages/literal" "$R/state/services.d"
for n in jellyfin literal; do
  printf '#!/usr/bin/env bash\n# recipe: %s: test\nct=${RECIPE_NAME:-%s}\n' "$n" "$n" > "$R/packages/$n/run.sh"
done
printf 'name = "jellyfin"\nkind = "recipe"\n[integrations.media]\napi_url = "http://{host}:8096"\n' > "$R/packages/jellyfin/package.toml"
printf 'name = "literal"\nkind = "recipe"\n[integrations.fixed]\napi_url = "http://10.1.1.1:80"\n' > "$R/packages/literal/package.toml"
printf 'container = "jellyfin"\n' > "$R/state/services.d/jellyfin.toml"
# the fake incus: NAMES is the answer to recipes-list.sh (the names), JSON the answer to the query for the addresses
cat > "$R/incus" <<'SH'
#!/usr/bin/env bash
case "$*" in *json*) how=$JSON ;; *) how=$NAMES ;; esac
case "$how" in
  fail) exit 1 ;;
  hang) exec sleep 30 ;;
  bad) echo 'Error: not authorized' ;;
  object) echo '{"error": 1}' ;;
  names) printf 'jellyfin\nliteral\n' ;;
  absent) echo '[]' ;;
  running|stopped)
    st=Stopped; [ "$how" = running ] && st=Running
    printf '[{"name":"jellyfin","status":"%s","expanded_devices":{"eth0":{"type":"nic","hwaddr":"00:16:3e:00:00:01"}},"state":{"network":{"eth0":{"hwaddr":"00:16:3e:00:00:01","addresses":[{"scope":"global","address":"192.168.1.20"}]}}}}]\n' "$st" ;;
esac
SH
chmod +x "$R/incus"
renv() { env -u HS_EXT_LISTING_CMD HS_PACKAGES_ROOT="$R" HS_RECIPES_DIR="$R/packages" HS_STATE_DIR="$R/state" HS_INCUS="$R/incus" HS_INCUS_TIMEOUT=1 NAMES="$1" JSON="$2" "${@:3}"; }
real() { renv "$1" "$2" python3 -I "$WORK/real.py" "$SCRIPTS/lib" "${@:3}"; }
check_eq "Incus answers: the address" "jellyfin=http://192.168.1.20:8096" "$(real names running media)"
check_eq "a stopped instance is a real answer: no address" "jellyfin=None" "$(real names stopped media)"
check_eq "an instance that is not in the answer: no address" "jellyfin=None" "$(real names absent media)"
for how in fail bad object hang; do
  check_eq "the address query $how: a failed listing" None "$(real names "$how" media)"
done
check_eq "the instance names cannot be read (the recipe would drop out): a failed listing" None "$(real fail fail media)"
s=$SECONDS
check_eq "the instance names query hangs: a failed listing" None "$(real hang running media 3)"
check "and the listing timeout ends it, with the hanging incus" test $((SECONDS - s)) -le 12
check_eq "no incus program: a failed listing" None "$(renv names running env HS_INCUS="$R/nosuch" python3 -I "$WORK/real.py" "$SCRIPTS/lib" media)"
check_eq "an address that needs no query: a failing query does not matter" "literal=http://10.1.1.1:80" "$(real names fail fixed)"
check_eq "no recipe offers it: Incus is not needed" empty "$(real fail fail nobody)"
today() { renv "$1" "$2" env -u HS_INTEGRATIONS_STRICT bash "$SCRIPTS/pkg.sh" --integrations media; }
rc=0; out=$(today names fail) || rc=$?
check_eq "hs pkg integrations and the start stay as before: exit 0, the row with -" "0 jellyfin media -" "$rc $(cut -f1,2,4 <<<"$out" | tr '\t' ' ')"
rc=0; out=$(today fail fail) || rc=$?
check_eq "and exit 0 without a row when the names cannot be read" "0 " "$rc $out"
check "ext.sh does not ask for the strict listing" sh -c "! grep -q HS_INTEGRATIONS_STRICT '$SCRIPTS/ext.sh'"

echo "-- svc-run: new rows restart the service process inside the same bridge"
PKG=$WORK/pkgs/fixsvc; mkdir -p "$PKG" "$WORK/svcstate"
printf 'name = "fixsvc"\npermissions = ["integration:media"]\n[service]\nexec = "@/run.sh"\nhealth_interval = 5\n' > "$PKG/package.toml"
printf '#!/usr/bin/env bash\nexec python3 -I "%s" good\n' "$SVC" > "$PKG/run.sh"
export SVC_LOG=$WORK/svc.log
printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/emit.sh"; chmod +x "$WORK/emit.sh"
export HS_EXT_EMIT=$WORK/emit.sh
fake_service_systemd
# this systemd-run also records every argument it got
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" >> "%s"\nwhile [ "$1" != -- ]; do shift; done; shift\nexec "$@"\n' "$WORK/run-argv.log" > "$WORK/systemd-run"
mkdir -p "$HS_STATE_DIR/services.d"
printf 'container = "jellyfin"\n' > "$HS_STATE_DIR/services.d/jellyfin.toml"
listing() { printf 'jellyfin\tmedia\trecipe\thttp://%s:8096\tok\tsecret=hunter2\t-\n' "$1"; }
listing 10.0.0.1 > "$WORK/a.tsv"; listing 10.0.0.2 > "$WORK/b.tsv"
# the listing: A the first time, then B
cat > "$WORK/listing.sh" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$WORK/listing-argv.log"
if [ -e "$WORK/listed" ]; then cat "$WORK/b.tsv"; else : > "$WORK/listed"; cat "$WORK/a.tsv"; fi
SH
export HS_EXT_LISTING_CMD="bash $WORK/listing.sh"
# the stream: one start of the instance after 1.5 s (so that its check is not the one after the connect)
cat > "$WORK/stream-once.py" <<'PY'
import os
import sys
import time
with open(sys.argv[1], "a") as f:
    f.write("%d\n" % os.getpid())
time.sleep(1.5)
print('{"type":"lifecycle","metadata":{"action":"instance-started","source":"/1.0/instances/jellyfin"}}', flush=True)
time.sleep(600)
PY
export HS_EXT_INCUS_EVENTS="python3 -I $WORK/stream-once.py $WORK/stream.pids"
SR="python3 -I $SCRIPTS/lib/ext_service.py svc-run --name fixsvc --dir $PKG --state-dir $WORK/svcstate"
state() { python3 -I "$SCRIPTS/lib/ext_service.py" status --name fixsvc --state-dir "$WORK/svcstate" --active yes | cut -f1; }
inits() { grep -c '"type": "init"' "$SVC_LOG" 2>/dev/null || true; }
: > "$SVC_LOG"
cp "$WORK/a.tsv" "$WORK/start.tsv"
$SR --integrations-file "$WORK/start.tsv" >/dev/null 2>"$WORK/bridge.err" & pid=$!
for _ in $(seq 1 80); do [ "$(inits)" = 2 ] && [ "$(state)" = running ] && break; sleep 0.5; done
check_eq "the service got init twice" 2 "$(inits)"
urls() { grep '"type": "init"' "$SVC_LOG" | python3 -I -c 'import json,sys; print(" ".join(json.loads(l)["integrations"][0]["api_url"] for l in sys.stdin))'; }
check_eq "first with the old rows, then with the new ones" "http://10.0.0.1:8096 http://10.0.0.2:8096" "$(urls)"
check_eq "the first process was stopped with shutdown" 1 "$(grep -c '"type": "shutdown"' "$SVC_LOG")"
check_eq "the state ends running" running "$(state)"
check_eq "the bridge is the same process" yes "$(kill -0 "$pid" 2>/dev/null && echo yes || echo no)"
sleep 2
check_eq "unchanged rows restart nothing more" 2 "$(inits)"
kill -TERM "$pid"; rc=0; wait "$pid" || rc=$?
check_eq "SIGTERM afterwards: exit 0" 0 "$rc"
check_eq "the journal says the restart once" 1 "$(grep -c 'fixsvc: integration rows changed, the service restarts' "$WORK/bridge.err")"
check_eq "the journal has no address and no extra" 0 "$(grep -c -e '10\.0\.0\.' -e hunter2 "$WORK/bridge.err")"
check_eq "one stream for both rounds" 1 "$(wc -l < "$WORK/stream.pids" | tr -d ' ')"
check_eq "no stream process stays" gone "$(kill -0 "$(cat "$WORK/stream.pids")" 2>/dev/null && echo alive || echo gone)"
check_eq "no listing and no key text in an argument of the unit" 0 "$(grep -c -e hunter2 -e '10\.0\.0\.' "$WORK/run-argv.log")"
check_eq "the listing gets the integration name only" "media" "$(sort -u "$WORK/listing-argv.log")"
check_eq "no failure was counted" 0 "$(grep -c '"failures"' "$WORK/svcstate/fixsvc.json")"

echo "-- svc-run: no stream without a provider instance, or for a start that is refused"
printf '#!/usr/bin/env bash\n: > "%s"\nexec sleep 30\n' "$WORK/stream.marker" > "$WORK/marker.sh"
export HS_EXT_INCUS_EVENTS="bash $WORK/marker.sh"
bridge_once() {   # run the bridge until the service runs (and a moment more), then stop it
  rm -f "$WORK/svcstate/fixsvc.json" "$WORK/stream.marker"; cp "$WORK/a.tsv" "$WORK/start.tsv"
  $SR --integrations-file "$WORK/start.tsv" >/dev/null 2>&1 & local p=$!
  for _ in $(seq 1 20); do [ "$(state)" = running ] && break; sleep 0.5; done
  sleep 1; kill -TERM "$p"; rc=0; wait "$p" || rc=$?
}
bridge_once
check_eq "with a provider instance the stream is started (the check below can see it)" "0 yes" "$rc $([ -e "$WORK/stream.marker" ] && echo yes || echo no)"
rm -f "$HS_STATE_DIR/services.d/jellyfin.toml"
bridge_once
check_eq "a provider without a container: the service runs, no stream" "0 no" "$rc $([ -e "$WORK/stream.marker" ] && echo yes || echo no)"
printf 'container = "jellyfin"\n' > "$HS_STATE_DIR/services.d/jellyfin.toml"
rm -f "$WORK/stream.marker"; rc=0
$SR --credential "integration-media-evil=../x=/etc/shadow" >/dev/null 2>&1 || rc=$?
check_eq "a refused start starts no stream" "69 no" "$rc $([ -e "$WORK/stream.marker" ] && echo yes || echo no)"
finish
