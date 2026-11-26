#!/usr/bin/env python3
"""scripts/web-serve.py: the read cache. Answers survive a restart (cache file), the warm-up keeps every read without arguments and everything
somebody asked for fresh, and an old answer is shown at once while a new one is read. `_run` (the call of `hs sys ...`) is replaced: no processes."""
import importlib.util
import json
import os
import sqlite3
import stat
import tempfile
import time
import unittest

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("web_serve", os.path.join(here, "..", "scripts", "web-serve.py"))
ws = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ws)
os.environ["HS_WEB_QUIET"] = "1"
_caps = tempfile.NamedTemporaryFile("w", suffix=".caps", delete=False)      # the poster read belongs to the extension package "posters"
_caps.write("posters\n")
_caps.close()
os.environ["HS_CAPABILITIES_FILE"] = _caps.name
os.environ["HS_STATE_DIR"] = tempfile.mkdtemp()
ws.ext_refresh(force=True)


class Fake:
    """what `hs sys <words>` would print; every call is counted"""

    def __init__(self):
        self.calls = []

    def __call__(self, cmd, stdin=None, timeout=10):
        self.calls.append(tuple(cmd[2:]))
        return 0, '{"x": 1}\n'          # valid for every kind of read (JSON, text, rows)


class Cache(unittest.TestCase):
    def setUp(self):
        self.fake = Fake()
        self.real_run = ws._run
        ws._run = self.fake
        self.tmp = tempfile.mkdtemp()
        self.file = os.path.join(self.tmp, "cache.json")
        self.cfg = ws.Config()
        self.cfg.cache_file = self.file

    def tearDown(self):
        ws._run = self.real_run

    def reads(self):
        return ws.Reads(self.cfg)

    def ask(self, r, path, query=None):
        hit = r.resolve(path.split("/"), query or {})
        self.assertIsNotNone(hit, path)
        return r.get_aged(*hit)

    def test_a_second_ask_is_served_from_memory(self):
        r = self.reads()
        self.ask(r, "ct/list")
        self.ask(r, "ct/list")
        self.assertEqual(len(self.fake.calls), 1)

    def test_the_answers_survive_a_restart(self):
        r = self.reads()
        self.ask(r, "ct/list")
        self.ask(r, "shares/overview")
        r.save(self.file)
        self.assertTrue(os.path.isfile(self.file))
        if os.name == "posix":
            self.assertEqual(stat.S_IMODE(os.stat(self.file).st_mode), 0o600)
        n = len(self.fake.calls)
        r2 = self.reads()
        self.assertEqual(r2.load(self.file), 2)
        code, obj, age = self.ask(r2, "ct/list")
        self.assertEqual(code, 200)
        self.assertEqual(obj["rows"][0][0], '{"x": 1}')
        self.assertIsNotNone(age)
        self.assertEqual(len(self.fake.calls), n)       # nothing was run: the old answer came out of the file

    def test_an_answer_past_its_ttl_is_shown_at_once_and_read_again(self):
        r = self.reads()
        self.ask(r, "ct/list")                           # ttl 5
        key = ("ct", "list")
        t, val = r.cache[key]
        r.cache[key] = (t - 100, val)                    # 100 s old: far past the ttl, inside the stale window
        before = len(self.fake.calls)
        code, obj, age = self.ask(r, "ct/list")
        self.assertGreaterEqual(age, 100)
        # the refresh runs in the background
        for _ in range(100):
            if len(self.fake.calls) > before:
                break
            time.sleep(0.02)
        self.assertGreater(len(self.fake.calls), before)

    def test_old_or_foreign_entries_are_not_loaded(self):
        now = time.time()
        items = [{"argv": ["ct", "list"], "t": now - 5, "code": 200, "obj": {"rows": [["a"]], "rc": 0}},
                 {"argv": ["ct", "list", "x"], "t": now, "code": 200, "obj": {}},                       # not an allowlisted shape
                 {"argv": ["nosuch", "read"], "t": now, "code": 200, "obj": {}},
                 {"argv": ["shares", "overview"], "t": now - 99999, "code": 200, "obj": {"rows": [], "rc": 0}},   # older than the stale window
                 {"argv": ["config", "check"], "t": now, "code": 200, "obj": {"text": "", "rc": 0}},    # ttl 0: never kept
                 {"argv": ["status"], "t": now, "code": 502, "obj": {"error": "x"}},                    # an error is not an answer
                 "junk", {"argv": 5}]
        with open(self.file, "w") as f:
            json.dump(items, f)
        r = self.reads()
        self.assertEqual(r.load(self.file), 1)
        self.assertEqual(list(r.cache), [("ct", "list")])

    def test_a_damaged_file_is_ignored(self):
        with open(self.file, "w") as f:
            f.write("{not json")
        self.assertEqual(self.reads().load(self.file), 0)
        self.assertEqual(self.reads().load(os.path.join(self.tmp, "missing.json")), 0)
        self.assertEqual(self.reads().load(""), 0)

    def test_errors_are_not_saved(self):
        r = self.reads()
        ws._run = lambda cmd, stdin=None, timeout=10: (1, "")
        self.ask(r, "ct/list")                           # 502
        r.dirty = True
        r.save(self.file)
        with open(self.file) as f:
            self.assertEqual(json.load(f), [])

    def test_save_only_when_something_changed(self):
        r = self.reads()
        self.ask(r, "ct/list")
        r.save(self.file)
        os.remove(self.file)
        r.save(self.file)
        self.assertFalse(os.path.exists(self.file))     # nothing new since the last save

    def test_warm_targets_hold_every_read_without_arguments(self):
        r = self.reads()
        names = {"/".join(k[0].words) if hasattr(k[0], "words") else "/".join(k[1]) for k in r.warm_targets()}
        for must in ("net/nics", "system/doctor", "logs/units", "testlab/results", "pool/list"):
            self.assertIn(must, names)
        for topic in ("ct/list", "shares/overview", "recipes/list", "services/list", "dc/state", "state/disks"):
            self.assertNotIn(topic, names)              # a live topic: the collector keeps it, the warm-up leaves it alone
        self.assertNotIn("config/check", names)         # ttl 0: always read fresh, never warmed
        self.assertFalse(any(k[1][:2] == ["ct", "bindings"] for k in r.warm_targets()))   # needs an argument nobody gave yet

    def test_what_somebody_asked_for_stays_warm_with_its_arguments(self):
        r = self.reads()
        self.ask(r, "ct/bindings/jellyfin")
        targets = [(argv, every) for spec_, argv, key, every in r.warm_targets()]
        self.assertIn((["ct", "bindings", "jellyfin"], 10), targets)

    def test_a_read_nobody_asked_for_is_not_read_more_often_than_the_idle_ttl(self):
        r = self.reads()
        every = {tuple(argv): e for spec_, argv, key, e in r.warm_targets()}
        self.assertGreaterEqual(every[("net", "nics")], self.cfg.warm_idle_ttl)

    def test_an_ondemand_read_is_not_warmed_not_even_after_it_was_asked_for(self):
        r = self.reads()
        warmed = lambda: any(argv[:2] == ["pkg", "fit"] for _s, argv, _k, _e in r.warm_targets())
        self.assertFalse(warmed())
        self.ask(r, "pkg/fit")
        self.assertFalse(warmed())

    def test_an_ondemand_read_is_never_answered_past_its_ttl(self):
        r = self.reads()
        self.ask(r, "pkg/fit")
        self.ask(r, "pkg/fit")                           # younger than the ttl: from memory
        self.assertEqual(len(self.fake.calls), 1)
        key = ("pkg", "fit")
        t, val = r.cache[key]
        r.cache[key] = (t - 100, val)                    # past the ttl: a normal read would show this one and read again behind it
        code, _obj, age = self.ask(r, "pkg/fit")
        self.assertEqual(code, 200)
        self.assertEqual(len(self.fake.calls), 2)        # run before the answer
        self.assertTrue(age is None or age < 60)

    def test_the_warm_up_reads_what_is_missing_and_stops_when_nobody_is_there(self):
        class App:
            pass
        app = App()
        app.cfg = self.cfg
        app.reads = self.reads()
        app.sessions = type("S", (), {"last_seen": staticmethod(lambda: time.time())})()
        app.auth = type("A", (), {"storage_locked": staticmethod(lambda: False)})()
        self.cfg.warm_pause = 0
        w = ws.Warmer(app)
        n = w.once()
        self.assertGreater(n, 20)                        # every read without arguments and without a live topic
        self.assertEqual(w.once(), 0)                    # all warm now
        app.sessions = type("S", (), {"last_seen": staticmethod(lambda: time.time() - 99999)})()
        self.assertEqual(w.once(), 0)
        app.sessions = type("S", (), {"last_seen": staticmethod(lambda: time.time())})()
        app.auth = type("A", (), {"storage_locked": staticmethod(lambda: True)})()
        app.reads.cache.clear()
        self.assertEqual(w.once(), 0)                    # storage locked: nothing is run

    def test_the_defaults_show_old_data_for_a_while(self):
        cfg = ws.Config()
        self.assertGreaterEqual(cfg.stale_max, 900)
        self.assertGreaterEqual(cfg.stale_factor, 20)


class Nocache(unittest.TestCase):
    """a read marked nocache (docker/logs) is never kept in memory, seen, warm-up, or on disk; ordinary ct logs stay cached"""

    def setUp(self):
        self.fake = Fake()
        self.real_run = ws._run
        ws._run = self.fake
        self.tmp = tempfile.mkdtemp()
        self.file = os.path.join(self.tmp, "cache.json")
        self.cfg = ws.Config()
        self.cfg.cache_file = self.file

    def tearDown(self):
        ws._run = self.real_run

    def reads(self):
        return ws.Reads(self.cfg)

    def ask(self, r, path, query=None):
        hit = r.resolve(path.split("/"), query or {})
        self.assertIsNotNone(hit, path)
        return r.get_aged(*hit)

    def test_a_nocache_read_runs_every_time(self):
        r = self.reads()
        self.ask(r, "docker/logs/arr")
        self.ask(r, "docker/logs/arr")
        self.assertEqual(len(self.fake.calls), 2)

    def test_a_nocache_read_is_not_in_seen(self):
        r = self.reads()
        self.ask(r, "docker/logs/arr")
        self.assertNotIn(("docker", "logs", "arr"), r.seen)

    def test_a_nocache_read_is_not_warmed(self):
        r = self.reads()
        self.assertFalse(any(k[1][:2] == ["docker", "logs"] for k in r.warm_targets()))

    def test_a_nocache_read_is_not_saved(self):
        r = self.reads()
        self.ask(r, "docker/logs/arr")
        r.dirty = True
        r.save(self.file)
        if os.path.exists(self.file):
            with open(self.file) as f:
                data = json.load(f)
            self.assertFalse(any(isinstance(x, dict) and x.get("argv", [])[:2] == ["docker", "logs"] for x in data))

    def test_a_nocache_entry_is_not_loaded(self):
        now = time.time()
        items = [{"argv": ["docker", "logs", "arr"], "t": now - 1, "code": 200, "obj": {"text": "secret", "rc": 0}}]
        with open(self.file, "w") as f:
            json.dump(items, f)
        r = self.reads()
        self.assertEqual(r.load(self.file), 0)
        self.assertNotIn(("docker", "logs", "arr"), r.cache)

    def test_docker_app_not_cached(self):
        r = self.reads()
        hit = r.resolve(["docker", "app", "arr"], {})
        self.assertIsNotNone(hit)
        r.get_aged(*hit)
        r.get_aged(*hit)
        # ttl 0 means it runs every time
        self.assertEqual(len(self.fake.calls), 2)

    def test_ordinary_ct_logs_stay_cached(self):
        r = self.reads()
        self.ask(r, "ct/logs/ct", {"lines": "10"})
        self.ask(r, "ct/logs/ct", {"lines": "10"})
        self.assertEqual(len(self.fake.calls), 1)


if __name__ == "__main__":
    unittest.main()
