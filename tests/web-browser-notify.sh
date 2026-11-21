#!/usr/bin/env bash
# Browser notifications logic (web/src/shell/notify.js), run with node.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
if ! command -v node >/dev/null 2>&1; then skip "node is not installed"; finish; exit 0; fi
node "$SCRIPTS/../tests/web-browser-notify.mjs"
rc=$?
check_eq "the browser notification tests pass" 0 "$rc"
finish
