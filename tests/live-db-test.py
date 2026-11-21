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
        c = lc.Collector(db, run=run, topic_rows=list(self.rows), emit=lambda *a: events.append(a), topic_info=dict(INFO))
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


class Listen(Base):
    """the refresh path without Redis: a hook counts a topic up in the table `topics`, the collector reads it again"""

    def test_a_counted_topic_is_asked_for_again_and_our_own_counters_are_not(self):
        c, db, _ = self.make([])
        asked = []
        c.refresh = lambda t, since=None: asked.append(t)

        class Stop:      # four rounds, then the collector stops
            n = 4

            def wait(self, every):
                self.n -= 1
                return self.n < 0
        c.stop = Stop()
        counters = iter([{"status": 1}, {"status": 1}, {"status": 2, "live:status": 5, "reads:x": 1}, {"status": 2, "live:status": 6, "other": 1}])
        db.counters = lambda: next(counters)
        c.listen()
        self.assertEqual(asked, ["status"])      # the first look is the baseline; live:/reads: and an unknown topic ask for nothing

    def test_counters_reads_the_table(self):
        c, db, _ = self.make([(0, "a\n", "")])
        self.read(c)
        self.assertEqual(db.counters().get("live:status"), 1)


class Delay(Base):
    """#486: the delay from the trigger to the new generation, the health note, the status columns, the additive table."""

    def trigger_read(self, c, at, read_at):
        real = time.time
        time.time = lambda: float(at)
        try:
            c.refresh("status")
        finally:
            time.time = real
        return self.read(c, read_at)

    def test_a_triggered_read_with_a_new_gen_records_last_and_worst(self):
        c, db, _ = self.make([(0, "a\n", ""), (0, "b\n", ""), (0, "c\n", "")])
        self.read(c, 1000)      # no trigger: no sample
        self.assertEqual(q("SELECT COUNT(*) FROM live_delay"), [(0,)])
        self.assertTrue(self.trigger_read(c, 1010, 1012))
        self.assertTrue(self.trigger_read(c, 1020, 1021))
        self.assertEqual(q("SELECT ms_last, ms_worst, ms_n, ms_recent FROM live_delay WHERE topic='status'"), [(1000, 2000, 2, "2000,1000")])

    def test_an_unchanged_read_leaves_no_sample_and_clears_the_trigger(self):
        c, db, _ = self.make([(0, "a\n", ""), (0, "a\n", ""), (0, "b\n", "")])
        self.read(c, 1000)
        self.assertFalse(self.trigger_read(c, 1010, 1011))
        self.assertEqual(q("SELECT COUNT(*) FROM live_delay"), [(0,)])
        self.assertEqual(c.trig, {})
        self.read(c, 5000)      # a later change without a trigger does not inherit the old one
        self.assertEqual(q("SELECT COUNT(*) FROM live_delay"), [(0,)])

    def test_a_hook_counts_from_the_time_the_counter_moved(self):
        c, db, _ = self.make([(0, "a\n", "")])
        c.refresh("status", 990)
        self.assertEqual(c.trig["status"], 990)
        c.refresh("status", 995)      # the first trigger of a read that has not run yet keeps its time
        self.assertEqual(c.trig["status"], 990)

    def test_only_the_last_20_samples_are_kept(self):
        c, db, _ = self.make([])
        for i in range(25):
            db.delay("status", i, 1000 + i)
        rec = q("SELECT ms_recent, ms_worst, ms_n FROM live_delay")[0]
        self.assertEqual((rec[0].split(",")[0], len(rec[0].split(",")), rec[1], rec[2]), ("5", 20, 24, 25))

    def test_a_slow_topic_raises_the_health_note_and_a_fast_one_does_not(self):
        c, db, _ = self.make([(0, "a\n", "")])
        db.delay("status", 11000, 1000)
        notes = ls.slow_notes(ls.delays_read(), {"status"}, 10.0)
        self.assertEqual([k for k, _ in notes], ["live:slow:status"])
        self.assertIn("11.0 s", notes[0][1])
        self.assertEqual(ls.slow_notes(ls.delays_read(), {"status"}, 12.0), [])
        self.assertEqual(ls.slow_notes(ls.delays_read(), {"other"}, 10.0), [])      # a topic that is gone says nothing
        sdb_c = sdb.open_rw()
        sdb.live_delay_put(sdb_c, "status", 30000, 1001, web=True)
        sdb_c.close()
        self.assertEqual([k for k, _ in ls.slow_notes(ls.delays_read(), {"status"}, 12.0)], ["live:slowweb:status"])

    def test_check_prints_the_slow_note_with_a_running_collector(self):
        import io
        now = time.time()
        doc = {"status": {"out": "x", "rc": 0, "gen": 1, "ts": now, "err": None, "ts_err": None, "ttl": 100, "src": "t"}}
        real = ls.topics
        ls.topics = lambda *a: [("status", ["status"], 15, "run")]
        try:
            buf = io.StringIO()
            rc = ls.cli_check(buf, (doc, (int(now), 5)), {"status": {"ms_recent": [200, 15000], "web_recent": []}})
            quiet = io.StringIO()
            rc2 = ls.cli_check(quiet, (doc, (int(now), 5)), {"status": {"ms_recent": [200, 900], "web_recent": []}})
        finally:
            ls.topics = real
        self.assertEqual(rc, 1)
        self.assertTrue(buf.getvalue().startswith("live:slow:status	live state 'status' is slow"), buf.getvalue())
        self.assertEqual((rc2, quiet.getvalue()), (0, ""))

    def test_the_limit_is_read_from_the_limits_file(self):
        path = os.path.join(TMP, "limits.tsv")
        with open(path, "w") as f:
            f.write("# c\nnote\t3\tx\nhook\t1\tx\n")
        self.assertEqual((ls.limits(path)["note"], ls.limits(path)["timed"]), (3.0, 20.0))
        self.assertEqual(ls.limits(os.path.join(TMP, "none.tsv"))["note"], 10.0)
        self.assertEqual(ls.limits()["note"], 10.0)      # the shipped file

    def test_status_has_the_delay_columns_at_the_end_with_a_dash_for_none(self):
        import io
        doc = {"status": {"out": "x", "rc": 0, "gen": 1, "ts": 1000, "err": None, "ts_err": None, "ttl": 100, "src": "t"}}
        real = ls.topics
        ls.topics = lambda *a: [("status", ["status"], 15, "run"), ("other", ["o"], 15, "run")]
        try:
            buf = io.StringIO()
            ls.cli_status(buf, (doc, (1000, 5)), {"status": {"ms_last": 40, "ms_worst": 900, "web_last": None, "web_worst": None}})
        finally:
            ls.topics = real
        rows = [l.split("\t") for l in buf.getvalue().splitlines()]
        self.assertEqual([len(r) for r in rows], [14, 14])
        self.assertEqual(rows[0][10:], ["40", "900", "-", "-"])
        self.assertEqual(rows[1][10:], ["-", "-", "-", "-"])
        self.assertEqual(len(rows[0][:10]), 10)      # the first ten keep their place

    def test_an_old_database_without_the_table_gets_it_and_reads_empty(self):
        reset()
        c = sqlite3.connect(DB)
        c.executescript(sdb.SCHEMA + sdb.LIVE_SCHEMA.split("-- #486")[0])      # a state.db of the release before: live and heartbeat, no live_delay
        c.execute("INSERT INTO live (topic, payload, updated, gen) VALUES ('status', 'old', 5, 3)")
        c.commit()
        c.close()
        self.assertEqual(ls.delays_read(), {})      # a reader does not fail on the missing table
        r = subprocess.run([sys.executable, os.path.join(scripts, "live_state.py"), "status"], capture_output=True, text=True, env=dict(os.environ))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue(all(len(l.split("\t")) == 14 and l.split("\t")[10:] == ["-"] * 4 for l in r.stdout.splitlines() if l))
        db = lc.DbStore(sdb)      # the collector opens it: the table is added, the old document stays
        OPEN.append(db)
        self.assertEqual(q("SELECT payload, gen FROM live WHERE topic='status'"), [("old", 3)])
        db.delay("status", 7, 100)
        self.assertEqual(q("SELECT ms_last, ms_n FROM live_delay"), [(7, 1)])
        db2 = lc.DbStore(sdb)      # and a second open does not fail or clear it
        OPEN.append(db2)
        self.assertEqual(q("SELECT ms_n FROM live_delay"), [(1,)])

    def test_the_sample_command_stores_a_browser_number(self):
        reset()
        env = dict(os.environ)
        run = lambda *a: subprocess.run([sys.executable, os.path.join(scripts, "state-db.py"), "live-sample"] + list(a), capture_output=True, text=True, env=env).returncode
        self.assertEqual(run("status", "250"), 0)
        self.assertEqual(run("status", "1500"), 0)
        self.assertEqual(run("status", "x"), 1)
        self.assertEqual(run("bad topic!", "5"), 1)
        self.assertEqual(q("SELECT web_last, web_worst, web_n, ms_n FROM live_delay"), [(1500, 1500, 2, 0)])


class Bump(unittest.TestCase):
    def test_a_hook_bump_creates_no_live_table(self):
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
