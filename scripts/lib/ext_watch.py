"""Watches whether the integration rows of a running service extension still hold (hobnix/core#1328, ADR 0011 rule 6). Python stdlib only, no CLI:
the bridge (ext_service.py svc-run) imports it. The rows in `init` name the address of a provider's instance as it was at the start; a provider that
stops, restarts or gets another address, or has none yet at boot, changes them, and the bridge then restarts the service process with new rows.

What is watched: the instances that the service records of the providers in the rows name (also one that is down at the start).
  - the lifecycle stream of Incus (`incus monitor`, reconnected with a back-off): an event of a watched instance plans a few checks;
  - after the start, while a row has no address: a few checks without any event (boot: the instances get their addresses later);
  - after every connect of the stream one check (an event can be lost while nothing listens);
  - every 30 minutes one check, for an address that changed without any event.
A check builds the listing again and compares it with the rows the service runs with; two changes are at least REINIT_GAP apart. Nothing else is
polled. Cost: one `incus monitor` process per service that has such a provider, idle it blocks on a read and on a condition. Not tested on
hardware yet.
"""
import bisect
import json
import os
import shlex
import subprocess
import threading
import time

WATCH_ACTIONS = ("created", "started", "stopped", "shutdown", "deleted", "restarted", "renamed", "resumed", "updated", "rebuilt")
CHECK_DELAYS = (2, 10, 30, 60)             # seconds after an event: an address comes some time after `started`
START_DELAYS = (10, 30, 60, 120, 300)      # seconds after the start, only while a row has no address
SLOW_CHECK = 1800.0                        # the safety net for a change without an event
REINIT_GAP = 20.0                          # at least this long between two changes: a flapping provider does not restart the service all the time
BACKOFF = (5, 10, 20, 40, 60)              # seconds before the stream is connected again
STREAM_OK = 60.0                           # a stream that lived this long starts the back-off again
MERGE = 1.0                                # two checks closer than this are one
MAX_LINE = 1 << 20


def events_cmd():
    """The command that streams Incus lifecycle events; HS_EXT_INCUS_EVENTS (a command line) replaces it in tests."""
    o = os.environ.get("HS_EXT_INCUS_EVENTS")
    if o:
        return shlex.split(o)
    return [os.environ.get("HS_INCUS") or "incus", "monitor", "--type=lifecycle", "--format=json"]


def parse(line, pi):
    """The instance name of one line of the event stream, or None when it is no change of an instance of the default project (the rows are read
    there only). Only type, action, source and project are read: the context of the event (can hold config values) is never looked at.
    `pi` is the pkg_integrations module: its INSTANCE is the one rule for an instance name."""
    try:
        ev = json.loads(line)
        md = ev.get("metadata") or {}
        action, src = md.get("action"), md.get("source")
        if ev.get("type") != "lifecycle" or not isinstance(action, str) or not isinstance(src, str) or ev.get("project") not in (None, "default"):
            return None
    except (ValueError, AttributeError, RecursionError):
        return None
    if not action.startswith("instance-") or action[len("instance-"):] not in WATCH_ACTIONS:
        return None
    path = src.split("?", 1)[0]
    if not path.startswith("/1.0/instances/"):
        return None
    name = path[len("/1.0/instances/"):]
    return name if pi.INSTANCE.fullmatch(name) else None


def watched_instances(rows, services_dir, pi):
    """The instance names that the service records of the packages in `rows` give as their `container`."""
    out = set()
    for package in {r["package"] for r in rows}:
        name = pi.service_record(services_dir, package).get("container")
        if isinstance(name, str) and pi.INSTANCE.fullmatch(name):
            out.add(name)
    return out


class IntegrationWatch:
    """Calls on_change(new rows) when list_rows() gives something else than the rows the service runs with (`baseline`). Two daemon threads: one
    reads the event stream and plans checks, one runs them. list_rows() returns None when it cannot say: then nothing happens. `pi` as in parse()."""

    def __init__(self, watched, baseline, list_rows, on_change, pi, cmd=events_cmd, delays=CHECK_DELAYS, start_delays=START_DELAYS, gap=REINIT_GAP,
                 backoff=BACKOFF, clock=time.monotonic, log=None, every=SLOW_CHECK):
        self.watched, self.baseline = set(watched), baseline
        self.list_rows, self.on_change, self.pi, self.cmd = list_rows, on_change, pi, cmd
        self.delays, self.start_delays, self.gap, self.backoff, self.every = delays, start_delays, gap, backoff, every
        self.clock = clock
        self.log = log or (lambda text: None)
        self._cond = threading.Condition()      # guards _due and _proc
        self._stop = threading.Event()
        self._due = []                          # times of the planned checks, ascending
        self._proc = None
        self._changed = None                    # the time of the last change

    def start(self):
        if any(r.get("api_url") is None for r in self.baseline):
            self._plan(self.start_delays)
        for f in (self._stream, self._schedule):
            threading.Thread(target=f, daemon=True).start()

    def stop(self):
        with self._cond:
            self._stop.set()
            proc = self._proc
            self._cond.notify_all()
        if proc:
            self._end(proc)

    def _add(self, t):          # the caller holds _cond
        if all(abs(t - x) >= MERGE for x in self._due):
            bisect.insort(self._due, t)
            self._cond.notify_all()

    def _plan(self, delays):
        with self._cond:
            now = self.clock()
            for d in delays:
                self._add(now + d)

    @staticmethod
    def _end(proc):
        try:
            proc.terminate()
            proc.wait(2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
        except OSError:
            pass

    def _spawn(self):
        with self._cond:        # stop() either sees the process or the process is never started
            if self._stop.is_set():
                return None
            try:
                self._proc = subprocess.Popen(self.cmd(), stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            except (OSError, ValueError):
                return None
            return self._proc

    def _read(self, out):
        skipping = False
        while True:
            raw = out.readline(MAX_LINE + 1)
            if not raw:
                return
            if skipping or len(raw) > MAX_LINE:      # the rest of a long line is dropped too
                skipping = not raw.endswith(b"\n")
                continue
            if parse(raw, self.pi) in self.watched:
                self._plan(self.delays)

    def _stream(self):
        fails, said = 0, False
        while not self._stop.is_set():
            began = self.clock()
            proc = self._spawn()
            if proc is not None:
                try:
                    self._plan(self.delays[:1])      # an event between the listing before and this connect would be lost
                    self._read(proc.stdout)
                except Exception as e:               # the thread must live on
                    self.log("reading the Incus events failed (%s)" % type(e).__name__)
                finally:
                    self._end(proc)
                    proc.stdout.close()
            if self._stop.is_set():
                return
            if self.clock() - began >= STREAM_OK:
                fails, said = 0, False
            if not said:                             # once per outage
                self.log("the Incus event stream ended, it is connected again")
                said = True
            if self._stop.wait(self.backoff[min(fails, len(self.backoff) - 1)]):
                return
            fails += 1

    def _schedule(self):
        slow = self.clock() + self.every
        while True:
            with self._cond:
                while True:
                    if self._stop.is_set():
                        return
                    now = self.clock()
                    first = min(self._due[:1] + [slow])
                    if first <= now:
                        break
                    self._cond.wait(first - now)
                while self._due and self._due[0] <= now:     # one check for all that are due
                    self._due.pop(0)
                if slow <= now:
                    slow = now + self.every
            self.check()

    def check(self):
        try:
            new = self.list_rows()
            if new is None or new == self.baseline:
                return
            now = self.clock()
            if self._changed is not None and now - self._changed < self.gap:
                with self._cond:
                    self._add(self._changed + self.gap)
                return
            if self._stop.is_set():
                return
            self.baseline, self._changed = new, now
            self.log("the rows of an integration changed: the service restarts with them")
            self.on_change(new)
        except Exception as e:      # only the kind of error: a text could hold a row
            self.log("the check of the integration rows failed (%s)" % type(e).__name__)
