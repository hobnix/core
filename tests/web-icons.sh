#!/usr/bin/env bash
# Icons: every literal icon name used in web/src is on the one list (web/src/ui/icons.js), run with node.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
if ! command -v node >/dev/null 2>&1; then skip "node is not installed"; finish; exit 0; fi
out=$(node "$SCRIPTS/../tests/web-icons.mjs" 2>&1)
rc=$?
check_eq "every literal icon name is in ui/icons.js" 0 "$rc"
[ "$rc" = 0 ] || printf '%s\n' "$out"
finish
