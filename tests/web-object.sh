#!/usr/bin/env bash
# The Object frame, the disk page and the quick look of the web interface (docs/PLAN-navigation.md step 1), run with node.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
if ! command -v node >/dev/null 2>&1; then skip "node is not installed"; finish; exit 0; fi
node "$SCRIPTS/../tests/web-object.mjs"
rc=$?
check_eq "the object frame tests pass" 0 "$rc"
finish
