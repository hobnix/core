#!/usr/bin/env bash
# No page model returns a $derived by value (tests/web-model-getters.mjs), run with node.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
if ! command -v node >/dev/null 2>&1; then skip "node is not installed"; finish; exit 0; fi
node "$SCRIPTS/../tests/web-model-getters.mjs"
rc=$?
check_eq "no page model returns a derived by value" 0 "$rc"
finish
