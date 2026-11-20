#!/usr/bin/env python3
"""scripts/live-collect.py in db mode (DbStore) and the live functions of scripts/state-db.py, on a temp state.db (no Redis, no processes)."""
import importlib.util
import json
import os
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time
import unittest

here = os.path.dirname(os.path.abspath(__file__))
scripts = os.path.join(here, "..", "scripts")
TMP = tempfile.mkdtemp(prefix="live-db-")
os.environ["HS_STATE_DB"] = os.path.join(TMP, "state.db")      # before state-db.py is loaded: DB is read at import
os.environ["HS_STATE_DIR"] = TMP
sys.path.insert(0, scripts)
import live_state as ls  # noqa: E402,F401


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, os.path.join(scripts, file))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


lc = load("live_collect", "live-collect.py")
sdb = load("state_db", "state-db.py")
DB = os.environ["HS_STATE_DB"]
INFO = {"status": {"cap": None, "groups": set()}}


def q(sql, *a):
    c = sqlite3.connect(DB)
    try:
        return c.execute(sql, a).fetchall()
    finally:
        c.close()


OPEN = []


def reset():
    while OPEN:
        try:
            OPEN.pop().c.close()
        except Exception:
            pass
    for f in (DB, DB + "-wal", DB + "-shm"):
        try:
            os.remove(f)
        except OSError:
            pass


class Base(unittest.TestCase):
    rows = [("status", ["status"], 15, "run")]

    def setUp(self):
        reset()
        self.now = 1000

    def make(self, results, events=None):
        events = events if events is not None else []

        def run(words):
            return results.pop(0)
        db = lc.DbStore(sdb, clock=lambda: self.now)
        OPEN.append(db)
        c = lc.Collector(None, run=run, topic_rows=list(self.rows), db=db, emit=lambda *a: events.append(a), topic_info=dict(INFO))
        return c, db, events

    def read(self, c, t=None):
        if t is not None:
            self.now = t
        real = time.time
        time.time = lambda: float(self.now)
        try:
            return c.collect("status", ["status"])
        finally:
            time.time = real


class Db(Base):
    def test_first_read_writes_a_document_and_bumps_live_topic(self):
        c, db, _ = self.make([(0, "a\n", "")])
        self.assertTrue(self.read(c))
        self.assertEqual(q("SELECT gen, payload, rc FROM live WHERE topic='status'"), [(1, "a\n", 0)])
        self.assertEqual(q("SELECT gen FROM topics WHERE topic='live:status'"), [(1,)])
        self.assertEqual(q("SELECT COUNT(*) FROM topics WHERE topic='status'"), [(0,)])

    def test_same_output_writes_nothing(self):
        c, db, _ = self.make([(0, "a\n", ""), (0, "a\n", "")])
        self.read(c, 1000)
        docs = db.counts["docs"]
        probe = sqlite3.connect(DB)
        before = probe.total_changes
        self.assertFalse(self.read(c, 1100))
        self.assertEqual(probe.total_changes, before)
        self.assertEqual(q("SELECT gen, updated FROM live WHERE topic='status'"), [(1, 1000)])
        self.assertEqual(q("SELECT gen FROM topics WHERE topic='live:status'"), [(1,)])
        self.assertEqual(db.counts["docs"], docs)
        probe.close()

    def test_other_output_counts_up(self):
        c, db, _ = self.make([(0, "a\n", ""), (0, "b\n", "")])
        self.read(c, 1000)
        self.assertTrue(self.read(c, 1100))
        self.assertEqual(q("SELECT gen, updated, payload FROM live WHERE topic='status'"), [(2, 1100, "b\n")])
        self.assertEqual(q("SELECT gen FROM topics WHERE topic='live:status'"), [(2,)])

    def test_failure_keeps_payload_and_writes_once(self):
        c, db, ev = self.make([(0, "a\n", ""), (1, "", "boom"), (1, "", "boom")])
        self.read(c, 1000)
        self.read(c, 1100)
        self.read(c, 1200)
        self.assertEqual(db.counts["fails"], 1)
        self.assertEqual([e[0] for e in ev], ["live.collector-failed"])
        self.assertEqual(q("SELECT payload, updated, gen, err, ts_err, rc FROM live WHERE topic='status'"), [("a\n", 1000, 1, "boom", 1100, 1)])

    def test_recovery_writes_and_emits_recovered(self):
        c, db, ev = self.make([(1, "", "boom"), (0, "a\n", "")])
        self.read(c, 1000)
        self.assertTrue(self.read(c, 1100))
        self.assertEqual([e[0] for e in ev], ["live.collector-failed", "live.collector-recovered"])
        self.assertEqual(q("SELECT gen, err, ts_err FROM live WHERE topic='status'"), [(1, None, None)])

    def test_heartbeat_row(self):
        c, db, _ = self.make([])
        db.beat(5, None)
        self.now = 1007
        db.beat(5, 1001)
        rows = q("SELECT time, every, started, beats, read FROM heartbeat WHERE name='hs-live'")
        self.assertEqual(rows, [(1007, 5, 1000, 2, 1001)])

    def test_sqlite_error_becomes_oserror(self):
        c, db, _ = self.make([(0, "a\n", "")])
        db.c.close()
        with self.assertRaises(OSError):
            db.put("status", "x", 0, 1, "status", 45, 1000)

    def test_restart_loads_old_documents(self):
        c, db, _ = self.make([(0, "a\n", "")])
        self.read(c, 1000)
        c2, db2, _ = self.make([(0, "a\n", "")])
        self.assertFalse(self.read(c2, 1100))
        self.assertEqual(db2.counts["docs"], 0)
        self.assertEqual(q("SELECT gen, updated FROM live WHERE topic='status'"), [(1, 1000)])

    def test_rescan_gone_topic_deletes_row(self):
        c, db, _ = self.make([])
        db.put("ext-x", "x", 0, 1, "ext x", 45, 1000)
        c.rows.append(("ext-x", ["ext", "x"], 60, "run"))
        c.events["ext-x"], c.stops["ext-x"] = threading.Event(), threading.Event()
        c.info["ext-x"] = {"cap": None, "groups": set()}
        c.ext_rows = lambda log=None: ([], {})
        c.rescan()
        self.assertEqual(q("SELECT COUNT(*) FROM live WHERE topic='ext-x'"), [(0,)])

    def test_backend_names(self):
        c, db, _ = self.make([])
        self.assertEqual(c.backend, "state.db")
        c2 = lc.Collector(object(), topic_rows=list(self.rows), topic_info=dict(INFO))
        self.assertEqual(c2.backend, "redis")


class TakeOver(Base):
    """#561: the 27 slow reads of collected-reads.tsv are topics of the collector (db mode), two writers share the database."""

    def keys(self):
        out = []
        with open(os.path.join(scripts, "lib", "collected-reads.tsv"), encoding="utf-8") as f:
            for line in f:
                c = line.rstrip("\r\n").split("\t")
                if c[0].strip() and not c[0].startswith("#"):
                    out.append((tuple(c[0].split()), int(c[1])))
        return out

    def test_every_collected_read_is_a_topic_and_never_slower(self):
        keys = self.keys()
        self.assertEqual(len(keys), 27)
        topics = {tuple(w): i for _, w, i, _ in ls.topics(os.path.join(scripts, "lib", "live-topics.tsv"))}
        rows = lc.reads_intervals(ls.topics(os.path.join(scripts, "lib", "live-topics.tsv")))
        got = {tuple(w): i for _, w, i, _ in rows}
        for words, every in keys:
            self.assertIn(words, topics, "no topic for: " + " ".join(words))
            self.assertLessEqual(got[words], every)
            self.assertLessEqual(got[words], topics[words])
        self.assertEqual(len(rows), len(topics))

    def test_intervals_take_the_shorter_one(self):
        d = tempfile.mkdtemp(prefix="reads-")
        f = os.path.join(d, "c.tsv")
        with open(f, "w", encoding="utf-8") as fh:
            fh.write("# c\nstatus\t7\ndocker list\t30\nbad\tx\n")
        rows = [("status", ["status"], 15, "run"), ("docker-list", ["docker", "list"], 300, "run"), ("other", ["other"], 20, "run")]
        self.assertEqual([r[2] for r in lc.reads_intervals(rows, f)], [7, 30, 20])
        self.assertEqual(lc.reads_intervals(rows, os.path.join(d, "none.tsv")), rows)

    def test_busy_timeout_is_set(self):
        c = sdb.open_rw()
        try:
            self.assertEqual(c.execute("PRAGMA busy_timeout").fetchone()[0], 30000)
            self.assertEqual(c.execute("PRAGMA journal_mode").fetchone()[0], "wal")
        finally:
            c.close()

    def test_two_writers_lose_nothing(self):
        reset()
        a, b = lc.DbStore(sdb, clock=lambda: 1000), lc.DbStore(sdb, clock=lambda: 1000)
        OPEN.extend([a, b])
        errs = []

        def work(db, name):
            try:
                for i in range(40):
                    db.put("%s-%d" % (name, i % 5), "v%d" % i, 0, 1, name, 45, 1000 + i)
                    db.beat(5, None)
            except Exception as e:      # noqa: BLE001
                errs.append(e)
        ts = [threading.Thread(target=work, args=(db, n)) for db, n in ((a, "a"), (b, "b"))]
        for t in ts:
            t.start()
        for t in ts:
            t.join(60)
        self.assertEqual(errs, [])
        self.assertEqual(q("SELECT COUNT(*) FROM live"), [(10,)])
        self.assertEqual(q("SELECT SUM(gen) FROM live"), [(80,)])
        self.assertEqual(q("SELECT SUM(gen) FROM topics WHERE topic LIKE 'live:%'"), [(80,)])


class FakeResp:
    def __init__(self):
        self.data, self.published = {}, []

    def cmd(self, *a):
        if a[0] == "GET":
            return self.data.get(a[1])
        if a[0] == "SET":
            self.data[a[1]] = a[2]
            return "OK"
        if a[0] == "PUBLISH":
            self.published.append((a[1], a[2]))
            return 1
        raise AssertionError(a)


class Redis(unittest.TestCase):
    def test_redis_path_unchanged(self):
        st = FakeResp()
        c = lc.Collector(st, run=lambda w: (0, "ok\n", ""), topic_rows=[("status", ["status"], 15, "run")], topic_info=dict(INFO))
        self.assertTrue(c.collect("status", ["status"]))
        self.assertEqual(json.loads(st.data["hs:v1:status"])["gen"], 1)
        self.assertEqual(st.published, [("hs:v1:changed", "status 1")])


class Off(unittest.TestCase):
    def test_off_mode_creates_no_live_table(self):
        reset()
        r = subprocess.run([sys.executable, os.path.join(scripts, "state-db.py"), "topic-bump", "x"], capture_output=True, text=True,
                           env=dict(os.environ))
        self.assertEqual(r.returncode, 0)
        names = {t for (t,) in q("SELECT name FROM sqlite_master WHERE type='table'")}
        self.assertIn("topics", names)
        self.assertNotIn("live", names)
        self.assertNotIn("heartbeat", names)


if __name__ == "__main__":
    unittest.main()
