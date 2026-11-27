#!/usr/bin/env python3
"""Live state (ADR 0026): the topic list, the read side of the live tables in the state database and the CLI behind `hs sys live`.
Shared by scripts/live-collect.py (the one writer, through state-db.py) and scripts/web-serve.py (the reader). The documents are the raw text of one
`hs sys` read: table `live` of state.db (topic, payload, updated, ms, rc, gen, err, ts_err, ttl, src), one heartbeat row `hs-live` in table `heartbeat`
says the collector runs. Here a document is a dict {out, rc, gen, ts (= updated), err, ts_err, ttl, src}.
  python3 live_state.py refresh <topic>|@<group>...|--all   ask the collector to read again (exit 0 always): counts the topics up in the table
                                                     `topics` (state-db.py topic-bump); @<group> = every topic of that change area (and of `any`),
                                                     see live-topics.tsv columns 5 and 6
  python3 live_state.py status                       topic, interval, age (-1 none), gen, rc, err or -, ts_err or -, needs (comma list or -;
                                                     the 8th field, since #153, see live-topics.tsv column 7), status (fresh|stale|error|expired
                                                     or -; the 9th field, since #322, status_of)
  python3 live_state.py inspect   JSON: every topic with words, interval, lock, cap, groups and its stored state (the inspector page)
  python3 live_state.py raw <topic>   JSON: the stored document of one topic, out capped at RAW_MAX bytes (exit 2: unknown topic)
  python3 live_state.py check                        problems: live:down / live:never:<topic> / live:stale:<topic> TAB text (exit 1 when there are some)
"""
import heapq
import json
import os
import sqlite3
import subprocess
import sys
import threading
import time

RAW_MAX = 65536
HERE = os.path.dirname(os.path.abspath(__file__))
BEAT_NAME = "hs-live"


def state_db_path():
    return os.environ.get("HS_STATE_DB") or os.path.join(os.environ.get("HS_STATE_DIR") or "/var/lib/hs", "state.db")


def collector_alive(hb, now=None):
    """The heartbeat row (time, every) of the collector is fresh: not older than max(15, 3 x every) seconds (one rule for `down`, for the status of a
    document and for `hs sys live check`)."""
    t = time.time() if now is None else now
    return bool(hb) and t - hb[0] <= max(15, 3 * hb[1])


def _db_open():
    db = state_db_path()
    if not os.path.exists(db):
        return None
    c = sqlite3.connect("file:%s?mode=ro" % db.replace("\\", "/"), uri=True, timeout=2)
    c.execute("PRAGMA query_only=1")
    return c


def db_read(topic=None):
    """-> (documents, heartbeat) from the state database, read-only, no subprocess. documents: {topic: doc} (just the one topic when given; {} when it
    has no row, there is no database yet or no table); doc = {out, rc, gen, ts, err, ts_err, ttl, src}; heartbeat = (time, every) or None.
    OSError when the database cannot be read now."""
    try:
        c = _db_open()
        if c is None:
            return {}, None
        try:
            try:
                sql = "SELECT topic, payload, rc, gen, updated, err, ts_err, ttl, src FROM live" + (" WHERE topic = ?" if topic else "")
                rows = c.execute(sql, (topic,) if topic else ()).fetchall()
                hb = c.execute("SELECT time, every FROM heartbeat WHERE name = ?", (BEAT_NAME,)).fetchone()
            except sqlite3.OperationalError as e:
                if "no such table" in str(e):
                    return {}, None
                raise
        finally:
            c.close()
    except sqlite3.Error as e:
        raise OSError("state.db: %s" % e)
    docs = {r[0]: {"out": r[1], "rc": r[2], "gen": r[3], "ts": r[4], "err": r[5], "ts_err": r[6], "ttl": r[7], "src": r[8]} for r in rows}
    return docs, ((int(hb[0]), int(hb[1])) if hb else None)


DELAY_COLS = ("ms_last", "ms_worst", "ms_n", "ms_recent", "web_last", "web_worst", "web_n", "web_recent")


def delays_read():
    """-> {topic: {ms_last, ms_worst, ms_n, ms_recent (list of ints), web_last, web_worst, web_n, web_recent}} of the table live_delay (#486), read-only.
    {} when there is no database or no such table (a state.db from before this release): the measure is additive, nothing else depends on it."""
    try:
        c = _db_open()
        if c is None:
            return {}
        try:
            rows = c.execute("SELECT topic, %s FROM live_delay" % ", ".join(DELAY_COLS)).fetchall()
        finally:
            c.close()
    except sqlite3.Error:
        return {}
    out = {}
    for r in rows:
        d = dict(zip(DELAY_COLS, r[1:]))
        for k in ("ms_recent", "web_recent"):
            d[k] = [int(x) for x in (d[k] or "").split(",") if x.isdigit()]
        out[r[0]] = d
    return out


def limits(path=None):
    """{class: seconds} of scripts/lib/live-limits.tsv (the one file with the numbers of D9: hook, timed, note)"""
    out = {"hook": 5.0, "timed": 20.0, "note": 10.0}
    try:
        with open(path or os.environ.get("HS_LIVE_LIMITS", os.path.join(HERE, "lib", "live-limits.tsv")), encoding="utf-8") as f:
            for line in f:
                p = line.rstrip("\r\n").split("\t")
                if len(p) >= 2 and p[0] and not p[0].startswith("#"):
                    try:
                        out[p[0]] = float(p[1])
                    except ValueError:
                        pass
    except OSError:
        pass
    return out


def ext_live(log=None):
    """(rows, info) of the live reads that extension packages declare (scripts/hs_ext.py); nothing when that cannot be read"""
    try:
        import hs_ext
        return hs_ext.ext_live_rows(log)
    except Exception:       # a broken package must never take the core topics down
        return [], {}


def topics(path=None):
    """[(topic, words list, interval seconds, lock mode run|skip)] from live-topics.tsv, plus the live reads of the extension packages that are on
    (only for the real file: a test that passes its own path gets just that file)."""
    own = path is not None
    path = path or os.path.join(HERE, "lib", "live-topics.tsv")
    rows = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            c = line.split("\t")
            if len(c) < 3:
                continue
            rows.append((c[0], c[1].split(), int(c[2]), c[3] if len(c) > 3 and c[3] else "run"))
    if not own:
        known = {r[0] for r in rows}
        rows += [r for r in ext_live()[0] if r[0] not in known]
    return rows


def parse_demand(v):
    """column 9 of live-topics.tsv: `always` (or empty, `-`) -> None, `idle:<seconds>` -> the seconds (D14); anything else counts as always"""
    v = (v or "").strip()
    if v.startswith("idle:") and v[5:].isdigit() and int(v[5:]) > 0:
        return int(v[5:])
    return None


def demand_read(now=None):
    """-> {topic: until} of the leases that have not run out (table demand, read-only); {} when there is no database or table"""
    now = int(now if now is not None else time.time())
    try:
        c = _db_open()
        if c is None:
            return {}
        try:
            return {t: int(u) for t, u in c.execute("SELECT topic, until FROM demand WHERE until > ?", (now,))}
        finally:
            c.close()
    except sqlite3.Error:
        return {}


def topic_info(path=None):
    """{topic: {"cap": capability name or None, "groups": set of change areas}} from columns 5 and 6 of live-topics.tsv."""
    own = path is not None
    path = path or os.path.join(HERE, "lib", "live-topics.tsv")
    info = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            c = line.split("\t")
            if len(c) < 3:
                continue
            cap = c[4] if len(c) > 4 and c[4] not in ("", "-") else None
            groups = {g for g in (c[5].split(",") if len(c) > 5 else []) if g and g != "-"}
            ttl = None
            if len(c) > 7 and c[7] not in ("", "-"):
                try:
                    ttl = int(c[7]) if int(c[7]) > 0 else None
                except ValueError:
                    ttl = None
            info[c[0]] = {"cap": cap, "groups": groups}
            if ttl:
                info[c[0]]["ttl"] = ttl
            idle = parse_demand(c[8]) if len(c) > 8 else None
            if idle:
                info[c[0]]["idle"] = idle
    if not own:
        for t, i in ext_live()[1].items():
            info.setdefault(t, i)
    return info


def event_topics(path=None):
    """{kind: [topic]} from scripts/lib/event-topics.tsv (named events, D12; test knob HS_EVENT_TOPICS)."""
    path = path or os.environ.get("HS_EVENT_TOPICS") or os.path.join(HERE, "lib", "event-topics.tsv")
    out = {}
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                c = line.rstrip("\r\n").split("\t")
                if c[0] and not c[0].startswith("#") and len(c) > 1:
                    out[c[0]] = [t for t in c[1].split(",") if t and t != "-"]
    except OSError:
        pass
    return out


def topic_needs(path=None):
    """{topic: tuple of topics} from column 7 of live-topics.tsv (whose new gen re-reads the topic in a wave); extensions add theirs for the real file."""
    own = path is not None
    path = path or os.path.join(HERE, "lib", "live-topics.tsv")
    out = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            c = line.split("\t")
            if len(c) < 3:
                continue
            out[c[0]] = tuple(n for n in (x.strip() for x in (c[6].split(",") if len(c) > 6 else [])) if n and n != "-")
    if not own:
        for t, i in ext_live()[1].items():
            out.setdefault(t, tuple(i.get("needs", ())))
    return out


def graph(needs, known):
    """-> (order, clean, problems): every known topic in dependency order (a topic after those it needs, ties by name), the needs without unknown
    targets, self references and cycles, and the text of each problem. Pure."""
    problems, clean = [], {}
    for t in sorted(known):
        keep = set()
        for n in needs.get(t, ()):
            if n == t:
                problems.append("topic %s needs itself" % t)
            elif n not in known:
                problems.append("topic %s needs unknown topic %s" % (t, n))
            else:
                keep.add(n)
        clean[t] = tuple(sorted(keep))
    users = {t: [] for t in clean}
    left = {t: len(ns) for t, ns in clean.items()}
    for t, ns in clean.items():
        for n in ns:
            users[n].append(t)
    heap = [t for t, k in left.items() if k == 0]
    heapq.heapify(heap)
    order = []
    while heap:
        t = heapq.heappop(heap)
        order.append(t)
        for u in users[t]:
            left[u] -= 1
            if left[u] == 0:
                heapq.heappush(heap, u)
    stuck = sorted(t for t in clean if t not in set(order))
    if stuck:
        problems.append("dependency cycle among: %s" % ", ".join(stuck))
        for t in stuck:
            clean[t] = ()
        order += stuck
    return order, clean, problems


_CAP_CACHE = {}
_CAP_LOCK = threading.Lock()
CAP_TTL = 60.0


def cap_on(name):
    """True when the capability is on (lib/capability.sh capability_on); cached for 60 s per name. None/'-' is always on."""
    if not name or name == "-":
        return True
    now = time.time()
    with _CAP_LOCK:
        hit = _CAP_CACHE.get(name)
        if hit and now - hit[0] < CAP_TTL:
            return hit[1]
    try:
        p = subprocess.run(["bash", "-c", '. "$1"; capability_on "$2"', "_", os.path.join(HERE, "lib", "capability.sh"), name],
                           capture_output=True, timeout=10)
        on = p.returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        on = False
    with _CAP_LOCK:
        _CAP_CACHE[name] = (now, on)
    return on


def clean(text, limit=200):
    """one line of printable text: control characters (newline, tab, escape ...) become a space; what a package printed must never shape a check line"""
    return "".join(c if c.isprintable() else " " for c in str(text))[:limit]


def status_of(doc, interval, now=None):
    """The one status of a live entry: fresh, stale, error or expired. ttl = doc["ttl"], else 3 x interval.
    error = the last try failed and there is no good data inside the ttl (never read, or older than the ttl); stale = the last try failed but the
    last good data is still inside the ttl; expired = no failed try but the data is older than the ttl (the collector is not running);
    fresh = good data inside the ttl. An expired entry is still served (last good data), only marked. Old documents without ttl still work."""
    now = time.time() if now is None else now
    doc = doc or {}
    try:
        ttl = float(doc.get("ttl") or 0) or 3 * interval
    except (TypeError, ValueError):
        ttl = 3 * interval
    try:
        ts = float(doc.get("ts") or 0)
        ts_err = float(doc.get("ts_err") or 0)
    except (TypeError, ValueError):
        return "error"
    failed = bool(doc.get("err")) and ts_err > ts
    if not ts:
        return "error"
    inside = now - ts <= ttl
    if failed:
        return "stale" if inside else "error"
    return "fresh" if inside else "expired"


def checked_doc(doc, hb, now=None):
    """The document as the status rules see it: the collector looks at every topic at its interval, so while it runs an unchanged answer was
    confirmed at its last beat (ts = the later of the change time and the beat). Without a fresh heartbeat nothing was confirmed: ts stays, and
    the status turns `expired` (data older than its ttl). A failed document keeps its own times."""
    if not doc or not doc.get("ts") or not collector_alive(hb, now) or (doc.get("err") and (doc.get("ts_err") or 0) > doc["ts"]):
        return doc
    return dict(doc, ts=max(doc["ts"], hb[0]))


def _ttl(doc, interval, info=None):
    """seconds an entry counts as fresh: the document's own ttl, else the topic's override (live-topics.tsv column 8), else 3 x interval"""
    try:
        t = float((doc or {}).get("ttl") or 0)
    except (TypeError, ValueError):
        t = 0
    return t or float((info or {}).get("ttl") or 0) or 3 * interval


def cli_refresh(args):
    """count the topics up in the table `topics` (the collector wakes on it); best effort, always 0"""
    try:
        subprocess.run([sys.executable, os.path.join(HERE, "state-db.py"), "topic-bump"] + [a for a in args], capture_output=True, timeout=10)
    except (OSError, subprocess.TimeoutExpired):
        pass
    return 0


def _ms(v):
    return "-" if v is None else str(int(v))


def cli_status(out=None, docs=None, delays=None):
    out = out or sys.stdout
    try:
        docs, hb = docs if docs is not None else db_read()
    except OSError as e:
        sys.stderr.write("live state failed: %s\n" % e)
        return 1
    delays = delays if delays is not None else delays_read()
    now = time.time()
    needs = topic_needs()
    info = topic_info()
    beat = str(max(0, int(now - hb[0]))) if hb else "-"  # age of the collector's last round, the same on every line (column 10)
    for topic, _, interval, _ in topics():
        d = checked_doc(docs.get(topic), hb, now) or {}
        age = int(now - d["ts"]) if d.get("ts") else -1
        err = clean(d.get("err") or "-")
        ts_err = str(int(d["ts_err"])) if d.get("ts_err") else "-"
        dl = delays.get(topic) or {}
        # columns 11 to 14 (#486): delay from trigger to new gen, last and worst, then the browser sample, last and worst (milliseconds, - = none yet)
        out.write("%s\t%d\t%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" % (
            topic, interval, age, d.get("gen", 0), d.get("rc", "-") if d.get("rc") is not None else "-", err, ts_err, ",".join(needs.get(topic, ())) or "-",
            status_of(dict(d, ttl=_ttl(d, interval, info.get(topic))), interval, now) if d else "-", beat,
            _ms(dl.get("ms_last")), _ms(dl.get("ms_worst")), _ms(dl.get("web_last")), _ms(dl.get("web_worst"))))
    return 0


def cli_inspect(out=None, docs=None, delays=None):
    out = out or sys.stdout
    try:
        docs, hb = docs if docs is not None else db_read()
    except OSError as e:
        sys.stderr.write("live state failed: %s\n" % e)
        return 1
    delays = delays if delays is not None else delays_read()
    core = {t[0] for t in topics(os.path.join(HERE, "lib", "live-topics.tsv"))}
    info = topic_info()
    rows = topics()
    caps = {}
    for t in rows:
        c = info.get(t[0], {}).get("cap")
        if c is not None and c not in caps:
            caps[c] = cap_on(c)
    now = time.time()
    leases = demand_read(now)
    entries = []
    for topic, words, interval, lock in rows:
        raw = docs.get(topic)
        d = checked_doc(raw, hb, now) or {}
        i = info.get(topic, {})
        e = {"topic": topic, "words": words, "interval": interval, "lock": lock,
             "origin": "core" if topic in core else "extension",
             "cap": i.get("cap"), "cap_on": caps.get(i.get("cap"), True), "groups": sorted(i.get("groups") or ()),
             "age": int(now - d["ts"]) if d.get("ts") else None, "gen": int(d.get("gen") or 0),
             "rc": d.get("rc") if isinstance(d.get("rc"), int) else None,
             "err": clean(d["err"]) if d.get("err") else None,
             "ts_err": int(d["ts_err"]) if d.get("ts_err") else None,
             "bytes": len(str(d.get("out") or "").encode()) if d else None}
        # D14: demand = always | idle:<seconds>; lease = the time (seconds) the lease runs out, only while a stream wants the topic
        idle = i.get("idle")
        e["demand"] = "idle:%d" % idle if idle else "always"
        if idle:
            e["idle"] = idle
            u = leases.get(topic) or leases.get("*")
            if u:
                e["lease"] = u
        # #339 needs, #322 status/ttl/source: present only when those are in
        if i.get("needs") is not None:
            e["needs"] = sorted(i["needs"])
        if d:
            e["status"] = status_of(dict(d, ttl=_ttl(d, interval, i)), interval, now)
            e["ttl"] = int(_ttl(d, interval, i))
            if isinstance(d.get("src"), str):
                e["source"] = d["src"]
        dl = delays.get(topic)
        if dl:      # #486: milliseconds; the key is only there once a sample exists
            for k in ("ms_last", "ms_worst", "ms_n", "web_last", "web_worst", "web_n"):
                if dl.get(k) is not None:
                    e["delay_" + k] = int(dl[k])
        entries.append(e)
    out.write(json.dumps({"now": int(now), "topics": entries}, sort_keys=True) + "\n")
    return 0


def cli_raw(args, out=None, docs=None):
    out = out or sys.stdout
    if len(args) != 1 or args[0] not in {t[0] for t in topics()}:
        sys.stderr.write("unknown live topic\n")
        return 2
    topic = args[0]
    try:
        docs, _ = docs if docs is not None else db_read(topic)
    except OSError as e:
        sys.stderr.write("live state failed: %s\n" % e)
        return 1
    d = docs.get(topic)
    if d is None:
        res = {"topic": topic, "stored": False}
    else:
        b = str(d.get("out") or "").encode()
        res = {"topic": topic, "stored": True, "ts": d.get("ts"), "gen": d.get("gen"), "rc": d.get("rc"),
               "err": clean(d["err"], 2000) if d.get("err") else None, "ts_err": d.get("ts_err"),
               "bytes": len(b), "truncated": len(b) > RAW_MAX,
               "out": b[:RAW_MAX].decode("utf-8", "ignore")}
    out.write(json.dumps(res, sort_keys=True) + "\n")
    return 0


def slow_notes(delays, topics_known, limit_s):
    """[(key, text)]: a topic whose worst of its last samples is over the limit (D9: the last 20 samples, 10 s). Server samples and browser
    samples are judged apart; a topic that is not in the list any more (a package switched off) says nothing."""
    notes = []
    for topic in sorted(delays):
        if topic not in topics_known:
            continue
        for kind, key, what in (("ms_recent", "live:slow:", "to a new generation"), ("web_recent", "live:slowweb:", "until a page showed it")):
            rec = delays[topic].get(kind) or []
            if rec and max(rec) > limit_s * 1000:
                notes.append((key + topic, "live state '%s' is slow: the worst of its last %d changes took %.1f s %s (limit %g s). Details: hs sys live status" % (
                    topic, len(rec), max(rec) / 1000.0, what, limit_s)))
    return notes


def cli_check(out=None, docs=None, delays=None):
    out = out or sys.stdout
    problems = []
    try:
        docs, hb = docs if docs is not None else db_read()
    except OSError as e:
        docs, hb = None, None
        problems = [("live:down", "the live state database cannot be read (%s). Details: systemctl status hs-live" % e)]
    now = time.time()
    if docs is not None and not collector_alive(hb, now):
        if hb:
            problems = [("live:down", "the live state collector is not running (its last beat was %d s ago). Details: systemctl status hs-live" % (now - hb[0]))]
        elif docs:
            problems = [("live:down", "the live state collector is not running (it has no beat). Details: systemctl status hs-live")]
        # no beat and no document at all: the collector has not started yet (a fresh install), nothing to say
    elif docs is not None:
        info = topic_info()
        for topic, _, interval, _ in topics():
            if not cap_on((info.get(topic) or {}).get("cap")):
                continue   # the capability is off: the topic is not read
            d = docs.get(topic)
            if d is None:
                continue   # nothing read yet: the collector is still starting
            if not d.get("ts"):
                if d.get("err"):   # tried and never succeeded
                    problems.append(("live:never:" + topic, "live state '%s' has never been read: %s. Details: systemctl status hs-live" % (
                        topic, clean(d["err"]))))
                continue
            idle = (info.get(topic) or {}).get("idle")
            ttl = _ttl(d, interval, info.get(topic))
            failed = bool(d.get("err")) and (d.get("ts_err") or 0) > d["ts"]
            if idle and not failed:      # a failing topic keeps its own ttl: the health note must not come later (#1320)
                ttl = max(ttl, 3 * idle)      # D14: a topic nobody watches runs at its idle interval, that is not a stale topic
            st = status_of(dict(checked_doc(d, hb, now), ttl=ttl), interval, now)
            if st in ("expired", "error"):
                problems.append(("live:stale:" + topic, "live state '%s' is %s (%d s old, read every %d s). Details: systemctl status hs-live" % (
                    topic, st, now - d["ts"], interval)))
    if docs is not None and collector_alive(hb, now):
        problems += slow_notes(delays if delays is not None else delays_read(), {t[0] for t in topics()}, limits()["note"])
    for k, t in problems:
        out.write("%s\t%s\n" % (k, t))
    return 1 if problems else 0


def main(argv):
    if not argv:
        sys.stderr.write("usage: live_state.py refresh <topic>...|--all | status | check | inspect | raw <topic>\n")
        return 2
    if argv[0] == "refresh":
        return cli_refresh(argv[1:])
    if argv[0] == "status":
        return cli_status()
    if argv[0] == "check":
        return cli_check()
    if argv[0] == "inspect":
        return cli_inspect()
    if argv[0] == "raw":
        return cli_raw(argv[1:])
    sys.stderr.write("unknown command %s\n" % argv[0])
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
