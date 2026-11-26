#!/usr/bin/env bash
# Shares page views Local, Remote, Kept folders (issue #1151): source checks of the page, the Remote view and the Network page. Run with node.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
if ! command -v node >/dev/null 2>&1; then skip "node is not installed"; finish; exit 0; fi
node "$SCRIPTS/../tests/web-shares-views.mjs"
rc=$?
check_eq "the shares views tests pass" 0 "$rc"
finish
