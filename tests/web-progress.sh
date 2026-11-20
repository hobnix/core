#!/usr/bin/env bash
# Progress and StepList helpers (web/src/ui/progress.js), run with node.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
if ! command -v node >/dev/null 2>&1; then skip "node is not installed"; finish; exit 0; fi
node "$SCRIPTS/../tests/web-progress.mjs"
rc=$?
check_eq "the progress helper tests pass" 0 "$rc"
finish
