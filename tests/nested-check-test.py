#!/usr/bin/env python3
"""scripts/dev/nested_check.py: the dry check of the test-lab stages. The real stages must pass, and each wrong assumption that once cost a
full run (hobnix/server#712) must be found."""
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "scripts", "dev"))
import nested_check as c  # noqa: E402


def bad(text, **kw):
    s = {"kind": "run", "text": text, "what": "t"}
    s.update(kw)
    return c.check_steps([s], name="t")


def has(problems, needle):
    return any(needle in p for p in problems)


class RealStages(unittest.TestCase):
    def test_every_stage_passes(self):
        self.assertEqual(c.check_all(ROOT), [])

    def test_stages_are_covered(self):
        names = [n for n, _ in c.scenarios()]
        for stage in ("rollback", "backup", "restore", "pool", "upgrade"):
            self.assertIn(stage, names)


class Wrong(unittest.TestCase):
    def test_unknown_command(self):
        self.assertTrue(has(bad("hs frobnicate now"), "no registry row"))

    def test_rebuild_yes_is_not_a_flag(self):
        self.assertTrue(has(bad("hs rebuild --yes"), "--yes is not a flag"))

    def test_rebuild_foreground_is_fine(self):
        self.assertEqual(bad("hs rebuild --foreground"), [])

    def test_long_command_needs_foreground(self):
        self.assertTrue(has(bad("hs backup now"), "add --foreground"))
        self.assertEqual(bad("hs backup now --foreground"), [])

    def test_piped_output_has_no_terminal(self):
        self.assertEqual(bad("hs update --yes 2>&1 | tail -n 40"), [])

    def test_sys_by_hand_asks(self):
        self.assertTrue(has(bad("hs sys fm locations"), "HS_CALLER"))
        self.assertEqual(bad("HS_CALLER=test hs sys fm locations"), [])
        self.assertEqual(bad("hs sys fm locations | grep -q x"), [])

    def test_sudo_n(self):
        self.assertTrue(has(bad("sudo -n true"), "sudo -n"))
        self.assertEqual(bad("sudo -k"), [])

    def test_unknown_flag_of_sys_command(self):
        self.assertTrue(has(bad("HS_CALLER=test hs sys pool start fast add --diskz x"), "--diskz"))

    def test_disks_by_device_name(self):
        self.assertTrue(has(bad("HS_CALLER=test hs sys pool start fast add --disks /dev/sdb,/dev/sdc"), "by-id"))

    def test_disks_from_readlink_variable(self):
        steps = [{"kind": "capture", "text": "readlink -f /dev/disk/by-id/*incus_x", "var": "d", "what": "a"},
                 {"kind": "run_var", "text": "HS_CALLER=test hs sys pool plan fast add --disks {d}", "what": "b"}]
        self.assertTrue(has(c.check_steps(steps, name="t"), "by-id"))
        steps[0]["text"] = "ls /dev/disk/by-id/ | grep incus_x"
        self.assertEqual(c.check_steps(steps, name="t"), [])

    def test_unbalanced_quote(self):
        self.assertTrue(has(bad("hs config set x 'y"), "cannot split"))

    def test_captured_in_dollar_paren(self):
        self.assertEqual(bad("out=$(hs backup now); echo $out"), [])
        self.assertTrue(has(bad("echo x; hs backup now"), "long command"))

    def test_row_values_and_words(self):
        self.assertEqual(bad("hs pool bulk | grep -q data"), [])


if __name__ == "__main__":
    unittest.main()
