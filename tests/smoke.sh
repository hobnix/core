#!/usr/bin/env bash
# hs smoke: tools check and read-only probes, against a fake dispatcher and a PATH without the tools. No root.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
export HS_LANG=en HS_PLAIN=1
BIN=$WORK/bin; mkdir -p "$BIN"
for c in bash awk sed grep cut paste sort head tail cat basename dirname date timeout tr wc ls printf mktemp rm mkdir env uname cp mv sleep true false id hostname; do
  p=$(command -v "$c" 2>/dev/null) && ln -sf "$p" "$BIN/$c"
done
# a fake dispatcher: "ok" answers, "bad" prints a shell error, "fail" exits 1, "slow" hangs, "one" exits 1 which is allowed
cat > "$WORK/hs.sh" <<'FAKE'
#!/usr/bin/env bash
case "$1" in
  help) echo "list" ;;
  good) echo "fine" ;;
  bad) echo "x.sh: line 3: foo: command not found" ;;
  broken) echo "oops"; exit 1 ;;
  slow) sleep 5 ;;
  one) echo "problems"; exit 1 ;;
  ext) echo "$*" >> "${0%/*}/ran"; [ "$3" != one ] || exit 1; echo "fine" ;;
esac
FAKE
printf '# kind\nuser\tgood\tx.sh\t-\th\th\t-\nuser\tbad\tx.sh\t-\th\th\t-\nuser\tbroken\tx.sh\t-\th\th\t-\nuser\tslow\tx.sh\t-\th\th\t-\nuser\tone\tx.sh\t-\th\th\t-\nuser\tshare <share> show\tx.sh\t-\th\th\t-\n' > "$WORK/registry.tsv"
printf 'a good one\tgood\t0\nthe shell error\tbad\t0\nexit code\tbroken\t0\nhangs\tslow\t0\nallowed 1\tone\t0 1\nnot allowed\tone\t0\nunknown\tnope\t0\nwith a value\tshare docs show\t0\n' > "$WORK/probes"
export HS_SMOKE_HS=$WORK/hs.sh HS_REGISTRY=$WORK/registry.tsv HS_SMOKE_PROBES=$WORK/probes HS_SMOKE_TIMEOUT=1
S="env PATH=$BIN bash $SCRIPTS/smoke.sh"

echo "-- probes"
out=$($S --no-run 2>&1; true)
check_out "--no-run runs no probe" "Programs the scripts need" echo "$out"
list=$(HS_SMOKE_TOOLS="" $S --list 2>&1 || true)
check_out "a good command is ok" "probe	a good one	ok" echo "$list"
check_out "a shell error is a failure even with exit code 0" "probe	the shell error	fail	.*command not found" echo "$list"
check_out "an exit code is a failure" "probe	exit code	fail	exit code 1" echo "$list"
check_out "a command that hangs is stopped" "probe	hangs	fail	no answer after 1 seconds" echo "$list"
check_out "an allowed exit code is fine" "probe	allowed 1	ok" echo "$list"
check_out "another one is not" "probe	not allowed	fail" echo "$list"
check_out "a command this version lacks is skipped" "probe	unknown	skip	no such command" echo "$list"
check_out "a <value> in the registry matches" "probe	with a value	ok" echo "$list"
check_eq "exit status 1 when something failed" "1" "$(HS_SMOKE_TOOLS="" $S >/dev/null 2>&1; echo $?)"
printf 'a good one\tgood\t0\n' > "$WORK/probes"
check_eq "exit status 0 when all is well" "0" "$(HS_SMOKE_TOOLS="" $S >/dev/null 2>&1; echo $?)"

echo "-- coverage: every read-only command has a probe (or a reason)"
REAL=$SCRIPTS/lib/registry.tsv
COV="bash $SCRIPTS/smoke.sh --coverage"
check_out "every reads row of the real registry is probed or skipped" "every reads row has a probe" env HS_REGISTRY=$REAL $COV
check_eq "and the exit status is 0" "0" "$(HS_REGISTRY=$REAL $COV >/dev/null 2>&1; echo $?)"
{ cat "$REAL"; printf 'user\tbrandnew thing\tx.sh\t-\th\th\ttopic:system,reads\nuser\tbrandnew other\tx.sh\t-\th\th\ttopic:system,changes\n'; } > "$WORK/reg-new.tsv"
check_out "a new reads row without probe is reported" "no probe and no skip entry: brandnew thing" env HS_REGISTRY=$WORK/reg-new.tsv $COV
check_eq "with exit status 1" "1" "$(HS_REGISTRY=$WORK/reg-new.tsv $COV >/dev/null 2>&1; echo $?)"
if HS_REGISTRY=$WORK/reg-new.tsv $COV 2>&1 | grep -q 'brandnew other'; then fail "a changes row needs no probe"; else pass "a changes row needs no probe"; fi
grep -av '^user	smoke	' "$REAL" > "$WORK/reg-nosmoke.tsv"
check_out "a skip entry for a row that is gone is reported" "stale skip entry .*: smoke" env HS_REGISTRY=$WORK/reg-nosmoke.tsv $COV
echo "-- programs"
tl=$(HS_SMOKE_TOOLS="smartctl restic" $S --no-run --list 2>&1 || true)
check_out "a missing program is named with the scripts that use it" "tool	smartctl	fail	not installed; used by: .*disk-health" echo "$tl"
ln -sf /bin/true "$BIN/smartctl"; ln -sf /bin/true "$BIN/restic"
tl=$(HS_SMOKE_TOOLS="smartctl restic" $S --no-run --list 2>&1 || true)
check_out "an installed program passes" "tool	all other programs	ok" echo "$tl"
check_out "no gum is only a hint" "tool	gum	skip" echo "$tl"
check_out "a wrong option is refused" "usage: hs smoke" $S --nope

echo "-- packages bring their probes and tools"
rm -f "$BIN/smartctl" "$BIN/restic"
ln -sf "$(command -v python3)" "$BIN/python3"
PK=$WORK/pk; mkdir -p "$PK/onpkg" "$PK/offpkg"
printf 'name = "onpkg"
tools = ["smartctl"]
[[probe]]
label = "pkg probe"
words = "ext onpkg good"
ok = [0]
[[probe]]
label = "pkg one"
words = "ext onpkg one"
ok = [0, 1]
limit = 3
' > "$PK/onpkg/capability.toml"
printf 'name = "offpkg"
tools = ["restic"]
[[probe]]
label = "off probe"
words = "ext offpkg good"
ok = [0]
' > "$PK/offpkg/capability.toml"
# the rows the packages bring: a probe runs only a read row of its own package
printf 'user\text onpkg good\tx.sh\t-\th\th\ttopic:system,reads\nuser\text onpkg one\tx.sh\t-\th\th\ttopic:system,reads,capability:offpkg\n' > "$PK/onpkg/commands.tsv"
printf 'user\text offpkg good\tx.sh\t-\th\th\ttopic:system,reads\n' > "$PK/offpkg/commands.tsv"
printf 'onpkg
' > "$WORK/caps-on"
printf '# kind
user	good	x.sh	-	h	h	-
user	one	x.sh	-	h	h	capability:offpkg
user	bad	x.sh	-	h	h	capability:onpkg
' > "$WORK/registry-pk.tsv"
unset HS_SMOKE_PROBES
export HS_PACKAGES_DIR=$PK HS_CAPABILITIES_FILE=$WORK/caps-on HS_CAPABILITIES_TSV=$WORK/none.tsv HS_STATE_DIR=$WORK/state
PS="env PATH=$BIN HS_REGISTRY=$WORK/registry-pk.tsv bash $SCRIPTS/smoke.sh"
pl=$($PS --list 2>&1 || true)
check_out "a probe of a package that is on runs" "probe	pkg probe	ok" echo "$pl"
if grep -q 'off probe' <<<"$pl"; then fail "a probe of a package that is off is not run"; else pass "a probe of a package that is off is not run"; fi
check_out "the tool of a package that is on is looked for" "tool	smartctl	fail" echo "$pl"
if grep -q 'tool	restic' <<<"$pl"; then fail "the tool of a package that is off is not looked for"; else pass "the tool of a package that is off is not looked for"; fi
check_out "a core probe of a capability that is off is skipped" "probe	pkg one	skip	capability offpkg is off" echo "$pl"
printf 'onpkg
offpkg
' > "$WORK/caps-on"
pl=$($PS --list 2>&1 || true)
check_out "once it is on, the probe runs" "probe	off probe	ok" echo "$pl"
check_out "and so does the core probe of that capability" "probe	pkg one	ok" echo "$pl"
check_out "pkg_probes.py prints label, words, codes, limit" "pkg one	ext onpkg one	0 1	3" python3 "$SCRIPTS/lib/pkg_probes.py" probes "$PK/onpkg"
TAB=$(printf '\t')
echo "-- a package probe runs only a read"
rm -f "$WORK/ran"
mkdir -p "$PK/evil"
{
  printf 'user\text evil wipe\tx.sh\t-\th\th\ttopic:system,changes\n'
  printf 'user\text evil show\tx.sh\t-\th\th\ttopic:system,reads\n'
  printf 'user\text evil show hard\tx.sh\t-\th\th\ttopic:system,changes\n'
  printf 'user\text evil plain\tx.sh\t-\th\th\ttopic:system\n'
} > "$PK/evil/commands.tsv"
probe() { printf '[[probe]]\nlabel = "%s"\nwords = "%s"\n' "$1" "$2"; }
{
  printf 'name = "evil"\n'
  probe "changes" "ext evil wipe"
  probe "core row" "good"
  probe "foreign row" "ext onpkg good"
  probe "no row" "ext evil nothing"
  probe "longer row" "ext evil show hard"
  probe "no flag" "ext evil plain"
  probe "glob" "ext evil show *"
  probe "dry run not last" "ext evil wipe --dry-run --yes"
  probe "dry run" "ext evil wipe --dry-run"
  probe "own read" "ext evil show"
  probe 'esc\u001b[31m ape' "ext evil wipe"
} > "$PK/evil/capability.toml"
printf 'onpkg\nevil\n' > "$WORK/caps-on"
pl=$($PS --list 2>&1 || true)
for l in "changes" "core row" "foreign row" "no row" "longer row" "no flag" "glob" "dry run not last"; do
  check_out "refused: $l" "probe${TAB}$l${TAB}fail${TAB}probe $l of evil is not a read: skipped" echo "$pl"
done
check_out "a changes row with --dry-run last runs" "probe${TAB}dry run${TAB}ok" echo "$pl"
check_out "a read row of the package itself runs" "probe${TAB}own read${TAB}ok" echo "$pl"
check_out "control characters of a label are not printed" "probe${TAB}esc\[31mape${TAB}fail" echo "$pl"
check_eq "no refused probe reached hs" "ext evil show
ext evil wipe --dry-run" "$(grep 'ext evil' "$WORK/ran" | sort)"
check_eq "a refused probe fails the run" "1" "$(HS_SMOKE_TOOLS="" $PS >/dev/null 2>&1; echo $?)"
unset HS_PACKAGES_DIR HS_CAPABILITIES_FILE HS_CAPABILITIES_TSV HS_STATE_DIR

finish
