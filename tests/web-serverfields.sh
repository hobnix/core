#!/usr/bin/env bash
# The server-aware form fields (web/src/ui ShareField, DiskField, PoolField, InstanceField, UserField, the search of Combobox): parse, filters and the static contract, run with node.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
if ! command -v node >/dev/null 2>&1; then skip "node is not installed"; finish; exit 0; fi
out=$(node "$SCRIPTS/../tests/web-serverfields.mjs" 2>&1)
rc=$?
check_eq "server-aware form fields keep their contract" 0 "$rc"
[ "$rc" = 0 ] || printf '%s\n' "$out"
finish
