#!/usr/bin/env bash
# The pure logic of the chart and stat blocks (web/src/shell/generic.js, #473), run with node.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
if ! command -v node >/dev/null 2>&1; then skip "node is not installed"; finish; exit 0; fi
node "$SCRIPTS/../tests/web-blocks.mjs"
rc=$?
check_eq "the chart and stat tests pass" 0 "$rc"
finish
