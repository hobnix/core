#!/usr/bin/env bash
# The rows of the list Apps & VMs (web/src/pages/workloads.js): nesting, the App column, filters, the context row, sorting two levels. Run with node.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
if ! command -v node >/dev/null 2>&1; then skip "node is not installed"; finish; exit 0; fi
node "$SCRIPTS/../tests/web-workloads.mjs"
rc=$?
check_eq "the Apps and VMs list tests pass" 0 "$rc"
finish
