#!/usr/bin/env python3
"""scripts/dev/testlab-browser.py `live` (#485): the measuring logic with a fake page and a fake clock (no browser, no VM), the scenario file
and the limits file. The playwright part and the ssh trigger are not run here (test-lab stage 6, needs the nested VM)."""
import importlib.util
import os
import unittest

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.join(here, "..")
spec = importlib.util.spec_from_file_location("tlb", os.path.join(root, "scripts", "dev", "testlab-browser.py"))
tlb = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tlb)

SC = {"name": "x", "path": "/apps", "before": "Not installed", "after": "Installed", "klass": "hook", "cmd": "true"}


class FakePage:
    """shows `before` until `delay` seconds of fake time after the trigger, then `after`"""

    def __init__(self, delay):
        self.now, self.delay, self.fired = 0.0, delay, None

    def clock(self):
        return self.now

    def sleep(self, s):
        self.now += s

    def trigger(self):
        self.fired = self.now

    def text(self):
        return "Installed" if self.fired is not None and self.now - self.fired >= self.delay else "Not installed"


class Measure(unittest.TestCase):
    def go(self, delay, limit, scenario=SC):
        p = FakePage(delay)
        return tlb.measure(scenario, limit, p.text, p.trigger, clock=p.clock, sleep=p.sleep)

    def test_within_the_limit_passes(self):
        ok, took, _ = self.go(0.5, 5)
        self.assertTrue(ok)
        self.assertAlmostEqual(took, 0.5, delta=0.2)

    def test_slower_than_the_limit_fails(self):
        ok, _, msg = self.go(8, 5)
        self.assertFalse(ok)
        self.assertIn("not shown within", msg)

    def test_limit_zero_fails_even_when_fast(self):
        self.assertFalse(self.go(0.5, 0)[0])
        self.assertFalse(self.go(0, 0)[0])

    def test_a_page_that_did_not_show_the_start_state_fails(self):
        ok, _, msg = self.go(1, 5, dict(SC, before="Running"))
        self.assertFalse(ok)
        self.assertIn("before the change", msg)

    def test_the_trigger_runs_once_and_after_the_first_check(self):
        calls = []
        p = FakePage(1)
        tlb.measure(SC, 5, p.text, lambda: (calls.append(1), p.trigger()), clock=p.clock, sleep=p.sleep)
        self.assertEqual(calls, [1])


class Files(unittest.TestCase):
    def test_limits_file_has_the_two_classes(self):
        lim = tlb.load_limits(os.path.join(root, "scripts", "lib", "live-limits.tsv"))
        self.assertEqual((lim["hook"], lim["timed"]), (5.0, 20.0))

    def test_scenarios_use_known_limit_classes(self):
        lim = tlb.load_limits(os.path.join(root, "scripts", "lib", "live-limits.tsv"))
        rows = tlb.load_scenarios(os.path.join(root, "scripts", "dev", "testlab-live.tsv"))
        self.assertEqual(len(rows), 4)
        for r in rows:
            self.assertIn(r["klass"], lim)
            self.assertTrue(r["path"].startswith("/") and r["cmd"] and r["before"] != r["after"])


if __name__ == "__main__":
    unittest.main()
