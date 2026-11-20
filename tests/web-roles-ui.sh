#!/usr/bin/env bash
# The role-aware web interface (web/src/roles.js, nav.js, the wiring of the shell), run with node.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
if ! command -v node >/dev/null 2>&1; then skip "node is not installed"; finish; exit 0; fi
node "$SCRIPTS/../tests/web-roles-ui.mjs"
rc=$?
check_eq "the role-aware interface tests pass" 0 "$rc"
finish
