#!/usr/bin/env python3
"""End-to-end (#485): an action changes the server, an OPEN page shows the new state without a reload, within the limit of
scripts/lib/live-limits.tsv, with every timer off (the page only follows /api/events).

The chain is real: change counter (state-db.py topic-bump, what live_refresh calls) -> state.db table topics -> Events watcher ->
/api/events over HTTP -> the page model reads the topic read again. The page model is a thread that does what web/src/data.svelte.js
poll() does with a topic and the stream open (no timer, one read per `changed`); the Svelte code itself needs a browser (test-lab stage 6).
`hs sys` is replaced by a table of answers that the action changes."""
import http.client
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import threading
import time
import unittest

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.join(here, "..")
tmp = tempfile.mkdtemp()
os.environ["HS_WEB_QUIET"] = "1"
os.environ["HS_STATE_DIR"] = tmp
os.environ["HS_STATE_DB"] = os.path.join(tmp, "state.db")
spec = importlib.util.spec_from_file_location("web_serve", os.path.join(root, "scripts", "web-serve.py"))
ws = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ws)


def limits():
    out = {}
    with open(os.path.join(root, "scripts", "lib", "live-limits.tsv"), encoding="utf-8") as f:
        for line in f:
            if line.strip() and not line.startswith("#"):
                k, v = line.split("\t")[:2]
                out[k] = float(v)
    return out


LIMIT = limits()


class FakeAuth:
    def __init__(self, cfg): pass
    def storage_locked(self): return False
    def domain_password_ok(self, u, p): return u == "anna" and p == "pw"
    def domain_is_admin(self, u): return u == "anna"
    def domain_role(self, u): return "admin"
    def local_fingerprint(self, u, fresh=False): return ""
    def local_password_ok(self, u, p): return False


class Page:
    """An open page: shows what its read answered; follows the stream, has no timer. `shown` is the text on the page."""

    def __init__(self, port, cookie, path, topic):
        self.port, self.cookie, self.path, self.topic = port, cookie, path, topic
        self.shown, self.reads, self.stop = None, 0, False
        self.up = threading.Event()
        self.changed = threading.Event()
        self.read()
        threading.Thread(target=self.follow, daemon=True).start()
        assert self.up.wait(5), "the stream did not open"

    def read(self):
        c = http.client.HTTPConnection("127.0.0.1", self.port, timeout=10)
        c.request("GET", self.path, headers=self.cookie)
        r = c.getresponse()
        self.shown = "".join("\t".join(row) + "\n" for row in json.loads(r.read().decode())["rows"])
        self.reads += 1
        c.close()

    def follow(self):
        c = http.client.HTTPConnection("127.0.0.1", self.port, timeout=30)
        c.request("GET", "/api/events", headers=self.cookie)
        r = c.getresponse()
        ev = None
        while not self.stop:
            line = r.fp.readline()
            if not line:
                return
            line = line.decode().rstrip("\n")
            if line == "retry: 3000":
                self.up.set()
            elif line.startswith("event: "):
                ev = line[7:]
            elif line.startswith("data: ") and ev == "changed":
                if json.loads(line[6:]).get("topic") == self.topic:
                    self.read()
                    self.changed.set()


class E2E(unittest.TestCase):
    def setUp(self):
        self.answers = {("apps", "list"): "nextcloud\tavailable\n", ("ct", "list"): "web\tRUNNING\n", ("status",): "storage\tunlocked\n"}

        def fake_run(cmd, stdin=None, timeout=10):
            return 0, self.answers.get(tuple(cmd[2:]), "")
        self.real_run, ws._run = ws._run, fake_run
        self.tmp = tempfile.mkdtemp()
        os.makedirs(os.path.join(self.tmp, "assets"))
        cfg = ws.Config()
        cfg.root, cfg.workgroup, cfg.realm, cfg.fail_delay, cfg.hs = self.tmp, "HOME", "ad.home.lan", 0, "/nonexistent/hs"
        self.app = ws.App(cfg, FakeAuth(cfg))
        self.bump("baseline")                              # the table exists before the first round of the watcher (its baseline)
        self.app.events.start_watch()                      # the real watcher at its real pace (events_watch = 1 s)
        self.srv = ws.Server(("127.0.0.1", 0), ws.make_handler(self.app))
        self.port = self.srv.server_address[1]
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()
        c = http.client.HTTPConnection("127.0.0.1", self.port)
        c.request("POST", "/api/login", json.dumps({"realm": "domain", "user": "anna", "password": "pw"}),
                  {"Content-Type": "application/json", "Origin": "http://127.0.0.1:%d" % self.port})
        self.ck = {"Cookie": (c.getresponse().getheader("Set-Cookie") or "").split(";")[0]}
        c.close()
        self.pages = []
        time.sleep(1.5)

    def tearDown(self):
        for p in self.pages:
            p.stop = True
        ws._run = self.real_run
        self.srv.shutdown()
        self.srv.server_close()

    def bump(self, topic):
        """what live_refresh does for a change script"""
        subprocess.run([sys.executable, os.path.join(root, "scripts", "state-db.py"), "topic-bump", topic], check=True, capture_output=True)

    def act(self, page, key, new, topic, limit):
        """the action: change the server, say so; then wait for the OPEN page. -> seconds until the page showed the new state."""
        self.answers[key] = new
        reads = page.reads
        t0 = time.monotonic()
        self.bump(topic)
        got = page.changed.wait(limit)
        took = time.monotonic() - t0
        self.assertTrue(got, "the page did not change within %.0f s" % limit)
        self.assertEqual(page.shown, new)
        self.assertEqual(page.reads, reads + 1, "one read per change, no polling")
        print("  -> %s: %.2f s (limit %.0f)" % (topic, took, limit))
        return took

    def open(self, path, topic):
        p = Page(self.port, self.ck, path, topic)
        self.pages.append(p)
        return p

    def test_install_an_app_shows_on_the_open_apps_page(self):
        p = self.open("/api/sys/apps/list", "apps-list")
        self.assertEqual(p.shown, "nextcloud\tavailable\n")
        self.act(p, ("apps", "list"), "nextcloud\tinstalled\n", "apps-list", LIMIT["hook"])

    def test_stop_a_container_shows_on_the_open_instances_page(self):
        p = self.open("/api/sys/ct/list", "ct-list")
        self.assertEqual(p.shown, "web\tRUNNING\n")
        self.act(p, ("ct", "list"), "web\tSTOPPED\n", "ct-list", LIMIT["hook"])

    def test_lock_the_storage_shows_on_the_open_summary_page(self):
        p = self.open("/api/sys/status", "status")
        self.assertEqual(p.shown, "storage\tunlocked\n")
        self.act(p, ("status",), "storage\tlocked\n", "status", LIMIT["hook"])

    def test_the_limit_fails_the_test_when_it_is_passed(self):
        p = self.open("/api/sys/apps/list", "apps-list")
        with self.assertRaises(AssertionError):
            self.act(p, ("apps", "list"), "nextcloud\tinstalled\n", "apps-list", 0.0)

    def test_a_topic_of_another_page_does_not_change_this_page(self):
        p = self.open("/api/sys/ct/list", "ct-list")
        self.bump("apps-list")
        self.assertFalse(p.changed.wait(2.5))
        self.assertEqual(p.reads, 1)


if __name__ == "__main__":
    unittest.main()
