#!/usr/bin/env bash
# #485: the live scenarios of test-lab stage 6 (scripts/dev/testlab-browser.py live): measuring logic with a fake page, the scenario file, the wiring.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
if ! have python3; then skip "python3 missing"; finish; exit 0; fi
echo "-- test-lab live scenarios (fake page, limit as a parameter)"
if out=$(python3 -I "$ROOT/tests/testlab-live-test.py" 2>&1); then pass "testlab live ($(grep -E '^Ran ' <<<"$out"))"; else fail "testlab live: $(tail -n 25 <<<"$out")"; fi
check "stage 6 runs the live scenarios when HS_TESTLAB_LIVE_SSH is set" grep -q 'testlab-browser.py" live' "$SCRIPTS/testlab.sh"
check "the limit can be set for the stage (0 must fail)" grep -q 'HS_TESTLAB_LIVE_LIMIT' "$SCRIPTS/testlab.sh"
finish
