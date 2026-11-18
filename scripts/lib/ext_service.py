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
     core event ext.service-failed ONCE (systemd then refuses the sixth start). Event delivery, cursors and snapshots are steps 5 and 6 of
     docs/PLAN-extensions-access.md and are not wired here. Exit: 0 stopped on request, 1 failed, 75 never ready.
  ext_service.py has-service DIR      exit 0 when the package has a [service] table
  ext_service.py status --name N --state-dir DIR [--active yes|no] [--stopped yes|no]    prints state, reason, since (TAB, `-` when empty)
  ext_service.py reset --name N --state-dir DIR    forget the state and the failures (hs ext start)
  Test knobs: HS_NOW (the clock), HS_EXT_EMIT (a program called instead of `hs event emit`, same arguments).

Schema of the messages: docs/api/ext-service-v1.schema.json.
"""
import argparse
import fnmatch
import json
import os
import queue
import re
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
MAX_LINE = 1 << 20
MAX_SNAPSHOT = 256 << 10
WINDOW = 100                    # events sent but not yet acknowledged, at most
KIND = re.compile(r"^pkg\.[a-z][a-z0-9-]*\.[a-z][a-z0-9-]*$")
STATES = ("starting", "running", "degraded", "stopping", "stopped", "failed")
FROM_SERVICE = ("ready", "health", "ack", "log", "emit", "snapshot")


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
    if t == "snapshot" and (not isinstance(m.get("topic"), str) or not re.match(r"^[a-z0-9-]{1,60}$", m["topic"]) or "data" not in m):
        return "snapshot needs topic (a-z, 0-9, -) and data"
    if t == "snapshot" and len(json.dumps(m["data"])) > MAX_SNAPSHOT:
        return "snapshot data is larger than 256 KiB"
    return None


def read_cursor(path):
    try:
        return max(0, int(open(path).read().strip() or 0))
    except (OSError, ValueError):
        return 0


def write_cursor(path, n):
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
              grace=10.0, stop=None, on_state=None, on_message=None, lang="en"):
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
    send({"type": "init", "name": name, "lang": lang, "subscribe": list(subscribe), "health_interval": health_interval})

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


def svc_run(name, pkgdir, state_dir):
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

    def on_message(m):    # `log` goes to the journal (stderr); `emit` and `snapshot` are steps 5 and 6
        if m.get("type") == "log":
            print(f"{m['level']}: {m['text']}", file=sys.stderr, flush=True)
    res = supervise(program_of(pkgdir, table["exec"]), name, table.get("subscribe", []), None, None, 30,
                    float(table.get("health_interval", 30)), 3, 10, stop, on_state, on_message)
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


def main_svc(argv):
    """The subcommands of the unit and of hs ext; None when argv is not one of them."""
    if argv[:1] == ["has-service"] and len(argv) == 2:
        return 0 if service_table(argv[1]) else 1
    if argv[:1] not in (["svc-run"], ["status"], ["reset"]):
        return None
    ap = argparse.ArgumentParser(prog="ext_service.py " + argv[0])
    ap.add_argument("--name", required=True)
    ap.add_argument("--dir")
    ap.add_argument("--state-dir", required=True)
    ap.add_argument("--active", default="no")
    ap.add_argument("--stopped", default="no")
    a = ap.parse_args(argv[1:])
    if not re.match(r"^[a-z][a-z0-9-]{0,40}$", a.name):
        return 2
    if argv[0] == "svc-run":
        return svc_run(a.name, a.dir or ".", a.state_dir)
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
