#!/usr/bin/env python3
"""The axe check of test-lab stage 6 (scripts/dev/testlab-browser.py, #487): a finding that is not in the baseline fails, a listed one does not, a
fixture with a missing label (axe rule `label`) fails. The browser and axe-core are not run here (needs the nested VM)."""
import importlib.util
import os
import tempfile
import unittest

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("tlb", os.path.join(here, "..", "scripts", "dev", "testlab-browser.py"))
tlb = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tlb)

# what axe.run() returns for <input type="text"> without a label
MISSING_LABEL = [{"id": "label", "impact": "critical", "nodes": [{"target": ["#name"]}]}]


class AxeBaseline(unittest.TestCase):
    def test_missing_label_fails_without_baseline(self):
        new = tlb.axe_new("/apps", MISSING_LABEL, set())
        self.assertEqual([(n[1], n[3]) for n in new], [("label", "#name")])

    def test_listed_finding_passes(self):
        base = {tlb.axe_key("/apps", MISSING_LABEL[0], MISSING_LABEL[0]["nodes"][0])}
        self.assertEqual(tlb.axe_new("/apps", MISSING_LABEL, base), [])

    def test_same_finding_on_another_page_is_new(self):
        base = {tlb.axe_key("/apps", MISSING_LABEL[0], MISSING_LABEL[0]["nodes"][0])}
        self.assertEqual(len(tlb.axe_new("/disks", MISSING_LABEL, base)), 1)

    def test_second_node_of_a_listed_rule_is_new(self):
        v = [{"id": "label", "nodes": [{"target": ["#name"]}, {"target": ["#other"]}]}]
        base = {tlb.axe_key("/apps", v[0], v[0]["nodes"][0])}
        self.assertEqual([n[3] for n in tlb.axe_new("/apps", v, base)], ["#other"])

    def test_clean_page_passes(self):
        self.assertEqual(tlb.axe_new("/apps", [], set()), [])

    def test_baseline_file(self):
        self.assertEqual(tlb.load_axe_baseline(None), set())
        self.assertEqual(tlb.load_axe_baseline(os.path.join(here, "no-such-file.tsv")), set())
        with tempfile.NamedTemporaryFile("w", suffix=".tsv", delete=False) as f:
            f.write("# comment\n/apps\tlabel\t#name\n\n")
        try:
            self.assertEqual(tlb.load_axe_baseline(f.name), {"/apps\tlabel\t#name"})
        finally:
            os.unlink(f.name)

    def test_real_baseline_has_only_well_formed_rows(self):
        for row in tlb.load_axe_baseline(os.path.join(here, "..", "scripts", "dev", "axe-baseline.tsv")):
            self.assertEqual(len(row.split("\t")), 3, row)


if __name__ == "__main__":
    unittest.main()
