#!/usr/bin/env bash
# The info rows of package health checks on the Health page (web/src/pages/healthinfo.js), run with node.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
if ! command -v node >/dev/null 2>&1; then skip "node is not installed"; finish; exit 0; fi
node "$SCRIPTS/../tests/web-health-info.mjs"
rc=$?
check_eq "the health info tests pass" 0 "$rc"
finish
