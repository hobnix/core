#!/usr/bin/env python3
"""API tokens (ADR 0012 step 17, D4): the store keeps only a hash; a token never has more than its owner's role; a disabled or demoted owner ends the
token within the hour (a fake clock); 60 failures a minute lock a token id for 5 minutes; a token cannot manage tokens, people, secrets or the
unlock; a request with a token runs for `<user> via token <id>`. Real HTTP server on a free port, fake helpers, no domain controller."""
import http.client
import importlib.util
import json
import os
import stat
import sys
import tempfile
import threading
import time
import unittest

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.join(here, "..")
sys.path.insert(0, os.path.join(root, "scripts"))
import token_store as tk  # noqa: E402

spec = importlib.util.spec_from_file_location("web_serve", os.path.join(root, "scripts", "web-serve.py"))
ws = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ws)
os.environ["HS_WEB_QUIET"] = "1"


class Clock:
    def __init__(self, t=1_000_000.0):
        self.t = t

    def __call__(self):
        return self.t


def wrong_of(token):
    """the same id, a different secret"""
    return token[:11] + ("A" if token[11] != "A" else "B") + token[12:]


class StoreTests(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()
        self.st = tk.Store(os.path.join(self.d, "api-tokens.json"))

    def test_only_a_hash_is_stored_and_the_file_is_private(self):
        token, rec = self.st.create("dash", "anna", "domain", "viewer")
        self.assertTrue(tk.TOKEN_RE.fullmatch(token))
        with open(self.st.path, encoding="utf-8") as f:
            raw = f.read()
        self.assertNotIn(token, raw)
        self.assertNotIn(token[3:], raw)
        self.assertIn(tk.token_hash(token), raw)
        if os.name == "posix":
            self.assertEqual(stat.S_IMODE(os.stat(self.st.path).st_mode), 0o600)
        self.assertEqual(rec["id"], token[3:11])
        self.assertEqual(self.st.find(token)["name"], "dash")

    def test_refusals(self):
        self.st.create("dash", "anna", "domain", "viewer")
        for args, why in (
            (("dash", "anna", "domain", "viewer"), "name taken"),
            (("bad name", "anna", "domain", "viewer"), "name shape"),
            (("", "anna", "domain", "viewer"), "name empty"),
            (("x", "anna", "domain", "root"), "unknown role"),
            (("x", "anna", "ldap", "viewer"), "unknown realm"),
            (("x", "anna", "domain", "viewer", 0), "no expiry"),
            (("x", "anna", "domain", "viewer", 366), "more than a year"),
            (("x", "anna", "domain", "viewer", None), "no expiry (None)"),
        ):
            with self.assertRaises(ValueError, msg=why):
                self.st.create(*args)
        with self.assertRaises(ValueError):
            self.st.create("x", "mia", "domain", "admin", 30, "app-manager")      # more than the person who asks
        self.assertEqual(len(self.st.rows()), 1)

    def test_a_default_lifetime_of_90_days_and_revoke(self):
        _, rec = self.st.create("dash", "anna", "domain", "viewer", now=1000)
        self.assertEqual(rec["expires"] - rec["created"], 90 * 86400)
        self.assertFalse(self.st.revoke("dash", owner="mia"))      # somebody else's token
        self.assertTrue(self.st.revoke("dash", owner="anna"))
        self.assertFalse(self.st.revoke("dash"))
        self.assertEqual(self.st.rows(), [])

    def test_a_string_that_is_not_a_token(self):
        self.assertIsNone(self.st.find("hn_short"))
        self.assertIsNone(self.st.find("x" * 46))


class AuthTests(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()
        self.st = tk.Store(os.path.join(self.d, "api-tokens.json"))
        self.clock = Clock()
        self.roles = {"anna": "admin"}
        self.down = False
        self.asked = []

        def resolver(owner, realm):
            self.asked.append(owner)
            if self.down:
                return ("down", None)
            return ("role", self.roles[owner]) if owner in self.roles else ("gone", None)
        self.auth = tk.TokenAuth(self.st, resolver, self.clock)

    def make(self, role="admin", name="t", days=90):
        token, _ = self.st.create(name, "anna", "domain", role, days, now=self.clock.t)
        return token

    @staticmethod
    def hdr(token):
        return "Bearer " + token

    def test_a_good_token_has_its_role(self):
        r = self.auth.check(self.hdr(self.make("app-manager")))
        self.assertEqual((r[0], r[1]["role"], r[1]["owner"]), ("ok", "app-manager", "anna"))

    def test_no_header_is_no_verdict(self):
        self.assertEqual(self.auth.check("")[0], "none")
        self.assertEqual(self.auth.check("Basic abc")[0], "none")

    def test_never_above_the_owner(self):
        t = self.make("admin")
        self.assertEqual(self.auth.check(self.hdr(t))[1]["role"], "admin")
        self.roles["anna"] = "viewer"
        self.clock.t += 3599
        self.assertEqual(self.auth.check(self.hdr(t))[1]["role"], "admin")      # the cached answer is good for an hour
        self.clock.t += 2
        self.assertEqual(self.auth.check(self.hdr(t))[1]["role"], "viewer")     # read again: a lowered role lowers the token

    def test_a_disabled_owner_kills_the_token_within_the_hour(self):
        t = self.make("viewer")
        self.assertEqual(self.auth.check(self.hdr(t))[0], "ok")
        del self.roles["anna"]
        self.clock.t += 3600 + 1
        r = self.auth.check(self.hdr(t))
        self.assertEqual((r[0], r[1]), ("refused", 401))
        self.assertIn("owner", r[2])

    def test_the_owner_is_asked_once_an_hour_not_per_request(self):
        t = self.make("viewer")
        for _ in range(20):
            self.auth.check(self.hdr(t))
        self.assertEqual(len(self.asked), 1)

    def test_an_expired_token_is_refused(self):
        t = self.make("viewer", days=1)
        self.clock.t += 86400 + 1
        r = self.auth.check(self.hdr(t))
        self.assertEqual((r[0], r[1]), ("refused", 401))

    def test_a_revoked_token_is_refused_at_once(self):
        t = self.make("viewer")
        self.assertEqual(self.auth.check(self.hdr(t))[0], "ok")
        self.st.revoke("t")
        self.assertEqual(self.auth.check(self.hdr(t))[0], "refused")

    def test_the_domain_controller_is_down_a_day(self):
        t = self.make("admin")
        self.assertEqual(self.auth.check(self.hdr(t))[1]["role"], "admin")
        self.down = True
        self.clock.t += 3601
        self.assertEqual(self.auth.check(self.hdr(t))[1]["role"], "admin")      # no verdict: the known role stays
        self.clock.t += 20 * 3600
        self.assertEqual(self.auth.check(self.hdr(t))[1]["role"], "admin")      # still inside the day
        self.clock.t += 5 * 3600
        self.assertEqual(self.auth.check(self.hdr(t))[1]["role"], "viewer")     # more than a day: nothing above viewer
        self.down = False
        self.clock.t += 3601
        self.assertEqual(self.auth.check(self.hdr(t))[1]["role"], "admin")      # it answers again

    def test_60_failures_a_minute_lock_the_id_for_5_minutes(self):
        t = self.make("viewer")
        for i in range(tk.FAIL_LIMIT):
            r = self.auth.check(self.hdr(wrong_of(t)))
            self.assertEqual((r[0], r[1]), ("refused", 401), i)
        r = self.auth.check(self.hdr(wrong_of(t)))
        self.assertEqual((r[0], r[1]), ("refused", 429))
        self.assertEqual(self.auth.check(self.hdr(t))[1], 429)       # the id is locked: the right token waits too
        self.clock.t += tk.LOCK_SECONDS - 1
        self.assertEqual(self.auth.check(self.hdr(t))[1], 429)
        self.clock.t += 2
        self.assertEqual(self.auth.check(self.hdr(t))[0], "ok")

    def test_59_failures_and_slow_ones_do_not_lock(self):
        t = self.make("viewer")
        for _ in range(tk.FAIL_LIMIT - 1):
            self.auth.check(self.hdr(wrong_of(t)))
        self.assertEqual(self.auth.check(self.hdr(t))[0], "ok")      # a good answer starts the count again
        for _ in range(tk.FAIL_LIMIT * 2):      # one every 2 seconds never reaches 60 in a minute
            self.clock.t += 2
            self.auth.check(self.hdr(wrong_of(t)))
        self.assertEqual(self.auth.check(self.hdr(t))[0], "ok")

    def test_an_unknown_id_is_left_to_the_address_count(self):
        r = self.auth.check("Bearer hn_" + "a" * 43)
        self.assertEqual((r[0], r[1], r[3], r[4]), ("refused", 401, None, True))


USERS = {"vic": "viewer", "mia": "app-manager", "anna": "admin"}


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

    def domain_reachable(self):
        return True

    def local_password_ok(self, user, password):
        return user == "adminuser" and password == "local pw"


class WebTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        with open(os.path.join(self.tmp, "index.html"), "w") as f:
            f.write("<html>app</html>")
        os.environ["HS_TOKEN_FILE"] = os.path.join(self.tmp, "api-tokens.json")
        cfg = ws.Config()
        cfg.root, cfg.workgroup, cfg.realm, cfg.fail_delay = self.tmp, "HOME", "ad.home.lan", 0
        cfg.hs, cfg.session_file = "/nonexistent/hs", ""
        cfg.roles_file = os.path.join(root, "scripts", "lib", "sys-roles.tsv")
        self.calls, self.actors, self.cookies = [], [], {}
        self.real_run = ws._run

        def fake(cmd, stdin=None, timeout=10):
            self.calls.append(cmd)
            self.actors.append(ws.current_actor())
            return (0, "status\tok\n")
        ws._run = fake
        self.app = ws.App(cfg, FakeAuth(cfg))
        self.clock = Clock(time.time())
        self.app.tokens.clock = self.clock
        self.app.tokens.limiter.clock = self.clock
        self.srv = ws.Server(("127.0.0.1", 0), ws.make_handler(self.app))
        self.port = self.srv.server_address[1]
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()

    def tearDown(self):
        ws._run = self.real_run
        USERS.update({"vic": "viewer", "mia": "app-manager", "anna": "admin"})
        os.environ.pop("HS_TOKEN_FILE", None)
        self.srv.shutdown()
        self.srv.server_close()

    def req(self, method, path, body=None, headers=None):
        h = dict(headers or {})
        if body is not None:
            h["Content-Type"] = "application/json"
        c = http.client.HTTPConnection("127.0.0.1", self.port)
        c.request(method, path, json.dumps(body) if body is not None else None, h)
        r = c.getresponse()
        data = r.read()
        c.close()
        try:
            data = json.loads(data)
        except ValueError:
            pass
        return r.status, data

    def token(self, owner, role, name="t1", realm="domain"):
        t, _ = self.app.tokens.store.create(name, owner, realm, role, 30, now=self.clock.t)
        return {"Authorization": "Bearer " + t}

    def login(self, user):
        c = http.client.HTTPConnection("127.0.0.1", self.port)
        c.request("POST", "/api/login", json.dumps({"realm": "domain", "user": user, "password": "x"}),
                  {"Content-Type": "application/json", "Origin": "http://127.0.0.1:%d" % self.port})
        r = c.getresponse()
        r.read()
        c.close()
        return {"Cookie": (r.getheader("Set-Cookie") or "").split(";")[0]}

    def test_a_token_reads_as_the_role_of_its_owner(self):
        self.assertEqual(self.req("GET", "/api/session", headers=self.token("HOME_vic", "viewer"))[1]["role"], "viewer")
        self.assertEqual(self.req("GET", "/api/session", headers=self.token("HOME_mia", "admin", "t2"))[1]["role"], "app-manager")      # the token says admin, mia is not
        self.assertEqual(self.req("GET", "/api/session", headers=self.token("HOME_anna", "admin", "t3"))[1]["role"], "admin")

    def test_no_cookie_no_csrf_no_origin_needed_for_a_change(self):
        h = self.token("HOME_mia", "app-manager")
        s, d = self.req("POST", "/api/start", {"area": "ct", "args": ["docker", "update"]}, h)
        self.assertEqual(s, 200, d)
        self.assertTrue(self.actors[-1].startswith("HOME_mia_via_token_"), self.actors)
        self.assertNotIn(h["Authorization"][7:], " ".join(self.actors))

    def test_the_role_check_still_applies(self):
        h = self.token("HOME_vic", "viewer")
        self.assertEqual(self.req("POST", "/api/start", {"area": "ct", "args": ["docker", "update"]}, h)[0], 403)
        self.assertEqual(self.calls, [])

    def test_a_token_cannot_manage_tokens_people_or_secrets(self):
        h = self.token("HOME_anna", "admin")
        for args in (["create", "more"], ["revoke", "t1"]):
            for verb in ("plan", "start"):
                s, d = self.req("POST", "/api/" + verb, {"area": "token", "args": args}, h)
                self.assertEqual(s, 403, (verb, args, d))
        for path in ("/api/sys/token/list", "/api/sys/users/list", "/api/sys/vault/list"):
            self.assertEqual(self.req("GET", path, headers=h)[0], 403, path)
        self.assertEqual(self.calls, [])

    def test_a_token_reaches_nothing_but_plan_and_start(self):
        h = self.token("HOME_anna", "admin")
        for path in ("/api/unlock", "/api/terminal", "/api/sessions/end", "/api/login", "/api/logout"):
            s, d = self.req("POST", path, {}, h)
            self.assertEqual(s, 403, (path, d))

    def test_refused_tokens(self):
        self.assertEqual(self.req("GET", "/api/session", headers={"Authorization": "Bearer nonsense"})[0], 401)
        self.assertEqual(self.req("GET", "/api/session", headers={"Authorization": "Bearer hn_" + "a" * 43})[0], 401)
        self.assertEqual(self.req("GET", "/api/session")[0], 401)
        h = self.token("HOME_gone", "viewer", "t9")       # an owner who is in no group while the domain answers
        s, d = self.req("GET", "/api/session", headers=h)
        self.assertEqual(s, 401, d)
        self.assertNotIn(h["Authorization"][7:], json.dumps(d))

    def test_a_disabled_owner_kills_the_token_within_the_hour(self):
        h = self.token("HOME_mia", "app-manager")
        self.assertEqual(self.req("GET", "/api/session", headers=h)[0], 200)
        USERS.pop("mia")
        self.clock.t += 3599
        self.assertEqual(self.req("GET", "/api/session", headers=h)[0], 200)
        self.clock.t += 2
        self.assertEqual(self.req("GET", "/api/session", headers=h)[0], 401)

    def test_a_token_starts_changes_of_allowed_areas_only(self):
        # #944: an admin token must not start a row whose result outlives the token
        h = self.token("HOME_anna", "admin")
        key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIabcdefghijklmnop me"
        for area, args in (("ssh-key", ["add", key]), ("pkg", ["install", "x"]), ("system", ["rebuild"]), ("routes", ["apply"]), ("dc", ["ca"]),
                           ("node", ["remove", "x"]), ("preset", ["apply", "x"]), ("setup", ["wizard-done"]), ("incident", ["pause"])):
            for verb in ("plan", "start"):
                s, d = self.req("POST", "/api/" + verb, {"area": area, "args": args}, h)
                self.assertEqual(s, 403, (verb, area, d))
        self.assertEqual(self.calls, [])
        self.assertEqual(self.req("POST", "/api/start", {"area": "ct", "args": ["docker", "update"]}, h)[0], 200)

    def test_every_change_area_is_allowed_or_denied_for_tokens(self):
        # a new CHANGES area must be put in TOKEN_CHANGE_ALLOWED or TOKEN_CHANGE_DENIED on purpose
        ws.ext_refresh()
        self.assertEqual(ws.TOKEN_CHANGE_ALLOWED & ws.TOKEN_CHANGE_DENIED, frozenset())
        known = ws.TOKEN_CHANGE_ALLOWED | ws.TOKEN_CHANGE_DENIED
        self.assertEqual(sorted({a.split("/")[0] for a in ws.CHANGES} - known), [])

    def test_a_demoted_domain_session_is_lowered_within_the_hour(self):
        c = self.login("anna")
        self.assertEqual(self.req("GET", "/api/session", headers=c)[1]["role"], "admin")
        USERS["anna"] = "viewer"
        self.clock.t += 3599
        self.assertEqual(self.req("GET", "/api/session", headers=c)[1]["role"], "admin")
        self.clock.t += 2
        self.assertEqual(self.req("GET", "/api/session", headers=c)[1]["role"], "viewer")

    def test_a_disabled_domain_session_ends_within_the_hour(self):
        c = self.login("mia")
        self.assertEqual(self.req("GET", "/api/session", headers=c)[0], 200)
        USERS.pop("mia")
        self.clock.t += 3601
        self.assertEqual(self.req("GET", "/api/session", headers=c)[0], 401)

    def test_a_domain_session_keeps_its_role_a_day_while_the_dc_is_down(self):
        c = self.login("anna")
        self.app.auth.domain_role = lambda user: None
        self.app.auth.domain_reachable = lambda: False
        self.clock.t += 3601
        self.assertEqual(self.req("GET", "/api/session", headers=c)[1]["role"], "admin")
        self.clock.t += 86400
        self.assertEqual(self.req("GET", "/api/session", headers=c)[1]["role"], "viewer")

    def test_the_address_is_throttled_for_wrong_tokens(self):
        wrong = {"Authorization": "Bearer hn_" + "b" * 43}
        for _ in range(5):
            self.assertEqual(self.req("GET", "/api/session", headers=wrong)[0], 401)
        s, d = self.req("GET", "/api/session", headers=wrong)
        self.assertEqual(s, 429, d)

    def test_a_non_admin_sees_only_their_own_tokens(self):
        ck = self.login("mia")
        self.req("GET", "/api/sys/token/list", headers=ck)
        self.assertEqual(self.calls[-1][-2:], ["--owner", "HOME_mia"])
        self.req("GET", "/api/sys/token/list?owner=HOME_anna", headers=ck)
        self.assertEqual(self.calls[-1][-2:], ["--owner", "HOME_mia"])      # asking for somebody else's changes nothing
        self.req("GET", "/api/sys/token/list", headers=self.login("anna"))
        self.assertNotIn("--owner", self.calls[-1])

    def test_a_change_of_a_person_adds_who_asks_and_their_role(self):
        ck = self.login("mia")
        self.req("GET", "/api/session", headers=ck)
        csrf = self.req("GET", "/api/session", headers=ck)[1]["csrf"]
        h = dict(ck, **{"X-CSRF-Token": csrf, "Origin": "http://127.0.0.1:%d" % self.port})
        s, d = self.req("POST", "/api/start", {"area": "token", "args": ["create", "dash", "--role", "viewer"]}, h)
        self.assertEqual(s, 200, d)
        self.assertEqual(self.calls[-1][-4:], ["--by", "HOME_mia", "--cap", "app-manager"])
        s, d = self.req("POST", "/api/start", {"area": "token", "args": ["create", "dash", "--by", "anna", "--cap", "admin"]}, h)
        self.assertEqual(s, 400, d)      # a client never sends who asks


if __name__ == "__main__":
    unittest.main()
