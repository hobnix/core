#!/usr/bin/env bash
# The remote share code forms (web/src/forms/ops/remotecode.js, Remote*.svelte), run with node.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
if ! command -v node >/dev/null 2>&1; then skip "node is not installed"; finish; exit 0; fi
node "$SCRIPTS/../tests/web-remote-code.mjs"
rc=$?
check_eq "the remote code form tests pass" 0 "$rc"
finish
