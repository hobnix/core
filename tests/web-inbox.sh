#!/usr/bin/env bash
# ErrorNote and Inbox logic (web/src/ui/errornote.js, web/src/shell/inbox.js), run with node.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
if ! command -v node >/dev/null 2>&1; then skip "node is not installed"; finish; exit 0; fi
node "$SCRIPTS/../tests/web-inbox.mjs"
rc=$?
check_eq "the errornote and inbox tests pass" 0 "$rc"
finish
