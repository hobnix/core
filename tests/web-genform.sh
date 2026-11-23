#!/usr/bin/env bash
# The helpers of the declared form block (web/src/shell/genform.js): checks, plan arguments, the secret only as stdin. Run with node.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
if ! command -v node >/dev/null 2>&1; then skip "node is not installed"; finish; exit 0; fi
node "$SCRIPTS/../tests/web-genform.mjs"
rc=$?
check_eq "the genform tests pass" 0 "$rc"
finish
