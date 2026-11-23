#!/usr/bin/env bash
# The pure logic of the log and progress blocks (web/src/shell/generic.js), run with node.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
if ! command -v node >/dev/null 2>&1; then skip "node is not installed"; finish; exit 0; fi
node "$SCRIPTS/../tests/web-blocks-logprogress.mjs"
rc=$?
check_eq "the log and progress block tests pass" 0 "$rc"
finish
