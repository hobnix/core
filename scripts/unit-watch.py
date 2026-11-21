#!/usr/bin/env python3
"""hs-unit-watch: mark the live-state topics of the units the interface shows when a unit changes state (docs/PLAN-live-interface.md step 4, D4).

Source: `busctl monitor --json=short` on the system bus, matching PropertiesChanged signals of the unit objects of systemd
(/org/freedesktop/systemd1/unit/...). Every line is one JSON message. Only what is needed is read: the object path (the unit name, escaped by
systemd: `_2e` is `.`), and, when the payload is there, the property ActiveState of the interface org.freedesktop.systemd1.Unit. A line that does
not parse is skipped; a unit message whose payload cannot be read marks its topics anyway (a wrong refresh is cheap, a missed one is what the
collector interval is the safety net for). The rules (which unit marks which topics): scripts/lib/unit-topics.tsv.
Changes are coalesced for HS_UNIT_COALESCE seconds (default 1) into ONE `live_refresh` call (scripts/lib/live.sh). Exit 1 when the monitor
ends (systemd restarts the service).
Test knobs: HS_UNIT_FEED=<file> ('-' = stdin) reads the lines from there instead of busctl (exit 0 at the end), HS_UNIT_TOPICS (rules file),
HS_UNIT_COALESCE, HS_BUSCTL, HS_LIVE_LOG (see live.sh).
"""
import fnmatch
import json
import os
import queue
import re
import shlex
import subprocess
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
PREFIX = "/org/freedesktop/systemd1/unit/"
UNIT_IFACE = "org.freedesktop.systemd1.Unit"
MATCH = "type='signal',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',path_namespace='/org/freedesktop/systemd1/unit'"


def load_rules(path):
    rules = []
    for line in open(path, encoding="utf-8"):
        if line.startswith("#") or not line.strip():
            continue
        f = line.rstrip("\n").split("\t")
        if len(f) >= 4 and f[0] == "watch":
            rules.append({"pattern": f[1], "when": f[2], "topics": [t for t in f[3].split(",") if t]})
    return rules


def unescape(seg):
    """systemd's bus path escaping: every byte outside [A-Za-z0-9] is _xx (hex)."""
    return re.sub(r"_([0-9a-fA-F]{2})", lambda m: chr(int(m.group(1), 16)), seg)


def parse(line):
    """-> (unit, active_state) or None. active_state is None when the payload carries none (or cannot be read)."""
    try:
        m = json.loads(line)
    except ValueError:
        return None
    if not isinstance(m, dict):
        return None
    path = m.get("path")
    if not isinstance(path, str) or not path.startswith(PREFIX):
        return None
    if m.get("member") not in (None, "PropertiesChanged"):
        return None
    unit = unescape(path[len(PREFIX):])
    state = None
    unreadable = True
    try:
        data = m["payload"]["data"]
        if data[0] != UNIT_IFACE:
            return None            # the signal of another interface of the same object (Service, Mount ...): not a state change
        props = data[1]
        unreadable = False
        v = props.get("ActiveState")
        if isinstance(v, dict):
            v = v.get("data")
        state = v if isinstance(v, str) else None
        if state is None:
            return unit, "-"       # readable, but ActiveState did not change (SubState, timestamps): nothing to mark
    except (KeyError, IndexError, TypeError, AttributeError):
        pass
    return unit, (None if unreadable else state)


class Watcher:
    def __init__(self, rules):
        self.rules = rules
        self.last = {}     # unit -> last ActiveState seen

    def topics_for(self, unit, state):
        """Topics to mark for one parsed message; remembers the state."""
        if state == "-":
            return set()
        old = self.last.get(unit)
        if state is not None:
            if old == state:
                return set()
            self.last[unit] = state
        out = set()
        inst = unit.split("@", 1)[1].rsplit(".", 1)[0] if "@" in unit else ""
        for r in self.rules:
            if not fnmatch.fnmatchcase(unit, r["pattern"]):
                continue
            if r["when"] == "failed" and state is not None and state != "failed" and old != "failed":
                continue
            for t in r["topics"]:
                if "%i" in t:
                    if not inst:
                        continue
                    t = t.replace("%i", inst)
                out.add(t)
        return out


def refresh(topics):
    code = '. "$1/lib/live.sh"; shift; live_refresh "$@"'
    subprocess.run([os.environ.get("HS_BASH", "bash"), "-c", code, "_", HERE.replace("\\", "/")] + sorted(topics),
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)


def open_feed():
    feed = os.environ.get("HS_UNIT_FEED")
    if feed:
        return (sys.stdin if feed == "-" else open(feed, encoding="utf-8")), None
    p = subprocess.Popen(shlex.split(os.environ.get("HS_BUSCTL") or "busctl") + ["--system", "monitor", "--json=short", "--match=" + MATCH],
                         stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, encoding="utf-8", errors="replace")
    return p.stdout, p


def main():
    rules = load_rules(os.environ.get("HS_UNIT_TOPICS") or os.path.join(HERE, "lib", "unit-topics.tsv"))
    window = float(os.environ.get("HS_UNIT_COALESCE", "1"))
    w = Watcher(rules)
    stream, proc = open_feed()
    q = queue.Queue()

    def reader():
        for line in stream:
            q.put(line)
        q.put(None)
    threading.Thread(target=reader, daemon=True).start()
    pending, since, eof = set(), 0.0, False
    while not eof:
        timeout = None if not pending else max(0.0, since + window - time.monotonic())
        try:
            line = q.get(timeout=timeout)
        except queue.Empty:
            line = ""
        if line is None:
            eof = True
        elif line:
            r = parse(line)
            if r:
                t = w.topics_for(*r)
                if t:
                    if not pending:
                        since = time.monotonic()
                    pending |= t
        if pending and (eof or time.monotonic() - since >= window):
            refresh(pending)
            pending = set()
    if proc is not None:
        proc.wait()
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
