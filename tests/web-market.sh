#!/usr/bin/env bash
# The Marketplace store logic (web/src/pages/market.js), run with node.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
if ! command -v node >/dev/null 2>&1; then skip "node is not installed"; finish; exit 0; fi
node "$SCRIPTS/../tests/web-market.mjs"
rc=$?
check_eq "the marketplace tests pass" 0 "$rc"
finish
