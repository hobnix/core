#!/usr/bin/env bash
# The core-only profile: no capability switched on and no package repository checkout (the state of a core before hobnix/official is fetched, and
# the state CI proves with one checkout of official, hobnix/core#1074 P1). "Core-only works" means exactly this:
#   1. `hs help` runs and `hs smoke --list` answers with no packages root at all;
#   2. with the one-repository fixture of official (tests/fixtures/official: recipes/, extensions/, capabilities/ in one index) as the packages
#      root, the tree validates and repo-check passes, as CI runs them against the real checkout, and hs still loads.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
export HS_LANG=en HS_PLAIN=1
export HS_CAPABILITIES_FILE=$WORK/capabilities HS_STATE_DIR=$WORK/state HS_HEALTH_STATE=$WORK/health.state HS_NOTIFY_URL=
mkdir -p "$HS_STATE_DIR"
: > "$HS_CAPABILITIES_FILE"
HS="bash $SCRIPTS/lib/hs.sh"

echo "-- no package repository at all"
export HS_PACKAGES_ROOT=$WORK/none
out=$($HS help --all 2>&1); rc=$?
check_eq "hs help runs" "0" "$rc"
if grep -qiE 'command not found|syntax error|Traceback' <<<"$out"; then fail "no shell error in hs help"; else pass "no shell error in hs help"; fi
out=$(HS_SMOKE_TOOLS="" HS_SMOKE_PROBES= bash "$SCRIPTS/smoke.sh" --no-run --list 2>&1); rc=$?
check_eq "hs smoke --list answers" "0" "$rc"

echo "-- one official checkout (the fixture)"
have python3 || { skip "needs python3"; finish; exit 0; }
O=$ROOT/tests/fixtures/official
mkdir -p "$WORK/tree"
ln -s "$O/recipes" "$WORK/tree/packages"; ln -s "$O/extensions" "$WORK/tree/capabilities"
out=$(HS_PACKAGES_ROOT=$WORK/tree python3 -I "$SCRIPTS/pkg.py" validate 2>&1); rc=$?
check_eq "the tree validates" "0" "$rc"
out=$(python3 -I "$SCRIPTS/pkg.py" repo-check "$O" 2>&1); rc=$?
check_eq "repo-check of the checkout passes" "0" "$rc"
export HS_PACKAGES_ROOT=$WORK/tree
out=$($HS help --all 2>&1); rc=$?
check_eq "hs help still runs with the packages root" "0" "$rc"
finish
