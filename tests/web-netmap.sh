#!/usr/bin/env bash
# The layout of the network map (web/src/netmap/layout.js, #874), run with node.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
if ! command -v node >/dev/null 2>&1; then skip "node is not installed"; finish; exit 0; fi
if o=$(node "$ROOT/tests/web-netmap-layout.mjs" 2>&1); then pass "map layout ($(grep -E '^  -> ' <<<"$o"))"; else fail "map layout: $(grep -E 'FAIL|Error' <<<"$o" | head -n 12)"; fi
if o=$(node "$ROOT/tests/web-netmap-dots.mjs" 2>&1); then pass "map dots ($(grep -E '^  -> ' <<<"$o"))"; else fail "map dots: $(grep -E 'FAIL|Error' <<<"$o" | head -n 12)"; fi
if have python3; then
  if o=$(python3 -I "$ROOT/tests/web-netmap-stream-test.py" 2>&1); then pass "map counters stream ($(grep -E '^Ran ' <<<"$o"))"; else fail "map counters stream: $(tail -n 20 <<<"$o")"; fi
else skip "python3 missing"; fi
finish
