#!/usr/bin/env bash
# Overlay keyboard logic (web/src/ui/focus.js, menu-nav.js), run with node.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
if ! command -v node >/dev/null 2>&1; then skip "node is not installed"; finish; exit 0; fi
node "$SCRIPTS/../tests/web-overlays.mjs" >/dev/null
rc=$?
check_eq "the overlay keyboard tests pass" 0 "$rc"
finish
