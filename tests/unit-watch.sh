#!/usr/bin/env bash
# scripts/unit-watch.py (service hs-unit-watch): a fake feed of `busctl monitor --json=short` lines marks exactly the topics of scripts/lib/unit-topics.tsv
# (HS_LIVE_LOG records the live_refresh call), a unit nobody shows marks nothing, a repeated state marks nothing, the monitor ending is exit 1 (systemd restarts it).
# Not run against a real systemd/busctl: the line format is the one busctl prints for a signal (see the header of unit-watch.py).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
PY=${HS_PYTHON:-python3}
wp() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else echo "$1"; fi; }
export HS_LIVE_LOG=$(wp "$WORK/live.log") HS_UNIT_COALESCE=30 HS_BASH=$(wp "$(command -v bash)")
W="$PY -I $(wp "$SCRIPTS/unit-watch.py")"

# sig <unit> <ActiveState|-|raw> : one line as busctl prints a PropertiesChanged signal of a unit
cat > "$WORK/sig.py" <<'PYEOF'
import json, re, sys
unit, state = sys.argv[1], sys.argv[2]
esc = "".join(c if c.isalnum() else "_%02x" % ord(c) for c in unit)
msg = {"type": "signal", "endian": "l", "flags": 1, "version": 1, "cookie": 7, "sender": ":1.1",
       "path": "/org/freedesktop/systemd1/unit/" + esc, "interface": "org.freedesktop.DBus.Properties", "member": "PropertiesChanged"}
if state == "raw":
    pass
elif state == "other":   # the Service interface of the same object
    msg["payload"] = {"type": "sa{sv}as", "data": ["org.freedesktop.systemd1.Service", {"MainPID": {"type": "u", "data": 5}}, []]}
else:
    props = {"SubState": {"type": "s", "data": "running"}}
    if state != "-":
        props["ActiveState"] = {"type": "s", "data": state}
    msg["payload"] = {"type": "sa{sv}as", "data": ["org.freedesktop.systemd1.Unit", props, []]}
print(json.dumps(msg, separators=(",", ":")))
PYEOF
sig() { "$PY" -I "$(wp "$WORK/sig.py")" "$@"; }
run() {   # run <feed lines...>: the topics of the one refresh call (sorted), "-" when none
  : > "$WORK/live.log"
  printf '%s\n' "$@" > "$WORK/feed"
  HS_UNIT_FEED=$(wp "$WORK/feed") $W; rc=$?
  [ "$rc" = 0 ] || echo "exit $rc"
  if [ -s "$WORK/live.log" ]; then cat "$WORK/live.log" | tr ' ' '\n' | sort -u | paste -sd, -; else echo "-"; fi
}

check_eq "a job unit marks jobs-running" "jobs-running" "$(run "$(sig hs-job-pool-bulk-1.service active)")"
check_eq "a plain hs unit that runs marks nothing (only failed counts)" "-" "$(run "$(sig hs-reads-collect.service active)" "$(sig hs-reads-collect.service inactive)")"
check_eq "an hs unit that fails marks the health topics" "health-list,health-next" "$(run "$(sig hs-backup.service active)" "$(sig hs-backup.service failed)")"
check_eq "...and so does the one that leaves failed" "health-list,health-next" "$(run "$(sig hs-backup.service failed)" "$(sig hs-backup.service inactive)" | head -n 1)"
check_eq "a template unit marks the group of its instance" "@ext-confinefx" "$(run "$(sig 'hs-ext-svc@confinefx.service' active)")"
check_eq "samba stopping marks the share and health topics" "health-list,health-next,shares-overview,shares-principals" "$(run "$(sig samba-smbd.service inactive)")"
check_eq "docker marks the docker topics" "docker-apps,docker-list" "$(run "$(sig docker.service failed)")"
check_eq "a unit nobody shows marks nothing" "-" "$(run "$(sig sshd.service failed)" "$(sig NetworkManager.service inactive)")"
check_eq "a SubState-only change marks nothing" "-" "$(run "$(sig incus.service -)")"
check_eq "the same state twice marks once, a new one again (one call, union)" "docker-apps,docker-list" "$(run "$(sig docker.service inactive)" "$(sig docker.service inactive)")"
check_eq "another interface of the unit object marks nothing" "-" "$(run "$(sig incus.service other)")"
check_eq "a signal of another object marks nothing" "-" "$(run '{"type":"signal","path":"/org/freedesktop/systemd1","member":"PropertiesChanged"}')"
check_eq "garbage lines are skipped, the next one still counts" "gateway-health,gateway-routes,gateway-status" "$(run 'not json' '' '[1]' "$(sig traefik.service active)")"
check_eq "a unit message without a readable payload marks its topics" "docker-apps,docker-list" "$(run "$(sig docker.service raw)")"
check_eq "several units in the window are ONE refresh call" "1" "$(run "$(sig docker.service active)" "$(sig traefik.service active)" "$(sig samba-smbd.service active)" >/dev/null; grep -c . "$WORK/live.log")"

# every topic a rule names exists in live-topics.tsv (or is an @group of it / @ext-%i); a timed topic exists and is not also watched
cat > "$WORK/rules.py" <<'PYEOF'
import sys
topics, groups = set(), set()
for line in open(sys.argv[1], encoding="utf-8"):
    if line.startswith("#") or not line.strip():
        continue
    f = line.rstrip("\n").split("\t")
    topics.add(f[0]); groups.update(g for g in f[5].split(",") if g != "-")
bad, watched, timed = [], set(), set()
for line in open(sys.argv[2], encoding="utf-8"):
    if line.startswith("#") or not line.strip():
        continue
    f = line.rstrip("\n").split("\t")
    if len(f) < 5 or f[0] not in ("watch", "timed"):
        bad.append("row: " + line.strip()); continue
    if f[0] == "timed":
        timed.add(f[1]);
        if f[1] not in topics: bad.append("timed topic " + f[1])
        continue
    if f[2] not in ("all", "failed"): bad.append("when " + f[2])
    for t in f[3].split(","):
        watched.add(t)
        if t.startswith("@ext-"): continue
        if t.startswith("@"):
            if t[1:] not in groups: bad.append("group " + t)
        elif t not in topics: bad.append("topic " + t)
bad += ["both watched and timed: " + t for t in sorted(watched & timed)]
print(" ".join(bad) or "ok")
PYEOF
check_eq "unit-topics.tsv names real topics and groups" "ok" "$("$PY" -I "$(wp "$WORK/rules.py")" "$(wp "$SCRIPTS/lib/live-topics.tsv")" "$(wp "$SCRIPTS/lib/unit-topics.tsv")")"

# the monitor ends (a kill of busctl): exit 1, so that systemd restarts the service; a monitor that prints then ends still marks
cat > "$WORK/busctl.py" <<'PYEOF'
import sys
sys.stdout.write(open(sys.argv[1], encoding="utf-8").read())
PYEOF
printf '%s\n' "$(sig docker.service failed)" > "$WORK/feed"
: > "$WORK/live.log"
env -u HS_UNIT_FEED HS_BUSCTL="$PY $(wp "$WORK/busctl.py") $(wp "$WORK/feed")" $W; rc=$?
check_eq "the monitor ending is exit 1 (Restart=always brings it back)" "1" "$rc"
check_eq "...after it marked what it had seen" "docker-list" "$(tr ' ' '\n' < "$WORK/live.log" | grep -x docker-list)"
check "the service restarts on its own" grep -q 'hs-unit-watch' "$ROOT/configuration.nix"
check "...with Restart = always" grep -q 'Restart = "always"' <(grep -A6 'systemd.services.hs-unit-watch' "$ROOT/configuration.nix")
finish
