#!/usr/bin/env bash
# #485: an action updates the open page without a reload, within the limit of scripts/lib/live-limits.tsv (tests/live-e2e-test.py).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
if ! have python3; then skip "python3 missing"; finish; exit 0; fi
echo "-- live end to end (change counter, stream, open page; no timer)"
if out=$(python3 -I "$ROOT/tests/live-e2e-test.py" 2>&1); then pass "live e2e ($(grep -E '^Ran ' <<<"$out"); $(grep -c -- "-> " <<<"$out") timings)"; else fail "live e2e: $(tail -n 25 <<<"$out")"; fi
finish
