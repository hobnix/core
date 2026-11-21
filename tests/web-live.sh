#!/usr/bin/env bash
# Live state of the web interface (scripts/web-serve.py LiveStore): topic reads from the state database, no collector = the direct read, `_sys` goes through app.store.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
if ! have python3; then skip "python3 missing"; finish; exit 0; fi
echo "-- live state (LiveStore on the state database, /api/events)"
if out=$(python3 -I "$ROOT/tests/web-live-test.py" 2>&1); then pass "live state tests ($(grep -E '^Ran ' <<<"$out"))"; else fail "live state: $(tail -n 25 <<<"$out")"; fi
if have node; then
  if o=$(node "$ROOT/tests/web-live.mjs" 2>&1); then pass "poll timing ($(grep -E '^  -> ' <<<"$o"))"; else fail "poll timing: $(tail -n 12 <<<"$o")"; fi
  if o=$(node "$ROOT/tests/web-delaysample.mjs" 2>&1); then pass "delay sample ($(grep -E '^  -> ' <<<"$o"))"; else fail "delay sample: $(tail -n 12 <<<"$o")"; fi
  if o=$(node "$ROOT/tests/web-plan-timeout.mjs" 2>&1); then pass "plan/start timeout ($(grep -E '^  -> ' <<<"$o"))"; else fail "plan/start timeout: $(tail -n 12 <<<"$o")"; fi
  if o=$(node "$ROOT/tests/web-plan-pool.mjs" 2>&1); then pass "plan prefetch pool ($(grep -E '^  -> ' <<<"$o"))"; else fail "plan prefetch pool: $(tail -n 12 <<<"$o")"; fi
  if [ "$(uname -s)" = Linux ]; then if o=$(python3 -I "$ROOT/tests/web-plan-start-test.py" 2>&1); then pass "plan then start, slow hs ($(grep -E "^Ran " <<<"$o"))"; else fail "plan then start: $(tail -n 20 <<<"$o")"; fi; fi
else skip "node missing"; fi
finish
