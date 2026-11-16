#!/usr/bin/env bash
# `hs pool bulk add` of the first data disks (SnapRAID, no parity disk yet) must not end with exit 1 at the closing table: df fails for the
# parity-* that matches nothing, and under `set -euo pipefail` that ended the job right after /bulk was mounted (found by the test-lab, run 23).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
line=$(grep -F 'df -h /bulk "$(disks_root)"/data-*' "$SCRIPTS/manage-pool.sh" | head -n1)
check "the closing table is in manage-pool.sh" test -n "$line"
mkdir -p "$WORK/disks/data-01"
out=$(bash -c "set -euo pipefail; disks_root() { echo '$WORK/disks'; }; $line; echo survived" 2>&1 || true)
check_out "the table does not end the script when there is no parity disk" "survived" echo "$out"
finish
