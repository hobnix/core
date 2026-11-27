#!/usr/bin/env python3
"""scripts/web-serve.py: the `shares` entries of CHANGES that the share forms use (add, perm, rename, delete, purge, restore)."""
import contextlib
import http.client
import importlib.util
import io
import json
import os
import tempfile
import threading
import unittest

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("web_serve", os.path.join(here, "..", "scripts", "web-serve.py"))
ws = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ws)
os.environ["HS_WEB_QUIET"] = "1"

SID = "S-1-5-21-1111111111-2222222222-3333333333-1105"
LONG = "data-02-communityapplicationsappdatabackup"     # 42 characters: adopting a disk made it (issue 1245)
MAX = "a" * 80                                          # the longest name Samba takes
KEPT_DAY = ".deleted-20261012"


def ok(args, area="shares"):
    return ws.validate_change({"area": area, "args": args}) is not None


class Shapes(unittest.TestCase):
    def test_add(self):
        self.assertTrue(ok(["media", "add", "--kind", "shares"]))
        self.assertTrue(ok(["media", "add", "--kind", "sensitive", "--ct", "jellyfin", "--path", "/media", "--as", "1000:1000"]))
        self.assertTrue(ok(["media", "add", "--path", "/srv/media", "--ct", "jellyfin", "--kind", "shares"]))   # any order
        self.assertTrue(ok(["media", "add", "--kind", "shares", "--tier", "fast"]))
        self.assertFalse(ok(["media", "add", "--kind", "shares", "--tier", "slow"]))
        self.assertTrue(ok(["media", "add"]))                       # the script answers `needs kind`

    def test_add_refused(self):
        for a in (["Media", "add", "--kind", "shares"], ["me dia", "add"], ["-x", "add"], ["../x", "add"],
                  ["media", "add", "--kind", "other"], ["media", "add", "--ct", "Jelly"], ["media", "add", "--ct", "a;b"],
                  ["media", "add", "--kind", "shares", "--kind", "sensitive"],
                  ["media", "add", "--path", "media"], ["media", "add", "--path", "/a/../b"], ["media", "add", "--path", "/.."],
                  ["media", "add", "--as", "1000"], ["media", "add", "--as", "a:b"], ["media", "add", "--confirm", "media"],
                  ["media", "add", "--kind"]):
            self.assertFalse(ok(a), a)

    def test_perm(self):
        self.assertTrue(ok(["media", "perm", "--set", SID + "=read"]))
        self.assertTrue(ok(["media", "perm", "--set", "S-1-1-0=none", "--set", SID + "=full"]))
        self.assertTrue(ok(["media", "perm"]))

    def test_perm_refused(self):
        for a in (["media", "perm", "--set", SID + "=admin"], ["media", "perm", "--set", "HOME\\anna=read"], ["media", "perm", "--set", SID],
                  ["media", "perm", "--set", "S-1-=read"], ["media", "perm", "--set", SID + "=read;x"], ["media", "perm", "--set", "x" + SID + "=read"],
                  ["media", "perm", "--set", SID + "=read\n"], ["media", "perm", "--to", "on"]):
            self.assertFalse(ok(a), a)

    def test_rename_delete_purge(self):
        self.assertTrue(ok(["media", "rename", "--to", "movies"]))
        self.assertTrue(ok(["media", "delete"]))
        self.assertTrue(ok(["media.deleted-20261012", "purge"]))
        for a in (["media", "rename"], ["media", "rename", "--to", "Movies"], ["media", "rename", "--to", "a/b"], ["media", "rename", "--to", ".."],
                  ["media", "delete", "--confirm", "x"], ["media", "purge"], ["media.deleted-2026", "purge"], ["media.deleted-20261012", "delete"],
                  ["../media.deleted-20261012", "purge"], ["media.deleted-20261012x", "purge"]):
            self.assertFalse(ok(a), a)

    def test_undelete_kept(self):
        self.assertTrue(ok(["media.deleted-20261012", "undelete"]))
        for a in (["media", "undelete"], ["media.deleted-2026", "undelete"], ["../media.deleted-20261012", "undelete"],
                  ["media.deleted-20261012", "undelete", "--confirm", "x"], ["media.deleted-20261012x", "undelete"], ["media.deleted-20261012", "restore"]):
            self.assertFalse(ok(a), a)

    def test_restore(self):
        self.assertTrue(ok(["media", "restore", "--snapshot", "latest"]))
        self.assertTrue(ok(["media", "restore", "--snapshot", "a1b2c3d4", "--path", "photos/2025 trip"]))
        self.assertTrue(ok(["media", "restore", "--snapshot", "latest", "--path", "/docs/a.txt"]))
        for a in (["media", "restore", "--snapshot", "-x"], ["media", "restore", "--snapshot", "a b"], ["media", "restore", "--snapshot", "latest", "--path", "../etc"],
                  ["media", "restore", "--snapshot", "latest", "--path", "a/../../b"], ["media", "restore", "--snapshot", "latest", "--path", "..\\x"],
                  ["media", "restore", "--snapshot", "latest", "--path", "-rf"], ["media", "restore", "--snapshot", "latest", "--path", "a;b"],
                  ["media", "restore", "--snapshot", "latest", "--path", "a$(x)"]):
            self.assertFalse(ok(a), a)

    def test_old_shapes_still_work(self):
        for a in (["media", "snapshot"], ["media", "backup", "--to", "on"], ["media", "cache", "--to", "off"], ["media", "rollback", "--snapshot", "snap1"]):
            self.assertTrue(ok(a), a)

    def test_other_areas_unchanged(self):
        self.assertFalse(ok(["media", "add"], area="ct"))
        self.assertFalse(ok(["media", "perm", "--set", SID + "=read"], area="users"))

    def test_no_stdin(self):
        self.assertIsNone(ws.validate_change({"area": "shares", "args": ["media", "add", "--kind", "shares"], "stdin": "x"}))

    def test_confirm_word_for_delete(self):
        self.assertIsNotNone(ws.validate_change({"area": "shares", "args": ["media", "delete"], "confirm": "media"}))
        self.assertIsNone(ws.validate_change({"area": "shares", "args": ["media", "delete"], "confirm": "me;dia"}))


class LongNames(unittest.TestCase):
    """issue 1245: a share that exists can be changed up to 80 characters; a new name stays at most 41."""

    def existing(self, name):
        return [[name, "delete"], [name, "snapshot"], [name, "repair"], [name, "backup", "--to", "on"], [name, "perm", "--set", SID + "=read"],
                [name, "visibility", "--to", "hidden"], [name, "rename", "--to", "movies"], [name, "restore", "--snapshot", "latest"],
                [name, "rollback", "--snapshot", "snap1"], [name, "parity-skip", "--folder", "downloads"], [name, "parity-limit", "--to", "off"],
                [name + KEPT_DAY, "purge"], [name + KEPT_DAY, "undelete"]]

    def test_long_existing_share(self):
        self.assertEqual(len(LONG), 42)
        for name in (LONG, MAX):
            for a in self.existing(name):
                self.assertTrue(ok(a), a)

    def test_81_refused(self):
        for a in self.existing(MAX + "a"):
            self.assertFalse(ok(a), a)

    def test_class_stays_strict(self):
        for bad in ("-" + LONG, "--confirm", "../" + LONG, LONG + "/..", LONG + "/x", "." + LONG, LONG + ".x", LONG.upper(), LONG + " x",
                    LONG + "\n", LONG + ";x", ""):
            for a in self.existing(bad):
                self.assertFalse(ok(a), a)

    def test_confirm_word(self):
        # delete types the share, purge types the kept folder (80 + 17 characters)
        for name, action in ((LONG, "delete"), (MAX, "delete"), (MAX + KEPT_DAY, "purge")):
            self.assertIsNotNone(ws.validate_change({"area": "shares", "args": [name, action], "confirm": name}), name)
        self.assertIsNone(ws.validate_change({"area": "shares", "args": [LONG, "delete"], "confirm": "a" * 98}))

    def test_create_limit_unchanged(self):
        self.assertTrue(ok(["a" * 41, "add", "--kind", "shares"]))
        self.assertFalse(ok(["a" * 42, "add", "--kind", "shares"]))
        self.assertTrue(ok([LONG, "rename", "--to", "a" * 41]))
        self.assertFalse(ok(["media", "rename", "--to", "a" * 42]))

    def test_other_places_a_share_is_named(self):
        for name, want in ((LONG, True), (MAX, True), (MAX + "a", False), ("-x", False), ("a/b", False), ("..", False)):
            self.assertEqual(ok(["Family", "group-add", "--access", name + "=read"], area="users"), want, name)
            self.assertEqual(ok(["usb", "temp-copy", "--to", name], area="disk"), want, name)
            self.assertEqual(bool(ws.re.fullmatch(ws.FM_LOC, "share:" + name)), want, name)
            self.assertEqual(bool(ws.re.fullmatch(ws.READS[("share", "parity", "state")]["args"][0], name)), want, name)

    def test_backup_switch(self):
        for name, want in ((LONG, True), (MAX, True), (MAX + "a", False), ("-x", False), ("a/b", False)):
            self.assertEqual(ok(["toggle", "--name", name, "--kind", "shares", "--to", "off"], area="backup"), want, name)

    def test_reads_of_a_long_share(self):
        for word in ("acl", "visible", "mounts", "history"):
            pat = ws.READS[("shares", word)]["args"][0]
            self.assertTrue(ws.re.fullmatch(pat, MAX), word)
            self.assertTrue(ws.re.fullmatch(pat, "Photos_2024"), word)
            for bad in (MAX + "a", "-x", "a/b", "..", "a b"):
                self.assertIsNone(ws.re.fullmatch(pat, bad), (word, bad))

    def test_reason(self):
        why = ws.share_name_refusal({"area": "shares", "args": [MAX + "a", "delete"]})
        self.assertIn("longer than 80 characters", why)
        self.assertIn("rename", why)
        for body in ({"area": "shares", "args": ["a" * 42, "add"]}, {"area": "shares", "args": ["media", "rename", "--to", "a" * 42]}):
            self.assertIn("at most 41 characters", ws.share_name_refusal(body))
        for body in ({"area": "shares", "args": [MAX + "a" + KEPT_DAY, "purge"]},
                     {"area": "users", "args": ["Family", "group-add", "--access", MAX + "a=read"]}):
            self.assertIn("longer than 80 characters", ws.share_name_refusal(body))
        # not a length problem: the general refusal stays
        for body in ({"area": "shares", "args": [LONG, "delete"]}, {"area": "shares", "args": ["../" + MAX, "delete"]},
                     {"area": "shares", "args": ["-" + MAX, "delete"]}, {"area": "shares", "args": ["media" + KEPT_DAY, "purge"]},
                     {"area": "shares", "args": [MAX, "purge"]}, {"area": "ct", "args": [MAX + "a", "delete"]},
                     {"area": "shares", "args": "x"}, {"area": "shares", "args": [1, 2]}, {"area": "shares", "args": []}, {}):
            self.assertIsNone(ws.share_name_refusal(body), body)


class FakeAuth:
    def __init__(self, cfg):
        self.cfg = cfg

    def storage_locked(self):
        return False

    def domain_password_ok(self, user, password):
        return True

    def domain_is_admin(self, user):
        return True

    def domain_role(self, user):
        return "admin"

    def local_fingerprint(self, user, fresh=False):
        return ""

    def local_password_ok(self, user, password):
        return False


class Answer(unittest.TestCase):
    """what the page gets for a refused plan and start (real server, fake _run)"""

    def setUp(self):
        tmp = tempfile.mkdtemp()
        with open(os.path.join(tmp, "index.html"), "w") as f:
            f.write("app")
        cfg = ws.Config()
        cfg.root, cfg.workgroup, cfg.realm, cfg.fail_delay, cfg.hs = tmp, "HOME", "ad.home.lan", 0, "/nonexistent/hs"
        self.srv = ws.Server(("127.0.0.1", 0), ws.make_handler(ws.App(cfg, FakeAuth(cfg))))
        self.port = self.srv.server_address[1]
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()
        self.calls = []
        self.real_run = ws._run

        def fake(cmd, stdin=None, timeout=10):
            self.calls.append(cmd)
            return 0, "status\tok\nheading\tx\n"
        ws._run = fake
        _, data, r = self.post("/api/login", {"realm": "domain", "user": "anna", "password": "pw"})
        self.ck = {"Cookie": (r.getheader("Set-Cookie") or "").split(";")[0], "X-CSRF-Token": json.loads(data)["csrf"]}
        self.calls.clear()

    def tearDown(self):
        ws._run = self.real_run
        self.srv.shutdown()
        self.srv.server_close()

    def post(self, path, body, headers=None):
        h = {"Content-Type": "application/json", "Origin": "http://127.0.0.1:%d" % self.port, **(headers or {})}
        c = http.client.HTTPConnection("127.0.0.1", self.port)
        c.request("POST", path, json.dumps(body), h)
        r = c.getresponse()
        data = r.read()
        c.close()
        return r.status, data, r

    def test_long_share_reaches_the_script(self):
        with contextlib.redirect_stdout(io.StringIO()):
            status, _, _ = self.post("/api/plan", {"area": "shares", "args": [LONG, "delete"]}, self.ck)
        self.assertEqual(status, 200)
        self.assertEqual(self.calls[-1][-4:], ["shares", "plan", LONG, "delete"])

    def test_too_long_says_so(self):
        for verb in ("plan", "start"):
            status, data, _ = self.post("/api/" + verb, {"area": "shares", "args": [MAX + "a", "delete"]}, self.ck)
            out = json.loads(data)
            self.assertEqual((status, out.get("code")), (400, "share.name-too-long"), out)
            self.assertIn("longer than 80 characters", out["error"])
        status, data, _ = self.post("/api/plan", {"area": "shares", "args": ["../x", "delete"]}, self.ck)
        self.assertEqual((status, json.loads(data)), (400, {"error": "That change is not allowed."}))
        self.assertEqual(self.calls, [])


if __name__ == "__main__":
    unittest.main(verbosity=1)
