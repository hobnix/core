#!/usr/bin/env python3
"""scripts/web-serve.py: the reads and changes an extension package declares in its capability.toml ([[web.reads]], [[web.changes]]) are
allowlisted only while the package is on, only when they are rows of the package's own commands.tsv, and never outside its namespace."""
import importlib.util
import os
import re
import shutil
import tempfile
import unittest

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("web_serve", os.path.join(here, "..", "scripts", "web-serve.py"))
ws = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ws)
os.environ["HS_WEB_QUIET"] = "1"
TAB = "\t"


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(text)


def package(root, name, rows, web):
    write(os.path.join(root, name, "capability.toml"),
          'name = "%s"\ntitle = "t"\ntitle_de = "t"\nkind = "feature"\nrequires = []\nprovides = []\nneeds = []\nextension = true\n%s' % (name, web))
    write(os.path.join(root, name, "commands.tsv"), "".join(TAB.join(r) + "\n" for r in rows))


class ExtPages(unittest.TestCase):
    """[web.page]: a declaration may name only reads of the package and plans of its own area"""

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.pk = os.path.join(self.tmp, "packages")
        os.environ["HS_PACKAGES_DIR"] = self.pk
        os.environ["HS_CAPABILITIES_FILE"] = os.path.join(self.tmp, "caps")
        os.environ["HS_STATE_DIR"] = os.path.join(self.tmp, "state")
        write(os.path.join(self.tmp, "caps"), "demo\n")

    def tearDown(self):
        os.environ.pop("HS_PACKAGES_DIR", None)
        write(os.path.join(self.tmp, "caps"), "")
        ws.ext_refresh(force=True)
        shutil.rmtree(self.tmp, ignore_errors=True)

    def pages(self, page):
        package(self.pk, "demo", [["sys", "sys ext demo list", "x.sh", "list", "h", "-"]],
                '[[web.reads]]\nwords = "list"\nkind = "tsv"\nttl = 10\n' + page)
        ws.ext_refresh(force=True)
        return ws.ext_pages()

    def test_a_good_page(self):
        got = self.pages('[web.page]\ntitle = "Demo"\n[[web.page.blocks]]\ntype = "table"\nread = "list"\ncolumns = []\n')
        self.assertEqual(got[0]["name"], "demo")
        self.assertIn(("ext", "demo", "list"), ws.READS)       # the reads still work next to the page

    def test_a_page_that_reads_something_undeclared_drops_the_package(self):
        got = self.pages('[web.page]\ntitle = "Demo"\n[[web.page.blocks]]\ntype = "table"\nread = "secret"\n')
        self.assertEqual(got, [])
        self.assertNotIn(("ext", "demo", "list"), ws.READS)

    def test_a_page_may_not_plan_in_another_area(self):
        got = self.pages('[web.page]\ntitle = "Demo"\n[[web.page.actions]]\nlabel = "x"\nplan = ["ct", "a", "stop"]\n')
        self.assertEqual(got, [])

    def test_an_input_action_needs_a_label_and_the_input_in_its_plan(self):
        act = '[web.page]\ntitle = "Demo"\n[[web.page.actions]]\nlabel = "Go"\nplan = ["ext/demo", "go", "{input}"]\n'
        self.assertEqual(self.pages(act + 'input = { label = "Name", pattern = "^[a-z]+$", suggest = { read = "list" } }\n')[0]["name"], "demo")
        self.assertEqual(self.pages(act + 'input = { placeholder = "x" }\n'), [])                       # no label
        self.assertEqual(self.pages(act.replace(', "{input}"', '') + 'input = { label = "Name" }\n'), [])   # nothing takes the value
        self.assertEqual(self.pages(act + 'input = { label = "Name", suggest = { read = "secret" } }\n'), [])   # a read the package did not declare
        self.assertEqual(self.pages(act + 'input = { label = "Name", pattern = "(" }\n'), [])             # a pattern that does not compile

    def test_an_unknown_block_type_is_refused(self):
        self.assertEqual(self.pages('[web.page]\ntitle = "Demo"\n[[web.page.blocks]]\ntype = "script"\n'), [])

    def test_the_group_defaults_to_apps_and_an_unknown_group_drops_the_package(self):
        self.assertEqual(self.pages('[web.page]\ntitle = "Demo"\n')[0]["group"], "apps")
        self.assertEqual(self.pages('[web.page]\ntitle = "Demo"\ngroup = "network"\nafter = "services"\n')[0]["group"], "network")
        self.assertEqual(self.pages('[web.page]\ntitle = "Demo"\ngroup = "extensions"\n'), [])
        self.assertNotIn(("ext", "demo", "list"), ws.READS)

    def test_a_state_that_reads_more_than_declared_drops_the_package(self):
        ok = self.pages('[web.page]\ntitle = "Demo"\nstate = { read = "list", dot = 1, line = 2 }\n')
        self.assertEqual(ok[0]["state"]["read"], "list")
        self.assertEqual(self.pages('[web.page]\ntitle = "Demo"\nstate = { read = "secret", dot = 1, line = 2 }\n'), [])
        self.assertEqual(self.pages('[web.page]\ntitle = "Demo"\nstate = { read = "list" }\n'), [])

    def test_a_tab_that_reads_more_than_declared_drops_the_package(self):
        tab = '[web.page]\ntitle = "Demo"\n[[web.page.tabs]]\ntitle = "One"\n[[web.page.tabs.blocks]]\ntype = "table"\nread = "%s"\n'
        got = self.pages(tab % "list")[0]
        self.assertEqual((got["tabs"], got["blocks"][0]["tab"]), ([{"id": "t0", "label": "One"}], "t0"))
        self.assertEqual(self.pages(tab % "secret"), [])

    def test_template_role_and_the_default_template(self):
        self.assertEqual(self.pages('[web.page]\ntitle = "Demo"\n[[web.page.blocks]]\ntype = "table"\nread = "list"\n')[0]["template"], "list")
        self.assertEqual(self.pages('[web.page]\ntitle = "Demo"\ntemplate = "feed"\nrole = "viewer"\n')[0]["template"], "feed")
        self.assertEqual(self.pages('[web.page]\ntitle = "Demo"\ntemplate = "grid"\n'), [])
        self.assertEqual(self.pages('[web.page]\ntitle = "Demo"\nrole = "root"\n'), [])
        act = '[web.page]\ntitle = "Demo"\n[[web.page.actions]]\nlabel = "Go"\nplan = ["ext/demo", "go"]\nrole = "%s"\n'
        self.assertEqual(self.pages(act % "app-manager")[0]["actions"][0]["role"], "app-manager")
        self.assertEqual(self.pages(act % "root"), [])

    def recipe(self, web, rows=True):
        """a recipe package (package.toml only, on once hs recipe applied it: installed.toml) with the given [web] text"""
        write(os.path.join(self.pk, "demo", "package.toml"), 'name = "demo"\nkind = "recipe"\n' + web)
        if rows:
            write(os.path.join(self.pk, "demo", "commands.tsv"), TAB.join(["sys", "sys ext demo state", "x.sh", "state", "h", "-"]) + "\n")
        elif os.path.isfile(os.path.join(self.pk, "demo", "commands.tsv")):
            os.remove(os.path.join(self.pk, "demo", "commands.tsv"))
        write(os.path.join(self.tmp, "caps"), "")
        write(os.path.join(self.tmp, "state", "packages", "installed.toml"), '[package.demo]\nversion = "1"\n')
        ws.ext_refresh(force=True)
        return ws.ext_pages()

    def test_a_recipe_page_is_an_object_page(self):
        reads = '[[web.reads]]\nwords = "state"\nkind = "tsv"\nttl = 10\n'
        blk = '[web.page]\ntitle = "Demo"\n[[web.page.blocks]]\ntype = "kv"\nread = "state"\n'
        got = self.recipe(reads + blk)[0]
        self.assertEqual((got["kind"], got["template"], got["name"]), ("recipe", "object", "demo"))
        self.assertEqual(self.recipe('[web.page]\ntitle = "Demo"\n[[web.page.blocks]]\ntype = "text"\ntext = "x"\n', rows=False)[0]["kind"], "recipe")   # no reads: no commands.tsv needed
        self.assertEqual(self.recipe(reads + blk, rows=False), [])                  # a read without commands.tsv: dropped
        self.assertEqual(self.recipe(reads + blk.replace('title = "Demo"', 'title = "Demo"\ngroup = "network"')), [])     # no place in the tree
        self.assertEqual(self.recipe(reads + blk.replace('title = "Demo"', 'title = "Demo"\ntemplate = "list"')), [])
        self.assertEqual(self.recipe(reads + blk.replace('read = "state"', 'read = "secret"')), [])   # only its own reads
        act = reads + '[web.page]\ntitle = "Demo"\n[[web.page.actions]]\nlabel = "Go"\nplan = ["ct", "a", "stop"]\n'
        self.assertEqual(self.recipe(act), [])                                      # only plans of its own area

    def test_the_four_existing_pages_keep_working(self):
        """games, posters, passthrough, ad-selfservice declare no placement key: each loads, lands in apps and keeps its blocks"""
        names = ("games", "posters", "passthrough", "ad-selfservice")
        for name in names:
            package(self.pk, name, [["sys", "sys ext %s list" % name, "x.sh", "list", "h", "-"]],
                    '[[web.reads]]\nwords = "list"\nkind = "tsv"\nttl = 10\n[web.page]\ntitle = "%s"\nicon = "x"\n'
                    '[[web.page.actions]]\nlabel = "Go"\nplan = ["ext/%s", "go"]\n'
                    '[[web.page.blocks]]\ntype = "table"\nread = "list"\nkey = "n"\ncolumns = [ { key = "n", label = "N" } ]\n' % (name, name))
        write(os.path.join(self.tmp, "caps"), "\n".join(names) + "\n")
        ws.ext_refresh(force=True)
        got = {p["name"]: p for p in ws.ext_pages()}
        self.assertEqual(sorted(got), sorted(names))
        for p in got.values():
            self.assertEqual((p["group"], p["blocks"][0]["type"], len(p["actions"])), ("apps", "table", 1))


class ExtWeb(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.pk = os.path.join(self.tmp, "packages")
        self.caps = os.path.join(self.tmp, "caps")
        os.environ["HS_PACKAGES_DIR"] = self.pk
        os.environ["HS_CAPABILITIES_FILE"] = self.caps
        os.environ["HS_STATE_DIR"] = os.path.join(self.tmp, "state")
        write(self.caps, "")
        package(self.pk, "demo", [
            ["sys", "sys ext demo list", "x.sh", "list", "h", "-"],
            ["sys", "sys ext demo thing <id>", "x.sh", "thing {1}", "h", "-"],
            ["sys", "sys ext demo plan <action>", "x.sh", "plan {1}", "h", "-"],
            ["sys", "sys ext demo start <action>", "x.sh", "start {1}", "h", "-"],
        ], '''
[[web.reads]]
words = "list"
kind = "tsv"
ttl = 10

[[web.reads]]
words = "thing"
kind = "json"
ttl = 5
args = ['^[a-z]{1,8}$']

[[web.changes]]
patterns = ['^go$', '^[a-z]{1,8}$']

[[web.changes]]
fixed = ['^make$']
opts = [ { flag = "--size", pattern = '^[0-9]{1,3}$' } ]
''')

    def tearDown(self):
        for k in list(ws.READS):
            if k[0] == "ext":
                del ws.READS[k]
        for k in list(ws.CHANGES):
            if k.startswith("ext/"):
                del ws.CHANGES[k]
        shutil.rmtree(self.tmp, ignore_errors=True)

    def refresh(self, on):
        write(self.caps, "".join(n + "\n" for n in on))
        ws.ext_refresh(force=True)

    def ok(self, area, args):
        return ws.validate_change({"area": area, "args": args}) is not None

    def test_off_means_nothing_is_allowed(self):
        self.refresh([])
        self.assertNotIn(("ext", "demo", "list"), ws.READS)
        self.assertNotIn("ext/demo", ws.CHANGES)
        self.assertFalse(self.ok("ext/demo", ["go", "now"]))

    def test_on_registers_the_declared_reads_and_changes(self):
        self.refresh(["demo"])
        self.assertEqual(ws.READS[("ext", "demo", "list")], {"kind": "tsv", "ttl": 10, "role": "admin"})
        self.assertEqual(ws.READS[("ext", "demo", "thing")]["args"], ["^[a-z]{1,8}$"])
        self.assertTrue(self.ok("ext/demo", ["go", "now"]))
        self.assertTrue(self.ok("ext/demo", ["make", "--size", "12"]))
        for bad in (["go"], ["go", "NOW"], ["make", "--size", "1234"], ["make", "--size"], ["make", "--other", "1"], ["stop", "now"], []):
            self.assertFalse(self.ok("ext/demo", bad), bad)

    def test_switching_off_removes_them_again(self):
        self.refresh(["demo"])
        self.refresh([])
        self.assertNotIn(("ext", "demo", "list"), ws.READS)
        self.assertFalse(self.ok("ext/demo", ["go", "now"]))

    def test_the_overlay_of_hs_ext_enable_counts(self):
        write(os.path.join(self.tmp, "state", "capabilities-on"), "demo\n")
        ws.ext_refresh(force=True)
        self.assertIn(("ext", "demo", "list"), ws.READS)
        write(os.path.join(self.tmp, "state", "capabilities-off"), "demo\n")
        ws.ext_refresh(force=True)
        self.assertNotIn(("ext", "demo", "list"), ws.READS)

    def test_a_read_must_be_a_row_of_the_package(self):
        package(self.pk, "demo", [["sys", "sys ext demo list", "x.sh", "list", "h", "-"]], '''
[[web.reads]]
words = "list"
kind = "tsv"
ttl = 10
[[web.reads]]
words = "secret"
kind = "tsv"
ttl = 10
''')
        self.refresh(["demo"])
        self.assertNotIn(("ext", "demo", "list"), ws.READS)     # the whole declaration is ignored, not half of it

    def test_changes_need_the_plan_and_start_rows(self):
        package(self.pk, "demo", [["sys", "sys ext demo list", "x.sh", "list", "h", "-"]], '''
[[web.changes]]
patterns = ['^go$']
''')
        self.refresh(["demo"])
        self.assertNotIn("ext/demo", ws.CHANGES)

    def test_no_read_may_change_something(self):
        package(self.pk, "demo", [["sys", "sys ext demo start", "x.sh", "start", "h", "-"]], '''
[[web.reads]]
words = "start"
kind = "tsv"
ttl = 1
''')
        self.refresh(["demo"])
        self.assertNotIn(("ext", "demo", "start"), ws.READS)

    def test_a_bad_pattern_or_value_ignores_the_package(self):
        for web in ('[[web.reads]]\nwords = "list"\nkind = "tsv"\nttl = 99999\n',
                    '[[web.reads]]\nwords = "list"\nkind = "xml"\nttl = 5\n',
                    '[[web.reads]]\nwords = "list"\nkind = "tsv"\nttl = 5\nargs = ["("]\n',
                    '[[web.reads]]\nwords = "list"\nkind = "tsv"\n'):
            package(self.pk, "demo", [["sys", "sys ext demo list", "x.sh", "list", "h", "-"]], web)
            self.refresh(["demo"])
            self.assertNotIn(("ext", "demo", "list"), ws.READS, web)

    def test_a_package_cannot_declare_a_core_read(self):
        # the reads are always put under ext/<name>: there is no way to name ("ct", "list") or another package's words
        package(self.pk, "demo", [["sys", "sys ct list", "x.sh", "list", "h", "-"]], '[[web.reads]]\nwords = "../ct list"\nkind = "tsv"\nttl = 5\n')
        self.refresh(["demo"])
        self.assertFalse(any(k[:2] == ("ext", "demo") for k in ws.READS))
        self.assertIn(("ct", "list"), ws.READS)

    def test_a_folder_name_that_is_no_package_name_is_skipped(self):
        package(self.pk, "Bad_Name", [["sys", "sys ext Bad_Name list", "x.sh", "list", "h", "-"]], '[[web.reads]]\nwords = "list"\nkind = "tsv"\nttl = 5\n')
        self.refresh(["Bad_Name"])
        self.assertFalse(any(k[:2] == ("ext", "Bad_Name") for k in ws.READS))

    def test_the_sys_words_of_a_change_are_the_area(self):
        # validate_change keeps the area "ext/demo"; the call is `hs sys ext demo plan|start ...` (area.split("/"))
        self.refresh(["demo"])
        got = ws.validate_change({"area": "ext/demo", "args": ["go", "now"]})
        self.assertEqual(got[0].split("/"), ["ext", "demo"])
        self.assertIsNone(ws.validate_change({"area": "ext", "args": ["go", "now"]}))
        self.assertIsNone(ws.validate_change({"area": "ext/other", "args": ["go", "now"]}))


MANIFEST = """name = "app"
version = "1.0.0"
kind = "recipe"
title = "t"
[[web.reads]]
words = "status"
kind = "tsv"
ttl = 15
[web.page]
title = "App"
[[web.page.blocks]]
type = "table"
read = "status"
key = "x"
columns = [ { key = "x", label = "X" } ]
"""


class ExtLive(unittest.TestCase):
    """live = <seconds> on a read without args: the read gets a topic, the topic map and the group; wrong values drop the package"""

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.pk = os.path.join(self.tmp, "packages")
        os.environ["HS_PACKAGES_DIR"] = self.pk
        os.environ["HS_CAPABILITIES_FILE"] = os.path.join(self.tmp, "caps")
        os.environ["HS_STATE_DIR"] = os.path.join(self.tmp, "state")
        write(os.path.join(self.tmp, "caps"), "demo\n")

    def tearDown(self):
        os.environ.pop("HS_PACKAGES_DIR", None)
        write(os.path.join(self.tmp, "caps"), "")
        ws.ext_refresh(force=True)
        shutil.rmtree(self.tmp, ignore_errors=True)

    def load(self, extra, rows=None):
        package(self.pk, "demo", rows or [["sys", "sys ext demo list", "x.sh", "list", "h", "-"],
                                          ["sys", "sys ext demo thing <id>", "x.sh", "thing {1}", "h", "-"]],
                '[[web.reads]]\nwords = "list"\nkind = "tsv"\nttl = 10\n' + extra)
        return ws.ext_load_web()[0]

    def test_a_read_without_live_has_no_topic(self):
        self.assertNotIn("topic", self.load("")[("ext", "demo", "list")])

    def test_live_read_has_topic_cap_and_lock(self):
        spec = self.load("live = 30\n")[("ext", "demo", "list")]
        self.assertEqual((spec["topic"], spec["live"], spec["locked"], spec["cap"]), ("ext-demo-list", 30, "skip", "demo"))
        self.assertEqual(self.load('live = 10\nlocked = "run"\n')[("ext", "demo", "list")]["locked"], "run")

    def test_topic_map_has_the_ext_url(self):
        package(self.pk, "demo", [["sys", "sys ext demo list", "x.sh", "list", "h", "-"]],
                '[[web.reads]]\nwords = "list"\nkind = "tsv"\nttl = 10\nlive = 30\n')
        ws.ext_refresh(force=True)
        self.assertEqual(ws.live_topic_map().get("/api/sys/ext/demo/list"), "ext-demo-list")

    def test_wrong_live_values_drop_the_package(self):
        for extra in ("live = 9\n", "live = 3601\n", 'live = "30"\n', "live = true\n", 'live = 30\nlocked = "x"\n', "live = 30\nargs = ['^a$']\n"):
            self.assertEqual(self.load(extra), {}, extra)

    def test_words_that_cannot_be_a_topic_drop_the_package(self):
        reads = self.load("live = 30\n", [["sys", "sys ext demo list", "x.sh", "list", "h", "-"]])
        self.assertIn(("ext", "demo", "list"), reads)
        package(self.pk, "demo", [["sys", "sys ext demo Li_st", "x.sh", "list", "h", "-"]],
                '[[web.reads]]\nwords = "Li_st"\nkind = "tsv"\nttl = 10\nlive = 30\n')
        self.assertEqual(ws.ext_load_web()[0], {})

    def test_package_off_gives_no_read(self):
        self.load("live = 30\n")
        write(os.path.join(self.tmp, "caps"), "")
        self.assertEqual(ws.ext_load_web()[0], {})


class RecipePackage(unittest.TestCase):
    """a recipe package (packages/<name>/package.toml + commands.tsv) registers its reads and page only once the recipe has been applied"""

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.pk = os.path.join(self.tmp, "packages")
        os.environ["HS_PACKAGES_DIR"] = self.pk
        os.environ["HS_CAPABILITIES_FILE"] = os.path.join(self.tmp, "caps")
        os.environ["HS_STATE_DIR"] = os.path.join(self.tmp, "state")
        write(os.path.join(self.tmp, "caps"), "")
        write(os.path.join(self.pk, "app", "package.toml"), MANIFEST)
        write(os.path.join(self.pk, "app", "commands.tsv"), TAB.join(["sys", "sys ext app status", "@/s.sh", "--list", "h", "-"]) + "\n")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_off_until_applied(self):
        reads, _, pages = ws.ext_load_web()
        self.assertEqual((reads, pages), ({}, []))
        write(os.path.join(self.tmp, "state", "packages", "installed.toml"), '[package.app]\nversion = "1.0.0"'+"\n")
        reads, _, pages = ws.ext_load_web()
        self.assertIn(("ext", "app", "status"), reads)
        self.assertEqual([p["name"] for p in pages], ["app"])


class ExtRoles(unittest.TestCase):
    """step 18 of docs/PLAN-extensions-access.md: `role` per [[web.reads]] / [[web.changes]] entry (default admin), enforced with the core check"""
    USERS = {"vic": "viewer", "mia": "app-manager", "anna": "admin"}

    def setUp(self):
        import http.client
        import json
        import threading
        self.http, self.json = http.client, json
        self.tmp = tempfile.mkdtemp()
        self.pk = os.path.join(self.tmp, "packages")
        self.caps = os.path.join(self.tmp, "caps")
        os.environ["HS_PACKAGES_DIR"] = self.pk
        os.environ["HS_CAPABILITIES_FILE"] = self.caps
        os.environ["HS_STATE_DIR"] = os.path.join(self.tmp, "state")
        write(self.caps, "demo\n")
        write(os.path.join(self.tmp, "index.html"), "<html>app</html>")
        package(self.pk, "demo", [
            ["sys", "sys ext demo old", "x.sh", "old", "h", "-"],
            ["sys", "sys ext demo see", "x.sh", "see", "h", "-"],
            ["sys", "sys ext demo manage", "x.sh", "manage", "h", "-"],
            ["sys", "sys ext demo secret", "x.sh", "secret", "h", "-"],
            ["sys", "sys ext demo plan <action>", "x.sh", "plan {1}", "h", "-"],
            ["sys", "sys ext demo start <action>", "x.sh", "start {1}", "h", "-"],
        ], '''
[[web.reads]]
words = "old"
kind = "text"
ttl = 5

[[web.reads]]
words = "see"
kind = "text"
ttl = 5
role = "viewer"

[[web.reads]]
words = "manage"
kind = "text"
ttl = 5
role = "app-manager"

[[web.reads]]
words = "secret"
kind = "text"
ttl = 5
role = "admin"

[[web.changes]]
patterns = ['^light$']
role = "app-manager"

[[web.changes]]
fixed = ['^wipe$']
''')
        cfg = ws.Config()
        cfg.root, cfg.workgroup, cfg.realm, cfg.fail_delay = self.tmp, "HOME", "ad.home.lan", 0
        cfg.hs, cfg.session_file = "/nonexistent/hs", ""
        cfg.roles_file = os.path.join(here, "..", "scripts", "lib", "sys-roles.tsv")
        users = self.USERS

        class Auth:
            def __init__(self, cfg):
                self.cfg = cfg

            def local_fingerprint(self, user, fresh=False):
                return "fp"

            def storage_locked(self):
                return False

            def domain_password_ok(self, user, password):
                return user in users

            def domain_role(self, user):
                return users.get(user)

        self.calls, self.real_run = [], ws._run
        ws._run = lambda cmd, stdin=None, timeout=10: (self.calls.append(cmd) or (0, "ok\n"))
        self.app = ws.App(cfg, Auth(cfg))
        self.srv = ws.Server(("127.0.0.1", 0), ws.make_handler(self.app))
        self.port = self.srv.server_address[1]
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()
        self.sess = {}
        ws.ext_refresh(force=True)

    def tearDown(self):
        ws._run = self.real_run
        self.srv.shutdown()
        self.srv.server_close()
        write(self.caps, "")
        ws.ext_refresh(force=True)
        shutil.rmtree(self.tmp, ignore_errors=True)

    def req(self, method, path, body=None, headers=None):
        h = dict(headers or {})
        if body is not None:
            h["Content-Type"] = "application/json"
        if method == "POST":
            h.setdefault("Origin", "http://127.0.0.1:%d" % self.port)
        c = self.http.HTTPConnection("127.0.0.1", self.port)
        c.request(method, path, self.json.dumps(body) if body is not None else None, h)
        r = c.getresponse()
        raw = r.read()
        c.close()
        try:
            return r.status, self.json.loads(raw), r
        except ValueError:
            return r.status, raw, r

    def who(self, user):
        if user not in self.sess:
            s, d, r = self.req("POST", "/api/login", {"realm": "domain", "user": user, "password": "pw"})
            self.assertEqual(s, 200)
            self.sess[user] = ({"Cookie": r.getheader("Set-Cookie").split(";")[0]}, d["csrf"])
        return self.sess[user]

    def get(self, user, word):
        return self.req("GET", "/api/sys/ext/demo/" + word, headers=self.who(user)[0])[0]

    def post(self, user, verb, args):
        ck, csrf = self.who(user)
        return self.req("POST", "/api/" + verb, {"area": "ext/demo", "args": args}, dict(ck, **{"X-CSRF-Token": csrf}))[0]

    def test_a_read_without_role_is_admin_only(self):      # an old manifest
        self.assertEqual([self.get(u, "old") for u in ("vic", "mia", "anna")], [403, 403, 200])

    def test_an_admin_read_is_403_for_a_viewer_and_an_app_manager(self):
        self.assertEqual([self.get(u, "secret") for u in ("vic", "mia", "anna")], [403, 403, 200])

    def test_an_app_manager_read_works_for_an_app_manager_and_refuses_a_viewer(self):
        self.assertEqual([self.get(u, "manage") for u in ("vic", "mia", "anna")], [403, 200, 200])

    def test_a_viewer_read_works_for_everybody(self):
        self.assertEqual([self.get(u, "see") for u in ("vic", "mia", "anna")], [200, 200, 200])

    def test_the_403_names_both_roles_and_nothing_runs(self):
        s, d, _ = self.req("GET", "/api/sys/ext/demo/secret", headers=self.who("vic")[0])
        self.assertEqual((s, d["required"], d["role"]), (403, "admin", "viewer"))
        self.assertEqual(self.calls, [])

    def test_changes_use_the_role_of_their_entry(self):
        self.assertEqual([self.post(u, "plan", ["light"]) for u in ("vic", "mia", "anna")], [403, 200, 200])
        self.assertEqual([self.post(u, "plan", ["wipe"]) for u in ("vic", "mia", "anna")], [403, 403, 200])

    def test_a_token_never_exceeds_its_owners_role(self):
        # a token session carries its owner's role (tokens.check), so the same check refuses it
        self.assertFalse(ws.role_ok("viewer", ws.ext_need(["ext", "demo", "manage"], "viewer")))
        self.assertTrue(ws.role_ok("app-manager", ws.ext_need(["ext", "demo", "manage"], "viewer")))

    def test_an_unknown_role_drops_the_package(self):
        package(self.pk, "demo", [["sys", "sys ext demo see", "x.sh", "see", "h", "-"]],
                '[[web.reads]]\nwords = "see"\nkind = "text"\nttl = 5\nrole = "root"\n')
        ws.ext_refresh(force=True)
        self.assertNotIn(("ext", "demo", "see"), ws.READS)

    def test_the_core_row_still_counts(self):
        self.assertEqual(ws.ext_need(["ext", "demo", "see"], "admin"), "admin")      # the higher of the entry and the core row


if __name__ == "__main__":
    unittest.main()
