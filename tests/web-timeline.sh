#!/usr/bin/env bash
# Timeline helpers (web/src/ui/timeline.js), run with node.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
if ! command -v node >/dev/null 2>&1; then skip "node is not installed"; finish; exit 0; fi
node "$SCRIPTS/../tests/web-timeline.mjs"
rc=$?
check_eq "the timeline helper tests pass" 0 "$rc"
finish
