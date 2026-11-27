#!/usr/bin/env bash
# The pictures of a package (GET /api/pkg/asset, scripts/web-serve.py): session, role, name checks, type and size, nosniff and sandbox CSP.
# A fake hs answers by file name.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
if ! have python3; then skip "python3 missing"; finish; exit 0; fi

echo "-- web package pictures"
if out=$(python3 -I "$ROOT/tests/web-pkg-asset-test.py" 2>&1); then pass "web package picture tests ($(grep -E '^Ran ' <<<"$out"))"; else fail "web roles tests: $(tail -n 25 <<<"$out")"; fi
finish
