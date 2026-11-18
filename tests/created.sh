#!/usr/bin/env bash
# The created ledger (scripts/lib/created.sh): a run writes only what it created; a re-run over an existing app writes nothing. No server needed.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
export HS_LANG=en HS_PLAIN=1 HS_STATE_DIR=$WORK/state
mkdir -p "$WORK/bin" "$HS_STATE_DIR"
F=$HS_STATE_DIR/apps/demo.toml
L() { CREATED_APP=${APP-demo} bash -c '. "$1/lib/created.sh"; shift; "$@"' _ "$SCRIPTS" "$@"; }

echo "-- writing"
APP= L created container demo
check "no app, no record" test ! -e "$HS_STATE_DIR/apps"
L created container demo container
L created reservation 10.0.0.5 aa:bb:cc:dd:ee:ff
L created service demo
check "one record file per app" test -f "$F"
check_eq "three lines listed" 3 "$(L created_list | wc -l)"
check_eq "a line has kind, id, detail" "reservation	10.0.0.5	aa:bb:cc:dd:ee:ff" "$(L created_list | sed -n 2p)"
check_eq "an empty detail is -" "service	demo	-" "$(L created_list | sed -n 3p)"

echo "-- a re-run writes nothing new"
before=$(cksum <"$F")
L created container demo container
L created reservation 10.0.0.5 aa:bb:cc:dd:ee:ff
check_eq "the record is byte for byte the same" "$before" "$(cksum <"$F")"
APP=other L created_list >/dev/null
check "an app that created nothing has no file" test ! -e "$HS_STATE_DIR/apps/other.toml"

echo "-- quotes are not written"
L created share 'we"ird' '/x/a\b'
check_eq "no quote or backslash in a value" "share	weird	/x/ab" "$(L created_list | tail -n1)"

echo "-- check and drop"
mkdir -p "$WORK/shr" "$HS_STATE_DIR/services.d"; : >"$HS_STATE_DIR/services.d/demo.toml"
check "service is there" L created_check service demo
check "share dir is there" L created_check share x "$WORK/shr"
check_eq "share dir gone: 1" 1 "$(L created_check share x "$WORK/none" >/dev/null 2>&1; echo $?)"
check_eq "unknown kind: cannot tell (2)" 2 "$(L created_check zzz x >/dev/null 2>&1; echo $?)"
L created_drop service demo
check_eq "drop takes only that line" 3 "$(L created_list | wc -l)"
L created_drop container demo; L created_drop reservation 10.0.0.5; L created_drop share weird
check "the file goes with its last line" test ! -e "$F"

echo "-- the helpers record only what they made"
mkdir -p "$WORK/state2"
out=$(HS_STATE_DIR=$WORK/state2 CREATED_APP=demo bash -c '. "$1/lib/created.sh"; existed=true; $existed || created container demo; echo done' _ "$SCRIPTS")
check_eq "existed=true: nothing recorded" "done" "$out"
check "no file after a run that made nothing" test ! -e "$WORK/state2/apps/demo.toml"
grep -q 'created reservation "\$want"' "$SCRIPTS/recipes/_lib.sh" && grep -q 'created container' "$SCRIPTS/recipes/_lib.sh" && grep -q 'created service' "$SCRIPTS/recipes/_lib.sh" && grep -q 'created share' "$SCRIPTS/create-share.sh" && pass "ensure_container, fixed_address, declare_service and create-share call it" || fail "a hook is missing"
finish
