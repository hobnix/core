#!/usr/bin/env bash
# help: what the live-state collector costs right now: its CPU seconds, how many reads it started in the last minute, per topic
# help.de: was der Live-Zustand-Sammler gerade kostet: seine CPU-Sekunden und wie viele Lesevorgänge er in der letzten Minute gestartet hat, je Thema
# args: [--top <N>]
# Reads the file the collector hs-live writes every few seconds (scripts/live-collect.py write_stats; HS_LIVE_LOAD_FILE, default /run/hs/live-load.json).
# Also the line `web`: how often the web server looked at the change counters because of a push datagram and how often because the fallback period ran out. Changes nothing. A topic in the list that was read more often than its interval says is the place to look.
set -uo pipefail
here=$(dirname "$0")
. "$here/lib/ui.sh"
top=12
if [ "${1:-}" = --top ]; then top=${2:-12}; fi
[[ "$top" =~ ^[0-9]+$ ]] || { help_usage "usage: hs live load [--top <N>]"; exit 1; }
file=${HS_LIVE_LOAD_FILE:-${HS_RUN_DIR:-/run/hs}/live-load.json}
[ -r "$file" ] || fail "$(t 'No load numbers yet: the collector (hs-live) is not running, or has not written them. Look: systemctl status hs-live')"
out=$(python3 - "$file" "$top" <<'PY'
import json, sys, time
d = json.load(open(sys.argv[1], encoding="utf-8"))
age = int(time.time()) - int(d.get("time", 0))
print("age\t%d s" % age)
print("cpu\t%s s since the collector started (%d s ago)" % (d.get("cpu_s", "?"), int(d.get("time", 0)) - int(d.get("since", 0))))
print("busy\t%s cores of read time over the last %d s" % (d.get("busy", "?"), int(d.get("window", 60))))
print("stretch\t%s (1 = the timed reads run on their own interval)" % d.get("stretch", "?"))
print("reads\t%s started in the last %d s" % (d.get("reads", "?"), int(d.get("window", 60))))
print("--")
rows = sorted((d.get("topics") or {}).items(), key=lambda kv: -kv[1].get("reads", 0))[: int(sys.argv[2])]
print("topic\treads\tms of the last read")
for t, v in rows:
    print("%s\t%s\t%s" % (t, v.get("reads", 0), v.get("ms", 0)))
PY
)
step "$(t 'Live-state collector load')"
while IFS=$'\t' read -r k v; do
  [ "$k" = -- ] && break
  KV_WIDTH=8 kv "$k" "$v"
done <<<"$out"
# D11: how the web server woke up: by a datagram (push) or by the fallback period (scripts/web-serve.py Events.write_push_stats); nothing when it has not written
pushf=${HS_LIVE_PUSH_FILE:-${HS_RUN_DIR:-/run/hs}/live-push.json}
if [ -r "$pushf" ]; then
  pushline=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1], encoding="utf-8")); print("%s by push, %s by the fallback period, socket %s" % (d.get("push", 0), d.get("fallback", 0), "up" if d.get("socket") else "down"))' "$pushf" 2>/dev/null || true)
  [ -z "$pushline" ] || KV_WIDTH=8 kv "web" "$pushline"
fi
printf '%s\n' "$out" | sed -n '/^--$/,$p' | tail -n +2 | table
