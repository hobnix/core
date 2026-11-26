#!/usr/bin/env bash
# The breadcrumb trail and the marks of the tree (web/src/nav.js), run with node.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
if ! command -v node >/dev/null 2>&1; then skip "node is not installed"; finish; exit 0; fi
node "$SCRIPTS/../tests/web-trail.mjs"
rc=$?
check_eq "the trail tests pass" 0 "$rc"
finish
