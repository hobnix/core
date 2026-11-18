#!/usr/bin/env bash
# Web interface roles (ADR 0012, scripts/web-serve.py): viewer, app manager and admin get exactly the calls the x-hs-role of every sys row allows,
# a refused call is a 403 that runs nothing, the local account is an admin, a change runs with HS_ACTOR = the signed-in person. Fake helpers.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
if ! have python3; then skip "python3 missing"; finish; exit 0; fi

echo "-- web roles"
if out=$(python3 -I "$ROOT/tests/web-roles-test.py" 2>&1); then pass "web roles tests ($(grep -E '^Ran ' <<<"$out"))"; else fail "web roles tests: $(tail -n 25 <<<"$out")"; fi
finish
