"""/api/netmap/stream (scripts/web-serve.py NetmapSampler): one shared sample, only while a stream is open, a limit of streams. No root, no hs."""
import http.client
import importlib.util
import json
import os
import threading
import unittest

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("web_live_test", os.path.join(here, "web-live-test.py"))
wl = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wl)
ws = wl.ws


class Counters:
    """what `hs sys netmap counters` would print; every call is counted"""

    def __init__(self):
        self.calls, self.fail = 0, False

    def __call__(self, cmd, stdin=None, timeout=10):
        self.calls += 1
        if tuple(cmd[2:]) != ("netmap", "counters"):
            return 0, ""
        if self.fail:
            return 1, ""
        return 0, "wan\t%d\t%d\nbridge:br0\t-\t-\ninstance:web\t5\t6\n" % (100 * self.calls, 10 * self.calls)


class Netmap(wl.Base):
    def setUp(self):
        super().setUp()
        self.counters = Counters()
        ws._run = self.counters
        self.cfg.netmap_every = 0.05

    def open(self, headers=None):
        c = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        c.request("GET", "/api/netmap/stream", headers=self.ck if headers is None else headers)
        return c, c.getresponse()

    def data(self, r):
        while True:
            line = r.fp.readline()
            if line.startswith(b"data: ") and len(line) > 8:
                return json.loads(line[6:])

    def test_needs_a_session(self):
        self.assertEqual(self.req("GET", "/api/netmap/stream")[0], 401)

    def test_nothing_is_sampled_while_no_stream_is_open(self):
        threading.Event().wait(0.3)
        self.assertEqual(self.counters.calls, 0)
        self.assertIsNone(self.app.netmap.thread)

    def test_a_sample_arrives_as_rows_and_sampling_stops_with_the_last_stream(self):
        c, r = self.open()
        try:
            self.assertEqual((r.status, r.getheader("Content-Type")), (200, "text/event-stream"))
            d = self.data(r)
            self.assertEqual(d["rows"][0][0], "wan")
            self.assertEqual(d["rows"][1], ["bridge:br0", "-", "-"])
            self.assertIsInstance(d["t"], int)
        finally:
            c.close()
        for _ in range(200):          # the stream notices the closed browser at its next write (a ping at most 5 s later)
            if self.app.netmap.users == 0:
                break
            threading.Event().wait(0.05)
        self.app.netmap.users = 0
        with self.app.netmap.cond:
            self.app.netmap.cond.notify_all()
        threading.Event().wait(0.3)
        n = self.counters.calls
        threading.Event().wait(0.3)
        self.assertEqual(self.counters.calls, n)

    def test_two_streams_share_one_sampler(self):
        a, ra = self.open()
        b, rb = self.open()
        try:
            self.data(ra)
            self.data(rb)
            self.assertEqual(self.app.netmap.users, 2)
            self.assertEqual(threading.enumerate().count(self.app.netmap.thread), 1)
        finally:
            a.close()
            b.close()

    def test_the_limit_is_a_503(self):
        self.cfg.netmap_max = 0
        self.assertEqual(self.req("GET", "/api/netmap/stream", headers=self.ck)[0], 503)

    def test_a_failed_sample_sends_no_old_numbers(self):
        self.counters.fail = True
        s = self.app.netmap._take()
        self.assertIsNone(s)

    def test_defaults(self):
        c = ws.Config()
        self.assertEqual((c.netmap_every, c.netmap_max), (2.0, 4))


if __name__ == "__main__":
    unittest.main()
