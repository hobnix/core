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
# routes the admin check cannot judge (#1226): each is refused, not skipped
route() { printf '[app]\\ninstances = "one"\\n[app.routes.%s]\\nport = %s\\nexposure = %s' "$1" "$2" "$3"; }
pk routeok "$(route web 8000 '"private-ok"')" ''
pk badname "$(route Web 8000 '"public-ok"')" ''
pk badexp "$(route web 8000 '"Public"')" ''
pk badport "$(route web '"8000"' '"public-ok"')" ''
pk badadmin "$(route web 8000 '"public-ok"')"'\nadmin = "true"' ''
pk badtable '[app]\nroutes = "web"' ''
pk badapp 'app = "routes"' ''
# a trailing newline in a route name: a `$` anchor would let it through
pk badnl "$(route '"web\\n"' 8000 '"public-ok"')" ''
check "its manifest really holds the TOML escape for a newline" grep -qF '[app.routes."web\n"]' recipes/badnl/package.toml
# a route name with U+2028 (TOML escape)
pk sep "$(route '"a\\u2028b"' 8000 '"public-ok"')" ''
check "its manifest really holds the TOML escape for U+2028" grep -qF 'a\u2028b' recipes/sep/package.toml
# a row that uses a core first word (a recipe may only use ext <name>)
pk coreword '' "$(row user 'backup now' '@/run.sh')"
pk coresys '' "$(row sys 'sys backup now' '@/run.sh')"
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

echo "-- a route the admin check cannot judge is refused (#1226)"
check "a valid route installs" $PKGSH install routeok
for p in badname badexp badport badadmin badtable badapp badnl sep; do
  check "$p: install fails" bash -c "! $PKGSH install $p >/dev/null 2>&1"
  check "$p: nothing is left in current/" test ! -e "$HS_STATE_DIR/packages/current/$p"
  check "$p: nothing is recorded as installed" bash -c "! grep -q 'package.$p\]' '$HS_STATE_DIR/packages/installed.toml'"
done
check_out "the bad route name is named" "a route is a lower case name" bash -c "$PKGSH install badname 2>&1; true"
check_out "and carries the code" "^code${tab}pkg.rows" bash -c "$PKGSH install badname 2>&1; true"
check_out "the bad exposure is named" "exposure is not never-public" bash -c "$PKGSH install badexp 2>&1; true"
usep=$'\xe2\x80\xa8'
out=$($PKGSH install sep 2>&1 || true)
check_out "the U+2028 route is refused for its name" "a route is a lower case name" echo "$out"
check "no U+2028 reaches the output of an install" test "${out#*"$usep"}" = "$out"

echo "-- a row that uses a core first word is refused"
for p in coreword coresys; do
  check "$p: install fails" bash -c "! $PKGSH install $p >/dev/null 2>&1"
  check "$p: nothing is left in current/" test ! -e "$HS_STATE_DIR/packages/current/$p"
  check "$p: nothing is recorded as installed" bash -c "! grep -q 'package.$p\]' '$HS_STATE_DIR/packages/installed.toml'"
done
check_out "the user row is named" "row backup now: a user row must be: ext coreword" bash -c "$PKGSH install coreword 2>&1; true"
check_out "the sys row is named" "row sys backup now: a sys row must be: sys ext coresys" bash -c "$PKGSH install coresys 2>&1; true"
# also a capability package of a default repository, which may own words: never a word of the core
C=$WORK/own/own; mkdir -p "$C"
printf 'name = "own"\nkind = "capability"\nwords = ["backup"]\n' > "$C/package.toml"
row user 'backup now' '@/x.sh' > "$C/commands.tsv"
printf 'name = "test"\n' > "$WORK/default-repos.toml"
check_out "an owned word that the core uses is refused" "the word backup is also a core command" \
  env HS_PACKAGE_REPOS_FILE="$WORK/default-repos.toml" bash "$SCRIPTS/lib/pkg-stage-check.sh" own "$C" test

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

echo "-- an update to a bad route changes nothing"
cd "$R" || exit 1
sed -i '/^\[package.routeok\]/{n;s/1.0.0/2.0.0/}' index.toml
sed -i 's/^version = "1.0.0"/version = "2.0.0"/; s/^\[app\.routes\.web\]/[app.routes."a\\u2028b"]/' recipes/routeok/package.toml
check "the new manifest holds the TOML escape for U+2028" grep -qF 'a\u2028b' recipes/routeok/package.toml
git add -A && git commit -q -m route && git -c user.signingkey="$WORK/good.pub" tag -s v3.0.0 -m rel3
cd "$ROOT" || exit 1
$PKGSH fetch test >/dev/null 2>&1
rc=0; out=$($PKGSH update routeok --yes 2>&1) || rc=$?
check "the update is refused" test "$rc" -ne 0
check_out "for its route" "a route is a lower case name" echo "$out"
check "no U+2028 reaches the output of an update" test "${out#*"$usep"}" = "$out"
check_out "the old version is still installed" 'version = "1.0.0"' cat "$HS_STATE_DIR/packages/current/routeok/package.toml"

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

echo "-- the cost of the command list grows with the packages, not with their square (hobnix/core#1320)"
# registry_rows runs on every hs call. Counted, not timed: the external programs and the subshells of one call.
SHIM=$WORK/shim; mkdir -p "$SHIM"
for x in grep awk sort tr paste cut mktemp rm dirname basename sed cat head uniq; do
  printf '#!/bin/sh\necho %s >> "$COUNT_LOG"\nexec "%s" "$@"\n' "$x" "$(command -v "$x")" > "$SHIM/$x"; chmod +x "$SHIM/$x"
done
printf 'name = "official"\n' > "$WORK/official.toml"
crowd() {   # crowd <folder> <packages>: half in-tree folders, half default-repository packages; each owns two words, has a plan and a start row
  local i n d=$1
  mkdir -p "$d/pk" "$d/state/packages" "$d/etc"; : > "$d/state/packages/installed.toml"; : > "$d/on"
  for ((i = 1; i <= $2; i++)); do
    n=crowd$i; mkdir -p "$d/pk/$n"
    if ((i % 2)); then printf 'name = "%s"\nwords = ["%sa", "%sb"]\n' "$n" "$n" "$n" > "$d/pk/$n/capability.toml"
    else
      printf 'name = "%s"\nkind = "capability"\nwords = ["%sa", "%sb"]\n' "$n" "$n" "$n" > "$d/pk/$n/package.toml"
      printf '[package.%s]\nrepo = "official"\n' "$n" >> "$d/state/packages/installed.toml"
    fi
    { row sys "sys ${n}a plan x" '@/x.sh'; row sys "sys ${n}a start x" '@/x.sh'; row user "${n}b go" '@/x.sh'; } > "$d/pk/$n/commands.tsv"
    echo "$n" >> "$d/on"
  done
}
crowded() {   # crowded <folder> <command...>: run it against the fixtures of crowd
  local d=$1; shift
  HS_PACKAGES_DIR=$d/pk HS_STATE_DIR=$d/state HS_CAPABILITIES_FILE=$d/on HS_ETC_DIR=$d/etc HS_PACKAGE_REPOS_FILE=$WORK/official.toml "$@"
}
for k in 4 8 16; do
  crowd "$WORK/crowd$k" "$k"
  : > "$WORK/crowd$k/ext.log"
  COUNT_LOG=$WORK/crowd$k/ext.log crowded "$WORK/crowd$k" bash -c '. "$1/lib/registry-load.sh"; : > "$COUNT_LOG"; PATH=$2:$PATH; hash -r; registry_rows > "$3"' _ "$SCRIPTS" "$SHIM" "$WORK/crowd$k/rows"
  : > "$WORK/crowd$k/sub.log"
  crowded "$WORK/crowd$k" bash -c '. "$1/lib/registry-load.sh"; set -T; trap "echo \$BASHPID >> \"$2\"" DEBUG; registry_rows > /dev/null' _ "$SCRIPTS" "$WORK/crowd$k/sub.log"
  eval "ext$k=$(wc -l < "$WORK/crowd$k/ext.log" | tr -d ' ') sub$k=$(sort -u "$WORK/crowd$k/sub.log" | wc -l | tr -d ' ')"
  check_eq "$k packages: every row is loaded" "$((k * 3))" "$(grep -c "$tab.*$WORK/crowd$k/pk/crowd" "$WORK/crowd$k/rows")"
done
# shellcheck disable=SC2154   # set by the eval above
{
  echo "   external programs: $ext4 $ext8 $ext16, shells: $sub4 $sub8 $sub16 (4, 8, 16 packages)"
  check "the shim counts" test "$ext4" -gt 4
  check "external programs stay under 10 per package" test "$ext16" -le $((10 + 16 * 10))
  check "shells stay under 12 per package" test "$sub16" -le $((20 + 16 * 12))
  check "external programs grow linearly" test $((ext16 - ext8)) -le $((2 * (ext8 - ext4) + 4))
  check "shells grow linearly" test $((sub16 - sub8)) -le $((2 * (sub8 - sub4) + 6))
}

echo "-- nothing of one call is kept for the next (a shell that installs or stages packages)"
crowd "$WORK/live" 2
cat > "$WORK/live.sh" <<'EOF'
. "$1/lib/registry-load.sh"
w=$2
has() { registry_rows | grep -qF "$1"; }
has 'sys crowd1a plan x' && ! has 'newword go' || exit 10
# a package that appears is seen
mkdir -p "$w/pk/late"; printf 'name = "late"\nwords = ["newword"]\n' > "$w/pk/late/capability.toml"
printf 'user\tnewword go\t@/x.sh\t-\th\th\n' > "$w/pk/late/commands.tsv"; echo late >> "$w/on"
has 'newword go' || exit 11
# and so is a word it takes from another one
printf 'name = "late"\nwords = ["newword", "crowd1a"]\n' > "$w/pk/late/capability.toml"
! has 'sys crowd1a plan x' || exit 12
rm -r "$w/pk/late"
has 'sys crowd1a plan x' || exit 13
# the installed repository decides again
printf '[package.crowd2]\nrepo = "elsewhere"\n' > "$w/state/packages/installed.toml"
! has 'crowd2b go' || exit 14
HS_STAGE_PKG=crowd2 HS_STAGE_REPO=official has 'crowd2b go' || exit 15
! has 'crowd2b go' || exit 16
HS_PACKAGES_DIR=$w/none; ! has 'crowd1b go' || exit 17
HS_PACKAGES_DIR=$w/pk; has 'crowd1b go' || exit 18
HS_REGISTRY=$w/none.tsv; ! has 'crowd1b go' || exit 19
EOF
check "each call reads the packages again" crowded "$WORK/live" bash "$WORK/live.sh" "$SCRIPTS" "$WORK/live"

echo "-- the check itself breaking is a refusal, not a pass"
mkdir -p "$WORK/broken"; printf '#!/bin/sh\nexit 2\n' > "$WORK/broken/awk"; chmod +x "$WORK/broken/awk"
for call in '_ext_filter crowd1 "$3" 0' 'registry_rows_of crowd1' 'ext_package_names' 'registry_refused'; do
  check "a failing awk fails ${call%% *}, it is not an empty list" \
    crowded "$WORK/live" bash -c '. "$1/lib/registry-load.sh"; PATH=$2:$PATH; hash -r; ! eval "$4" >/dev/null 2>&1' _ "$SCRIPTS" "$WORK/broken" "$WORK/live/pk/crowd1" "$call"
done
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
