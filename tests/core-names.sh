#!/usr/bin/env bash
# scripts/dev/core-names-check.py: every name the core refers to is in the official checkout, flagged core = true (hobnix/core#1074 D4).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
have python3 || { skip "needs python3"; finish; exit 0; }
CN="python3 -I $SCRIPTS/dev/core-names-check.py"
O=$WORK/official; cp -r "$ROOT/tests/fixtures/official" "$O"
printf '[[repo]]\nname = "official"\nurl = "x"\ncore = ["fx"]\n' > "$WORK/repos-ok.toml"
printf '[[repo]]\nname = "official"\nurl = "x"\ncore = ["fx", "gone", "fx2"]\n' > "$WORK/repos-bad.toml"
printf '[[repo]]\nname = "recipes"\nurl = "x"\n' > "$WORK/repos-old.toml"

echo "-- the fixture has no core flag yet"
$CN "$O" --repos "$WORK/repos-ok.toml" >/dev/null 2>&1; check_eq "fx is not flagged: exit 1" "1" "$?"
sed -i '/^path = "recipes\/fx"/a core = true' "$O/index.toml"
$CN "$O" --repos "$WORK/repos-ok.toml" >/dev/null 2>&1; check_eq "flagged: exit 0" "0" "$?"

echo "-- a missing and an unflagged name are named"
out=$($CN "$O" --repos "$WORK/repos-bad.toml" 2>&1); rc=$?
check_eq "exit 1" "1" "$rc"
check_out "the missing name is named" "gone: .*not in the index" echo "$out"
check_out "the unflagged name is named" "fx2: .*not flagged core" echo "$out"
out=$($CN "$O" --repos "$WORK/repos-ok.toml" --name nope 2>&1)
check_out "--name adds a name" "nope: " echo "$out"

echo "-- no official row yet: the built-in list, which the fixture does not have"
out=$($CN "$O" --repos "$WORK/repos-old.toml" 2>&1); rc=$?
check_eq "exit 1" "1" "$rc"
check_out "domain is named" "domain: " echo "$out"
check_out "and the summary says where the names came from" "built-in list" echo "$out"
finish
