#!/usr/bin/env bash
# The tree switch (web/src/nav.js, D2 c): the new tree against the old one, roles, capabilities, extension groups. Run with node.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
if ! command -v node >/dev/null 2>&1; then skip "node is not installed"; finish; exit 0; fi
node "$SCRIPTS/../tests/web-tree.mjs"
rc=$?
check_eq "the tree tests pass" 0 "$rc"
finish
