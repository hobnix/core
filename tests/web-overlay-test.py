#!/usr/bin/env python3
"""scripts/web-serve.py: what installed capability packages add (step 6c): the keys the web may set (config-keys.overlay) and layout.overlay.json."""
import importlib.util
import json
import os
import re
import tempfile
import unittest

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("web_serve", os.path.join(here, "..", "scripts", "web-serve.py"))
ws = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ws)


def write(d, name, text):
    os.makedirs(os.path.join(d, "generated"), exist_ok=True)
    with open(os.path.join(d, "generated", name), "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


class Overlay(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.old = os.environ.get("HS_STATE_DIR")
        os.environ["HS_STATE_DIR"] = self.tmp.name

    def tearDown(self):
        if self.old is None:
            os.environ.pop("HS_STATE_DIR", None)
        else:
            os.environ["HS_STATE_DIR"] = self.old
        self.tmp.cleanup()

    def test_nothing_installed(self):
        self.assertEqual(ws.overlay_settable(), [])
        self.assertEqual(ws.overlay_layout(), {})
        e = ws._config_entries("")
        self.assertTrue(re.fullmatch(e[0][1], "language"))

    def test_settable_keys_only(self):
        write(self.tmp.name, "config-keys.overlay",
              "# generated\nzetaHost\tyes\t-\tmachine\tzeta\nzetaSecret\t-\tsecret\tmachine\tzeta\nBad|Key\tyes\t-\tmachine\tzeta\nalphaA\tyes\t-\tsettings\talpha\n")
        self.assertEqual(ws.overlay_settable(), ["alphaA", "zetaHost"])
        e = ws._config_entries("|".join(ws.overlay_settable()))
        self.assertTrue(re.fullmatch(e[0][1], "zetaHost"))
        self.assertFalse(re.fullmatch(e[0][1], "zetaSecret"))
        self.assertTrue(re.fullmatch(e[0][1], "language"))
        self.assertTrue(re.fullmatch(e[2]["opts"]["--set"][0], "alphaA=x"))
        self.assertFalse(re.fullmatch(e[2]["opts"]["--set"][0], "zetaSecret=x"))

    def test_layout(self):
        write(self.tmp.name, "layout.overlay.json", json.dumps({"keys": {"a": "cap:z"}, "caps": {"z": {"title": "Z", "icon": "x", "entry": True}}}))
        self.assertEqual(ws.overlay_layout()["keys"], {"a": "cap:z"})
        write(self.tmp.name, "layout.overlay.json", "[1]")
        self.assertEqual(ws.overlay_layout(), {})
        write(self.tmp.name, "layout.overlay.json", "{broken")
        self.assertEqual(ws.overlay_layout(), {})


if __name__ == "__main__":
    unittest.main()
