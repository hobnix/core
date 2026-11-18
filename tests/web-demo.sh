#!/usr/bin/env bash
# Demo mode (web/demo/): a fixture for every allowlisted read, plans open, starts are refused. Run with node.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
if ! command -v node >/dev/null 2>&1; then skip "node is not installed"; finish; exit 0; fi
node "$SCRIPTS/../tests/web-demo.mjs"
rc=$?
check_eq "the demo mode tests pass" 0 "$rc"
finish
