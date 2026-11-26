#!/usr/bin/env bash
# hs sys pkg plan|start (scripts/pkg-change.sh, the Marketplace of the web interface): the data rows (market, repos), install / update / remove,
# adding and removing a repository with its key on stdin, the typed names, the refusals. A local git repository with SSH-signed tags stands in for GitHub.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
have git || { skip "needs git"; finish; exit 0; }
have ssh-keygen || { skip "needs ssh-keygen"; finish; exit 0; }
export HS_LANG=en HS_PLAIN=1 HS_STATE_DIR=$WORK/state HS_PKG_ALLOW_LOCAL=1
mkdir -p "$HS_STATE_DIR"
tab=$'\t'
C="bash $SCRIPTS/pkg-change.sh"
PKGSH="bash $SCRIPTS/pkg.sh"
ssh-keygen -q -t ed25519 -N '' -f "$WORK/good" -C test >/dev/null
ssh-keygen -q -t ed25519 -N '' -f "$WORK/evil" -C test >/dev/null
GOOD=$(cut -d' ' -f1,2 "$WORK/good.pub"); EVIL=$(cut -d' ' -f1,2 "$WORK/evil.pub")
R=$WORK/repo; mkdir -p "$R/recipes/demo" "$R/recipes/corer"; cd "$R"
git init -q . && git config user.email t@t && git config user.name t && git config gpg.format ssh && git config commit.gpgsign false
release() {   # release <tag> <demo version> <key> [a line for demo in package.toml and index.toml]
  for n in demo corer; do
    v=1.0.0; [ "$n" != demo ] || v=$2
    printf 'name = "%s"\nversion = "%s"\nkind = "recipe"\ntitle = "The %s package"\nrequires_core = ">=1"\naudience = "generic"\nneeds = []\nuses = []\ninput = "none"\nscript = "run.sh"\n' "$n" "$v" "$n" > "$R/recipes/$n/package.toml"
    printf '#!/usr/bin/env bash\n# kind: generic\n# needs: -\n# uses: -\necho %s %s\n' "$n" "$v" > "$R/recipes/$n/run.sh"
  done
  printf '[package.demo]\nversion = "%s"\nkind = "recipe"\npath = "recipes/demo"\ntitle = "The demo package"\nrequires_core = ">=1"\n\n[package.corer]\nversion = "1.0.0"\nkind = "recipe"\npath = "recipes/corer"\ntitle = "The corer package"\nrequires_core = ">=1"\ncore = true\n' "$2" > "$R/index.toml"
  mkdir -p "$R/blueprints/bp" "$R/blueprints/bpl"   # bp says blueprint in the index; bpl lies there (kind = recipe)
  printf 'name = "bp"
version = "1.0.0"
kind = "blueprint"
title = "Bp"
requires_core = ">=11"
roles = ["homeserver"]
[blueprint]
recipes = []
' > "$R/blueprints/bp/package.toml"
  printf 'name = "bpl"
version = "1.0.0"
kind = "blueprint"
title = "Bp"
requires_core = ">=11"
roles = ["homeserver"]
[blueprint]
recipes = []
' > "$R/blueprints/bpl/package.toml"
  printf '[package.bp]
version = "1.0.0"
kind = "blueprint"
path = "blueprints/bp"
title = "Bp"
requires_core = ">=11"
[package.bpl]
version = "1.0.0"
kind = "recipe"
path = "blueprints/bpl"
title = "Bpl"
requires_core = ">=1"
' >> "$R/index.toml"
  if [ -n "${4:-}" ]; then printf '%s\n' "$4" >> "$R/recipes/demo/package.toml"; sed -i "/^\[package.demo\]\$/a $4" "$R/index.toml"; fi
  git add -A && git commit -q -m "demo $2" && git -c user.signingkey="$3.pub" tag -s "$1" -m "release $2"
}
release v1.0.0 1.0.0 "$WORK/good"
cd "$ROOT"

echo "-- adding a repository"
check_out "plan: the name must be a word" "refused" bash -c "$C plan repo-add 'Bad Name' $R </dev/null; true"
check_out "plan: an address that is not https/ssh/git is refused" "address must be" bash -c "HS_PKG_ALLOW_LOCAL= $C plan repo-add test file:///tmp/x </dev/null; true"
check_out "plan: asks for the name to be typed" "^confirm_name${tab}test" $C plan repo-add test "$R"
check_out "plan: repo-add is answered at once, so it is not a job (long no)" "^long${tab}no" $C plan repo-add test "$R"
check_out "start without the typed name is refused" "type the name" bash -c "echo '$GOOD' | $C start repo-add test $R; true"
check_out "a line that is no key is refused" "not an SSH public key" bash -c "echo 'hello world' | $C start repo-add test $R --confirm test; true"
check_out "a key that did not sign the release: the repository is not kept" "not kept" bash -c "echo '$EVIL' | $C start repo-add test $R --confirm test; true"
check_eq "and it is not on the list" "0" "$($PKGSH --repos | grep -c "^test${tab}")"
check_out "the right key adds it" "^status${tab}done" bash -c "echo '$GOOD' | $C start repo-add test $R --confirm test"
check_out "the list shows it as signed and added" "^test${tab}.*${tab}signed${tab}added" $PKGSH --repos
check_out "the same name twice is refused" "already" bash -c "echo '$GOOD' | $C plan repo-add test $R; true"

echo "-- the market"
check_out "market lists demo as new" "^demo${tab}recipe${tab}test${tab}1[.]0[.]0${tab}-${tab}new${tab}no${tab}generic${tab}The demo package" $PKGSH --market
check_out "and the core flag of corer" "^corer${tab}recipe${tab}test${tab}1[.]0[.]0${tab}-${tab}new${tab}yes" $PKGSH --market

echo "-- a blueprint is applied, never installed"
check_out "plan: a blueprint is refused with its reason" "blueprint: hs blueprint apply bp" bash -c "$C plan install bp; true"
check_eq "plan: not status ok" "0" "$($C plan install bp 2>&1 | grep -c "^status${tab}ok")"
check_out "plan: and its code" "pkg.blueprint" bash -c "$C plan install bp 2>&1; true"
check_out "a blueprint the index calls a recipe is refused at the install: the package.toml says" "is a blueprint" bash -c "python3 -I $SCRIPTS/pkg.py install bpl 2>&1; true"
check "and nothing of it is in current/" test ! -e "$HS_STATE_DIR/packages/current/bpl"

echo "-- install"
check_out "plan: a package of an added repository is red" "^confirm_name${tab}demo" $C plan install demo
check_out "plan: names the repository" "test" $C plan install demo
check_out "start without the typed name is refused" "type the name" bash -c "$C start install demo; true"
check_out "start with it installs" "^status${tab}done" $C start install demo --confirm demo
check "the files arrived" test -f "$HS_STATE_DIR/packages/current/demo/run.sh"
check_out "market: current" "^demo${tab}recipe${tab}test${tab}1[.]0[.]0${tab}1[.]0[.]0${tab}current" $PKGSH --market
check_out "installing again is refused" "installed already" bash -c "$C plan install demo; true"
check_out "an unknown package is refused" "no package" bash -c "$C plan install nope; true"

echo "-- update"
cd "$R"; release v1.1.0 1.1.0 "$WORK/good"; cd "$ROOT"
check_out "fetch (plan) says it uses the network" "^long${tab}yes" $C plan fetch test
# fetch runs as a job: a stand-in hs_job records the call and runs the command at once
mkdir -p "$WORK/jl"; cat > "$WORK/jl/job.sh" <<JOB
hs_job() { shift 2; printf '%s\n' "\$*" >> "$WORK/jobcalls"; "\${@:2}" >/dev/null 2>&1; echo hs-job-pkg-fetch-1; }
JOB
check_out "fetch (start) is a job: started and its unit" "^status${tab}started" env HS_JOB_LIB="$WORK/jl/job.sh" $C start fetch test
check_out "fetch (start) names the unit" "^unit${tab}hs-job-pkg-fetch-1" env HS_JOB_LIB="$WORK/jl/job.sh" $C start fetch test
check_out "the job fetches that repository" "fetch test" bash -c "cat '$WORK/jobcalls'"
# the same with a default repository and a stand-in that only records (needs neither the network nor the signed test repository)
mkdir -p "$WORK/jl2"; printf 'hs_job() { shift 2; printf "%%s\\n" "$*" > "%s/jobcalls2"; echo hs-job-pkg-fetch-2; }\n' "$WORK" > "$WORK/jl2/job.sh"
check_out "fetch of a default repository: started and its unit" "^status${tab}started" env HS_JOB_LIB="$WORK/jl2/job.sh" $C start fetch official
check_out "the unit is the one hs_job printed" "^unit${tab}hs-job-pkg-fetch-2" env HS_JOB_LIB="$WORK/jl2/job.sh" $C start fetch official
check_out "the job command fetches that repository" "pkg.sh fetch official" bash -c "cat '$WORK/jobcalls2'"
check_out "fetch without a name is a job too" "^status${tab}started" env HS_JOB_LIB="$WORK/jl2/job.sh" $C start fetch
check_out "fetch of an unknown repository is refused before any job" "no repository" bash -c "HS_JOB_LIB='$WORK/jl/job.sh' $C start fetch nope; true"
check_out "market: update" "^demo${tab}recipe${tab}test${tab}1[.]1[.]0${tab}1[.]0[.]0${tab}update" $PKGSH --market
check_out "plan shows the change of the code" "^diff${tab}" $C plan update demo
check_out "and asks for the name" "^confirm_name${tab}demo" $C plan update demo
check_out "update without the name is refused" "type the name" bash -c "$C start update demo; true"
check_out "update with it" "^status${tab}done" $C start update demo --confirm demo
check_out "market: current again" "^demo${tab}recipe${tab}test${tab}1[.]1[.]0${tab}1[.]1[.]0${tab}current" $PKGSH --market
check_out "updating a current package is refused" "up to date" bash -c "$C plan update demo; true"
echo "-- remove"
check_out "a core package cannot be removed" "core package" bash -c "$C start install corer --confirm corer >/dev/null; $C plan remove corer; true"
check_out "remove plan" "^step${tab}forget" $C plan remove demo
check_out "remove" "^status${tab}done" $C start remove demo
check "the files are gone" test ! -e "$HS_STATE_DIR/packages/current/demo"
check_out "market: new again" "^demo${tab}recipe${tab}test${tab}1[.]1[.]0${tab}-${tab}new" $PKGSH --market
check_out "removing what is not installed is refused" "not installed" bash -c "$C plan remove demo; true"
cd "$R"; release v1.1.5 1.1.5 "$WORK/good" "requires_core_max = 1"; cd "$ROOT"; $PKGSH fetch test >/dev/null 2>&1
check_out "market: a release whose range ends below this core waits (requires_core_max, #1265)" "^demo${tab}recipe${tab}test${tab}1[.]1[.]5${tab}-${tab}waits" $PKGSH --market
check_out "plan: its install is refused with the reason, not as installed already" "^reason${tab}.*does not support this core yet" bash -c "$C plan install demo; true"
check_out "plan: and its code, before anything is read" "^code${tab}pkg[.]core-too-new$" bash -c "$C plan install demo; true"
check_out "start: refused the same way" "^code${tab}pkg[.]core-too-new$" bash -c "$C start install demo --confirm demo; true"
check "and nothing is installed" test ! -e "$HS_STATE_DIR/packages/current/demo"
AC="bash $SCRIPTS/apps-change.sh"
check_out "the app install plan says so too, with the code of the range" "^code${tab}pkg[.]core-too-new$" bash -c "$AC plan install demo 2>&1; true"
check_out "and the reason, not hs update" "^reason${tab}.*does not support this core yet" bash -c "$AC plan install demo 2>&1; true"

echo "-- removing a repository"
check_out "a default repository stays" "default" bash -c "$C plan repo-remove official; true"
check_out "plan: red" "^confirm_name${tab}test" $C plan repo-remove test
check_out "without the name it is refused" "type the name" bash -c "$C start repo-remove test; true"
check_out "with it the repository goes" "^status${tab}done" $C start repo-remove test --confirm test
check_eq "and is off the list" "0" "$($PKGSH --repos | grep -c "^test${tab}")"
check_out "corer stays as an orphan" "^corer${tab}[?]${tab}test${tab}-${tab}1[.]0[.]0${tab}orphan" $PKGSH --market
sed -i '/^repo = /d;/^commit = /d;/^tag = /d' "$HS_STATE_DIR/packages/installed.toml"
check_out "an orphan without recorded provenance has a remove plan" "^step${tab}forget" $C plan remove corer
check_out "an orphan without recorded provenance can be removed" "^status${tab}done" $C start remove corer
check "the orphan's files are gone" test ! -e "$HS_STATE_DIR/packages/current/corer"
check "the orphan's record is gone" bash -c "! grep -q '^\\[package.corer\\]' '$HS_STATE_DIR/packages/installed.toml'"
coded() {   # coded <what> <code> <output>: the refusal carries the code and the catalogue knows it
  check_match "$1 is refused with $2" "code${tab}$2" "$3"
  check "$2 is in the catalogue" bash -c "python3 '$SCRIPTS/errors-doc-gen.py' codes | grep -qxF '$2'"
}
coded "a bad package name" name.invalid "$($C plan install 'A b' 2>&1)"
coded "an unknown package" pkg.unknown "$($C plan install nope 2>&1)"
coded "an unknown repository" pkg.repo-unknown "$($C plan repo-remove nosuchrepo 2>&1)"
echo "-- a coded refusal of pkg.sh keeps its reason and its code"
cat > "$WORK/pkg-coded.sh" <<'STUB'
case "$1" in
  --market) printf 'demo\trecipe\tofficial\t1.0.0\t-\tnew\tno\tgeneric\tDemo\n' ;;
  --repos) printf 'official\turl\tsigned\tdefault\n' ;;
  install) printf 'some terminal output\nstatus\trefused\nreason\tdemo: its commands clash\ncode\tpkg.rows\n'; exit 1 ;;
esac
STUB
out=$(HS_PKG="$WORK/pkg-coded.sh" $C start install demo 2>&1)
check_eq "exactly the lines of pkg.sh, nothing else" "status${tab}refused|reason${tab}demo: its commands clash|code${tab}pkg.rows" "$(paste -sd'|' <<<"$out")"
sed -i "s/^  install) .*/  install) echo 'it broke'; exit 1 ;;/" "$WORK/pkg-coded.sh"
out=$(HS_PKG="$WORK/pkg-coded.sh" $C start install demo 2>&1)
check_eq "a failure without a code keeps the last line as reason" "status${tab}refused|reason${tab}it broke|code${tab}pkg.action-failed" "$(paste -sd'|' <<<"$out")"
echo "-- checking a package draft (the web package builder)"
GOODDRAFT=$'name = "demo2"\nversion = "0.1.0"\nkind = "recipe"\ntitle = "Demo"\nrequires_core = ">=1"\nscript = "run.sh"\n'
check_out "a good draft is ok" "^status${tab}ok" bash -c "printf '%s' '$GOODDRAFT' | $C plan check-draft"
check_out "it says what was not checked" "^finding${tab}warn${tab}-${tab}Checked without files" bash -c "printf '%s' '$GOODDRAFT' | $C plan check-draft"
check_out "a bad version names its field" "^finding${tab}error${tab}version${tab}version is not semver" bash -c "printf 'name = \"x\"\nversion = \"1.0\"\n' | $C plan check-draft; true"
check_out "a bad draft is refused with the count" "^reason${tab}The draft has [0-9]+ problem" bash -c "printf 'name = \"x\"\n' | $C plan check-draft; true"
check_out "text that is no TOML is a finding, not a crash" "^finding${tab}error${tab}-${tab}not valid TOML" bash -c "printf 'name = ' | $C plan check-draft; true"
check_out "an unknown permission is found" "permissions: " bash -c "printf '%s\npermissions = [\"root.all\"]\n' '$GOODDRAFT' | $C plan check-draft; true"
check_out "a draft is never started" "only checked" bash -c "$C start check-draft </dev/null; true"
check "a draft writes nothing into the packages" bash -c "! ls '$HS_STATE_DIR/packages/current' | grep -q demo2"
echo "-- one name in two repositories: the installed copy belongs to the row of its own repository (#933)"
mkrepo() {   # mkrepo <dir> <version>: a signed repository with the recipe foo at that version
  mkdir -p "$1/recipes/foo"
  ( cd "$1" || exit 1
    [ -d .git ] || { git init -q . && git config user.email t@t && git config user.name t && git config gpg.format ssh && git config commit.gpgsign false; }
    printf 'name = "foo"\nversion = "%s"\nkind = "recipe"\ntitle = "Foo"\nrequires_core = ">=1"\naudience = "generic"\nneeds = []\nuses = []\ninput = "none"\nscript = "run.sh"\n' "$2" > recipes/foo/package.toml
    printf '#!/usr/bin/env bash\n# kind: generic\n# needs: -\n# uses: -\necho foo %s\n' "$2" > recipes/foo/run.sh
    printf '[package.foo]\nversion = "%s"\nkind = "recipe"\npath = "recipes/foo"\ntitle = "Foo"\nrequires_core = ">=1"\n' "$2" > index.toml
    git add -A && git commit -q -m "foo $2" && git -c user.signingkey="$WORK/good.pub" tag -s "v$2" -m "release $2" )
}
mkrepo "$WORK/alpha" 99.0.0; mkrepo "$WORK/beta" 1.0.0      # alpha is listed first: its row comes first for the name
echo "$GOOD" | $C start repo-add alpha "$WORK/alpha" --confirm alpha >/dev/null
echo "$GOOD" | $C start repo-add beta "$WORK/beta" --confirm beta >/dev/null
check_out "install foo from beta" "^status${tab}done" $C start install foo --repo beta --confirm foo
check_out "market: the row of beta carries the installed copy" "^foo${tab}recipe${tab}beta${tab}1[.]0[.]0${tab}1[.]0[.]0${tab}current" $PKGSH --market
check_out "market: the row of alpha is no update of it" "^foo${tab}recipe${tab}alpha${tab}99[.]0[.]0${tab}-${tab}new" $PKGSH --market
check_eq "market: the copy is no orphan" "0" "$($PKGSH --market | grep -c "^foo${tab}.*${tab}orphan${tab}")"
check_out "plan: an update says up to date (its own repository has nothing newer)" "up to date" bash -c "$C plan update foo; true"
check_out "plan: installing the name from alpha is refused, the copy of beta is there" "installed already" bash -c "$C plan install foo --repo alpha; true"
mkrepo "$WORK/beta" 1.1.0; $PKGSH fetch beta >/dev/null 2>&1
check_out "plan: the update is the newer release of beta, not alpha's 99.0.0" "^heading${tab}update foo 1[.]0[.]0 -> 1[.]1[.]0$" $C plan update foo
check_out "start: it installs that release" "^status${tab}done" $C start update foo --confirm foo
check_out "and installed.toml still names beta" '^repo = "beta"$' cat "$HS_STATE_DIR/packages/installed.toml"
check_out "plan: remove names the package of beta" "^status${tab}ok" $C plan remove foo
# installing the name from another repository never replaces the copy of beta: not by hand, not by the app install of the web
check_out "pkg install --repo alpha is refused with its code" "^code${tab}pkg[.]other-repo$" bash -c "python3 -I $SCRIPTS/pkg.py install foo --repo alpha 2>&1; true"
check_out "and says how to switch on purpose" "hs pkg remove foo" bash -c "python3 -I $SCRIPTS/pkg.py install foo --repo alpha 2>&1; true"
check_out "the copy of beta stays" '^repo = "beta"$' cat "$HS_STATE_DIR/packages/installed.toml"
check_out "the app install plan from alpha is refused" "^code${tab}pkg[.]other-repo$" bash -c "$AC plan install foo --repo alpha 2>&1; true"
check_out "an update of beta's own copy still works (same repository)" "current" bash -c "python3 -I $SCRIPTS/pkg.py update foo --yes 2>&1"
# an orphan: beta's row is gone, the copy stays; alpha's package of the same name does not take its place
$C start repo-remove beta --confirm beta >/dev/null
check_out "market: the copy of beta is an orphan" "^foo${tab}[?]${tab}beta${tab}-${tab}1[.]1[.]0${tab}orphan" $PKGSH --market
check_out "pkg install --repo alpha does not replace the orphan" "^code${tab}pkg[.]other-repo$" bash -c "python3 -I $SCRIPTS/pkg.py install foo --repo alpha 2>&1; true"
check_out "plan install from alpha is refused" "installed already" bash -c "$C plan install foo --repo alpha; true"
check_out "the app install plan from alpha is refused" "^code${tab}pkg[.]other-repo$" bash -c "$AC plan install foo --repo alpha 2>&1; true"
check_out "the orphan is still beta's" '^repo = "beta"$' cat "$HS_STATE_DIR/packages/installed.toml"
python3 -I "$SCRIPTS/pkg.py" remove foo >/dev/null
check_out "after remove, alpha's package installs (the switch on purpose)" "foo 99[.]0[.]0 from alpha" python3 -I "$SCRIPTS/pkg.py" install foo --repo alpha
finish
