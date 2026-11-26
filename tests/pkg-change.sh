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
release() {   # release <tag> <demo version> <key>
  for n in demo corer; do
    v=1.0.0; [ "$n" != demo ] || v=$2
    printf 'name = "%s"\nversion = "%s"\nkind = "recipe"\ntitle = "The %s package"\nrequires_core = ">=1"\naudience = "generic"\nneeds = []\nuses = []\ninput = "none"\nscript = "run.sh"\ncategory = "media"\nicon = "ph:film-strip"\n' "$n" "$v" "$n" > "$R/recipes/$n/package.toml"
    printf '#!/usr/bin/env bash\n# kind: generic\n# needs: -\n# uses: -\necho %s %s\n' "$n" "$v" > "$R/recipes/$n/run.sh"
  done
  printf '[package.demo]\nversion = "%s"\nkind = "recipe"\npath = "recipes/demo"\ntitle = "The demo package"\nrequires_core = ">=1"\n\n[package.corer]\nversion = "1.0.0"\nkind = "recipe"\npath = "recipes/corer"\ntitle = "The corer package"\nrequires_core = ">=1"\ncore = true\nverified = "2026-01-02"\n' "$2" > "$R/index.toml"
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
# the store cards: category and icon from package.toml, the tested date only from the index entry (corer has one, demo none)
check_out "cards: demo" "^demo${tab}test${tab}media${tab}ph:film-strip${tab}-$" $PKGSH --cards
check_out "cards: an added repository never passes its verified day on" "^corer${tab}test${tab}media${tab}ph:film-strip${tab}-$" $PKGSH --cards
check_eq "the tested day counts only from the default, signed official repository" "True False False False" "$(python3 -I -c "
import importlib.util as u
s = u.spec_from_file_location('pr', '$SCRIPTS/pkg_repo.py'); m = u.module_from_spec(s); s.loader.exec_module(m)
R = object.__new__(m.Repos)
for rows in ({'official': {'default': True}}, {'official': {'default': False}}, {'official': {'default': True, 'unsigned': True}}, {'test': {'default': True}}):
    R.all = lambda rows=rows: rows
    print(R.official(next(iter(rows))), end=' ')
" | sed 's/ $//')"

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
finish
