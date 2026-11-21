#!/usr/bin/env python3
"""scripts/web-serve.py: the live state (ADR 0026): LiveStore reads a topic from the state database (tables live and heartbeat), /api/events follows the
change counters and the heartbeat, no Redis and no mode. A store set on app.store is what `_sys` uses. Real HTTP server on a free port, fake helpers,
`_run` replaced (no processes)."""
import http.client
import importlib.util
import json
import os
import tempfile
import threading
import time
import unittest

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("web_serve", os.path.join(here, "..", "scripts", "web-serve.py"))
ws = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ws)
os.environ["HS_WEB_QUIET"] = "1"
os.environ["HS_STATE_DIR"] = tempfile.mkdtemp()

_sdb_spec = importlib.util.spec_from_file_location("state_db_for_web", os.path.join(here, "..", "scripts", "state-db.py"))
sdb = importlib.util.module_from_spec(_sdb_spec)
os.environ.setdefault("HS_STATE_DB", os.path.join(tempfile.mkdtemp(), "x.db"))
_sdb_spec.loader.exec_module(sdb)


class FakeAuth:
    def __init__(self, cfg):
        self.cfg = cfg

    def storage_locked(self):
        return False

    def domain_password_ok(self, user, password):
        return user in ("anna", "vera") and password == "pw"

    def domain_is_admin(self, user):
        return user == "anna"

    def domain_role(self, user):
        return "admin" if self.domain_is_admin(user) else ("viewer" if user == "vera" else None)

    def local_fingerprint(self, user, fresh=False):
        return ""

    def local_password_ok(self, user, password):
        return False


class Fake:
    """what `hs sys <words>` would print; every call is counted"""

    def __init__(self):
        self.calls = []

    def __call__(self, cmd, stdin=None, timeout=10):
        self.calls.append(tuple(cmd[2:]))
        return 0, "a\tb\n"


class FakeStore:
    def __init__(self):
        self.asked = []

    def get(self, spec, argv, key, fresh=False):
        self.asked.append((tuple(key), fresh))
        return 200, {"from": "fake"}, 7, (("X-HS-Stale", "99"),)


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        os.makedirs(os.path.join(self.tmp, "assets"))
        cfg = ws.Config()
        cfg.root, cfg.workgroup, cfg.realm, cfg.fail_delay = self.tmp, "HOME", "ad.home.lan", 0
        cfg.hs = "/nonexistent/hs"
        self.cfg = cfg
        self.db = os.path.join(self.tmp, "state.db")
        os.environ["HS_STATE_DB"] = self.db      # the state database of the test: not there until a test makes it
        self.fake, self.real_run = Fake(), ws._run
        ws._run = self.fake
        self.app = ws.App(cfg, FakeAuth(cfg))
        self.srv = ws.Server(("127.0.0.1", 0), ws.make_handler(self.app))
        self.port = self.srv.server_address[1]
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()
        r = self.req("POST", "/api/login", {"realm": "domain", "user": "anna", "password": "pw"})[2]
        self.ck = {"Cookie": (r.getheader("Set-Cookie") or "").split(";")[0]}
        self.fake.calls.clear()

    def tearDown(self):
        ws._run = self.real_run
        os.environ.pop("HS_STATE_DB", None)
        self.srv.shutdown()
        self.srv.server_close()

    def req(self, method, path, body=None, headers=None):
        h = dict(headers or {})
        if body is not None:
            h["Content-Type"] = "application/json"
        if method == "POST":
            h.setdefault("Origin", "http://127.0.0.1:%d" % self.port)
        c = http.client.HTTPConnection("127.0.0.1", self.port)
        c.request(method, path, json.dumps(body) if body is not None else None, h)
        r = c.getresponse()
        out = (r.status, r.read(), r)
        c.close()
        return out


class NoCollector(Base):
    """No state database (a server whose collector never ran): every read is the direct read with the short cache, as before live state existed."""

    def test_config_defaults(self):
        self.assertTrue(ws.features(ws.Config())["live"])
        self.assertEqual(ws.features(ws.Config())["topics"], ws.live_topic_map())
        self.assertEqual(ws.Config().events_max, 32)
        self.assertFalse(hasattr(ws.Config(), "live_socket"))

    def test_the_store_is_the_live_store(self):
        self.assertIsInstance(self.app.store, ws.LiveStore)
        self.assertIs(self.app.store.reads, self.app.reads)

    def test_status_is_read_directly_with_the_cache_age(self):
        s, d, r = self.req("GET", "/api/sys/status", headers=self.ck)
        self.assertEqual(s, 200)
        self.assertEqual(self.fake.calls, [("status",)])
        self.assertEqual(r.getheader("X-HS-Age"), "0")
        self.assertIsNone(r.getheader("X-HS-Stale"))
        self.req("GET", "/api/sys/status", headers=self.ck)
        self.assertEqual(self.fake.calls, [("status",)])          # the second ask comes from the short cache

    def test_fresh_runs_again(self):
        self.req("GET", "/api/sys/status", headers=self.ck)
        s, d, r = self.req("GET", "/api/sys/status?fresh=1", headers=self.ck)
        self.assertEqual((s, r.getheader("X-HS-Age")), (200, "0"))
        self.assertEqual(len(self.fake.calls), 2)

    def test_the_status_read_has_a_topic(self):
        self.assertEqual(ws.READS[("status",)]["topic"], "status")

    def test_the_live_status_read_has_a_topic(self):
        self.assertEqual(ws.READS[("live", "status")]["topic"], "live")

    def test_mapped_storage_reads_run_directly_without_a_collector(self):
        for path, argv in (("monitor/disks", ("monitor", "disks")), ("shares/overview", ("shares", "overview")),
                           ("pool/info?pool=bulk", ("pool", "info", "--pool", "bulk"))):
            self.fake.calls.clear()
            s, d, r = self.req("GET", "/api/sys/" + path, headers=self.ck)
            self.assertEqual(s, 200, path)
            self.assertEqual(len(self.fake.calls), 1, path)
            self.assertEqual(self.fake.calls[0][:len(argv[:2])], argv[:2])

    def test_live_status_runs_directly_without_a_collector(self):
        s, d, r = self.req("GET", "/api/sys/live/status", headers=self.ck)
        self.assertEqual(s, 200)
        self.assertEqual(self.fake.calls, [("live", "status")])
        self.assertEqual(r.getheader("X-HS-Age"), "0")


class FakeStoreUsed(Base):
    def test_sys_goes_through_app_store(self):
        self.app.store = FakeStore()
        s, d, r = self.req("GET", "/api/sys/status", headers=self.ck)
        self.assertEqual((s, json.loads(d)), (200, {"from": "fake"}))
        self.assertEqual(r.getheader("X-HS-Age"), "7")
        self.assertEqual(r.getheader("X-HS-Stale"), "99")
        self.assertEqual(self.app.store.asked, [(("status",), False)])
        self.assertEqual(self.fake.calls, [])
        self.req("GET", "/api/sys/status?fresh=1", headers=self.ck)
        self.assertEqual(self.app.store.asked[-1], (("status",), True))

    def test_still_needs_a_session(self):
        self.app.store = FakeStore()
        self.assertEqual(self.req("GET", "/api/sys/status")[0], 401)
        self.assertEqual(self.app.store.asked, [])


class DbBase(Base):
    """The state database of the test with the live tables; ws.ls.cli_refresh (what LiveStore.request calls) records what was asked for."""

    def setUp(self):
        super().setUp()
        import sqlite3
        self.asked = []
        self.real_refresh, ws.ls.cli_refresh = ws.ls.cli_refresh, lambda args: self.asked.append(list(args)) or 0
        self.c = sqlite3.connect(self.db)
        self.c.executescript(sdb.SCHEMA + sdb.LIVE_SCHEMA)
        self.c.commit()
        self.hub = self.app.events
        self.hub.cfg.probe_file = ""
        self.q = self.hub.add()

    def tearDown(self):
        ws.ls.cli_refresh = self.real_refresh
        self.c.close()
        super().tearDown()

    def put(self, out="x\ty\n", t=None, topic="status", gen_only=False):
        return sdb.live_put(self.c, topic, out, 0, 5, "test", 60, int(t or time.time()))

    def beat(self, t=None, every=5):
        sdb.live_beat(self.c, "hs-live", every, 0, int(t or time.time()), {}, 0)

    def get(self, path="/api/sys/status"):
        return self.req("GET", path, headers=self.ck)

    def counters(self):
        self.hub.poll_counters()
        out = []
        while not self.q.empty():
            out.append(self.q.get())
        return out

    def csrf(self):
        return json.loads(self.req("GET", "/api/session", headers=self.ck)[1])["csrf"]

    def with_caps(self, on):
        real = ws.ls.cap_on
        ws.ls.cap_on = lambda name: True if name is None else on
        self.addCleanup(setattr, ws.ls, "cap_on", real)


class Topics(DbBase):
    def test_features_and_the_topic_map(self):
        self.assertTrue(ws.features(self.cfg)["live"])
        m = ws.live_topic_map()
        self.assertEqual(m["/api/sys/status"], "status")
        self.assertEqual(m["/api/sys/monitor/disks"], "monitor-disks")
        self.assertEqual(m["/api/sys/pool/info?pool=bulk"], "pool-info-bulk")
        self.assertEqual(m["/api/sys/pool/state?pool=fast"], "pool-state-fast")
        self.assertNotIn("/api/sys/pool/disks", m)
        self.assertNotIn("/api/sys/pool/info", m)
        self.assertNotIn("/api/sys/pool/info?pool=tank", m)
        self.assertEqual(len([k for k in m if "?pool=" in k]), 6)
        self.assertEqual(ws.features(self.cfg)["topics"], m)

    def test_reads_without_a_topic_still_run(self):
        s, d, r = self.req("GET", "/api/sys/gateway/status", headers=self.ck)
        self.assertEqual(s, 200)
        self.assertEqual(self.fake.calls, [("gateway", "status")])

    def test_warm_up_skips_topics(self):
        targets = [tuple(a[2]) for a in self.app.reads.warm_targets()]
        self.assertNotIn(("status",), targets)
        self.assertNotIn(("live", "status"), targets)

    def test_live_status_comes_from_the_row(self):
        self.put("live\t5\t2\t1\t0\t-\t-\n", topic="live")
        self.beat()
        s, d, r = self.get("/api/sys/live/status")
        self.assertEqual((s, json.loads(d)["rows"]), (200, [["live", "5", "2", "1", "0", "-", "-"]]))
        self.assertEqual(self.fake.calls, [])

    def test_status_header(self):
        self.beat()
        sdb.live_put(self.c, "status", "x\n", 0, 5, "test", 100, int(time.time()) - 60)
        sdb.live_fail(self.c, "status", 1, 3, "boom", "test", 100, int(time.time()) - 5)
        s, _, r = self.get()
        self.assertEqual((s, r.getheader("X-HS-Status")), (200, "stale"))
        sdb.live_delete(self.c, "status")
        sdb.live_fail(self.c, "status", 1, 3, "boom", "test", 100, int(time.time()) - 5)
        s, _, r = self.get()
        self.assertEqual((s, r.getheader("X-HS-Status"), r.getheader("X-HS-State")), (502, "error", "error"))      # never read: nothing to show, marked error

    def test_cap_off_topic_reads_directly(self):
        self.with_caps(False)
        self.app.store.caps["status"] = "nosuchcap"
        self.put()
        self.beat()
        s, d, r = self.get()
        self.assertEqual((s, self.fake.calls), (200, [("status",)]))

    def test_area_refresh_messages(self):
        self.assertEqual(ws.area_refresh("ct"), "@instances")
        self.assertEqual(ws.area_refresh("pool"), "@disks")
        self.assertEqual(ws.area_refresh("ext/games"), "@ext-games")
        self.assertEqual(ws.area_refresh("nonsense"), "*")

    def test_a_started_change_asks_for_its_group(self):
        ch = dict(self.ck, **{"X-CSRF-Token": self.csrf()})
        self.assertEqual(self.req("POST", "/api/plan", {"area": "ct", "args": ["web1", "restart"]}, ch)[0], 200)
        self.assertEqual(self.asked, [])
        self.assertEqual(self.req("POST", "/api/start", {"area": "ct", "args": ["web1", "restart"]}, ch)[0], 200)
        for _ in range(50):
            if self.asked:
                break
            time.sleep(0.02)
        self.assertEqual(self.asked, [["@instances"]])

    def test_inspect_and_raw_reads_are_never_cached(self):
        self.assertEqual(ws.READS[("live", "inspect")]["ttl"], 0)
        self.assertNotIn("topic", ws.READS[("live", "inspect")])
        self.assertEqual(ws.READS[("live", "raw")]["ttl"], 0)
        self.assertTrue(ws.READS[("live", "raw")]["args"])

    def test_live_refresh_checks(self):
        body = {"topic": "status"}
        ch = dict(self.ck, **{"X-CSRF-Token": self.csrf()})
        self.assertEqual(self.req("POST", "/api/live/refresh", body)[0], 401)
        self.assertEqual(self.req("POST", "/api/live/refresh", body, dict(self.ck, **{"X-CSRF-Token": "bad"}))[0], 403)
        self.assertEqual(self.req("POST", "/api/live/refresh", body, dict(ch, Origin="http://evil.example"))[0], 403)
        self.assertEqual(self.req("POST", "/api/live/refresh", {"topic": "no-such-topic"}, ch)[0], 400)
        self.assertEqual(self.req("POST", "/api/live/refresh", {"topic": 5}, ch)[0], 400)
        self.assertEqual(self.asked, [])
        self.assertEqual(self.req("POST", "/api/live/refresh", body, ch)[0], 200)      # no mode switch any more: never 409
        for _ in range(50):
            if self.asked:
                break
            time.sleep(0.02)
        self.assertEqual(self.asked, [["status"]])

    def test_delay_sample_is_open_to_a_viewer_and_stores_only_numbers(self):
        import sqlite3
        r = self.req("POST", "/api/login", {"realm": "domain", "user": "vera", "password": "pw"})[2]
        ck = {"Cookie": (r.getheader("Set-Cookie") or "").split(";")[0]}
        csrf = json.loads(self.req("GET", "/api/session", headers=ck)[1])["csrf"]
        ch = dict(ck, **{"X-CSRF-Token": csrf})
        body = {"topic": "status", "ms": 1234}
        self.assertEqual(self.req("POST", "/api/live/sample", body)[0], 401)
        self.assertEqual(self.req("POST", "/api/live/sample", body, dict(ck, **{"X-CSRF-Token": "bad"}))[0], 403)
        self.assertEqual(self.req("POST", "/api/live/sample", {"topic": "nope", "ms": 5}, ch)[0], 400)
        for bad in (-1, 600001, "5", 1.5, True, None):
            self.assertEqual(self.req("POST", "/api/live/sample", {"topic": "status", "ms": bad}, ch)[0], 400, bad)
        self.assertEqual(self.req("POST", "/api/live/sample", body, ch)[0], 200)
        c = sqlite3.connect(self.db)
        try:
            self.assertEqual(c.execute("SELECT web_last, web_worst, web_n, web_recent, ms_n FROM live_delay WHERE topic='status'").fetchall(),
                             [(1234, 1234, 1, "1234", 0)])
        finally:
            c.close()

    def test_delay_sample_batch(self):
        ch = dict(self.ck, **{"X-CSRF-Token": self.csrf()})
        self.app.samples.SAMPLE_PER_SESSION = 2
        batch = {"samples": [{"topic": "status", "ms": 5}, {"topic": "status", "ms": 6}, {"topic": "status", "ms": 7}]}
        self.assertEqual(self.req("POST", "/api/live/sample", batch, ch)[0], 200)      # one request, three samples, one slot of the limit
        self.assertEqual(self.req("POST", "/api/live/sample", {"samples": []}, ch)[0], 400)
        self.assertEqual(self.req("POST", "/api/live/sample", {"samples": [{"topic": "status", "ms": 1}] * (ws.SAMPLE_BATCH + 1)}, ch)[0], 400)
        self.assertEqual(self.req("POST", "/api/live/sample", {"samples": [{"topic": "status", "ms": 1}, {"topic": "nope", "ms": 1}]}, ch)[0], 400)
        self.assertEqual(self.req("POST", "/api/live/sample", {"samples": "x"}, ch)[0], 400)

    def test_delay_sample_is_rate_limited(self):
        ch = dict(self.ck, **{"X-CSRF-Token": self.csrf()})
        self.app.samples.SAMPLE_PER_SESSION = 3
        codes = [self.req("POST", "/api/live/sample", {"topic": "status", "ms": 10 + i}, ch)[0] for i in range(5)]
        self.assertEqual(codes, [200, 200, 200, 429, 429])
        g = ws.SampleGate(clock=lambda: 100.0)
        g.SAMPLE_TOTAL = 2
        self.assertEqual([g.allow("a"), g.allow("b"), g.allow("c")], [True, True, False])      # the total is shared by all sessions
        later = ws.SampleGate(clock=iter([0.0, 0.0, 61.0]).__next__)
        later.SAMPLE_PER_SESSION = 2
        self.assertEqual([later.allow("a"), later.allow("a"), later.allow("a")], [True, True, True])      # a minute later the window is free

    def test_login_facts_read_the_stored_status(self):
        self.put("instances\t3\t4\n")
        self.beat()
        facts = ws.Facts(self.cfg)._read(False)
        self.assertEqual(facts[0]["text"], "3 of 4 instances running")
        self.assertEqual(self.fake.calls, [])

    def test_login_facts_fall_back_to_the_command(self):
        ws.Facts(self.cfg)._read(False)
        self.assertEqual(self.fake.calls[0], ("status",))


NO_ARG = {
    ("monitor", "disks"): "monitor-disks", ("disk-health", "list"): "disk-health", ("state", "disks"): "disk-inventory",
    ("disk", "marks"): "disk-marks", ("shares", "overview"): "shares-overview", ("shares", "deleted"): "shares-deleted",
    ("shares", "principals"): "shares-principals", ("encryption", "list"): "encryption", ("vault", "list"): "vault-list",
    ("vault", "usage"): "vault-usage", ("vault", "uses"): "vault-uses", ("state", "history"): "state-history",
    ("fm", "locations"): "fm-locations", ("temp-disk", "raw"): "temp-disks",
}
SYSTEM = {
    ("deck",): "deck", ("jobs", "running"): "jobs-running", ("jobs", "list"): "jobs-list", ("health", "next"): "health-next",
    ("health", "list"): "health-list", ("hardware",): "hardware", ("ups", "status"): "ups", ("system", "updates"): "system-updates",
    ("system", "config"): "system-config", ("setup", "list"): "setup-list", ("config", "list"): "config-list",
    ("parts", "list"): "parts-list", ("node", "list"): "node-list", ("ssh-key", "list"): "ssh-keys", ("expiry", "list"): "expiry",
    ("notify", "channels"): "notify-channels", ("notify", "providers"): "notify-providers",
}
INSTANCES = {
    ("ct", "list"): "ct-list", ("ct", "profiles"): "ct-profiles", ("services", "list"): "services-list", ("services", "app"): "services-app",
    ("services", "routes"): "services-routes", ("services", "local-routes"): "services-local-routes",
    ("services", "tiles"): "services-tiles", ("services", "stats"): "services-stats",
}

APPS = {("pkg", "market"): "pkg-market", ("pkg", "states"): "pkg-states", ("apps", "list"): "apps-list", ("pkg", "repos"): "pkg-repos", ("recipes", "list"): "recipes-list", ("recipes", "versions"): "recipes-versions"}


NETWORK = {
    ("gateway", "status"): "gateway-status", ("gateway", "routes"): "gateway-routes", ("gateway", "health"): "gateway-health",
    ("dns", "list"): "dns-list", ("unifi", "networks"): "unifi-networks", ("unifi", "clients"): "unifi-clients",
    ("ports", "list"): "ports-list", ("remote", "list"): "remote-list",
}


IDENTITY = {
    ("users", "list"): "users-list", ("users", "groups"): "users-groups", ("dc", "state"): "dc-state",
    ("backup", "state"): "backup-state", ("backup", "overview"): "backup-overview", ("backup", "shares"): "backup-shares",
}
DIRECT_IDENTITY = [("cache", "state"), ("users", "access"), ("users", "group-access"), ("users", "details"), ("users", "group-details"),
                   ("backup", "find"), ("backup", "snapshots")]


class StorageTopics(DbBase):
    def test_web_areas_that_change_apps_ask_for_groups_that_wake_the_app_topics(self):
        info = ws.ls.topic_info()
        # pkg (install, update, remove, fetch, repo), parts and system (update, rebuild) change the package tree; recipes change instances
        for area, topics in (("pkg", ("pkg-market", "pkg-repos", "recipes-list", "recipes-versions")), ("parts", ("pkg-market", "recipes-list", "recipes-versions")),
                             ("system", ("pkg-market", "recipes-list", "recipes-versions")), ("recipes", ("pkg-market", "recipes-list", "recipes-versions")),
                             ("ct", ("pkg-market", "recipes-list", "recipes-versions"))):
            g = ws.area_refresh(area)[1:]
            for n in topics:
                self.assertTrue(g in info[n]["groups"] or "any" in info[n]["groups"], (area, n))

    def test_every_network_read_has_its_topic(self):
        known = {r[0] for r in ws.ls.topics()}
        for words, topic in NETWORK.items():
            self.assertEqual(ws.READS[words]["topic"], topic, words)
            self.assertIn(topic, known)
            self.assertEqual(ws.live_topic_map()["/api/sys/" + "/".join(words)], topic)

    def test_docker_list_read_has_its_topic(self):
        self.assertEqual(ws.READS[("docker", "list")]["topic"], "docker-list")
        self.assertIn("docker-list", {r[0] for r in ws.ls.topics()})
        self.assertEqual(ws.live_topic_map()["/api/sys/docker/list"], "docker-list")

    def test_web_areas_that_change_the_network_ask_for_groups_that_wake_the_network_topics(self):
        info = ws.ls.topic_info()
        net = set(NETWORK) - {("remote", "list")}
        for area, topics in (("gateway", net), ("routes", net), ("net", net), ("ct", net - {("unifi", "networks")}),
                             ("system", set(NETWORK)), ("config", set(NETWORK)), ("shares", {("remote", "list")})):
            g = ws.area_refresh(area)[1:]
            for w in topics:
                n = NETWORK[w]
                self.assertTrue(g in info[n]["groups"] or "any" in info[n]["groups"], (area, n))

    def test_every_identity_and_backup_read_has_its_topic(self):
        known = {r[0] for r in ws.ls.topics()}
        for words, topic in IDENTITY.items():
            self.assertEqual(ws.READS[words]["topic"], topic, words)
            self.assertIn(topic, known)
            self.assertEqual(ws.live_topic_map()["/api/sys/" + "/".join(words)], topic)
        for words in DIRECT_IDENTITY:
            self.assertNotIn("topic", ws.READS[words], words)
            self.assertNotIn("/api/sys/" + "/".join(words), ws.live_topic_map())

    def test_web_areas_that_change_identity_or_backup_ask_for_groups_that_wake_the_topics(self):
        info = ws.ls.topic_info()
        ids = {("users", "list"), ("users", "groups"), ("dc", "state")}
        bk = {w for w in IDENTITY if w[0] == "backup"}
        for area, topics in (("users", ids | {("backup", "state")}), ("dc", ids), ("admin", ids), ("backup", bk), ("ct", set(IDENTITY)),
                             ("recipes", set(IDENTITY)), ("shares", {w for w in IDENTITY if w != ("dc", "state")}), ("pool", bk),
                             ("secrets", {("dc", "state"), ("backup", "state")}), ("system", set(IDENTITY)), ("config", set(IDENTITY))):
            g = ws.area_refresh(area)[1:]
            for w in topics:
                n = IDENTITY[w]
                self.assertTrue(g in info[n]["groups"] or "any" in info[n]["groups"], (area, n))

    def test_every_apps_read_has_its_topic(self):
        known = {r[0] for r in ws.ls.topics()}
        for words, topic in APPS.items():
            self.assertEqual(ws.READS[words]["topic"], topic, words)
            self.assertIn(topic, known)
            self.assertEqual(ws.live_topic_map()["/api/sys/" + "/".join(words)], topic)

    def test_web_areas_of_instances_and_services_ask_for_groups_that_wake_them(self):
        info = ws.ls.topic_info()
        for area, group in (("ct", "@instances"), ("recipes", "@instances"), ("routes", "@network"), ("net", "@network"),
                            ("gateway", "@network")):
            self.assertEqual(ws.area_refresh(area), group, area)
            g = group[1:]
            for n in ("ct-list", "services-list", "services-app", "services-routes", "services-tiles"):
                self.assertTrue(g in info[n]["groups"], (area, n))

    def test_every_instance_read_has_its_topic(self):
        self.assertEqual(len(INSTANCES), 8)
        known = {r[0] for r in ws.ls.topics()}
        for words, topic in INSTANCES.items():
            self.assertEqual(ws.READS[words]["topic"], topic, words)
            self.assertIn(topic, known)
            self.assertEqual(ws.live_topic_map()["/api/sys/" + "/".join(words)], topic)

    def with_caps(self, on):
        real = ws.ls.cap_on
        ws.ls.cap_on = lambda name: True if name is None else on
        self.addCleanup(setattr, ws.ls, "cap_on", real)

    def test_ct_list_comes_from_its_row(self):
        self.with_caps(True)
        self.put("web\trunning\n", topic="ct-list")
        self.beat()
        s, d, r = self.req("GET", "/api/sys/ct/list", headers=self.ck)
        self.assertEqual((s, json.loads(d)["rows"]), (200, [["web", "running"]]))
        self.assertEqual(self.fake.calls, [])

    def test_ct_list_without_the_incus_capability_is_read_directly(self):
        self.with_caps(False)
        self.put("web\trunning\n", topic="ct-list")
        self.beat()
        s, d, r = self.req("GET", "/api/sys/ct/list", headers=self.ck)
        self.assertEqual(s, 200)
        self.assertEqual(self.fake.calls, [("ct", "list")])

    def test_every_no_argument_read_has_its_topic(self):
        for words, topic in NO_ARG.items():
            self.assertEqual(ws.READS[words]["topic"], topic, words)

    def test_every_system_read_has_its_topic(self):
        self.assertEqual(len(SYSTEM), 17)
        known = {r[0] for r in ws.ls.topics()}
        for words, topic in SYSTEM.items():
            self.assertEqual(ws.READS[words]["topic"], topic, words)
            self.assertIn(topic, known)
            self.assertEqual(ws.live_topic_map()["/api/sys/" + "/".join(words)], topic)

    def test_the_pool_reads_map_exactly_bulk_and_fast(self):
        for kind in ("info", "members", "state"):
            self.assertEqual(ws.READS[("pool", kind)]["topic"], ("pool", kind))
            for pool in ("bulk", "fast"):
                self.assertEqual(ws.live_topic_map()["/api/sys/pool/%s?pool=%s" % (kind, pool)], "pool-%s-%s" % (kind, pool))
        self.assertNotIn("topic", ws.READS[("pool", "disks")])

    # D5 (a), #886 part 2: a free-argument read follows the topic of its list (refetch when it changes), no timer while the stream is open
    FOLLOW = {
        "forms/backup/SetupDisk.svelte": ["pool-disks"], "forms/storage/AddDisks.svelte": ["pool-disks"],
        "forms/storage/ReplaceMember.svelte": ["pool-disks"],
        "forms/shares/RestoreShare.svelte": ["backup-state"], "pages/Backup.svelte": ["backup-state", "backup-state"],
        "pages/Shares.svelte": ["backup-state"],
        "pages/Instances.svelte": ["ct-list"], "pages/protection/CtSnapRow.svelte": ["ct-list"],
        "pages/Disks.svelte": ["disk-health"], "forms/ops/ServiceForm.svelte": ["services-list"],
    }

    def test_free_argument_reads_follow_the_topic_of_their_list(self):
        import re
        known = {r[0] for r in ws.ls.topics()}
        root = os.path.join(here, "..", "web", "src")
        needles = ("pool/disks", "backup/snapshots", "ct/snapshots", "state/smart", "services/show")
        for rel, topics in self.FOLLOW.items():
            src = open(os.path.join(root, rel), encoding="utf-8").read()
            found = []
            for line in src.splitlines():
                if "poll(" in line and any(n in line for n in needles):
                    m = re.search(r",\s*\d+,\s*'([a-z-]+)'\)", line)
                    self.assertIsNotNone(m, rel + ": " + line.strip())
                    found.append(m.group(1))
            self.assertEqual(found, topics, rel)
            for t in found:
                self.assertIn(t, known)

    def test_resolution_picks_the_topic_per_pool(self):
        for kind in ("info", "members", "state"):
            for pool in ("bulk", "fast"):
                spec, argv, key = self.app.reads.resolve(["pool", kind], {"pool": [pool]})
                self.assertEqual(spec["topic"], "pool-%s-%s" % (kind, pool))
            self.assertNotIn("topic", self.app.reads.resolve(["pool", kind], {})[0])
            self.assertNotIn("topic", self.app.reads.resolve(["pool", kind], {"pool": ["archive"]})[0])
            self.assertIsInstance(ws.READS[("pool", kind)]["topic"], tuple)      # the global entry is never changed

    def test_fixed_pool_read_uses_its_own_row_and_no_process(self):
        self.put("fast\t1\n", topic="pool-info-fast")
        self.put("bulk\t2\n", topic="pool-info-bulk")
        self.beat()
        s, d, r = self.req("GET", "/api/sys/pool/info?pool=fast", headers=self.ck)
        self.assertEqual((s, json.loads(d)["rows"]), (200, [["fast", "1"]]))
        self.assertEqual(self.fake.calls, [])

    def test_no_argument_storage_read_comes_from_its_row(self):
        self.put("s\tx\n", topic="shares-overview")
        self.beat()
        s, d, r = self.req("GET", "/api/sys/shares/overview", headers=self.ck)
        self.assertEqual((s, json.loads(d)["rows"]), (200, [["s", "x"]]))
        self.assertEqual(self.fake.calls, [])

    def test_fresh_runs_the_fixed_pool_read_now(self):
        self.put("old\n", topic="pool-state-bulk")
        self.beat()
        s, d, r = self.req("GET", "/api/sys/pool/state?pool=bulk&fresh=1", headers=self.ck)
        self.assertEqual(s, 200)
        self.assertEqual(len(self.fake.calls), 1)

    def test_arbitrary_and_no_pool_reads_still_run_directly(self):
        for q in ("", "?pool=archive"):
            self.fake.calls.clear()
            s, d, r = self.req("GET", "/api/sys/pool/info" + q, headers=self.ck)
            self.assertEqual(s, 200, q)
            self.assertEqual(len(self.fake.calls), 1, q)
            self.assertEqual(self.fake.calls[0][:2], ("pool", "info"))
            if q:
                self.assertIn("archive", self.fake.calls[0])
        self.assertEqual(self.asked, [])

    def test_warm_targets_keep_direct_pool_reads_only(self):
        for kind in ("info", "members", "state"):
            for pool in ("bulk", "fast"):
                hit = self.app.reads.resolve(["pool", kind], {"pool": [pool]})
                self.assertTrue(isinstance(hit[0].get("topic"), str))
        targets = [tuple(a[1]) for a in self.app.reads.warm_targets()]
        for words in list(NO_ARG) + list(SYSTEM):
            self.assertNotIn(words, targets)
        for t in targets:
            self.assertFalse(len(t) >= 4 and t[:2] == ("pool", "info") and t[-1] in ("bulk", "fast"), t)

    def test_new_storage_topics_are_in_the_list(self):
        topics = [r[0] for r in ws.ls.topics()]
        self.assertIn("pool-info-bulk", topics)
        self.assertIn("fm-locations", topics)


class Events(Base):
    def open(self, path="/api/events", headers=None):
        c = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        c.request("GET", path, headers=headers if headers is not None else self.ck)
        return c, c.getresponse()

    def test_needs_a_session(self):
        self.assertEqual(self.req("GET", "/api/events")[0], 401)

    def test_foreign_origin_is_refused(self):
        s = self.req("GET", "/api/events", headers=dict(self.ck, Origin="http://evil.example"))[0]
        self.assertEqual(s, 403)

    def test_too_many_streams(self):
        self.cfg.events_max = 0
        self.assertEqual(self.req("GET", "/api/events", headers=self.ck)[0], 503)

    def test_a_changed_frame_arrives(self):
        c, r = self.open(headers=dict(self.ck, Origin="http://127.0.0.1:%d" % self.port))
        try:
            self.assertEqual((r.status, r.getheader("Content-Type")), (200, "text/event-stream"))
            self.assertEqual(r.fp.readline(), b"retry: 3000\n")
            r.fp.readline()
            for _ in range(100):
                if self.app.events.queues:
                    break
                threading.Event().wait(0.02)
            self.app.events.feed("changed", "status", 5)
            self.assertEqual(r.fp.readline(), b"event: changed\n")
            self.assertEqual(json.loads(r.fp.readline()[len(b"data: "):]), {"topic": "status", "gen": 5})
        finally:
            c.close()

    def test_an_idle_stream_sends_the_named_beat(self):
        self.cfg.events_ping = 0.2
        c, r = self.open()
        try:
            self.assertEqual(r.fp.readline(), b"retry: 3000\n")
            r.fp.readline()
            lines = [r.fp.readline() for _ in range(4)]
            self.assertEqual(lines[0], b": ping\n")
            self.assertIn(b"event: beat\n", lines)
            self.assertIn(b"data: {}\n", lines)
        finally:
            c.close()

    def test_the_counter_goes_back(self):
        c, r = self.open()
        r.fp.readline()
        r.close()
        c.close()
        for _ in range(100):
            self.app.events.feed("down")
            if self.app.event_streams == 0:
                break
            threading.Event().wait(0.05)
        self.assertEqual(self.app.event_streams, 0)


class Replay(Base):
    """Domain events on /api/events: ids, Last-Event-ID replay, resync (docs/adr/0005-events.md rules 6 and 7)."""

    def setUp(self):
        super().setUp()
        import sqlite3
        c = sqlite3.connect(self.db)
        c.execute("CREATE TABLE events (id INTEGER PRIMARY KEY AUTOINCREMENT, time INTEGER NOT NULL, kind TEXT NOT NULL, subject TEXT, text TEXT, "
                  "source TEXT NOT NULL DEFAULT 'storage', level TEXT NOT NULL DEFAULT 'info', payload TEXT, v INTEGER NOT NULL DEFAULT 1)")
        c.commit()
        c.close()

    def tearDown(self):
        os.environ.pop("HS_STATE_DB", None)
        super().tearDown()

    def add(self, n=1, first=1):
        import sqlite3
        c = sqlite3.connect(self.db)
        for i in range(n):
            c.execute("INSERT INTO events (id, time, kind, subject, text, payload) VALUES (?, 1, 'new', 'd', 't', '{\"a\": 1}')", (first + i,))
        c.commit()
        c.close()

    def frames(self, last, count):
        c = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        c.request("GET", "/api/events", headers=dict(self.ck, **{"Last-Event-ID": str(last)}))
        r = c.getresponse()
        out = []
        try:
            r.fp.readline()
            r.fp.readline()
            while len(out) < count:
                ev = {}
                while True:
                    line = r.fp.readline().decode().rstrip("\n")
                    if not line:
                        break
                    k, _, v = line.partition(": ")
                    ev[k] = v
                out.append(ev)
        finally:
            c.close()
        return out

    def test_reconnect_gets_the_rows_after_the_id(self):
        self.add(5)
        f = self.frames(2, 3)
        self.assertEqual([x["id"] for x in f], ["3", "4", "5"])
        self.assertEqual(f[0]["event"], "domain")
        d = json.loads(f[0]["data"])
        self.assertEqual((d["id"], d["kind"], d["subject"], d["payload"]), (3, "new", "d", {"a": 1}))

    def test_up_to_date_gets_nothing_then_live_rows_without_repeats(self):
        self.add(3)
        c = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        c.request("GET", "/api/events", headers=dict(self.ck, **{"Last-Event-ID": "3"}))
        r = c.getresponse()
        try:
            r.fp.readline()
            r.fp.readline()
            for _ in range(100):
                if self.app.events.queues:
                    break
                threading.Event().wait(0.02)
            self.app.events.feed("domain", {"id": 4, "kind": "y"})
            self.app.events.feed("domain", {"id": 4, "kind": "y"})      # a repeat: skipped
            self.app.events.feed("domain", {"id": 5, "kind": "z"})
            self.assertEqual(r.fp.readline(), b"id: 4\n")
            self.assertEqual(r.fp.readline(), b"event: domain\n")
            r.fp.readline()
            r.fp.readline()
            self.assertEqual(r.fp.readline(), b"id: 5\n")
        finally:
            c.close()

    def test_an_id_before_the_oldest_row_resyncs(self):
        self.add(3, first=10)
        self.assertEqual(self.frames(5, 1)[0]["event"], "resync")

    def test_an_id_after_the_newest_row_resyncs(self):
        self.add(3)
        self.assertEqual(self.frames(99, 1)[0]["event"], "resync")

    def test_500_behind_replays_501_resyncs(self):
        self.add(501)
        self.assertEqual(self.frames(1, 1)[0]["event"], "domain")
        self.add(1, first=502)
        self.assertEqual(self.frames(1, 1)[0]["event"], "resync")

    def test_the_watcher_feeds_new_rows(self):
        self.add(2)
        q = self.app.events.add()
        self.app.events.poll_events()                                   # baseline
        self.add(1, first=3)
        self.app.events.poll_events()
        item = q.get_nowait()
        self.assertEqual((item[0], item[1]["id"]), ("domain", 3))
        self.assertTrue(q.empty())

    def test_a_full_queue_becomes_a_resync(self):
        hub = ws.Events(self.cfg)
        q = hub.add()
        for i in range(300):
            hub.feed("changed", "t", i)
        items = []
        while not q.empty():
            items.append(q.get_nowait())
        self.assertIn(("resync",), items)
        self.assertLess(len(items), 256)


class Counters(Base):
    """The change counters (table topics of state.db): the watcher feeds `changed` and clears the read cache."""

    def setUp(self):
        super().setUp()
        self.db = os.path.join(self.tmp, "state.db")
        os.environ["HS_STATE_DB"] = self.db
        self.hub = self.app.events
        self.q = self.hub.add()

    def tearDown(self):
        os.environ.pop("HS_STATE_DB", None)
        super().tearDown()

    def bump(self, topic, n=1):
        import sqlite3
        c = sqlite3.connect(self.db)
        c.execute("CREATE TABLE IF NOT EXISTS topics (topic TEXT PRIMARY KEY, gen INTEGER NOT NULL DEFAULT 0, time INTEGER NOT NULL DEFAULT 0)")
        for _ in range(n):
            c.execute("INSERT INTO topics (topic, gen, time) VALUES (?, 1, 0) ON CONFLICT(topic) DO UPDATE SET gen = gen + 1", (topic,))
        c.commit()
        c.close()

    def drain(self):
        out = []
        while not self.q.empty():
            out.append(self.q.get())
        return out

    def test_no_database_is_no_event(self):
        self.hub.poll_counters()
        self.hub.poll_counters()
        self.assertEqual(self.drain(), [])

    def test_a_bump_is_one_changed_and_clears_the_cache(self):
        cleared = []
        self.hub.on_change = lambda: cleared.append(1)
        self.hub.poll_counters()                  # baseline: no database yet
        self.bump("status")
        self.hub.poll_counters()
        self.assertEqual(self.drain(), [("changed", "status", 1)])
        self.assertEqual(cleared, [1])
        self.hub.poll_counters()                  # nothing moved
        self.assertEqual((self.drain(), cleared), ([], [1]))

    def test_the_first_read_is_a_baseline(self):
        self.bump("status", 3)
        self.hub.poll_counters()
        self.assertEqual(self.drain(), [])
        self.bump("status")
        self.hub.poll_counters()
        self.assertEqual(self.drain(), [("changed", "status", 4)])

    def test_a_collector_counter_keeps_the_cache(self):
        cleared = []
        self.hub.on_change = lambda: cleared.append(1)
        self.hub.poll_counters()
        self.bump("reads:monitor disks")
        self.hub.poll_counters()
        self.assertEqual(self.drain(), [("changed", "reads:monitor disks", 1)])
        self.assertEqual(cleared, [])

    def test_a_job_records_counter_keeps_the_cache(self):
        """The job record writer counts `reads:jobs-records`: a `changed`, the cache stays. A name without the `reads:` prefix clears it."""
        cleared = []
        self.hub.on_change = lambda: cleared.append(1)
        self.hub.poll_counters()
        self.bump("reads:jobs-records")
        self.hub.poll_counters()
        self.assertEqual(self.drain(), [("changed", "reads:jobs-records", 1)])
        self.assertEqual(cleared, [])
        self.bump("jobs-records")
        self.hub.poll_counters()
        self.assertEqual(self.drain(), [("changed", "jobs-records", 1)])
        self.assertEqual(cleared, [1])

    def test_a_change_clears_the_read_cache(self):
        self.app.reads.cache["k"] = (time.time(), (200, {}))
        self.hub.poll_counters()
        self.bump("storage")
        self.hub.poll_counters()
        self.assertEqual(self.app.reads.cache, {})


class DbMode(Base):
    """`down`/`up` come from the heartbeat row of the collector, live: counters keep the cache."""

    def setUp(self):
        super().setUp()
        self.probe = os.path.join(self.tmp, "probe.tsv")
        self.cfg.probe_file = self.probe
        self.hub = self.app.events
        self.q = self.hub.add()

    def sql(self, *stmts):
        import sqlite3
        c = sqlite3.connect(self.db)
        for st in stmts:
            c.execute(*st) if isinstance(st, tuple) else c.execute(st)
        c.commit()
        c.close()

    def beat(self, t, every=5):
        self.sql("CREATE TABLE IF NOT EXISTS heartbeat (name TEXT PRIMARY KEY, time INTEGER NOT NULL, every INTEGER NOT NULL)",
                 ("INSERT INTO heartbeat (name, time, every) VALUES ('hs-live', ?, ?) ON CONFLICT(name) DO UPDATE SET time = excluded.time, every = excluded.every",
                  (t, every)))

    def bump(self, topic, n=1):
        self.sql("CREATE TABLE IF NOT EXISTS topics (topic TEXT PRIMARY KEY, gen INTEGER NOT NULL DEFAULT 0, time INTEGER NOT NULL DEFAULT 0)")
        for _ in range(n):
            self.sql(("INSERT INTO topics (topic, gen, time) VALUES (?, 1, 0) ON CONFLICT(topic) DO UPDATE SET gen = gen + 1", (topic,)))

    def drain(self):
        out = []
        while not self.q.empty():
            out.append(self.q.get())
        return out

    def test_the_watcher_follows_the_heartbeat(self):
        calls = []
        self.hub.poll_heartbeat = lambda now=None: calls.append(1)
        self.hub.poll_counters = lambda: None
        self.hub.poll_events = lambda: None
        self.hub.cfg.events_watch = 0.01
        threading.Thread(target=self.hub._watch, daemon=True).start()
        time.sleep(0.2)
        self.assertTrue(calls)

    def test_heartbeat_fresh_then_old_feeds_down_then_up(self):
        self.beat(1000)
        self.hub.poll_heartbeat(now=1005)
        self.assertEqual(self.drain(), [])                  # baseline, alive
        self.hub.poll_heartbeat(now=1015)
        self.assertEqual(self.drain(), [])                  # 15 s old: still within max(15, 3 x 5)
        self.hub.poll_heartbeat(now=1016)
        self.assertEqual(self.drain(), [("down",)])
        self.hub.poll_heartbeat(now=1020)
        self.assertEqual(self.drain(), [])                  # once
        self.beat(1021)
        self.hub.poll_heartbeat(now=1022)
        self.assertEqual(self.drain(), [("up",)])

    def test_heartbeat_missing_at_start_feeds_down(self):
        self.hub.poll_heartbeat(now=1000)
        self.assertEqual(self.drain(), [("down",)])
        self.assertIs(self.hub.collector_up, False)

    def test_live_prefix_does_not_clear_cache(self):
        cleared = []
        self.hub.on_change = lambda: cleared.append(1)
        self.hub.poll_counters()
        self.bump("live:status")
        self.hub.poll_counters()
        self.assertEqual(self.drain(), [("changed", "status", 1)])      # the page knows the topic by its own name
        self.assertEqual(cleared, [])
        self.bump("status")
        self.hub.poll_counters()
        self.assertEqual(cleared, [1])

    def test_probe_is_recorded(self):
        self.hub.poll_counters()
        self.bump("live:probe")
        self.hub.poll_counters()
        with open(self.probe, encoding="utf-8") as f:
            parts = f.read().rstrip("\n").split("\t")
        self.assertEqual((parts[0], parts[1], parts[3]), ("live:probe", "1", "1"))
        self.assertTrue(parts[2].isdigit())

    def test_probe_off_with_empty_setting(self):
        self.cfg.probe_file = ""
        self.hub.poll_counters()
        self.bump("live:probe")
        self.hub.poll_counters()
        self.assertFalse(os.path.exists(self.probe))

    def test_stream_open_says_down_without_a_collector(self):
        self.hub.collector_up = False
        c = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        c.request("GET", "/api/events", headers=self.ck)
        r = c.getresponse()
        try:
            self.assertEqual(r.fp.readline(), b"retry: 3000\n")
            r.fp.readline()
            self.assertEqual(r.fp.readline(), b"event: down\n")
            self.assertEqual(r.fp.readline(), b"data: {}\n")
        finally:
            c.close()


class DbRead(DbBase):
    """Topic reads and /api/events come from the state database only (no Redis, no process)."""

    def test_store_and_feature(self):
        self.assertIsInstance(self.app.store, ws.LiveStore)
        self.assertTrue(ws.features(self.cfg)["live"])
        self.assertEqual(ws.features(self.cfg)["topics"].get("/api/sys/status"), "status")

    def test_status_comes_from_the_row_and_starts_no_process(self):
        self.put(t=time.time() - 400)
        self.beat()
        s, d, r = self.get()
        self.assertEqual((s, json.loads(d)["rows"]), (200, [["x", "y"]]))
        self.assertEqual(self.fake.calls, [])
        self.assertEqual(r.getheader("X-HS-Status"), "fresh")                 # unchanged for 400 s, but the collector checked just now
        self.assertIn(r.getheader("X-HS-Age"), ("0", "1"))                    # the age is the heartbeat's
        self.assertIn(int(r.getheader("X-HS-Updated")), range(int(time.time()) - 402, int(time.time()) - 397))

    def test_collector_stopped_marks_the_document_expired(self):
        self.put(t=time.time() - 400)
        self.beat(t=time.time() - 120)
        s, d, r = self.get()
        self.assertEqual((s, r.getheader("X-HS-Status")), (200, "expired"))   # still served, only marked
        self.assertEqual(self.fake.calls, [])

    def test_no_row_and_no_collector_reads_directly(self):
        s, d, r = self.get()
        self.assertEqual(s, 200)
        self.assertEqual(self.fake.calls, [("status",)])

    def test_no_row_with_a_collector_asks_to_retry(self):
        self.beat()
        s, d, r = self.get()
        self.assertEqual((s, json.loads(d)["error"], r.getheader("Retry-After")), (503, "refreshing", "2"))
        self.assertEqual(self.fake.calls, [])

    def test_unreadable_database_reads_directly_never_503(self):
        os.environ["HS_STATE_DB"] = self.tmp                                   # a directory: sqlite cannot open it
        s, d, r = self.get()
        self.assertEqual(s, 200)

    def test_fresh_runs_the_command(self):
        self.put()
        self.beat()
        s, d, r = self.req("GET", "/api/sys/status?fresh=1", headers=self.ck)
        self.assertEqual((s, self.fake.calls), (200, [("status",)]))

    def test_newer_failure_marks_it_stale(self):
        self.put(t=time.time() - 30)
        self.beat()
        sdb.live_fail(self.c, "status", 1, 3, "boom", "test", 60, int(time.time()))
        s, d, r = self.get()
        self.assertEqual((s, r.getheader("X-HS-State"), r.getheader("X-HS-Error"), r.getheader("X-HS-Status")), (200, "stale", "boom", "stale"))

    def test_events_come_from_the_counters_only(self):
        self.beat()
        self.counters()                                                        # baseline
        gen = self.put()
        self.assertEqual(self.counters(), [("changed", "status", gen)])
        self.assertEqual(self.counters(), [])

    def test_an_unchanged_document_bumps_nothing(self):
        gen = self.put("a\tb\n")
        self.counters()
        self.assertEqual(self.counters(), [])                                  # nothing written: no event
        self.assertEqual(self.c.execute("SELECT gen FROM live WHERE topic = 'status'").fetchone()[0], gen)
        self.assertEqual(self.counters(), [])

    def test_a_hook_bump_does_not_double_the_event(self):
        self.put()
        self.counters()
        with self.c:
            sdb.bump(self.c, ["status"])                                       # live_refresh from a hook
        self.assertEqual(self.counters(), [])                                  # the collector's live:status is the one event
        gen = self.put("z\n")
        self.assertEqual(self.counters(), [("changed", "status", gen)])

    def test_down_and_up_follow_the_heartbeat(self):
        self.beat(t=1000)
        self.hub.poll_heartbeat(now=1005)
        self.hub.poll_heartbeat(now=1030)
        self.assertEqual(self.q.get_nowait(), ("down",))
        self.beat(t=1031)
        self.hub.poll_heartbeat(now=1032)
        self.assertEqual(self.q.get_nowait(), ("up",))

    def test_reconnect_after_a_gap_resyncs(self):
        self.c.execute("INSERT INTO events (time, kind) VALUES (1, \"x\")")
        self.c.commit()
        c = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        c.request("GET", "/api/events", headers=dict(self.ck, **{"Last-Event-ID": "99"}))
        r = c.getresponse()
        try:
            self.assertEqual(r.fp.readline(), b"retry: 3000\n")
            r.fp.readline()
            self.assertEqual(r.fp.readline(), b"event: resync\n")
        finally:
            c.close()


if __name__ == "__main__":
    unittest.main()
