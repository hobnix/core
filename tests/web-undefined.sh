#!/usr/bin/env bash
# No .svelte file uses a name nothing declares (tests/web-undefined.mjs), run with node.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
if ! command -v node >/dev/null 2>&1; then skip "node is not installed"; finish; exit 0; fi
node "$SCRIPTS/../tests/web-undefined.mjs"
rc=$?
check_eq "no svelte file uses an undefined name" 0 "$rc"
finish
