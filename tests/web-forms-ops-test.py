#!/usr/bin/env python3
"""scripts/web-serve.py CHANGES for the ops forms: system reboot|shutdown, pc wake, expiry add|remove (what passes, what is refused, the plan shapes)."""
import importlib.util
import os
import tempfile
import unittest

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("web_serve", os.path.join(here, "..", "scripts", "web-serve.py"))
ws = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ws)
_caps = tempfile.NamedTemporaryFile("w", suffix=".caps", delete=False)
_caps.write("")
_caps.close()
os.environ["HS_CAPABILITIES_FILE"] = _caps.name
os.environ["HS_STATE_DIR"] = tempfile.mkdtemp()
ws.ext_refresh(force=True)


def ok(area, args, confirm=None, stdin=None):
    return ws.validate_change({"area": area, "args": args, "confirm": confirm, "stdin": stdin}) is not None


class Changes(unittest.TestCase):
    def test_system_power(self):
        self.assertTrue(ok("system", ["reboot"]))
        self.assertTrue(ok("system", ["shutdown"]))
        self.assertTrue(ok("system", ["reboot"], confirm="reboot"))
        self.assertTrue(ok("system", ["update"]))
        for bad in (["reboot", "--force"], ["poweroff"], ["reboot;x"], ["REBOOT"], []):
            self.assertFalse(ok("system", bad), bad)
        self.assertFalse(ok("system", ["reboot"], stdin="x"))

    def test_marketplace(self):
        for good in (["install", "arr"], ["install", "arr", "--repo", "recipes"], ["update", "arr"], ["remove", "arr"], ["fetch"], ["fetch", "recipes"],
                     ["repo-add", "friends", "https://github.com/someone/recipes"], ["repo-add", "friends", "git@github.com:someone/recipes.git"],
                     ["repo-remove", "friends"]):
            self.assertTrue(ok("pkg", good), good)
        for bad in (["install"], ["install", "Arr"], ["install", "arr;x"], ["install", "arr", "--repo"], ["install", "arr", "--force"], ["update", "arr", "x"],
                    ["remove"], ["fetch", "a b"], ["repo-add", "friends"], ["repo-add", "friends", "file:///tmp/x"], ["repo-add", "friends", "/tmp/x"],
                    ["repo-add", "friends", "https://x y"], ["repo-add", "Friends", "https://github.com/a/b"], ["repo-remove"], ["wipe", "arr"]):
            self.assertFalse(ok("pkg", bad), bad)
        self.assertTrue(ok("pkg", ["repo-add", "friends", "https://github.com/someone/recipes"], stdin="ssh-ed25519 AAAAC3Nza"))   # the key is the one stdin line
        for words in (("pkg", "market"), ("pkg", "repos")):
            self.assertEqual(ws.READS[words]["kind"], "tsv", words)
            self.assertNotIn("args", ws.READS[words], words)

    def test_new_reads(self):
        for words in (("hardware",), ("encryption", "list"), ("vault", "usage"), ("vault", "uses")):
            self.assertEqual(ws.READS[words]["kind"], "tsv", words)
            self.assertNotIn("args", ws.READS[words], words)            # nothing from the browser reaches these commands
            self.assertNotIn("query", ws.READS[words], words)
        for words in (("encryption",), ("vault",), ("unlock", "list"), ("pc", "state"), ("vault", "list", "x"), ("encryption", "list", "x")):
            self.assertNotIn(words, ws.READS, words)

    def test_expiry_add(self):
        self.assertTrue(ok("expiry", ["add", "DC certificate", "--date", "2028-09-01"]))
        self.assertTrue(ok("expiry", ["add", "token", "--date", "2027-01-31", "--renew", "Cloudflare dashboard > Tunnels"]))
        self.assertTrue(ok("expiry", ["add", "token", "--renew", "x", "--date", "2027-01-31"]))
        self.assertTrue(ok("expiry", ["add", "token"]))      # the plan answers "needs date"
        bad = [
            ["add", "token", "--date", "tomorrow"],
            ["add", "token", "--date", "2028-9-1"],
            ["add", "token", "--date", "2028-09-01", "--date", "2028-09-02"],
            ["add", "token", "--date", "2028-09-01", "--note", "x"],
            ["add", "token", "--date", "2028-09-01", "--renew", "a\tb"],
            ["add", "token", "--date", "2028-09-01", "--renew", "a\nb"],
            ["add", "token", "--date", "2028-09-01", "--renew", "x" * 121],
            ["add", "#x", "--date", "2028-09-01"],
            ["add", "../x", "--date", "2028-09-01"],
            ["add", "a" * 70, "--date", "2028-09-01"],
            ["add", "tok;en", "--date", "2028-09-01"],
            ["add"],
        ]
        for b in bad:
            self.assertFalse(ok("expiry", b), b)

    def test_expiry_remove(self):
        self.assertTrue(ok("expiry", ["remove", "DC certificate"]))
        for bad in (["remove"], ["remove", "x", "y"], ["remove", "$(x)"], ["remove", " x"], ["delete", "x"]):
            self.assertFalse(ok("expiry", bad), bad)

    def test_health(self):
        for good in (["ack", "backup:stale"], ["ack", "zfs:tank:scrub-old"], ["ack", "backup:stale", "--for", "7d", "--note", "disk swap on Friday"], ["unack", "expiry:DC certificate (old):soon"], ["resume"]):
            self.assertTrue(ok("health", good), good)
        for bad in (["ack"], ["ack", "x;y"], ["ack", "$(x)"], ["ack", ":x"], ["ack", "a\tb"], ["ack", "a", "b"], ["resume", "x"],
                    ["unack"], ["frob", "x"], ["ack", "x" * 102], ["ack", "a", "--for", "7"], ["ack", "a", "--for", "0x"], ["ack", "a", "--note", "x	y"], ["ack", "a", "--note", "x" * 201]):
            self.assertFalse(ok("health", bad), bad)

    def test_service_add(self):
        self.assertTrue(ok("routes", ["add", "wiki", "--port", "3000", "--container", "wiki"]))
        self.assertTrue(ok("routes", ["add", "wiki", "--port", "80", "--host", "10.0.0.5", "--title", "Wiki", "--names", "wiki,notes",
                                      "--exposure", "public-ok", "--public-path", "/hook", "--public-path", "/api", "--want", "reverse-proxy,dashboard"]))
        bad = [
            ["add", "Wiki", "--port", "80", "--host", "x"],
            ["add", "wiki", "--port", "80x", "--host", "x"],
            ["add", "wiki", "--port", "80", "--host", "x;y"],
            ["add", "wiki", "--port", "80", "--host", "x", "--exposure", "open"],
            ["add", "wiki", "--port", "80", "--host", "x", "--port", "81"],
            ["add", "wiki", "--port", "80", "--host", "x", "--public-path", "/a/../b;"],
            ["add", "wiki", "--port", "80", "--host", "x", "--title", "a\nb"],
            ["add", "wiki", "--port", "80", "--host", "x", "--icon"],
            ["add", "wiki", "--port", "80", "--host", "x", "--scheme", "ftp"],
            ["add"],
        ]
        for b in bad:
            self.assertFalse(ok("routes", b), b)
        self.assertFalse(ok("routes", ["add", "wiki", "--port", "80", "--host", "x"], stdin="x"))     # nothing here takes a password

    def test_service_set(self):
        self.assertTrue(ok("routes", ["set", "wiki", "--local", "yes"]))
        self.assertTrue(ok("routes", ["set", "wiki", "--public", "yes", "--public-name", "wiki.example.org"]))
        self.assertTrue(ok("routes", ["set", "wiki", "--public", "no", "--local", "no"]))
        for b in (["set"], ["set", "Wiki", "--local", "yes"], ["set", "wiki", "--local", "maybe"], ["set", "wiki", "--public-name", "x;y"],
                  ["set", "wiki", "--port", "80"], ["set", "wiki", "--local"]):
            self.assertFalse(ok("routes", b), b)

    def test_offer(self):
        self.assertTrue(ok("peers", ["offer", "cousin", "media"]))
        self.assertTrue(ok("peers", ["offer", "cousin", "media", "--new-password"]))
        for b in (["offer", "Cousin", "media"], ["offer", "cousin"], ["offer", "cousin", "media", "--yes"], ["offer", "cousin", "me dia"],
                  ["offer", "cousin", "media", "--new-password", "--new-password"]):
            self.assertFalse(ok("peers", b), b)
        self.assertFalse(ok("peers", ["offer", "cousin", "media"], stdin="x"))      # the password is made on the server, never sent

    def test_secret_lines(self):
        d = ws.parse_change("status\tdone\nsecret\tlogin\tremote-bob\nsecret\tdomain\tHOME\nsecret\thost\tme.local\nsecret\tpassword\tPw-Aa1\nsecret\tother\tx\n", 0)
        self.assertEqual(d["secret"], {"login": "remote-bob", "domain": "HOME", "host": "me.local", "password": "Pw-Aa1"})
        self.assertNotIn("secret", ws.parse_change("status\tdone\n", 0))

    def test_fix_lines_of_a_refused_plan(self):
        d = ws.parse_change("status\trefused\nreason\tno route\nfix\ths ext x expose public <name>\nfix\ths services apply\n", 1)
        self.assertEqual(d["fixes"], ["hs ext x expose public <name>", "hs services apply"])
        self.assertEqual(ws.parse_change("status\tdone\n", 0)["fixes"], [])

    def test_plan_shapes(self):
        d = ws.parse_change("status\tok\nheading\treboot the server\nstep\ta\nwarn\tLOCKED\ndanger\tgoes down\ncommand\tbash power.sh reboot --yes\n"
                            "confirm_name\treboot\nlong\tno\n", 0)
        self.assertEqual(d["status"], "ok")
        self.assertEqual(d["confirm_name"], "reboot")
        self.assertFalse(d["long"])
        self.assertEqual([s[0] for s in d["steps"]], ["step", "warn", "danger"])
        d = ws.parse_change("status\trefused\nreason\tNot now\nreason\tbackup is running\n", 1)
        self.assertEqual(d["status"], "refused")
        d = ws.parse_change("status\tneeds\nneeds\tdate\n", 2)
        self.assertEqual(d["needs"], ["date"])
        d = ws.parse_change("status\tdone\n", 0)
        self.assertEqual(d["status"], "done")
        d = ws.parse_change("status\tstarted\nunit\ths-job-system-reboot-031500\n", 0)
        self.assertRegex(d["unit"], ws.UNIT)

    def test_one_install_plan_lines(self):
        out = ("status\tok\nheading\tInstall jellyfin\npackage\tjellyfin\nkind\trecipe\nrepo\trecipes\nversion\t1.2.0\ntag\tv1.2.0\ncommit\tabc123\n"
               "title\tJellyfin\ndescription\tMedia server\ncreates\ta container\ncreates\ta share\nneed\tdocker\tmissing\tneeds docker\tyes\nneeds\tdate\n"
               "ask\tPORT\tPort\ttext\t-\t8096\t[0-9]+\t-\nask\tKIND\tKind\tchoice\ta,b\ta\t-\tPORT=1\njobstep\tread\tFetch the release\njobstep\trun\tSet it up\n"
               "note\thello\nlong\tyes\n")
        d = ws.parse_change(out, 0)
        for k, v in (("package", "jellyfin"), ("kind", "recipe"), ("repo", "recipes"), ("version", "1.2.0"), ("tag", "v1.2.0"), ("commit", "abc123"),
                     ("title", "Jellyfin"), ("description", "Media server")):
            self.assertEqual(d[k], v)
        self.assertEqual(d["creates"], ["a container", "a share"])
        self.assertEqual(d["needl"], [["docker", "missing", "needs docker", "yes"]])
        self.assertEqual(d["needs"], ["date"])
        self.assertEqual(d["asks"], [["PORT", "Port", "text", "-", "8096", "[0-9]+", "-"], ["KIND", "Kind", "choice", "a,b", "a", "-", "PORT=1"]])
        self.assertEqual(d["jobsteps"], [["read", "Fetch the release"], ["run", "Set it up"]])
        self.assertEqual(d["steps"], [["note", "hello"]])
        self.assertTrue(d["long"])
        e = ws.parse_change("status\tdone\n", 0)
        for k in ("creates", "needl", "asks", "jobsteps"):
            self.assertNotIn(k, e)


if __name__ == "__main__":
    unittest.main()
