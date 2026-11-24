#!/usr/bin/env bash
# A package that brings rows or an app route the core refuses is not installed (#1072 S3): hs pkg install leaves nothing in packages/current,
# hs pkg validate names the rows, and the loader refuses a start row without its plan row. Hostile fixtures: a script path with .., a rust: script,
# a row name with a tab-free trick, an admin page published. A local git repository with an SSH-signed tag stands in for GitHub.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
have git || { skip "needs git"; finish; exit 0; }
have ssh-keygen || { skip "needs ssh-keygen"; finish; exit 0; }
export HS_LANG=en HS_PLAIN=1 HS_STATE_DIR=$WORK/state
mkdir -p "$HS_STATE_DIR"
PKGSH="bash $SCRIPTS/pkg.sh"
tab=$'\t'
ssh-keygen -q -t ed25519 -N '' -f "$WORK/good" -C test >/dev/null
printf 'releaser@test namespaces="git" %s\n' "$(cut -d' ' -f1,2 "$WORK/good.pub")" > "$WORK/signers"
R=$WORK/repo; mkdir -p "$R/recipes"; cd "$R" || exit 1
git init -q . && git config user.email t@t && git config user.name t && git config gpg.format ssh && git config commit.gpgsign false
: > "$R/index.toml"
pk() {   # pk <name> <extra package.toml lines> <commands.tsv content, printf %b>: one recipe package of the repository
  mkdir -p "$R/recipes/$1"
  printf 'name = "%s"\nversion = "1.0.0"\nkind = "recipe"\ntitle = "T"\nrequires_core = ">=1"\naudience = "generic"\nneeds = []\nuses = []\ninput = "none"\nscript = "run.sh"\n%b\n' "$1" "$2" > "$R/recipes/$1/package.toml"
  printf '#!/usr/bin/env bash\n# kind: generic\n# needs: -\n# uses: -\necho x\n' > "$R/recipes/$1/run.sh"
  printf '%b' "$3" > "$R/recipes/$1/commands.tsv"
  printf '[package.%s]\nversion = "1.0.0"\nkind = "recipe"\npath = "recipes/%s"\nrequires_core = ">=1"\n' "$1" "$1" >> "$R/index.toml"
}
row() { printf '%s\t%s\t%s\t-\th\th\n' "$1" "$2" "$3"; }
pk fine '' "$(row user 'ext fine hello' '@/run.sh')"
pk nostart '' "$(row sys 'sys ext nostart start go' '@/run.sh')"
pk withplan '' "$(row sys 'sys ext withplan start go' '@/run.sh')"$'
'"$(row sys 'sys ext withplan plan go' '@/run.sh')"
pk dotdot '' "$(row user 'ext dotdot x' '@/../../etc/passwd')"
pk rusty '' "$(row user 'ext rusty x' 'rust:evil')"
pk zoraxy '[app]\ninstances = "one"\n[app.health]\ncheck = "container"\n[app.routes.web]\nport = 8000\nexposure = "public-ok"\n[app.uses]\nram_mb = 64\ndisk_gb = 1' "$(row user 'ext zoraxy x' '@/run.sh')"
pk upd '' "$(row user 'ext upd hello' '@/run.sh')"
# a start row whose plan twin is itself refused (a rust: script) does not count as a plan row
pk twin '' "$(row sys 'sys ext twin start go' '@/run.sh')"$'\n'"$(row sys 'sys ext twin plan go' 'rust:evil')"
# an ESC and a tab in the words of a row must never reach the terminal or the machine lines as they are
pk ctrl '' "$(row user $'ext ctrl\033[31mx' '@/run.sh')"
# a package the core names (core = true): hs pkg install --core must apply the same rules
pk coreclash '' "$(row sys 'sys ext coreclash start go' '@/run.sh')"
printf 'core = true\n' >> "$R/index.toml"
git add -A && git commit -q -m pkgs && git -c user.signingkey="$WORK/good.pub" tag -s v1.0.0 -m rel
cd "$ROOT" || exit 1
$PKGSH repo add test "$R" --key "$WORK/signers" --confirm-name test >/dev/null 2>&1
$PKGSH fetch test >/dev/null 2>&1

echo "-- a package that is fine is kept"
check "a plain row installs" $PKGSH install fine
check "and stays in current/" test -f "$HS_STATE_DIR/packages/current/fine/package.toml"
check "a start row with its plan row installs" $PKGSH install withplan

echo "-- a refused row keeps the whole package out"
for p in nostart dotdot rusty zoraxy twin ctrl; do
  check "$p: install fails" bash -c "! $PKGSH install $p >/dev/null 2>&1"
  check "$p: nothing is left in current/" test ! -e "$HS_STATE_DIR/packages/current/$p"
  check "$p: nothing is recorded as installed" bash -c "! grep -q 'package.$p\]' '$HS_STATE_DIR/packages/installed.toml'"
done
check_out "the reason names the plan row" "a start row needs its plan row" bash -c "$PKGSH install nostart 2>&1; true"
check_out "the refusal carries the code" "^code${tab}pkg.rows" bash -c "$PKGSH install nostart 2>&1; true"
check_out "the script with .. is named" "without \.\." bash -c "$PKGSH install dotdot 2>&1; true"
check_out "a rust: script is refused" "rust: rows belong to the core" bash -c "$PKGSH install rusty 2>&1; true"
check_out "an admin page is never public" "admin page is never public" bash -c "$PKGSH install zoraxy 2>&1; true"

check "no control character reaches the output or the machine lines" bash -c "! { $PKGSH install ctrl 2>&1; } | LC_ALL=C grep -q \$'\\033'"
check_out "a refused plan twin leaves the start row refused too" "twin" bash -c "$PKGSH install twin 2>&1; true"

echo "-- hs pkg install --core applies the same rules"
$PKGSH install --core >/dev/null 2>&1 || true
check "a core package with a refused row is not kept" test ! -e "$HS_STATE_DIR/packages/current/coreclash"
check "and is not recorded" bash -c "! grep -q 'package.coreclash\]' '$HS_STATE_DIR/packages/installed.toml'"

echo "-- an update to a refused version changes nothing"
$PKGSH install upd >/dev/null 2>&1
cd "$R" || exit 1
sed -i '/^\[package.upd\]/{n;s/1.0.0/2.0.0/}' index.toml
sed -i 's/^version = "1.0.0"/version = "2.0.0"/' recipes/upd/package.toml
printf '[[events]]\nkind = "done"\nlevel = "warn"\nlabel = "Done"\nmeaning = "x"\nretention = "audit"\nnotify = { category = "ok", title = "{kind}", message = "{text}" }\n' >> recipes/upd/package.toml
{ printf '
'; row sys 'sys ext upd start go' '@/run.sh'; } >> recipes/upd/commands.tsv
git add -A && git commit -q -m upd2 && git -c user.signingkey="$WORK/good.pub" tag -s v2.0.0 -m rel2
cd "$ROOT" || exit 1
$PKGSH fetch test >/dev/null 2>&1
check "the update is refused" bash -c "! $PKGSH update upd --yes >/dev/null 2>&1"
check_out "the old version is still installed" 'version = "1.0.0"' cat "$HS_STATE_DIR/packages/current/upd/package.toml"
check "its events were not written" test ! -e "$HS_STATE_DIR/pkg-events/upd.tsv"
check "no previous copy was made" test ! -e "$HS_STATE_DIR/packages/previous"
check "nothing half staged is left" bash -c "! ls -a '$HS_STATE_DIR/packages/current' | grep -q '^[.]new-'"

echo "-- the loader, without an install"
D=$WORK/pk; mkdir -p "$D/one"
printf 'name = "one"\nversion = "1.0.0"\nkind = "recipe"\ntitle = "T"\nrequires_core = ">=1"\n' > "$D/one/package.toml"
{ row sys 'sys ext one start a' '@/x.sh'; row sys 'sys ext one plan a' '@/x.sh'; row sys 'sys ext one start b' '@/x.sh'; } > "$D/one/commands.tsv"
check_out "a start row without its plan row is refused" "sys ext one start b${tab}a start row needs its plan row" \
  bash -c "HS_PACKAGES_DIR='$D' bash -c '. $SCRIPTS/lib/registry-load.sh; registry_refused one'"
check_eq "the start row with its plan row is not refused" "1" "$(HS_PACKAGES_DIR=$D bash -c ". $SCRIPTS/lib/registry-load.sh; registry_refused one" | wc -l | tr -d ' ')"

mkdir -p "$D/two"
cp "$D/one/package.toml" "$D/two/package.toml"; sed -i 's/"one"/"two"/' "$D/two/package.toml"
{ row sys 'sys ext two start a' '@/x.sh'; row sys 'sys ext two plan a' 'rust:evil'; } > "$D/two/commands.tsv"
check_out "a start row does not pass on a refused plan row" "sys ext two start a${tab}a start row needs its plan row" \
  bash -c "HS_PACKAGES_DIR='$D' bash -c '. $SCRIPTS/lib/registry-load.sh; registry_refused two'"
{ row sys 'sys ext two start a' '@/x.sh'; row user 'ext two plan a' '@/x.sh'; } > "$D/two/commands.tsv"
check_out "a plan twin of the wrong kind does not count" "sys ext two start a${tab}a start row needs its plan row" \
  bash -c "HS_PACKAGES_DIR='$D' bash -c '. $SCRIPTS/lib/registry-load.sh; registry_refused two'"

echo "-- the check itself breaking is a refusal, not a pass"
mkdir -p "$D/three/x"
printf 'name = "x"\nkind = "recipe"\n' > "$D/three/x/package.toml"
row user 'ext x go' 'rust:evil' > "$D/three/x/commands.tsv"
check_eq "the normal run refuses the row (exit 1)" "1" "$(bash "$SCRIPTS/lib/pkg-stage-check.sh" x "$D/three/x" test >/dev/null 2>&1; echo $?)"
rc=$(HS_REGISTRY=/nonexistent bash "$SCRIPTS/lib/pkg-stage-check.sh" x "$D/three/x" test >/dev/null 2>&1; echo $?)
check "a missing registry is not a pass (exit $rc)" test "$rc" -ne 0
rc=$(TMPDIR=/nonexistent/x bash "$SCRIPTS/lib/pkg-stage-check.sh" x "$D/three/x" test >/dev/null 2>&1; echo $?)
check "an unusable temp folder is not a pass (exit $rc)" test "$rc" -ne 0

echo "-- every refusal text is made printable (U+2028, U+0085, C0, DEL)"
check_eq "clean_text" "a?b?c?d?e?f" "$(python3 -I -c "
import sys; sys.path.insert(0, sys.argv[1]); import pkg_repo
print(pkg_repo.clean_text('a\u2028b\u0085c\x1bd\x7fe\u2029f'))" "$SCRIPTS")"
check_eq "a Refused is cleaned" "x?y" "$(python3 -I -c "
import sys; sys.path.insert(0, sys.argv[1]); import pkg_repo
print(str(pkg_repo.Refused('x\u2028y')))" "$SCRIPTS")"

echo "-- hs pkg validate lists the rows"
check_out "validate names a refused row" "start row needs its plan row" bash -c "HS_PACKAGES_DIR='$D' $PKGSH validate 2>&1; true"
check "and exits 1" bash -c "! HS_PACKAGES_DIR='$D' $PKGSH validate >/dev/null 2>&1"
finish
