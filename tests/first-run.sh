#!/usr/bin/env bash
# First-run setup (docs/adr/0022-first-run-console-token.md): token, flag, expiry, burn, POST /api/setup, and `hs setup-code` on a temp state folder.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
if ! have python3; then skip "python3 missing"; finish; exit 0; fi

echo "-- first-run token and endpoint"
if out=$(python3 -I "$ROOT/tests/first-run-test.py" 2>&1); then pass "first-run tests ($(grep -E '^Ran ' <<<"$out"))"; else fail "first-run tests: $(tail -n 25 <<<"$out")"; fi

echo "-- hs setup-code"
export HS_FIRST_RUN_FILE="$WORK/first-run.json" HS_CALLER=
check "status with no flag says nothing is waiting" bash -c "bash '$SCRIPTS/setup-code.sh' status 2>&1 | grep -q 'No first setup'"
check "boot with no flag prints nothing" bash -c "out=\$(HS_SETUP_WAIT=1 HS_SETUP_ADDRS='' bash '$SCRIPTS/setup-code.sh' boot 2>&1); test -z \"\$out\""
out=$(bash "$SCRIPTS/setup-code.sh" issue 2>&1); rc=$?
check "issue succeeds" test "$rc" = 0
check "issue prints a code" grep -Eq '[A-HJ-NP-Z2-9]{5}(-[A-HJ-NP-Z2-9]{5}){3}' <<<"$out"
check "the state file holds no code" bash -c "! grep -Eq '[A-HJ-NP-Z2-9]{5}-[A-HJ-NP-Z2-9]{5}' '$HS_FIRST_RUN_FILE'"
check "status says a code is waiting" bash -c "bash '$SCRIPTS/setup-code.sh' status 2>&1 | grep -q 'waiting'"
check "boot prints a code and both addresses while pending" bash -c "out=\$(HS_SETUP_WAIT=1 HS_SETUP_ADDRS='192.168.1.50' bash '$SCRIPTS/setup-code.sh' boot 2>&1); grep -Eq '[A-HJ-NP-Z2-9]{5}(-[A-HJ-NP-Z2-9]{5}){3}' <<<\"\$out\" && grep -q '\.local:8480' <<<\"\$out\" && grep -q 'http://192.168.1.50:8480' <<<\"\$out\""
check "reset removes the flag" bash -c "bash '$SCRIPTS/setup-code.sh' reset && test ! -e '$HS_FIRST_RUN_FILE'"
echo "-- arm (the installer)"
bash "$SCRIPTS/setup-code.sh" arm
check "arm makes a pending flag without a code" bash -c "bash '$SCRIPTS/setup-code.sh' status 2>&1 | grep -q 'expired'"
check "boot then issues the first code" bash -c "HS_SETUP_WAIT=1 HS_SETUP_ADDRS='10.0.0.2' bash '$SCRIPTS/setup-code.sh' boot 2>&1 | grep -Eq '[A-HJ-NP-Z2-9]{5}(-[A-HJ-NP-Z2-9]{5}){3}'"
bash "$SCRIPTS/setup-code.sh" arm
check "arm never overwrites a flag that exists" bash -c "bash '$SCRIPTS/setup-code.sh' status 2>&1 | grep -q 'waiting'"
printf '%s' '{"state":"done","user":"adminuser","done":1}' > "$HS_FIRST_RUN_FILE"
check "boot after done prints nothing, not even on stderr" bash -c "out=\$(HS_SETUP_WAIT=1 HS_SETUP_ADDRS='' bash '$SCRIPTS/setup-code.sh' boot 2>&1); test -z \"\$out\""
echo "-- the boot unit"
check "both Nix configurations use the shared unit" bash -c "grep -q 'setup-code-unit.nix' '$ROOT/install.nix' && grep -q 'setup-code-unit.nix' '$ROOT/configuration.nix'"
check "the unit prints to the tty only" bash -c "grep -q 'StandardOutput = \"tty\"' '$ROOT/setup-code-unit.nix' && grep -q 'TTYPath = \"/dev/console\"' '$ROOT/setup-code-unit.nix' && ! grep -q '/etc/issue' '$ROOT/setup-code-unit.nix'"
check "the unit is ordered after time-sync.target" grep -q '"time-sync.target"' "$ROOT/setup-code-unit.nix"
echo "-- optional parts (hs first-run --parts)"
FRB=$WORK/hsbin.sh; FRL=$WORK/hs-calls
cat > "$FRB" <<STUB
#!/usr/bin/env bash
echo "\$*" >> "$FRL"
case "\$*" in
  "sys pkg capabilities") printf 'a	caps	1.0.0	-	new	-	feature	A part
' ;;
  "sys pkg bundle plan a") printf 'status	ok
step	install a 1.0.0
' ;;
  "sys pkg bundle start a") printf 'status	started
unit	hs-job-demo-1
' ;;
esac
exit 0
STUB
frun() { : > "$FRL"; HS_BIN="$FRB" HS_STATE_DIR="$WORK/frstate" bash "$SCRIPTS/first-run.sh" "$@" 2>&1 </dev/null || true; }
mkdir -p "$WORK/frstate"
out=$(frun --yes --language en --notify none)
check "--yes alone never calls the bundle" bash -c "! grep -q 'bundle' '$FRL'"
out=$(frun --yes --language en --parts none)
check "--parts none says it adds nothing" grep -q 'No optional parts added' <<<"$out"
out=$(frun --yes --language en --parts a)
check "--parts a --yes plans then starts" bash -c "grep -n 'bundle' '$FRL' | tr '\n' ' ' | grep -q 'bundle plan a.*bundle start a'"
check "and prints the unit" grep -q 'hs-job-demo-1' <<<"$out"
echo "-- what the server is for (#1075): a blueprint, the recorded choice"
cat > "$FRB" <<STUB
#!/usr/bin/env bash
echo "\$*" >> "$FRL"
case "\$*" in
  "sys blueprint plan apply media") printf 'status\tok\nheading\tapply\nblueprint\tmedia\tofficial\t1.0.0\tv1.0.0\npart\t1\tapp\tr1\tinstall\tinstall r1\nnote\tOne job\033[31m does it\n' ;;
  "sys blueprint plan apply foreign") printf 'status\tok\nheading\tapply\nconfirm_name\tforeign\n' ;;
  "sys blueprint plan apply nope") printf 'status\trefused\nreason\tNo blueprint called nope.\n'; exit 1 ;;
  "sys blueprint start apply media --tag v1.0.0") printf 'status\tstarted\nunit\ths-job-bp-1\n' ;;
esac
exit 0
STUB
CH=$WORK/frstate/setup-choice
record() { printf 'choice\t%s\nname\t%s\n' "$1" "$2" > "$CH"; }
recorded() { tr '\t\n' '  ' < "$CH"; }
rm -f "$CH"
out=$(frun --yes --blueprint media)
check "--blueprint --yes plans then starts" bash -c "grep 'blueprint' '$FRL' | tr '\n' ' ' | grep -q 'blueprint plan apply media.*blueprint start apply media'"
check_out "and prints the unit" 'hs-job-bp-1' echo "$out"
check "the start carries the tag of the plan, so a changed blueprint is refused" grep -qx 'sys blueprint start apply media --tag v1.0.0' "$FRL"
check "no record is made where the installer made none" test ! -e "$CH"
check "no escape byte of the plan reaches the terminal" bash -c '! grep -q "$(printf "\033")\[31m" <<<"$1"' _ "$out"
record blueprint media
out=$(frun --yes)
check "--yes carries out the recorded blueprint" grep -q 'blueprint start apply media' "$FRL"
check_eq "and marks the record done" "choice done name - " "$(recorded)"
out=$(frun --yes)
check "a done record starts nothing" bash -c "! grep -q 'blueprint start\|bundle' '$FRL'"
record blueprint media
out=$(frun)
check "without a terminal and --yes nothing is planned or started" bash -c "! grep -q 'blueprint \(plan\|start\)' '$FRL'"
check_eq "and the record stays" "choice blueprint name media " "$(recorded)"
out=$(frun --blueprint media)
check "an explicit blueprint without a terminal shows the plan only" bash -c "grep -q 'blueprint plan apply media' '$FRL' && ! grep -q 'blueprint start' '$FRL'"
out=$(frun --yes --blueprint foreign)
check "--yes never types a name" bash -c "! grep -q 'blueprint start' '$FRL'"
check_out "and says how to go on" 'hs blueprint apply foreign' echo "$out"
out=$(frun --yes --blueprint nope)
check_out "a refused plan is shown" 'No blueprint called nope' echo "$out"
check "and nothing starts" bash -c "! grep -q 'blueprint start' '$FRL'"
record core -
out=$(frun --yes)
check "a recorded core only installs no part" bash -c "! grep -q 'bundle\|blueprint' '$FRL'"
check_eq "and is done" "choice done name - " "$(recorded)"
record blueprint 'x;rm'
out=$(frun --yes)
check "a damaged record is ignored" bash -c "! grep -q 'blueprint' '$FRL'"
out=$(frun --yes --blueprint media --core-only)
check_out "two choices are refused" 'only one of' echo "$out"
out=$(frun --yes --blueprint '--confirm')
check_out "a name of the wrong shape is refused" 'not a blueprint name' echo "$out"
finish
