#!/usr/bin/env python3
"""scripts/web-serve.py: GET /api/pkg/asset/<repo>/<name>/<file> (the pictures of a package, #474). Session, role of the row `pkg asset`,
name and path checks, the type checked against the bytes, the size cap (read bounded), and nosniff with a sandbox CSP on success.
Real HTTP server on a free port; `hs` is a fake script that answers by file name."""
import http.client
import importlib.util
import json
import os
import stat
import tempfile
import threading
import unittest

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
spec = importlib.util.spec_from_file_location("web_serve", os.path.join(root, "scripts", "web-serve.py"))
ws = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ws)
os.environ["HS_WEB_QUIET"] = "1"
USERS = {"vic": "viewer", "mia": "app-manager"}

FAKE_HS = r"""#!/usr/bin/env bash
# hs sys pkg asset <name> <file> --repo <repo>
[ "$1 $2 $3" = "sys pkg asset" ] || exit 2
printf '%s %s %s %s\n' "$4" "$5" "$6" "$7" >> "${0%/*}/calls"
case "$5" in
  icon.svg) printf '<svg xmlns="http://www.w3.org/2000/svg"/>' ;;
  shots/a.png) printf '\x89PNG\r\n\x1a\nrest' ;;
  shots/a.webp) printf 'RIFF1234WEBPrest' ;;
  fake.png) printf '<svg onload="x"/>' ;;
  huge.png) printf '\x89PNG\r\n\x1a\n'; head -c 400000 /dev/zero ;;
  *) echo "no such store file" >&2; exit 1 ;;
esac
"""


class FakeAuth:
    def __init__(self, cfg):
        self.cfg = cfg

    def local_fingerprint(self, user, fresh=False):
        return "fp"

    def storage_locked(self):
        return False

    def domain_password_ok(self, user, password):
        return user in USERS

    def domain_role(self, user):
        return USERS.get(user)

    def local_password_ok(self, user, password):
        return user == "adminuser" and password == "pw"


class Asset(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        with open(os.path.join(self.tmp, "index.html"), "w") as f:
            f.write("<html>app</html>")
        hs = os.path.join(self.tmp, "hs")
        with open(hs, "w", newline="\n") as f:
            f.write(FAKE_HS)
        os.chmod(hs, os.stat(hs).st_mode | stat.S_IEXEC)
        os.environ["HS_STATE_DIR"] = self.tmp
        cfg = ws.Config()
        cfg.root, cfg.workgroup, cfg.realm, cfg.fail_delay, cfg.hs, cfg.session_file = self.tmp, "HOME", "ad.home.lan", 0, hs, ""
        cfg.roles_file = os.path.join(root, "scripts", "lib", "sys-roles.tsv")
        ws._pkg_assets.clear()
        self.app = ws.App(cfg, FakeAuth(cfg))
        self.srv = ws.Server(("127.0.0.1", 0), ws.make_handler(self.app))
        self.port = self.srv.server_address[1]
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()
        self.cookies = {}

    def tearDown(self):
        self.srv.shutdown()
        self.srv.server_close()
        os.environ.pop("HS_STATE_DIR", None)

    def cookie(self, user):
        if user not in self.cookies:
            realm = "local" if user == "adminuser" else "domain"
            c = http.client.HTTPConnection("127.0.0.1", self.port)
            c.request("POST", "/api/login", json.dumps({"realm": realm, "user": user, "password": "pw"}),
                      {"Content-Type": "application/json", "Origin": "http://127.0.0.1:%d" % self.port})
            r = c.getresponse()
            r.read()
            self.cookies[user] = (r.getheader("Set-Cookie") or "").split(";")[0]
            c.close()
        return self.cookies[user]

    def get(self, path, user="adminuser"):
        c = http.client.HTTPConnection("127.0.0.1", self.port)
        c.request("GET", path, headers={"Cookie": self.cookie(user)} if user else {})
        r = c.getresponse()
        body = r.read()
        headers = {k.lower(): v for k, v in r.getheaders()}
        csp = r.msg.get_all("Content-Security-Policy") or []
        c.close()
        return r.status, headers, csp, body

    def calls(self):
        try:
            with open(os.path.join(self.tmp, "calls")) as f:
                return f.read().splitlines()
        except OSError:
            return []

    def test_needs_a_session(self):
        self.assertEqual(self.get("/api/pkg/asset/official/demo/icon.svg", user=None)[0], 401)
        self.assertEqual(self.calls(), [])

    def test_role_of_the_row(self):
        for user in ("vic", "mia"):
            self.assertEqual(self.get("/api/pkg/asset/official/demo/icon.svg", user=user)[0], 403, user)
        self.assertEqual(self.calls(), [])

    def test_bad_names_are_404_and_run_nothing(self):
        for p in ("/api/pkg/asset/Official/demo/icon.svg", "/api/pkg/asset/off.icial/demo/icon.svg", "/api/pkg/asset/official/De-mo/icon.svg",
                  "/api/pkg/asset/official/demo/../x.png", "/api/pkg/asset/official/demo/%2e%2e/x.png", "/api/pkg/asset/official/demo/a%2F..%2Fb.png",
                  "/api/pkg/asset/official/demo/.x.png", "/api/pkg/asset/official/demo/x.gif", "/api/pkg/asset/official/demo/x.html",
                  "/api/pkg/asset/official/demo", "/api/pkg/asset/official/demo/a/b/c/d/e.png"):
            self.assertEqual(self.get(p)[0], 404, p)
        self.assertEqual(self.calls(), [])

    def test_success_headers(self):
        for path, ctype in (("icon.svg", "image/svg+xml"), ("shots/a.png", "image/png"), ("shots/a.webp", "image/webp")):
            s, h, csp, body = self.get("/api/pkg/asset/official/demo/" + path)
            self.assertEqual((s, h["content-type"]), (200, ctype), path)
            self.assertEqual(h["x-content-type-options"], "nosniff")
            self.assertIn("default-src 'none'; style-src 'unsafe-inline'; sandbox", csp)
        self.assertIn("demo icon.svg --repo official", self.calls())

    def test_type_must_match_the_bytes(self):
        self.assertEqual(self.get("/api/pkg/asset/official/demo/fake.png")[0], 404)

    def test_over_the_size_cap(self):
        self.assertEqual(self.get("/api/pkg/asset/official/demo/huge.png")[0], 404)

    def test_refused_by_hs(self):
        self.assertEqual(self.get("/api/pkg/asset/official/demo/missing.png")[0], 404)


if __name__ == "__main__":
    unittest.main()
