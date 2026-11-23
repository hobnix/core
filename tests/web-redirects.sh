#!/usr/bin/env bash
# The old-address table (web/src/redirects.js) against the snapshot of the 0.10 tree (tests/fixtures/old-tree.json): every old path lands on a page, no loop. Run with node.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
if ! command -v node >/dev/null 2>&1; then skip "node is not installed"; finish; exit 0; fi
node "$SCRIPTS/../tests/web-redirects.mjs"
rc=$?
check_eq "the redirect tests pass" 0 "$rc"
finish
