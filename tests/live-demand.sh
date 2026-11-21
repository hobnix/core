#!/usr/bin/env bash
# Demand-driven sampling (docs/PLAN-live-interface.md step 15, D14): the table `demand`, column 9 of live-topics.tsv, the collector's pace, the leases of hs-web.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
if ! have python3; then skip "python3 missing"; finish; exit 0; fi
echo "-- live demand (leases, idle interval)"
if out=$(python3 -I "$ROOT/tests/live-demand-test.py" 2>&1); then pass "live demand tests ($(grep -E '^Ran ' <<<"$out"))"; else fail "live demand: $(tail -n 25 <<<"$out")"; fi
finish
