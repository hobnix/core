#!/usr/bin/env bash
# The selection foundation of the web interface (?sel= and its history rule, the table of named places, the object registry), run with node.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
if ! command -v node >/dev/null 2>&1; then skip "node is not installed"; finish; exit 0; fi
node "$SCRIPTS/../tests/web-select.mjs"
rc=$?
check_eq "the selection tests pass" 0 "$rc"
finish
