#!/usr/bin/env bash
# Stepper helpers (web/src/ui/stepper.js), run with node.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
if ! command -v node >/dev/null 2>&1; then skip "node is not installed"; finish; exit 0; fi
node "$SCRIPTS/../tests/web-stepper.mjs"
rc=$?
check_eq "the stepper helper tests pass" 0 "$rc"
finish
