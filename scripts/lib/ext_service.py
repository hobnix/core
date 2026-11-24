#!/usr/bin/env python3
"""Reference supervisor of ONE service extension, protocol version 1 (docs/adr/0011-extension-service-lifecycle.md). Python stdlib only.

It is the bridge the unit hs-ext-svc@<name>.service runs (`hs ext svc-run <name>`, see svc-run below): start the service process, send `init`, wait for `ready`,
deliver the events the service subscribed to from the event log with at-least-once acks and a cursor file, watch the heartbeat, and stop the
service (shutdown message, SIGTERM to the process group, SIGKILL). Restarting after a crash is NOT done here: the unit does it (systemd Restart=).

  ext_service.py run --name N [--subscribe GLOB]... [--events FILE] [--cursor FILE] [--ready-timeout S] [--health-interval S]
                     [--missed N] [--grace S] [--run-for S] -- PROGRAM [ARG...]
     --events FILE   a JSON Lines file of event-log rows (id, time, source, kind, subject, level, text, payload): the stand-in for the log
     --run-for S     stop after S seconds (a test knob); otherwise SIGTERM/SIGINT stops it
  Output: every state change as {"v":1,"type":"state","state":...} and every message the service sent (`log`, `emit`, `snapshot`), then one
  {"type":"final",...}. Exit code: 0 stopped on request, 1 the service exited or broke the protocol, 75 it never became ready.

  ext_service.py svc-run --name N --dir PACKAGE_DIR --state-dir DIR
     The unit's ExecStart: reads [service] (exec, subscribe, health_interval) of the package, supervises it, writes the states to
     DIR/<N>.json and records a failed run. The fifth failure within 10 minutes (the unit's StartLimitBurst, ADR 0011 rule 2) emits the
     core event ext.service-failed ONCE (systemd then refuses the sixth start). Events come from the event log (state.db) after the cursor
     file CURSOR_DIR/<N> (decision D12); `emit` becomes an event (50 a minute, the 51st is dropped with a warning); `snapshot` is written to
     SNAP_DIR/<N>/<topic>.json, which the live collector serves as the live topic ext-<N>-<topic>. Exit: 0 stopped on request, 1 failed, 75 never ready.
  ext_service.py has-service DIR      exit 0 when the package has a [service] table
  ext_service.py status --name N --state-dir DIR [--active yes|no] [--stopped yes|no]    prints state, reason, since (TAB, `-` when empty)
  ext_service.py reset --name N --state-dir DIR    forget the state and the failures (hs ext start)
  Test knobs: HS_NOW (the clock), HS_EXT_EMIT (a program called instead of `hs event emit`, same arguments), HS_STATE_DIR (the state root,
  default LIB_DIR), HS_STATE_DB (the event log).

Schema of the messages: docs/api/ext-service-v1.schema.json.
"""
import argparse
import fnmatch
import importlib.util
import json
import math
import os
import queue
import re
import shutil
import signal
import subprocess
import sys
import threading
import time
try:
    import tomllib
except ImportError:   # Python 3.10 or older: [service] cannot be read
    tomllib = None

VERSION = 1
LIB_DIR = "/var/lib/hs"         # the state root: the ONE place that names it, so the later hs -> hn rename is one edit
CURSOR_SUB = "ext-cursors"      # decision D12: one file per service, the last acknowledged event id
SNAP_SUB = "ext-snapshots"      # one file per snapshot topic; the live collector serves it as the live topic ext-<name>-<topic>
EMIT_LIMIT = 50                 # emits a minute per service
EMIT_WINDOW = 60.0
MAX_LINE = 1 << 20
MAX_SNAPSHOT = 256 << 10
WINDOW = 100                    # events sent but not yet acknowledged, at most
KIND = re.compile(r"^pkg\.[a-z][a-z0-9-]*\.[a-z][a-z0-9-]*$")
STATES = ("starting", "running", "degraded", "stopping", "stopped", "failed")
FROM_SERVICE = ("ready", "health", "ack", "log", "emit", "snapshot", "rollup")


def check_message(m):
    """None when m is a valid message from the service, else the reason."""
    if not isinstance(m, dict) or m.get("v") != VERSION:
        return f"a message is a JSON object with v {VERSION}"
    t = m.get("type")
    if t not in FROM_SERVICE:
        return f"unknown type {t!r}"
    if t == "health" and (not isinstance(m.get("ok"), bool) or not isinstance(m.get("text", ""), str)
                              or len(m.get("text", "")) > 200):
        return "health needs ok (boolean) and text of at most 200 characters"
    if t == "ack" and (isinstance(m.get("id"), bool) or not isinstance(m.get("id"), int) or m["id"] < 1):
        return "ack needs id (a positive integer)"
    if t == "log" and (m.get("level") not in ("debug", "info", "warn", "error") or not isinstance(m.get("text"), str)
                            or len(m["text"]) > 1000):
        return "log needs level and text of at most 1000 characters"
    if t == "emit" and (not isinstance(m.get("kind"), str) or not KIND.match(m["kind"]) or not isinstance(m.get("subject"), str)):
        return "emit needs kind (pkg.<package>.<what>) and subject"
    if t == "emit" and (m.get("level", "info") not in ("info", "warn", "error") or not isinstance(m.get("payload", {}), dict)
                        or not isinstance(m.get("text", ""), str)):
        return "emit.level is info|warn|error, payload an object, text a string"
    if t == "rollup" and (not isinstance(m.get("kind"), str) or not KIND.match(m["kind"])
                          or not isinstance(m.get("user"), str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.@-]{0,63}", m["user"])):
        return "rollup needs kind (pkg.<package>.<what>) and user (letters, digits, _ . @ -, at most 64)"
    if t == "rollup" and any(k in m and (isinstance(m[k], bool) or not isinstance(m[k], (int, float)) or not math.isfinite(m[k]) or not 0 <= m[k] <= 1e12)
                             for k in ("n", "sum")):
        return "rollup.n and rollup.sum are finite numbers of 0 or more"
    if t == "snapshot" and (not isinstance(m.get("topic"), str) or not re.match(r"^[a-z0-9-]{1,60}$", m["topic"]) or "data" not in m):
        return "snapshot needs topic (a-z, 0-9, -) and data"
    if t == "snapshot" and len(json.dumps(m["data"])) > MAX_SNAPSHOT:
        return "snapshot data is larger than 256 KiB"
    return None


def state_root():
    return os.environ.get("HS_STATE_DIR") or LIB_DIR


def cursor_path(name):
    return os.path.join(state_root(), CURSOR_SUB, name)


def snapshot_dir(name):
    return os.path.join(state_root(), SNAP_SUB, name)


def read_cursor(path):
    try:
        return max(0, int(open(path).read().strip() or 0))
    except (OSError, ValueError):
        return 0


def write_cursor(path, n):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    tmp = f"{path}.tmp"
    with open(tmp, "w") as f:
        f.write(f"{n}\n")
    os.replace(tmp, path)


def file_events(path):
    """The stand-in event log: fetch(after, limit) -> rows with id > after, oldest first."""
    def fetch(after, limit):
        rows = []
        try:
            for line in open(path):
                if line.strip():
                    r = json.loads(line)
                    if r["id"] > after:
                        rows.append(r)
        except OSError:
            pass
        rows.sort(key=lambda r: r["id"])
        return rows[:limit]
    return fetch


def supervise(prog, name, subscribe=(), fetch=None, cursor_file=None, ready_timeout=30.0, health_interval=30.0, missed=3,
              grace=10.0, stop=None, on_state=None, on_message=None, lang="en", integrations=()):
    """Run the service until `stop` is set or it ends. Returns {"state", "code", "reason", "exit"}."""
    stop = stop or threading.Event()
    state = {"v": None}

    def set_state(s, why=""):
        if state["v"] != s:
            state["v"] = s
            if on_state:
                on_state(s, why)
    set_state("starting")
    try:
        proc = subprocess.Popen(prog, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, start_new_session=True)
    except OSError as e:
        set_state("failed", str(e))
        return {"state": "failed", "code": "spawn_failed", "reason": str(e), "exit": None}
    lines = queue.Queue()

    def reader():
        while True:
            raw = proc.stdout.readline(MAX_LINE + 1)
            if not raw:
                break
            if len(raw) > MAX_LINE:          # no newline within the limit
                lines.put(b"\x00toolong")
                return
            lines.put(raw)
        lines.put(None)
    threading.Thread(target=reader, daemon=True).start()

    outbox = queue.Queue()

    def writer():   # a service that stops reading must not freeze the loop, the heartbeat check or the stop
        while True:
            b = outbox.get()
            if b is None:
                return
            try:
                proc.stdin.write(b)
                proc.stdin.flush()
            except (BrokenPipeError, OSError, ValueError):
                return
    threading.Thread(target=writer, daemon=True).start()

    def send(m):
        outbox.put((json.dumps({"v": VERSION, **m}, separators=(",", ":")) + "\n").encode())
    init = {"type": "init", "name": name, "lang": lang, "subscribe": list(subscribe), "health_interval": health_interval}
    if integrations:    # additive: a service that does not know the field ignores it (ADR 0011)
        init["integrations"] = list(integrations)
    send(init)

    cursor = read_cursor(cursor_file) if cursor_file else 0
    sent = cursor              # the highest id sent
    inflight = []              # ids sent and not yet acked, ascending
    acked = set()
    ready = False
    t0 = time.monotonic()
    last_health = t0
    result = None
    try:
        while result is None:
            if stop.is_set():
                result = ("stopped", "stopped", "stopped on request")
                break
            try:
                raw = lines.get(timeout=0.05)
            except queue.Empty:
                raw = b""
            now = time.monotonic()
            if raw is None:
                result = ("failed", "exited", f"the service ended (exit {proc.poll()})")
                break
            if raw == b"\x00toolong":
                result = ("failed", "protocol_error", "a line is longer than 1 MiB")
                break
            if raw.strip():
                try:
                    m = json.loads(raw)
                except ValueError:
                    m = None
                why = check_message(m) if m is not None else "stdout line is not JSON"
                if why:
                    result = ("failed", "protocol_error", why)
                    break
                t = m["type"]
                if t == "ready":
                    if not ready:
                        ready = True
                        last_health = now
                        set_state("running")
                elif not ready:
                    result = ("failed", "protocol_error", f"{t} before ready")
                    break
                elif t == "health":
                    last_health = now
                    set_state("running" if m["ok"] else "degraded", m.get("text", ""))
                elif t == "ack":
                    if m["id"] in inflight:
                        acked.add(m["id"])
                        while inflight and inflight[0] in acked:
                            cursor = inflight.pop(0)
                            acked.discard(cursor)
                            if cursor_file:
                                write_cursor(cursor_file, cursor)
                    else:
                        result = ("failed", "protocol_error", f"ack of {m['id']}, which was not sent")
                        break
                elif on_message:
                    on_message(m)
            if not ready:
                if now - t0 > ready_timeout:
                    result = ("failed", "start_timeout", f"no ready within {ready_timeout:g} s")
                continue
            if now - last_health > health_interval * missed:
                set_state("degraded", "heartbeat missed")
            if subscribe and fetch and len(inflight) < WINDOW:
                for r in fetch(sent, WINDOW - len(inflight)):
                    sent = r["id"]
                    if any(fnmatch.fnmatchcase(f"{r['source']}.{r['kind']}", g) for g in subscribe):
                        inflight.append(r["id"])
                        send({"type": "event", **{k: r.get(k) for k in ("id", "time", "source", "kind", "subject", "level", "text", "payload")}})
            if not inflight and sent > cursor:   # everything up to `sent` was acknowledged or not wanted: the cursor moves
                cursor = sent
                if cursor_file:
                    write_cursor(cursor_file, cursor)
    except BaseException:   # an error here (a cursor file that cannot be written) must not leave the service running
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass
        raise
    final_state, code, reason = result
    if final_state == "stopped":
        set_state("stopping")
        send({"type": "shutdown", "grace_ms": int(grace * 1000)})
        try:
            proc.wait(timeout=grace)       # the service ends by itself after `shutdown`
        except subprocess.TimeoutExpired:
            pass
    for sig, wait in ((signal.SIGTERM, 2.0), (signal.SIGKILL, 0)):   # a service still alive gets SIGTERM, then SIGKILL, as a command (ADR 0010)
        if proc.poll() is not None:
            break
        try:
            os.killpg(proc.pid, sig)
        except (ProcessLookupError, PermissionError):
            pass
        if wait:
            try:
                proc.wait(timeout=wait)
            except subprocess.TimeoutExpired:
                pass
    try:
        os.killpg(proc.pid, signal.SIGKILL)    # children of the service
    except (ProcessLookupError, PermissionError):
        pass
    proc.wait()
    set_state(final_state, reason)
    return {"state": final_state, "code": code, "reason": reason, "exit": proc.returncode}


FAIL_LIMIT = 5          # StartLimitBurst of the unit
FAIL_WINDOW = 600       # StartLimitIntervalSec of the unit


def now():
    return int(os.environ.get("HS_NOW") or time.time())


def service_table(pkgdir):
    """The [service] table of the package (package.toml, else capability.toml) as a dict, or None."""
    if tomllib is None:
        return None
    for f in ("package.toml", "capability.toml"):
        try:
            with open(os.path.join(pkgdir, f), "rb") as fh:
                t = tomllib.load(fh).get("service")
        except (OSError, ValueError):
            continue
        if isinstance(t, dict):
            return t
    return None


def program_of(pkgdir, exec_):
    """The argv of a service `exec`: @/file inside the package, else a path under scripts/ (scripts/lib/pkg_protocol.py validated it)."""
    if exec_.startswith("@/"):
        path = os.path.join(pkgdir, exec_[2:])
    else:
        path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), exec_)
    if path.endswith(".py"):
        return [sys.executable, path]
    if path.endswith(".sh"):
        return ["bash", path]
    return [path]


def state_path(state_dir, name):
    return os.path.join(state_dir, f"{name}.json")


def load_state(state_dir, name):
    try:
        with open(state_path(state_dir, name)) as f:
            d = json.load(f)
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def save_state(state_dir, name, d):
    os.makedirs(state_dir, exist_ok=True)
    tmp = state_path(state_dir, name) + ".tmp"
    with open(tmp, "w") as f:
        json.dump(d, f)
    os.replace(tmp, state_path(state_dir, name))


def emit_failed(name, code, reason):
    """The core event ext.service-failed (kind registered in scripts/lib/event-kinds.tsv)."""
    scripts = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    prog = [os.environ["HS_EXT_EMIT"]] if os.environ.get("HS_EXT_EMIT") else ["bash", os.path.join(scripts, "event.sh"), "emit"]
    text = f"The service of {name} failed {FAIL_LIMIT} times in {FAIL_WINDOW // 60} minutes and was given up: {reason}"
    try:
        subprocess.run(prog + ["ext.service-failed", name, text, "--level", "error",
                               "--payload", json.dumps({"package": name, "code": code}, separators=(",", ":"))],
                       stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30, check=False)
    except (OSError, subprocess.SubprocessError):
        pass


def record_failure(state_dir, name, code, reason):
    """Count a failed run; the FAIL_LIMIT-th within FAIL_WINDOW emits the event once. Returns the number of failures in the window."""
    d = load_state(state_dir, name)
    t = now()
    fails = [x for x in d.get("failures", []) if isinstance(x, int) and t - x < FAIL_WINDOW] + [t]
    if len(fails) < FAIL_LIMIT:
        d["notified"] = False
    d["failures"] = fails
    emit = len(fails) >= FAIL_LIMIT and not d.get("notified")
    if emit:
        d["notified"] = True
    save_state(state_dir, name, d)      # before emitting, so a crash while emitting cannot make a second event
    if emit:
        emit_failed(name, code, reason)
    return len(fails)


def db_events():
    """The real event log: fetch(after, limit) -> rows with id > after, oldest first (read only; nothing when there is no database yet)."""
    import sqlite3
    path = os.environ.get("HS_STATE_DB") or os.path.join(state_root(), "state.db")

    def fetch(after, limit):
        if not os.path.exists(path):
            return []
        try:
            c = sqlite3.connect("file:%s?mode=ro" % path.replace("\\", "/"), uri=True, timeout=10)
            try:
                c.execute("PRAGMA query_only=1")
                rows = c.execute("SELECT id, time, source, kind, subject, level, text, payload FROM events WHERE id > ? ORDER BY id LIMIT ?",
                                 (after, limit)).fetchall()
            finally:
                c.close()
        except sqlite3.Error:
            return []
        out = []
        for i, t, src, kind, subj, lvl, text, payload in rows:
            try:
                pl = json.loads(payload) if payload else None
            except ValueError:
                pl = None
            out.append({"id": i, "time": t, "source": src, "kind": kind, "subject": subj or "", "level": lvl, "text": text or "", "payload": pl})
        return out
    return fetch


def db_latest():
    """The newest event id, 0 without a database: a service that starts for the first time gets what happens from now on, not the whole log."""
    path = os.environ.get("HS_STATE_DB") or os.path.join(state_root(), "state.db")
    if not os.path.exists(path):
        return 0
    import sqlite3
    try:
        c = sqlite3.connect("file:%s?mode=ro" % path.replace("\\", "/"), uri=True, timeout=10)
        try:
            return c.execute("SELECT COALESCE(MAX(id), 0) FROM events").fetchone()[0]
        finally:
            c.close()
    except sqlite3.Error:
        return 0


class RateLimit:
    """At most `limit` events in any `window` seconds (a sliding window). allow() -> True and counts, or False."""

    def __init__(self, limit=EMIT_LIMIT, window=EMIT_WINDOW, clock=time.monotonic):
        self.limit, self.window, self.clock, self.stamps = limit, window, clock, []

    def allow(self):
        t = self.clock()
        self.stamps = [x for x in self.stamps if t - x < self.window]
        if len(self.stamps) >= self.limit:
            return False
        self.stamps.append(t)
        return True


def emit_event(name, m):
    """Write the event of an `emit` message into the event log: `hs event emit pkg.<package>.<what> <subject> [text] --level L --payload JSON`."""
    scripts = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    prog = [os.environ["HS_EXT_EMIT"]] if os.environ.get("HS_EXT_EMIT") else ["bash", os.path.join(scripts, "event.sh"), "emit"]
    args = [m["kind"], m["subject"] or name, m.get("text", ""), "--level", m.get("level", "info")]
    if m.get("payload"):
        args += ["--payload", json.dumps(m["payload"], separators=(",", ":"))]
    try:
        subprocess.run(prog + args, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30, check=False)
    except (OSError, subprocess.SubprocessError):
        pass


def write_snapshot(name, topic, data):
    """Store a snapshot where the collector looks for it; only a changed document is written (no new generation for the same data)."""
    d = snapshot_dir(name)
    os.makedirs(d, exist_ok=True)
    path = os.path.join(d, topic + ".json")
    text = json.dumps(data, sort_keys=True, separators=(",", ":"))
    try:
        with open(path) as f:
            if f.read() == text:
                return False
    except OSError:
        pass
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        f.write(text)
    os.replace(tmp, path)
    return True


def emit_globs(perms):
    """The kind globs of `events.emit:<glob>` in a list of permissions, or None when the package declares no permissions (perms is None).
    A declaration without events.emit is an empty list: such a package may emit nothing."""
    if perms is None:
        return None
    return [p.partition(":")[2] for p in perms if p.partition(":")[0] == "events.emit"]


def declared_perms(pkgdir):
    """`permissions` of the package.toml (else capability.toml) in pkgdir as a list of texts, or None when it declares none."""
    if tomllib is None:
        return None
    for f in ("package.toml", "capability.toml"):
        try:
            with open(os.path.join(pkgdir, f), "rb") as fh:
                p = tomllib.load(fh).get("permissions")
        except (OSError, ValueError):
            continue
        if isinstance(p, list):
            return [str(x) for x in p]
    return None


def emit_verdict(name, perms, kind):
    """None when `name` may emit `kind`, else the reason. Always below pkg.<name>.; with declared `permissions` also covered by one events.emit glob.
    Without `permissions` only the prefix is checked (today's behaviour; the install warning names the missing declaration)."""
    if not kind.startswith(f"pkg.{name}."):
        return f"a package may only emit pkg.{name}.<what>"
    globs = emit_globs(perms)
    if globs is not None and not any(fnmatch.fnmatchcase(kind, g) for g in globs):
        return "not covered by its events.emit permission"
    return None


def metric_kinds(pkgdir):
    """The kinds the package declared with `retention = "metric"` in its [[events]] (package.toml, else capability.toml)."""
    if tomllib is None or not pkgdir:
        return set()
    for f in ("package.toml", "capability.toml"):
        try:
            with open(os.path.join(pkgdir, f), "rb") as fh:
                ev = tomllib.load(fh).get("events")
        except (OSError, ValueError):
            continue
        if isinstance(ev, list):
            return {e["kind"] for e in ev if isinstance(e, dict) and e.get("retention") == "metric" and isinstance(e.get("kind"), str)}
    return set()


def rollup_verdict(name, pkgdir, kind):
    """None when `name` may add to the monthly rollup of `kind`, else the reason: only a kind of its own that its [[events]] declare with retention = metric."""
    if not kind.startswith(f"pkg.{name}."):
        return f"a package may only roll up pkg.{name}.<what>"
    if kind not in metric_kinds(pkgdir):
        return 'not declared in [[events]] with retention = "metric"'
    return None


def _plain(v):
    """A number as the text rollup-add reads: a whole number without a point, else a plain decimal (no exponent)."""
    return str(int(v)) if float(v) == int(v) else format(v, "f")


def rollup_add(m):
    """`hs sys state rollup-add <kind> <user> --n N --sum S`, run by the bridge (root, outside the sandbox of the service). None, or why it failed."""
    scripts = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    prog = [os.environ["HS_EXT_ROLLUP"]] if os.environ.get("HS_EXT_ROLLUP") else ["bash", os.path.join(scripts, "state.sh"), "rollup-add"]
    args = [m["kind"], m["user"], "--n", _plain(m.get("n", 1)), "--sum", _plain(m.get("sum", 0))]
    try:
        r = subprocess.run(prog + args, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=30, check=False)
    except (OSError, subprocess.SubprocessError) as e:
        return str(e)
    if r.returncode:
        return "rollup-add exited %d: %s" % (r.returncode, r.stderr.decode("utf-8", "replace").strip()[:200])
    return None


def make_handler(name, limit=None, warn=None, perms=None, pkgdir=None):
    """The on_message of svc-run: `log` to the journal, `emit` into the event log under the rate limit, `snapshot` to the snapshot file.
    perms = the declared permissions (None = none declared). A refused kind is warned once per kind, not per call."""
    limit = limit or RateLimit()
    warn = warn or (lambda s: print(f"warn: {s}", file=sys.stderr, flush=True))
    state = {"warned": False}
    refused = set()

    def handle(m):
        t = m.get("type")
        if t == "log":
            print(f"{m['level']}: {m['text']}", file=sys.stderr, flush=True)
        elif t == "emit":
            why = emit_verdict(name, perms, m["kind"])
            if why:
                if m["kind"] not in refused:
                    refused.add(m["kind"])
                    warn(f"{name}: emit of {m['kind']} dropped ({why})")
            elif limit.allow():
                state["warned"] = False
                emit_event(name, m)
            elif not state["warned"]:     # one warning per burst, not one per dropped event
                state["warned"] = True
                warn(f"{name}: more than {limit.limit} emits in {limit.window:g} s, further ones are dropped")
        elif t == "rollup":
            why = rollup_verdict(name, pkgdir, m["kind"])
            if why:
                if ("rollup", m["kind"]) not in refused:
                    refused.add(("rollup", m["kind"]))
                    warn(f"{name}: rollup of {m['kind']} dropped ({why})")
            elif limit.allow():
                bad = rollup_add(m)
                if bad:
                    warn(f"{name}: rollup of {m['kind']} was not stored ({bad})")
        elif t == "snapshot":
            write_snapshot(name, m["topic"], m["data"])
    return handle


def unit_of(name):
    return f"hs-ext-run-{name}"


def stop_unit(name):
    """Stop the transient unit of the service (a stop of the systemd-run client alone may leave it running)."""
    try:
        subprocess.run([os.environ.get("HS_SYSTEMCTL", "systemctl"), "stop", unit_of(name) + ".service"], stdin=subprocess.DEVNULL,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30, check=False)
    except (OSError, subprocess.SubprocessError):
        pass


def _load_lib(mod):
    spec = importlib.util.spec_from_file_location(mod, os.path.join(os.path.dirname(os.path.abspath(__file__)), mod + ".py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def cred_root():
    return os.environ.get("HS_CRED_DIR") or "/run/hs-ext-cred"


def cred_dir(name):
    """The private folder (0700, one per service, below a 0700 parent in /run) that holds the copies of the keys of one service for LoadCredential=.
    The copy lives only until the unit has started (systemd reads it before the service runs; `running` removes it), and the transient unit
    cannot enter /run/hs-ext-cred (InaccessiblePaths, ext_confine.py). The unit gets its own copy in its private $CREDENTIALS_DIRECTORY."""
    return os.path.join(cred_root(), name)


def make_private_dir(d):
    old = os.umask(0o077)
    try:
        os.makedirs(d, mode=0o700, exist_ok=True)
    finally:
        os.umask(old)
    os.chmod(d, 0o700)


def drop_creds(name):
    shutil.rmtree(cred_dir(name), ignore_errors=True)


def sweep_creds(name, active=None):
    """At the start of a bridge: remove the key copies a crash left (its own, and those of units that are not running)."""
    active = active or (lambda n: subprocess.run([os.environ.get("HS_SYSTEMCTL", "systemctl"), "is-active", "--quiet", f"hs-ext-svc@{n}.service"],
                                                  stdin=subprocess.DEVNULL, check=False).returncode == 0)
    make_private_dir(cred_root())    # always there before any unit starts, so InaccessiblePaths=-/run/hs-ext-cred applies to every service
    drop_creds(name)
    try:
        others = os.listdir(cred_root())
    except OSError:
        return
    for n in others:
        try:
            if n != name and not active(n):
                drop_creds(n)
        except (OSError, subprocess.SubprocessError):
            pass


def confined_program(name, pkgdir, prog, creds=()):
    """(argv, None) or (None, problem): PROG as a transient systemd unit confined by the declared permissions (scripts/lib/ext_confine.py, the same
    mapping as a confined command). The bridge itself stays outside the sandbox: it alone writes state.db, the snapshots and the cursors, so
    `emit`, `rollup` and `snapshot` need no wider mount. creds = [(credential name, key file)]: systemd LoadCredential= reads the file as root
    before the sandbox and the service finds it in $CREDENTIALS_DIRECTORY (never argv or environment). Not tested on hardware yet."""
    spec = importlib.util.spec_from_file_location("ext_confine", os.path.join(os.path.dirname(os.path.abspath(__file__)), "ext_confine.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    props, _, bad = mod.properties(declared_perms(pkgdir), name)
    if bad:
        return None, bad
    if os.path.abspath(pkgdir).startswith(LIB_DIR + "/"):
        props.append("BindReadOnlyPaths=-" + os.path.abspath(pkgdir))     # its own folder comes back into the empty /var/lib/hs
    try:
        make_private_dir(cred_root())    # a service without credentials needs the folder too: a missing path is skipped by InaccessiblePaths=-
    except OSError as e:
        return None, f"cannot prepare {cred_root()} ({e.strerror}): without it the key copies could not be hidden"
    pi = _load_lib("pkg_integrations")
    seen = set()
    for cname, provider, path in creds:    # every name is checked BEFORE any key is read or any copy written: a refusal leaves nothing behind
        # integration-<name>-<provider>: systemd allows [A-Za-z0-9_.-] up to 255 characters, the names here are [a-z0-9-] (NAME of pkg_integrations.py)
        if (not re.fullmatch(r"[a-z][a-z0-9-]{0,200}", cname) or not re.fullmatch(r"[a-z][a-z0-9-]*", provider or "")
                or not path.startswith("/") or ":" in path):
            return None, f"bad credential {cname!r}"
        if cname in seen:    # integration "a-b" of provider "c" and integration "a" of provider "b-c" would share a name: never hand over the wrong key silently
            return None, f"credential {cname} is named twice (an integration and a provider name run together)"
        seen.add(cname)
    try:
        for cname, provider, path in creds:
            # systemd reads a credential as root. So the bridge reads the key itself ONCE (read_key: only from the folder of the registered providing package,
            # a regular file, checked on the open descriptor) and writes a private 0600 copy; systemd gets that copy, never a path somebody else can change.
            key, why = pi.read_key(path, provider, name, root=LIB_DIR)
            if why:
                drop_creds(name)    # copies of the credentials before this one
                return None, f"credential {cname}: {why}"
            make_private_dir(cred_root())
            d = cred_dir(name)
            make_private_dir(d)
            copy = os.path.join(d, cname)
            try:
                os.unlink(copy)
            except OSError:
                pass
            fd = os.open(copy, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_CLOEXEC", 0), 0o600)
            with os.fdopen(fd, "wb") as fh:
                fh.write(key)
            props.append(f"LoadCredential={cname}:{copy}")
    except OSError as e:
        drop_creds(name)
        return None, f"cannot write the key copies ({e.strerror})"
    # the transient unit has no environment: the PATH of the bridge (no secrets) so `#!/usr/bin/env python3` works; it ends with the bridge unit
    path_env = os.environ.get("PATH") or "/run/current-system/sw/bin:/usr/bin:/bin"
    cmd = [os.environ.get("HS_SYSTEMD_RUN", "systemd-run"), "--pipe", "--wait", "--collect", "--quiet", "--unit=" + unit_of(name),
           f"--description=hs extension service {name}", "--property=KillMode=control-group", "--property=TimeoutStopSec=15", "--property=MountFlags=private",
           f"--property=BindsTo=hs-ext-svc@{name}.service", f"--property=After=hs-ext-svc@{name}.service", "--setenv=PATH=" + path_env]
    return cmd + ["--property=" + x for x in props] + ["--"] + prog, None


def integration_rows(text, perms):
    """The rows for `init.integrations`: `text` is the listing of `hs sys pkg integrations <name>` (package, integration, source, api_url, key_state,
    extra, key_header; `-` = empty, tab separated), `perms` the declared permissions of the package. Only an integration declared as
    integration:<name> is kept, whatever the text holds (the bridge does not trust the caller to have filtered). No key and no key path is in a
    row: keys travel only as systemd credentials."""
    declared = {p[len("integration:"):] for p in (perms or []) if p.startswith("integration:")}
    opt = lambda v: None if v in ("-", "") else v
    out = []
    for line in (text or "").splitlines():
        f = line.split("	")
        if len(f) < 6 or f[1] not in declared:
            continue
        extras = {}
        for kv in (opt(f[5]) or "").split(","):
            k, eq, v = kv.partition("=")
            if eq and k:
                extras[k] = v
        out.append({"package": f[0], "integration": f[1], "source": f[2], "api_url": opt(f[3]), "extras": extras,
                    "key_header": opt(f[6]) if len(f) > 6 else None})
    return out


def svc_run(name, pkgdir, state_dir, creds=(), integrations_text=""):
    table = service_table(pkgdir)
    if not table or not isinstance(table.get("exec"), str):
        print(f"ext_service.py: {name} has no [service] table with exec", file=sys.stderr)
        return 2
    stop = threading.Event()
    for s in (signal.SIGTERM, signal.SIGINT):
        signal.signal(s, lambda *_: stop.set())

    def on_state(s, why):
        d = load_state(state_dir, name)
        d.update({"state": s, "reason": why, "since": now()})
        save_state(state_dir, name, d)
        if s == "running":
            drop_creds(name)    # systemd read the credential when it started the unit; no copy stays on disk

    subscribe = table.get("subscribe", [])
    if subscribe and not os.path.exists(cursor_path(name)):
        write_cursor(cursor_path(name), db_latest())
    sweep_creds(name)
    prog, bad = confined_program(name, pkgdir, program_of(pkgdir, table["exec"]), creds)
    if bad:     # fail closed: a service whose confinement cannot be set up does not run
        print(f"ext_service.py: {name}: {bad}", file=sys.stderr)
        drop_creds(name)    # never a copy left by a refused start
        record_failure(state_dir, name, "confine_failed", bad)
        return 69
    stop_unit(name)     # one that outlived an earlier bridge would collide with the new unit name
    try:
        res = supervise(prog, name, subscribe, db_events() if subscribe else None, cursor_path(name), 30,
                        float(table.get("health_interval", 30)), 3, 10, stop, on_state, make_handler(name, perms=declared_perms(pkgdir), pkgdir=pkgdir),
                        integrations=integration_rows(integrations_text, declared_perms(pkgdir)))
    finally:
        stop_unit(name)
        drop_creds(name)
    if res["state"] == "failed":
        record_failure(state_dir, name, res["code"], res["reason"])
        return 75 if res["code"] == "start_timeout" else 1
    return 0


def status(name, state_dir, active, stopped):
    """(state, reason, since): the state file, corrected by what systemd says. A state file of a process that is gone is `stopped`."""
    d = load_state(state_dir, name)
    st, why, since = d.get("state"), d.get("reason") or "", d.get("since")
    if stopped:
        return "stopped", "stopped by hand", since
    if st in ("starting", "running", "degraded", "stopping") and not active:
        return "stopped", "", since
    if st is None:
        return "stopped", "", None
    return st, why, since


def emit_check(argv):
    """emit-check --name N --kind K --state-dir DIR [-- PERMISSION ...]: the check `hs event emit --pkg N` runs. A lone "-" = the package declares
    no permissions. Exit 0 = write the event; 3 = dropped (one warning on stderr per kind: a marker file in DIR/emit-warned/N/ remembers it)."""
    ap = argparse.ArgumentParser(prog="ext_service.py emit-check")
    ap.add_argument("--name", required=True)
    ap.add_argument("--kind", required=True)
    ap.add_argument("--state-dir", required=True)
    ap.add_argument("perms", nargs=argparse.REMAINDER)
    a = ap.parse_args(argv)
    if not re.match(r"^[a-z][a-z0-9-]{0,40}$", a.name):
        return 2
    perms = a.perms[1:] if a.perms[:1] == ["--"] else a.perms
    why = emit_verdict(a.name, None if perms == ["-"] else perms, a.kind)
    if not why:
        return 0
    mark = os.path.join(a.state_dir, "emit-warned", a.name, re.sub(r"[^A-Za-z0-9._-]", "_", a.kind))
    if not os.path.exists(mark):
        try:
            os.makedirs(os.path.dirname(mark), exist_ok=True)
            open(mark, "w").close()
        except OSError:
            pass
        print(f"{a.name}: emit of {a.kind} dropped ({why})", file=sys.stderr)
    return 3


def main_svc(argv):
    """The subcommands of the unit and of hs ext; None when argv is not one of them."""
    if argv[:1] == ["has-service"] and len(argv) == 2:
        return 0 if service_table(argv[1]) else 1
    if argv[:1] == ["emit-check"]:
        return emit_check(argv[1:])
    if argv[:1] not in (["svc-run"], ["status"], ["reset"]):
        return None
    ap = argparse.ArgumentParser(prog="ext_service.py " + argv[0])
    ap.add_argument("--name", required=True)
    ap.add_argument("--dir")
    ap.add_argument("--state-dir", required=True)
    ap.add_argument("--active", default="no")
    ap.add_argument("--stopped", default="no")
    ap.add_argument("--integrations", default="", help="the listing of hs sys pkg integrations for the declared integrations (no keys): sent in init")
    ap.add_argument("--credential", action="append", default=[], help="NAME=PROVIDER=KEYFILE (the key is copied privately for LoadCredential=)")
    a = ap.parse_args(argv[1:])
    if not re.match(r"^[a-z][a-z0-9-]{0,40}$", a.name):
        return 2
    if argv[0] == "svc-run":
        creds = []
        for c in a.credential:    # NAME=PROVIDER=KEYFILE, the provider is the registered package that offers the integration
            n, _, rest = c.partition("=")
            prov, _, p = rest.partition("=")
            creds.append((n, prov, p))
        return svc_run(a.name, a.dir or ".", a.state_dir, creds, a.integrations)
    if argv[0] == "reset":
        try:
            os.unlink(state_path(a.state_dir, a.name))
        except OSError:
            pass
        return 0
    st, why, since = status(a.name, a.state_dir, a.active == "yes", a.stopped == "yes")
    print("\t".join([st, why or "-", str(since) if since else "-"]))
    return 0


def main(argv):
    rc = main_svc(argv)
    if rc is not None:
        return rc
    return main_run(argv)


def main_run(argv):
    ap = argparse.ArgumentParser(prog="ext_service.py")
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("run")
    r.add_argument("--name", required=True)
    r.add_argument("--subscribe", action="append", default=[])
    r.add_argument("--events")
    r.add_argument("--cursor")
    r.add_argument("--ready-timeout", type=float, default=30)
    r.add_argument("--health-interval", type=float, default=30)
    r.add_argument("--missed", type=int, default=3)
    r.add_argument("--grace", type=float, default=10)
    r.add_argument("--run-for", type=float)
    r.add_argument("prog", nargs=argparse.REMAINDER)
    a = ap.parse_args(argv)
    prog = a.prog[1:] if a.prog[:1] == ["--"] else a.prog
    if not prog or not re.match(r"^[a-z][a-z0-9-]{0,40}$", a.name):
        print("usage: ext_service.py run --name N [options] -- PROGRAM [ARG...]", file=sys.stderr)
        return 2
    stop = threading.Event()
    for s in (signal.SIGTERM, signal.SIGINT):
        signal.signal(s, lambda *_: stop.set())
    if a.run_for:
        tm = threading.Timer(a.run_for, stop.set)
        tm.daemon = True
        tm.start()

    def out(o):
        sys.stdout.write(json.dumps(o, separators=(",", ":")) + "\n")
        sys.stdout.flush()
    res = supervise(prog, a.name, a.subscribe, file_events(a.events) if a.events else None, a.cursor, a.ready_timeout,
                    a.health_interval, a.missed, a.grace, stop,
                    on_state=lambda s, why: out({"v": VERSION, "type": "state", "state": s, "reason": why}),
                    on_message=out)
    out({"v": VERSION, "type": "final", **res})
    return 0 if res["state"] == "stopped" else 75 if res["code"] == "start_timeout" else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
