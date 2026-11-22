#!/usr/bin/env bash
# The group pages of the web interface (docs/PLAN-navigation.md step 9): state lines with fixtures and the rules of the pages, run with node.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
if ! command -v node >/dev/null 2>&1; then skip "node is not installed"; finish; exit 0; fi
node "$SCRIPTS/../tests/web-groups.mjs"
rc=$?
check_eq "the group page tests pass" 0 "$rc"
finish
