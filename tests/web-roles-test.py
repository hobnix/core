#!/usr/bin/env python3
"""scripts/web-serve.py: roles (ADR 0012 step 15). A viewer, an app manager and an admin session each get exactly the calls their role allows
(the oracle is `x-hs-role` of docs/api/openapi.json, read here on its own, not the table the server reads); a refused call is a 403 that names
both roles and runs nothing; the local account is an admin; the command of a change runs with HS_ACTOR = the signed-in person.
Real HTTP server on a free port, fake helpers, no domain controller."""
import http.client
import importlib.util
import json
import os
import re
import subprocess
import tempfile
import threading
import unittest

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.join(here, "..")
spec = importlib.util.spec_from_file_location("web_serve", os.path.join(root, "scripts", "web-serve.py"))
ws = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ws)
os.environ["HS_WEB_QUIET"] = "1"

ROLES = ("viewer", "app-manager", "admin")
USERS = {"vic": "viewer", "mia": "app-manager", "anna": "admin"}      # the domain: what the groups say


class FakeAuth:
    def __init__(self, cfg):
        self.cfg = cfg

    def local_fingerprint(self, user, fresh=False):
        return "fp"

    def storage_locked(self):
        return False

    def domain_password_ok(self, user, password):
        return user in USERS or user == "nobody"

    def domain_role(self, user):
        return USERS.get(user)

    def local_password_ok(self, user, password):
        return user == "adminuser" and password == "local pw"


def oracle_rows():
    """[(words, role)] from docs/api/openapi.json: every sys row with its x-hs-role"""
    with open(os.path.join(root, "docs", "api", "openapi.json"), encoding="utf-8") as f:
        d = json.load(f)
    return [(op["x-hs-sys"]["words"], op["x-hs-role"]) for v in d["paths"].values() for op in v.values()]


def oracle(rows, words):
    """the role a request needs: the longest row the words start with (a `<x>` stands for one word); no row = admin"""
    best, role = 0, "admin"
    for row, r in rows:
        if len(row) <= len(words) and len(row) > best and all(a == w or (a.startswith("<") and a.endswith(">")) for a, w in zip(row, words)):
            best, role = len(row), r
    return role


def allowed(have, need):
    return ROLES.index(have) >= ROLES.index(need)


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        with open(os.path.join(self.tmp, "index.html"), "w") as f:
            f.write("<html>app</html>")
        cfg = ws.Config()
        cfg.root, cfg.workgroup, cfg.realm, cfg.fail_delay = self.tmp, "HOME", "ad.home.lan", 0
        cfg.hs = "/nonexistent/hs"
        cfg.session_file = ""
        cfg.roles_file = os.path.join(root, "scripts", "lib", "sys-roles.tsv")
        self.cfg, self.calls, self.actors = cfg, [], []
        self.answer = (0, "a\tb\nc\td\n")
        self.real_run = ws._run

        def fake(cmd, stdin=None, timeout=10):
            self.calls.append(cmd)
            self.actors.append(ws.current_actor())
            return self.answer
        ws._run = fake
        self.app = ws.App(cfg, FakeAuth(cfg))
        self.srv = ws.Server(("127.0.0.1", 0), ws.make_handler(self.app))
        self.port = self.srv.server_address[1]
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()
        self.sessions = {}

    def tearDown(self):
        ws._run = self.real_run
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
        data = r.read()
        c.close()
        try:
            data = json.loads(data)
        except ValueError:
            pass
        return r.status, data, r

    def login(self, user, realm="domain"):
        pw = "local pw" if realm == "local" else "pw"
        s, d, r = self.req("POST", "/api/login", {"realm": realm, "user": user, "password": pw})
        return s, d, (r.getheader("Set-Cookie") or "").split(";")[0]

    def as_(self, user):
        """a signed-in person -> (cookie headers, csrf), signed in once"""
        if user not in self.sessions:
            realm = "local" if user == "adminuser" else "domain"
            s, d, ck = self.login(user, realm)
            assert s == 200, (user, s, d)
            self.sessions[user] = ({"Cookie": ck}, d["csrf"])
        return self.sessions[user]

    def get(self, user, path):
        return self.req("GET", path, headers=self.as_(user)[0])

    def post(self, user, path, body):
        ck, csrf = self.as_(user)
        return self.req("POST", path, body, headers=dict(ck, **{"X-CSRF-Token": csrf}))


class SignIn(Base):
    def test_each_group_gives_its_role(self):
        for user, role in USERS.items():
            s, d, ck = self.login(user)
            self.assertEqual((s, d["role"]), (200, role), user)
            s2, d2, _ = self.req("GET", "/api/session", headers={"Cookie": ck})
            self.assertEqual(d2["role"], role, user)

    def test_a_person_in_no_group_is_refused_and_the_message_names_the_groups(self):
        s, d, ck = self.login("nobody")
        self.assertEqual(s, 403)
        self.assertEqual(ck, "")
        for name in ("Domain Admins", "hn-app-managers", "hn-viewers"):
            self.assertIn(name, d["error"])

    def test_the_local_account_is_an_admin(self):
        s, d, ck = self.login("adminuser", "local")
        self.assertEqual((s, d["role"]), (200, "admin"))
        self.assertEqual(self.get("adminuser", "/api/session")[1]["role"], "admin")
        self.assertEqual(self.post("adminuser", "/api/plan", {"area": "users", "args": ["anna", "lock"]})[0], 200)

    def test_the_group_names_are_the_settings_or_the_defaults(self):
        self.assertEqual((self.cfg.viewer_group, self.cfg.manager_group), ("hn-viewers", "hn-app-managers"))

    def test_the_highest_group_wins(self):
        a = ws.Auth(self.cfg)
        member = {"Domain Admins": False, "hn-app-managers": True, "hn-viewers": True}
        a.domain_in_group = lambda user, group: member.get(group, False)
        self.assertEqual(a.domain_role("x"), "app-manager")
        member["Domain Admins"] = True
        self.assertEqual(a.domain_role("x"), "admin")
        member.update({"Domain Admins": False, "hn-app-managers": False})
        self.assertEqual(a.domain_role("x"), "viewer")
        member["hn-viewers"] = False
        self.assertIsNone(a.domain_role("x"))

    def test_a_session_without_a_role_is_an_admin_and_a_strange_one_a_viewer(self):
        old = self.app.sessions.create("old", "local", "127.0.0.1")
        self.app.sessions.items[old].pop("role")        # written before roles existed: only admins could sign in then
        odd = self.app.sessions.create("odd", "local", "127.0.0.1", role="root")
        self.assertEqual(self.req("GET", "/api/session", headers={"Cookie": "hs_session=" + old})[1]["role"], "admin")
        self.assertEqual(self.req("GET", "/api/session", headers={"Cookie": "hs_session=" + odd})[1]["role"], "viewer")


class Matrix(Base):
    """Every allowlisted read and a list of changes, for each role: 403 exactly when the row asks for more."""

    def test_every_read(self):
        rows, n = oracle_rows(), 0
        for key, spec in sorted(ws.READS.items()):
            args = [next((c for c in ("x", "x1", "1", "a.b", "disk:x", "x:x", "xx-1") if re.fullmatch(p, c)), None) for p in spec.get("args", [])]
            if None in args:
                continue        # an argument shape this list does not know: the 404 of the read is not what is tested here
            words = list(key) + args
            need = oracle(rows, words)
            for user, role in USERS.items():
                s, d, _ = self.get(user, "/api/sys/" + "/".join(words))
                n += 1
                if allowed(role, need):
                    self.assertNotIn(s, (401, 403), (words, role))
                else:
                    self.assertEqual(s, 403, (words, role))
                    self.assertEqual((d["required"], d["role"]), (need, role))
        self.assertGreater(n, 250)

    CHANGES = [("ct", ["docker", "update"]), ("ct", ["docker", "restore", "--snapshot", "snap1"]), ("recipes", ["qbittorrent", "run"]),
               ("users", ["anna", "lock"]), ("system", ["update"]), ("system", ["sync"]), ("backup", ["now"]), ("config", ["sync"]),
               ("jobs", ["stop", "hs-bulk-sync.service"]), ("shares", ["media", "snapshot"]), ("admin", ["test-push"]), ("jobs", ["run", "hs-health-check.service"])]

    def test_changes(self):
        rows = oracle_rows()
        seen = set()
        for area, args in self.CHANGES:
            for verb in ("plan", "start"):
                need = oracle(rows, [area, verb] + args)
                seen.add(need)
                for user, role in USERS.items():
                    before = len(self.calls)
                    body = {"area": area, "args": args}
                    if verb == "start":
                        body["confirm"] = "stop"
                    s, d, _ = self.post(user, "/api/" + verb, body)
                    if allowed(role, need):
                        self.assertNotEqual(s, 403, (area, args, verb, role))
                        self.assertEqual(len(self.calls), before + 1, (area, args, verb, role))
                    else:
                        self.assertEqual(s, 403, (area, args, verb, role))
                        self.assertEqual((d["required"], d["role"]), (need, role))
                        self.assertEqual(len(self.calls), before, "a refused call runs nothing: %s %s %s" % (area, args, role))
        self.assertEqual(seen, {"app-manager", "admin"})        # the list covers both kinds of change

    def test_the_first_viewer_calls_the_manager_can_do_and_the_viewer_cannot(self):
        # the plain case behind the matrix, spelled out
        self.assertEqual(self.post("vic", "/api/plan", {"area": "ct", "args": ["docker", "update"]})[0], 403)
        self.assertEqual(self.post("mia", "/api/plan", {"area": "ct", "args": ["docker", "update"]})[0], 200)
        self.assertEqual(self.post("mia", "/api/plan", {"area": "users", "args": ["anna", "lock"]})[0], 403)
        self.assertEqual(self.post("anna", "/api/plan", {"area": "users", "args": ["anna", "lock"]})[0], 200)
        self.assertEqual(self.get("vic", "/api/sys/ct/list")[0], 200)
        self.assertEqual(self.get("vic", "/api/sys/users/list")[0], 403)
        self.assertEqual(self.get("mia", "/api/sys/users/list")[0], 403)

    def test_a_viewer_cannot_list_files_or_search_backups(self):
        """#946: file names of every share (sensitive ones too) and a search over all backups are admin reads, not viewer reads"""
        for path in ("/api/sys/fm/locations", "/api/sys/fm/ls/share:sensitive", "/api/sys/fm/du/share:sensitive", "/api/sys/fm/stat/share:sensitive?path=/a",
                     "/api/sys/backup/find/secret"):
            for user in ("vic", "mia"):
                s, d, _ = self.get(user, path)
                self.assertEqual(s, 403, (path, user))
                self.assertEqual(d["required"], "admin", path)
            self.assertNotEqual(self.get("anna", path)[0], 403, path)

    def test_the_403_body(self):
        s, d, _ = self.post("vic", "/api/start", {"area": "ct", "args": ["docker", "update"]})
        self.assertEqual(s, 403)
        self.assertEqual((d["required"], d["role"]), ("app-manager", "viewer"))
        self.assertIn("app-manager", d["error"])
        self.assertIn("viewer", d["error"])

    def test_the_csrf_check_still_comes_first(self):
        ck = self.as_("vic")[0]
        self.assertEqual(self.req("POST", "/api/start", {"area": "ct", "args": ["docker", "update"]}, headers=dict(ck, **{"X-CSRF-Token": "x"}))[0], 403)
        self.assertEqual(self.calls, [])

    def test_unlock_terminal_and_console_are_for_admins(self):
        for path, body in (("/api/unlock", {"passphrase": "x"}), ("/api/terminal", {"target": "host"}), ("/api/vmconsole", {"name": "vm1"})):
            for user in ("vic", "mia"):
                s, d, _ = self.post(user, path, body)
                self.assertEqual((s, d.get("required")), (403, "admin"), (path, user))

    def test_a_missing_table_locks_a_viewer_out_and_never_lets_one_in(self):
        t = ws.RoleTable("/nonexistent/roles.tsv")
        self.assertEqual(t.need(["ct", "list"]), "admin")
        self.assertEqual(t.need(["ct", "plan", "a", "b"]), "admin")

    def test_the_best_row_wins(self):
        t = ws.RoleTable(os.path.join(root, "scripts", "lib", "sys-roles.tsv"))
        self.assertEqual(t.need(["ct", "plan", "x", "update", "--extra"]), "app-manager")      # more words than the row are fine
        self.assertEqual(t.need(["pkg", "bundle", "plan", "x"]), "admin")
        self.assertEqual(t.need(["ext", "games", "plan", "x"]), "admin")                        # no row: admin
        self.assertEqual(t.need(["jobs", "tail", "u"]), "viewer")

    def test_every_allowlisted_read_has_a_row(self):
        t = ws.RoleTable(os.path.join(root, "scripts", "lib", "sys-roles.tsv"))
        bare = [k for k, spec in ws.READS.items() if t.match(list(k) + ["x"] * len(spec.get("args", [])))[1] is None]
        self.assertEqual(bare, [], "a read without a row would be admin only: add it to docs/api/sys.toml")


class Sessions(Base):
    def test_a_viewer_sees_and_ends_only_their_own_sessions(self):
        self.as_("vic")
        self.as_("mia")
        self.as_("anna")
        names = lambda user: sorted({r["user"] for r in self.get(user, "/api/sessions")[1]["sessions"]})
        self.assertEqual(names("vic"), ["HOME\\vic"])
        self.assertEqual(names("mia"), ["HOME\\mia"])
        self.assertEqual(names("anna"), ["HOME\\anna", "HOME\\mia", "HOME\\vic"])
        other = next(r["id"] for r in self.get("anna", "/api/sessions")[1]["sessions"] if r["user"] == "HOME\\mia")
        self.assertEqual(self.post("vic", "/api/sessions/end", {"id": other})[0], 404)
        self.post("vic", "/api/sessions/end-others", {})
        self.assertEqual(names("anna"), ["HOME\\anna", "HOME\\mia", "HOME\\vic"])        # mia's and anna's sessions are still there
        self.assertEqual(self.post("anna", "/api/sessions/end", {"id": other})[0], 200)


class Actor(Base):
    def test_a_change_runs_for_the_signed_in_person(self):
        self.post("mia", "/api/start", {"area": "ct", "args": ["docker", "update"]})
        self.post("mia", "/api/plan", {"area": "ct", "args": ["docker", "update"]})
        self.assertEqual(self.actors, ["HOME_mia", "HOME_mia"])
        self.assertEqual(self.calls[0][:5], ["/nonexistent/hs", "sys", "ct", "start", "docker"])
        self.assertEqual(ws.current_actor(), "")        # nobody is left over for the next request of this thread

    def test_a_refused_call_runs_nothing(self):
        self.post("vic", "/api/start", {"area": "ct", "args": ["docker", "update"]})
        self.assertEqual((self.calls, self.actors), ([], []))

    def test_the_command_gets_HS_ACTOR_in_its_environment_and_nothing_else_new(self):
        ws._run = self.real_run
        ws._actor.name = "HOME_mia"
        try:
            rc, out = ws._run_plain(["sh", "-c", "printf %s \"$HS_ACTOR\""])
        finally:
            ws._actor.name = ""
        self.assertEqual((rc, out), (0, "HOME_mia"))
        env = dict(os.environ, HS_ACTOR="stale")
        os.environ["HS_ACTOR"] = "stale"
        try:
            rc, out = ws._run_plain(["sh", "-c", "printf %s \"$HS_ACTOR\""])
        finally:
            os.environ.pop("HS_ACTOR", None)
        self.assertEqual(out, "stale")      # no actor of ours: the environment is left as it is (reads are not audited)
        del env

    def test_the_audit_line_names_the_person(self):
        who = ws.actor_name("HOME\\mia")
        out = subprocess.run(["bash", "-c", '. scripts/lib/audit.sh; audit_actor'], cwd=root,
                             env=dict(os.environ, HS_ACTOR=who, HS_CALLER="web"), capture_output=True, text=True).stdout
        self.assertEqual(out, "HOME_mia")


if __name__ == "__main__":
    unittest.main()
