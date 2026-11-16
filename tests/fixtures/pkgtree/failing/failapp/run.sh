#!/usr/bin/env bash
# recipe: Fixture app that fails on purpose (tests of a failed install: no real app)
# kind: generic
# needs: -
# uses: -
# phases: fetch configure
# RECIPE_FAIL_AT=<phase> makes that phase fail, as an unreachable image would; each phase records what it makes in the created ledger.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "${HS_SCRIPTS:-$here/../../../../../scripts}/lib/created.sh"
CREATED_APP=${CREATED_APP:-failapp}
phase=${RECIPE_PHASE:-run}
case "$phase" in
  fetch)     created container "$CREATED_APP" container; created reservation 10.0.0.9 aa:bb:cc:dd:ee:09 ;;
  configure) created service "$CREATED_APP" ;;
esac
if [ "${RECIPE_FAIL_AT:-}" = "$phase" ]; then echo "cannot pull the image (the fixture fails at $phase on purpose)" >&2; exit 1; fi
echo "failapp $phase done"
