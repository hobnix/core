#!/usr/bin/env bash
# The action slot logic (web/src/shell/slots.js) with node; the Svelte row and header are not run here.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
if ! command -v node >/dev/null 2>&1; then skip "node is not installed"; finish; exit 0; fi
node "$ROOT/tests/web-slots.mjs"
rc=$?
check_eq "the slot tests pass" 0 "$rc"
finish
