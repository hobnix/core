#!/usr/bin/env python3
"""Demand-driven sampling (docs/PLAN-live-interface.md step 15, D14): column 9 of live-topics.tsv, the table `demand`, the collector's pace and wake, the lease
writer of the web server, the inspector fields. No processes, no real server: a temporary state database and a stand-in store."""
import importlib.util
import io
import json
import os
import re
import sqlite3
import sys
import tempfile
import time
import unittest
from unittest import mock

here = os.path.dirname(os.path.abspath(__file__))
scripts = os.path.join(here, "..", "scripts")
sys.path.insert(0, scripts)
TMP = tempfile.mkdtemp()
os.environ["HS_STATE_DB"] = os.path.join(TMP, "state.db")
os.environ["HS_STATE_DIR"] = TMP
os.environ["HS_WEB_QUIET"] = "1"
import live_state as ls  # noqa: E402


def load(name, f):
    spec = importlib.util.spec_from_file_location(name, os.path.join(scripts, f))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


sdb = load("state_db_demand", "state-db.py")
lc = load("live_collect_demand", "live-collect.py")
ws = load("web_serve_demand", "web-serve.py")
TOPICS_TSV = os.path.join(scripts, "lib", "live-topics.tsv")

# Reads that keep their interval. health-next and health-list run health-check.sh dry, which writes health-since and emits health.new and
# health.resolved; health-info is named in health-check.sh (#1320). For the others: their scripts contain emit/notify calls; read mode not verified (#1320). The second test finds more in the files.
ALWAYS_TOPICS = ["health-next", "health-list", "health-info", "encryption", "vault-list", "vault-uses", "ups", "notify-channels", "notify-providers",
                 "pkg-index", "backup-state"]
CANDIDATES = ["disk-health", "monitor-disks", "shares-overview", "shares-deleted", "vault-usage", "fm-locations", "backup-overview", "backup-shares"]


class Table(unittest.TestCase):
    def setUp(self):
        self.info = ls.topic_info(TOPICS_TSV)

    def test_the_candidates_of_d14_are_idle_topics(self):
        for t in CANDIDATES:
            self.assertTrue(self.info[t].get("idle"), t)

    def test_every_always_topic_is_always(self):
        for t in ALWAYS_TOPICS:
            self.assertIn(t, self.info)
            self.assertIsNone(self.info[t].get("idle"), "%s can write events or notifications: it keeps its interval" % t)

    def test_every_topic_decides(self):
        for topic, _, interval, _ in ls.topics(TOPICS_TSV):
            self.assertTrue(topic in ALWAYS_TOPICS or self.info[topic].get("idle") or interval >= 3600, topic)

    def test_health_topics_follow_the_timer(self):
        for t in ("health-next", "health-list", "health-info"):
            self.assertIn(t, ls.event_topics()["health.checked"])

    def test_topics_named_by_the_health_check_and_the_rules_are_always(self):
        text = ""
        for f in ("health-check.sh", os.path.join("lib", "notify-rules.tsv")):
            with open(os.path.join(scripts, f), encoding="utf-8") as fh:
                text += fh.read()
        named = set(re.findall(r"hs sys ([a-z][a-z -]*[a-z])", text))
        for topic, words, _, _ in ls.topics(TOPICS_TSV):
            if " ".join(words) in named:
                self.assertIsNone(self.info[topic].get("idle"), topic)

    def test_idle_is_never_shorter_than_the_interval(self):
        for topic, _, interval, _ in ls.topics(TOPICS_TSV):
            idle = self.info[topic].get("idle")
            if idle:
                self.assertGreaterEqual(idle, interval, topic)

    def test_parse_demand(self):
        self.assertIsNone(ls.parse_demand("always"))
        self.assertIsNone(ls.parse_demand("-"))
        self.assertIsNone(ls.parse_demand("idle:0"))
        self.assertIsNone(ls.parse_demand("idle:x"))
        self.assertEqual(ls.parse_demand("idle:300"), 300)


class Leases(unittest.TestCase):
    def test_a_lease_runs_out(self):
        c = sdb.demand_open()
        c.execute("DELETE FROM demand")
        c.commit()
        sdb.demand_put(c, ["a", "b"], 1000)
        self.assertEqual(sdb.demand_active(c, 1010), {"a": 1030, "b": 1030})
        self.assertEqual(sdb.demand_active(c, 1030), {})          # a killed web server: nobody renews, the lease is over after 30 s
        sdb.demand_put(c, ["a"], 1020)
        self.assertEqual(sdb.demand_active(c, 1040), {"a": 1050})
        c.close()

    def test_the_live_database_has_the_table(self):
        c = sdb.live_open()
        self.assertGreaterEqual(c.execute("SELECT count(*) FROM demand").fetchone()[0], 0)
        c.close()


class Store:
    """the DbStore as far as the collector looks at demand"""
    def __init__(self):
        self.leases, self.seen, self.times = {}, None, {}

    def demand(self, now):
        return {t: u for t, u in self.leases.items() if u > now}


class Pace(unittest.TestCase):
    def make(self):
        rows = [("disk-health", ["disk-health", "list"], 30, "run"), ("status", ["status"], 15, "run")]
        info = {"disk-health": {"cap": None, "groups": {"disks"}, "idle": 300}, "status": {"cap": None, "groups": set()}}
        st = Store()
        c = lc.Collector(st, run=lambda w: (0, "x", ""), topic_rows=rows, topic_info=info, topic_needs={}, watchers=[], snapshots=False)
        return c, st

    def test_no_lease_means_the_idle_interval(self):
        c, st = self.make()
        self.assertEqual(c.pace("disk-health", 30), 300)
        self.assertEqual(c.pace("status", 15), 15)           # an always topic never changes pace

    def test_a_lease_gives_the_normal_interval_and_wakes_the_topic_at_once(self):
        c, st = self.make()
        self.assertFalse(c.events["disk-health"].is_set())
        st.leases = {"disk-health": time.time() + 30}
        c.lease_round()
        self.assertTrue(c.events["disk-health"].is_set())
        self.assertFalse(c.events["status"].is_set())
        self.assertEqual(c.pace("disk-health", 30), 30)

    def test_a_renewed_lease_wakes_nothing_again(self):
        c, st = self.make()
        st.leases = {"disk-health": time.time() + 30}
        c.lease_round()
        c.events["disk-health"].clear()
        st.leases = {"disk-health": time.time() + 30}
        c.lease_round()
        self.assertFalse(c.events["disk-health"].is_set())

    def test_the_star_lease_is_every_demand_topic(self):
        c, st = self.make()
        st.leases = {"*": time.time() + 30}
        c.lease_round()
        self.assertTrue(c.events["disk-health"].is_set())
        self.assertEqual(c.pace("disk-health", 30), 30)

    def test_an_expired_lease_goes_back_to_idle(self):
        c, st = self.make()
        c.leases = {"disk-health": time.time() - 1}
        self.assertEqual(c.pace("disk-health", 30), 300)
        c.lease_round()
        self.assertEqual(c.pace("disk-health", 30), 300)

    def test_a_failing_topic_is_retried_at_its_interval(self):
        c, st = self.make()
        st.get, st.fail, st.put = (lambda t: None), (lambda *a: None), (lambda *a: None)
        c._store("disk-health", 1, "", "boom", time.time(), [])
        self.assertEqual(c.pace("disk-health", 30), 30)
        c._store("disk-health", 0, "x", "", time.time(), [])
        self.assertEqual(c.pace("disk-health", 30), 300)

    def test_a_group_wake_passes_an_idle_topic_nobody_watches(self):
        for group in ("@disks", "@shares"):                  # hard (its own group) and soft (it lists `any`)
            c, st = self.make()
            c.info["disk-health"]["groups"] = {"disks", "any"}
            c.refresh(group)
            self.assertFalse(c.events["disk-health"].is_set(), group)
            self.assertNotIn("disk-health", c.trig)
            c.leases = {"disk-health": time.time() + 30}
            c.refresh(group)
            self.assertTrue(c.events["disk-health"].is_set(), group)

    def test_its_name_and_the_star_still_wake_an_idle_topic(self):
        for word in ("disk-health", "*"):
            c, st = self.make()
            c.refresh(word)
            self.assertTrue(c.events["disk-health"].is_set(), word)

    def test_a_wave_reads_only_a_watched_idle_dependent(self):
        c, st = self.make()
        c.min_gap = 0
        c.order, c.needs = ["status", "disk-health"], {"disk-health": ("status",)}
        read = []
        c.collect = lambda t, words, mode="run": read.append(t) or False
        self.assertEqual(c.wave({"status"}), [])
        c.leases = {"disk-health": time.time() + 30}
        self.assertEqual(c.wave({"status"}), ["disk-health"])
        self.assertEqual(read, ["disk-health"])

    def test_only_the_idle_wait_of_an_unwatched_topic_is_not_stretched(self):
        c, st = self.make()
        c.stretch = lambda: 10.0
        self.assertEqual(c.wait_for("disk-health", 30), 300)        # nobody watches: the safety net stays at its idle interval
        self.assertEqual(c.wait_for("status", 15), 150)             # an always topic is stretched
        c.leases = {"disk-health": time.time() + 30}
        self.assertEqual(c.wait_for("disk-health", 30), 300)        # watched: 30 x 10
        c.stretch = lambda: 2.0
        self.assertEqual(c.wait_for("disk-health", 30), 60)
        c.leases = {}
        c.failing.add("disk-health")
        self.assertEqual(c.wait_for("disk-health", 30), 60)         # failing: its interval, stretched as before

    def test_a_table_that_cannot_be_read_keeps_the_leases_and_raises_nothing(self):
        c, st = self.make()
        c.leases = {"disk-health": time.time() + 20}

        def busy(now):
            raise OSError("busy")
        st.demand = busy
        c.lease_round()
        self.assertEqual(c.pace("disk-health", 30), 30)


class Web(unittest.TestCase):
    def hub(self):
        cfg = ws.Config()
        cfg.live_sock = cfg.live_push_file = ""
        return ws.Events(cfg)

    def test_the_streams_topics_are_the_demand(self):
        h = self.hub()
        self.assertEqual(h.demanded(), set())
        h.add(frozenset({"a", "b"}))
        h.add(frozenset({"b", "c"}))
        self.assertEqual(h.demanded(), {"a", "b", "c"})
        h.add(None)                                          # an old client wants everything
        self.assertEqual(h.demanded(), {"*"})

    def test_a_star_stream_wants_everything(self):
        h = self.hub()
        h.add(frozenset({"*"}))
        self.assertEqual(h.demanded(), {"*"})

    def test_leases_are_written_and_only_while_a_stream_is_open(self):
        h = self.hub()
        sdb.live_open().close()
        self.assertFalse(h.write_leases())
        q = h.add(frozenset({"disk-health"}))
        self.assertTrue(h.write_leases())
        c = sdb.demand_open()
        self.assertIn("disk-health", sdb.demand_active(c, time.time()))
        c.close()
        h.remove(q)
        self.assertEqual(h.demanded(), set())

    def test_no_database_no_write(self):
        h = self.hub()
        h.add(frozenset({"x"}))
        old = os.environ["HS_STATE_DB"]
        os.environ["HS_STATE_DB"] = os.path.join(TMP, "none", "state.db")
        try:
            self.assertFalse(h.write_leases())
        finally:
            os.environ["HS_STATE_DB"] = old

    def test_a_new_stream_asks_for_a_lease_at_once(self):
        h = self.hub()
        h.lease_now.clear()
        h.add(frozenset({"a"}))
        self.assertTrue(h.lease_now.is_set())


class Inspect(unittest.TestCase):
    def test_inspect_shows_demand_idle_and_lease(self):
        info = {"disk-health": {"cap": None, "groups": set(), "idle": 300}}
        rows = [("disk-health", ["disk-health", "list"], 30, "run"), ("status", ["status"], 15, "run")]
        out = io.StringIO()
        c = sdb.demand_open()
        sdb.demand_put(c, ["disk-health"], time.time())
        c.close()
        with mock.patch.object(ls, "topics", lambda *a, **k: rows), mock.patch.object(ls, "topic_info", lambda *a, **k: info), \
                mock.patch.object(ls, "_db_open", lambda: sqlite3.connect(os.environ["HS_STATE_DB"])):
            ls.cli_inspect(out=out, docs=({}, None), delays={})
        doc = {t["topic"]: t for t in json.loads(out.getvalue())["topics"]}
        self.assertEqual(doc["status"]["demand"], "always")
        self.assertEqual(doc["disk-health"]["demand"], "idle:300")
        self.assertEqual(doc["disk-health"]["idle"], 300)
        self.assertGreater(doc["disk-health"]["lease"], time.time())
        self.assertNotIn("lease", doc["status"])


if __name__ == "__main__":
    unittest.main()
