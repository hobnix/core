#!/usr/bin/env bash
# The first-run Storage step logic (web/src/setup/storage.js), run with node.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
if ! command -v node >/dev/null 2>&1; then skip "node is not installed"; finish; exit 0; fi
node "$SCRIPTS/../tests/web-storage-step.mjs"
rc=$?
check_eq "the storage step tests pass" 0 "$rc"
finish
