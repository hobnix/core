#!/usr/bin/env bash
# The pending state of a row from job events and records (web/src/rowstate.js), run with node.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
if ! command -v node >/dev/null 2>&1; then skip "node is not installed"; finish; exit 0; fi
node "$SCRIPTS/../tests/web-rowstate.mjs"
rc=$?
check_eq "the row state tests pass" 0 "$rc"
finish
