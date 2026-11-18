#!/usr/bin/env bash
# Web interface backend: the settable keys and the Settings layout of installed capability packages (scripts/web-serve.py, step 6c).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
if ! have python3; then skip "python3 missing"; finish; exit 0; fi

echo "-- web overlay"
if out=$(python3 -I "$ROOT/tests/web-overlay-test.py" 2>&1); then pass "overlay tests ($(grep -E '^Ran ' <<<"$out"))"; else fail "overlay tests: $(tail -n 25 <<<"$out")"; fi
finish
