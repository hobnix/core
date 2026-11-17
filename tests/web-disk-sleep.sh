#!/usr/bin/env bash
# The sleep state of the Disks page (web/src/disk-sleep.js), run with node.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
if ! command -v node >/dev/null 2>&1; then skip "node is not installed"; finish; exit 0; fi
node "$SCRIPTS/../tests/web-disk-sleep.mjs" >/dev/null
rc=$?
check_eq "the disk sleep tests pass" 0 "$rc"
finish
