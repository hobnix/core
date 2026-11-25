#!/usr/bin/env bash
# The early reads of the web interface after unlock and the one running request per address (web/src/api.js get), run with node.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
if ! have node; then skip "node is not installed"; finish; exit 0; fi
echo "-- early reads and shared requests"
if o=$(node "$ROOT/tests/web-early-reads.mjs" 2>&1); then pass "early and shared reads ($(grep -E '^  -> ' <<<"$o"))"; else fail "early and shared reads: $(tail -n 25 <<<"$o")"; fi
if o=$(node "$ROOT/tests/web-session-reads.mjs" 2>&1); then pass "sign-out and lock ($(grep -E '^  -> ' <<<"$o"))"; else fail "sign-out and lock: $(tail -n 25 <<<"$o")"; fi
finish
