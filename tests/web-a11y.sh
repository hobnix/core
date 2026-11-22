#!/usr/bin/env bash
# Accessibility acceptance without a browser (docs/PLAN-navigation.md step 11, #487): the label check (a fixture with a missing label fails), the contrast of
# the tokens in both themes, the keyboard checklist as source checks (tests/web-a11y.mjs, node), and the axe baseline logic of test-lab stage 6
# (tests/web-a11y-axe-test.py). The keyboard walk of every page and the screen reader run need a real browser: not run here.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
if ! command -v node >/dev/null 2>&1; then skip "node is not installed"; else
  out=$(node "$ROOT/tests/web-a11y.mjs" 2>&1); rc=$?
  check_eq "label check, token contrast and keyboard checklist pass" 0 "$rc"
  [ "$rc" = 0 ] && : || printf '%s\n' "$out" | grep -v '^  ok'
  out=$(node "$ROOT/tests/web-a11y-contrast.mjs" 2>&1); rc=$?
  check_eq "the tokens reach WCAG AA in both themes" 0 "$rc"
  [ "$rc" = 0 ] && : || printf '%s\n' "$out"
fi
if have python3; then
  if out=$(python3 -I "$ROOT/tests/web-a11y-axe-test.py" 2>&1); then pass "axe baseline ($(grep -E '^Ran ' <<<"$out"))"; else fail "axe baseline: $(tail -n 25 <<<"$out")"; fi
else skip "python3 missing"; fi
check "stage 6 passes the axe script and the baseline when HS_TESTLAB_AXE_JS is set" grep -q 'axe-baseline.tsv' "$SCRIPTS/testlab.sh"
finish
