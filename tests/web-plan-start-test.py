#!/usr/bin/env python3
"""scripts/web-serve.py: a plan that takes seconds, then a start, through the real server and a real (slow) fake `hs`: the way the browser does it
(hover prefetch plan, click plan, start, on keep-alive connections, also pipelined). The start must arrive and a job unit must come back; a plan the
browser dropped is logged. Posix only (the fake hs is a shell script)."""
import http.client
import importlib.util
import io
import contextlib
import json
import os
import socket
import stat
import tempfile
import threading
import time
import unittest

here = os.path.dirname(os.path.abspath(__file__))
os.environ["HS_WEB_QUIET"] = "1"
os.environ["HS_STATE_DIR"] = tempfile.mkdtemp()
spec = importlib.util.spec_from_file_location("web_serve", os.path.join(here, "..", "scripts", "web-serve.py"))
ws = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ws)

SLOW = float(os.environ.get("PLAN_TEST_SLOW", "2.5"))
FAKE_HS = """#!/bin/sh
# hs sys release plan|start channel beta
case "$3" in
  plan) sleep %s; printf 'status\tok\nheading\tSwitch\nstep\tdo it\n' ;;
  start) printf 'status\tstarted\nunit\tjob-1\n' ;;
esac
""" % SLOW


class FakeAuth:
    def __init__(self, cfg): self.cfg = cfg
    def storage_locked(self): return False
    def domain_password_ok(self, user, password): return user == "anna" and password == "pw"
    def domain_is_admin(self, user): return user == "anna"
    def domain_role(self, user): return "admin" if user == "anna" else None
    def local_fingerprint(self, user, fresh=False): return ""
    def local_password_ok(self, user, password): return False


@unittest.skipUnless(os.name == "posix", "needs a shell script as hs")
class PlanThenStart(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        os.makedirs(os.path.join(self.tmp, "assets"))
        hs = os.path.join(self.tmp, "hs")
        with open(hs, "w") as f:
            f.write(FAKE_HS)
        os.chmod(hs, os.stat(hs).st_mode | stat.S_IXUSR)
        cfg = ws.Config()
        cfg.root, cfg.workgroup, cfg.realm, cfg.fail_delay, cfg.hs = self.tmp, "HOME", "ad.home.lan", 0, hs
        self.app = ws.App(cfg, FakeAuth(cfg))
        self.srv = ws.Server(("127.0.0.1", 0), ws.make_handler(self.app))
        self.port = self.srv.server_address[1]
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()
        c = self.conn()
        c.request("POST", "/api/login", json.dumps({"realm": "domain", "user": "anna", "password": "pw"}), self.h())
        r = c.getresponse()
        self.csrf = json.loads(r.read())["csrf"]
        self.cookie = (r.getheader("Set-Cookie") or "").split(";")[0]

    def tearDown(self):
        self.srv.shutdown()
        self.srv.server_close()

    def conn(self):
        return http.client.HTTPConnection("127.0.0.1", self.port, timeout=30)

    def h(self):
        h = {"Content-Type": "application/json", "Origin": "http://127.0.0.1:%d" % self.port}
        if getattr(self, "cookie", None):
            h.update({"Cookie": self.cookie, "X-CSRF-Token": self.csrf})
        return h

    BODY = {"area": "release", "args": ["channel", "beta"]}

    def post(self, c, path, out=None):
        c.request("POST", path, json.dumps(self.BODY), self.h())
        r = c.getresponse()
        d = json.loads(r.read())
        if out is not None:
            out.append(d)
        return d

    def test_prefetch_click_then_start(self):
        a, b, got = self.conn(), self.conn(), []
        t1 = threading.Thread(target=self.post, args=(a, "/api/plan", got))      # the hover
        t1.start()
        time.sleep(0.5)
        t2 = threading.Thread(target=self.post, args=(b, "/api/plan", got))      # the click, while the first still runs
        t2.start()
        t1.join(); t2.join()
        self.assertEqual([g["status"] for g in got], ["ok", "ok"])
        r = self.post(a, "/api/start")      # the same keep-alive connection that carried the hover
        self.assertEqual((r["status"], r["unit"]), ("started", "job-1"))

    def test_pipelined_plan_and_start_on_one_connection(self):
        s = socket.create_connection(("127.0.0.1", self.port), timeout=30)
        body = json.dumps(self.BODY)
        req = lambda p: ("POST %s HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nOrigin: http://127.0.0.1:%d\r\nContent-Type: application/json\r\nCookie: %s\r\nX-CSRF-Token: %s\r\nContent-Length: %d\r\n\r\n%s"
                         % (p, self.port, self.port, self.cookie, self.csrf, len(body), body)).encode()
        s.sendall(req("/api/plan") + req("/api/start"))
        f = s.makefile("rb")
        answers = []
        for _ in range(2):
            line = f.readline()
            self.assertTrue(line.startswith(b"HTTP/1.1 200"), line)
            n = 0
            while True:
                h = f.readline()
                if h in (b"\r\n", b""):
                    break
                if h.lower().startswith(b"content-length"):
                    n = int(h.split(b":")[1])
            answers.append(json.loads(f.read(n)))
        self.assertEqual([x["status"] for x in answers], ["ok", "started"])

    def test_dropped_plan_is_logged_and_start_still_works(self):
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            s = socket.create_connection(("127.0.0.1", self.port), timeout=30)
            body = json.dumps(self.BODY)
            s.sendall(("POST /api/plan HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nOrigin: http://127.0.0.1:%d\r\nContent-Type: application/json\r\nCookie: %s\r\nX-CSRF-Token: %s\r\nContent-Length: %d\r\n\r\n%s"
                       % (self.port, self.port, self.cookie, self.csrf, len(body), body)).encode())
            time.sleep(0.6)
            s.close()               # the browser aborts the older question
            r = self.post(self.conn(), "/api/start")
            time.sleep(SLOW)         # the dropped plan notices the close within a poll
        self.assertEqual(r["unit"], "job-1")
        self.assertIn("web plan dropped", buf.getvalue())


if __name__ == "__main__":
    unittest.main()
