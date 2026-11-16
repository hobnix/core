#!/usr/bin/env bash
# Packages (docs/PLAN-packages.md): the manifest validator, the converter, `hs pkg list|updates` and a recipe run remembering the version it applied,
# on a small fixture tree (tests/fixtures/pkgtree). The real packages are checked in their own repositories. No root.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
export HS_LANG=en HS_PLAIN=1 HS_STATE_DIR=$WORK/state
mkdir -p "$HS_STATE_DIR"
FIX=$ROOT/tests/fixtures/pkgtree
export HS_PACKAGES_ROOT=$FIX
PKG="python3 -I $SCRIPTS/pkg.py"
tab=$'\t'

echo "-- the fixture tree"
check "every manifest is valid" $PKG validate
n_recipes=$(ls "$FIX"/packages/*/run.sh | wc -l)
check_eq "every recipe has a manifest" "$n_recipes" "$(ls "$FIX"/packages/*/package.toml | wc -l)"
check_eq "the fixture extension is an extension package" "1" "$($PKG list --all --kind extension | wc -l)"
check_eq "the fixture capability is a capability package" "1" "$($PKG list --all --kind capability | wc -l)"
check_out "list --kind capability names it" "^fixcap${tab}capability${tab}1[.]0[.]0" $PKG list --kind capability
check_eq "list --kind extension does not show it" "0" "$($PKG list --all --kind extension | grep -c '^fixcap')"
check_out "list shows fixapp with a version" "^fixapp${tab}recipe${tab}1[.]1[.]0" $PKG list
check_eq "a personal recipe is hidden without --all" "0" "$($PKG list | grep -c "^fixpersonal${tab}")"
check_eq "and shown with it" "1" "$($PKG list --all | grep -c "^fixpersonal${tab}")"
check_eq "the API level is a number" "1" "$($PKG api | grep -cE '^[1-9][0-9]*$')"

echo "-- the converter (header lines to manifest)"
check_out "convert reads kind, needs and an ask" 'key = "' bash -c "$PKG convert $FIX/convert/ask.sh"
check_out "convert reads the runs header" 'runs = \["lxc", "docker"\]' bash -c "$PKG convert $FIX/packages/fixapp/run.sh"
check_out "convert gives the audience" 'audience = "personal"' bash -c "$PKG convert $FIX/convert/personal.sh"

echo "-- the validator on a broken tree"
BAD=$WORK/tree; mkdir -p "$BAD/packages/demo" "$BAD/packages/other" "$BAD/scripts"
printf '#!/usr/bin/env bash\n# recipe: demo: a demo\n# kind: generic\n# needs: docker\n# uses: -\n' > "$BAD/scripts/demo.sh"
mkdir -p "$BAD/scripts/recipes"; mv "$BAD/scripts/demo.sh" "$BAD/scripts/recipes/demo.sh"
good='name = "demo"\nversion = "1.0.0"\nkind = "recipe"\ntitle = "d"\nrequires_core = ">=1"\nneeds = ["docker"]\nscript = "scripts/recipes/demo.sh"\n'
run() { HS_PACKAGES_ROOT=$BAD $PKG validate; }
printf "$good" > "$BAD/packages/demo/package.toml"; rm -rf "$BAD/packages/other"
check "a good manifest passes" run
printf "${good/1.0.0/1.0}" > "$BAD/packages/demo/package.toml"
check_out "a version that is not semver is named" "semver" bash -c "HS_PACKAGES_ROOT=$BAD $PKG validate; true"
printf "${good/>=1/>=99}" > "$BAD/packages/demo/package.toml"
check_out "a package that needs a newer core is named" "above the API level" bash -c "HS_PACKAGES_ROOT=$BAD $PKG validate; true"
printf "${good/docker/share}" > "$BAD/packages/demo/package.toml"
check_out "needs that differ from the header are named" "differ from the script" bash -c "HS_PACKAGES_ROOT=$BAD $PKG validate; true"
printf "${good/demo/Demo}" > "$BAD/packages/demo/package.toml"
check_out "a name that differs from the folder is named" "differs from the folder" bash -c "HS_PACKAGES_ROOT=$BAD $PKG validate; true"

echo "-- applied versions and updates"
check_eq "nothing is applied yet, no update" "" "$($PKG updates)"
echo "-- the capability kind"
CAP=$WORK/captree; mkdir -p "$CAP/capabilities"
capcase() {   # capcase <label> <expected text | ""> <sed expression on the good package.toml> [extra shell]
  rm -rf "$CAP/capabilities/fixcap"; cp -r "$FIX/capabilities/fixcap" "$CAP/capabilities/fixcap"
  sed -i "$3" "$CAP/capabilities/fixcap/package.toml"
  if [ -n "$4" ]; then ( cd "$CAP/capabilities/fixcap" && eval "$4" ); fi
  if [ -z "$2" ]; then check "$1" bash -c "HS_PACKAGES_ROOT=$CAP $PKG validate"
  else check_out "$1" "$2" bash -c "HS_PACKAGES_ROOT=$CAP $PKG validate; true"; fi
}
capcase "the fixture capability is valid" "" 's/^$//'
capcase "a type that is not feature or provider is named" "type is not feature or provider" 's/type = "feature"/type = "thing"/'
capcase "a missing type is named" "type is not feature or provider" '/^type = /d'
capcase "requires that is not a list of names is named" "requires is not a list" 's/^requires = \[\]/requires = "x"/'
capcase "a module that is not a .nix name is named" "module must be" 's/module.nix/..\/x.sh/'
capcase "a module file that is missing is named" "module module.nix not found" 's/^$//' "rm module.nix"
capcase "a module without requires_nix_api is named" "requires_nix_api is required" '/requires_nix_api/d'
capcase "requires_nix_api of 0 is named" "requires_nix_api must be" 's/requires_nix_api = 1/requires_nix_api = 0/'
capcase "requires_nix_api without a module is named" "requires_nix_api without module" '/^module/d'
capcase "an options file that is missing is named" "options options.toml not found" 's/^$//' "rm options.toml"
capcase "an option of another capability is named" "needs capability" 's/^$//' "sed -i 's/capability = \"fixcap\"/capability = \"other\"/' options.toml"
capcase "a capability.toml beside it is refused" "has no capability.toml" 's/^$//' "touch capability.toml"
capcase "a module needing a higher Nix API level is named" "above the Nix API level" 's/requires_nix_api = 1/requires_nix_api = 99/'
capcase "the kind of a draft stays valid" "" 's/^$//'

$PKG record fixapp
check_out "record writes the version" 'version = "1.1.0"' cat "$HS_STATE_DIR/packages/installed.toml"
check_eq "up to date after record" "" "$($PKG updates)"
printf '[package.fixapp]\nversion = "0.9.0"\n' > "$HS_STATE_DIR/packages/installed.toml"
check_out "an older applied version shows as an update" "^fixapp${tab}0[.]9[.]0${tab}1[.]1[.]0" $PKG updates
check "an unknown package cannot be recorded" bash -c "! $PKG record nope 2>/dev/null"
rm -f "$HS_STATE_DIR/packages/installed.toml"
$PKG record fixapp
check "record without --applied writes no applied" bash -c "! grep -q '^applied' '$HS_STATE_DIR/packages/installed.toml'"
check_eq "so pkg.py applied prints nothing" "" "$($PKG applied)"
$PKG record fixapp --applied
check_out "record --applied writes applied" 'applied = "1.1.0"' cat "$HS_STATE_DIR/packages/installed.toml"
check_eq "pkg.py applied prints name and version" "fixapp${tab}1.1.0" "$($PKG applied)"
$PKG record fixapp
check_eq "a plain record keeps applied" "fixapp${tab}1.1.0" "$($PKG applied)"

echo "-- hs pkg"
check_out "hs pkg validate says ok" "valid" bash "$SCRIPTS/pkg.sh" validate
check_out "hs sys pkg list has a row per package" "^fixext${tab}extension" bash "$SCRIPTS/pkg.sh" --list

echo "-- a recipe package with commands (fixapp)"
PK=$WORK/pk; mkdir -p "$PK"; cp -r "$FIX"/packages/* "$FIX"/capabilities/* "$PK"/; export HS_PACKAGES_DIR=$PK HS_RECIPES_DIR=$PK
export HS_CAPABILITIES_FILE=$WORK/caps; : > "$HS_CAPABILITIES_FILE"
HS="bash $SCRIPTS/lib/hs.sh"
rm -f "$HS_STATE_DIR/packages/installed.toml"
check_eq "before the recipe is applied its commands do not exist" "0" "$($HS help --all 2>/dev/null | grep -c 'ext fixapp status')"
check_out "hs ext fixapp names the recipe and says to apply it" "hs recipe fixapp" $HS ext fixapp
check_eq "hs ext list shows extensions only" "0" "$($HS ext list 2>/dev/null | grep -c '^fixapp')"
check_out "hs ext enable refuses a recipe" "is a recipe" bash -c "$HS ext enable fixapp 2>&1; true"
$PKG record fixapp
check "after the recipe was applied the command is there" bash -c "$HS help --all 2>/dev/null | grep -q 'ext fixapp status'"
check_out "hs sys ext fixapp status prints nothing without incus/container" "^$" bash -c "PATH=/nonexistent:\$PATH $HS sys ext fixapp status 2>/dev/null; echo"
echo "-- the old reads stay byte-equal (market, recipes list)"
GS=$WORK/gold; mkdir -p "$GS/state/packages/current/oldthing" "$GS/bin"
printf '[package.oldthing]\nversion = "0.5.0"\nrepo = "gone"\n' > "$GS/state/packages/installed.toml"
printf '#!/bin/sh\necho fixapp\n' > "$GS/bin/incus"; chmod +x "$GS/bin/incus"
gold() { HS_STATE_DIR=$GS/state HS_INCUS=$GS/bin/incus bash "$@" | tr -d '\r'; }
check_eq "pkg.sh --market is unchanged" "$(cat "$ROOT/tests/fixtures/pkg-market.golden")" "$(gold "$SCRIPTS/pkg.sh" --market)"
check_eq "recipes-list.sh --list is unchanged" "$(cat "$ROOT/tests/fixtures/recipes-list.golden")" "$(gold "$SCRIPTS/recipes-list.sh" --list)"

echo "-- lifecycle states (ADR 0027)"
ST=$WORK/states; mkdir -p "$ST"
row() { local IFS=$tab; printf '%s\n' "$*"; }   # one tab separated line
{ row fixapp recipe repo 1.1.0 1.0.0 update no generic "Fixture app"
  row fixext extension repo 1.0.0 1.0.0 current no generic "Fixture extension"
  row fixcap capability repo 1.0.0 - new no generic "Fixture capability"
  row newapp recipe repo 1.0.0 - new no generic "New app"
  row gone "?" gone - 0.5.0 orphan no - -; } > "$ST/market"
{ row fixext on extension no yes "Fixture extension"; row fixcap off part yes yes "Fixture capability"; } > "$ST/parts"
: > "$ST/pending"
{ row fixapp "Fixture app" "fixapp,fixapp2" partly; row newapp "New app" - "not installed"; } > "$ST/recipes"
printf '%s\n' "fixapp,RUNNING" "fixapp2,STOPPED" "other,RUNNING" > "$ST/running"
states() { $PKG states --market "$ST/market" --parts "$ST/parts" --pending "$ST/pending" --recipes "$ST/recipes" --running "$ST/running" "$@" | tr -d '\r'; }
check_out "a recipe with one instance stopped is on, flagged update and stopped" "^fixapp${tab}recipe${tab}on${tab}update,stopped${tab}repo${tab}1[.]1[.]0${tab}1[.]0[.]0${tab}fixapp,fixapp2${tab}Fixture app\$" states
check_out "a recipe that is not fetched is available" "^newapp${tab}recipe${tab}available${tab}-${tab}" states
check_out "an extension that is on and not pending is running" "^fixext${tab}extension${tab}running${tab}-${tab}" states
check_out "a capability that is off is installed" "^fixcap${tab}capability${tab}installed${tab}-${tab}" states
check_out "an orphan is flagged" "^gone${tab}[?]${tab}installed${tab}orphan${tab}" states
printf '%s\n' "fixapp,RUNNING" "fixapp2,RUNNING" > "$ST/running"
check_out "a recipe whose instances all run is running" "^fixapp${tab}recipe${tab}running${tab}update${tab}" states
: > "$ST/running"
check_out "without a container list a recipe is on, never running" "^fixapp${tab}recipe${tab}on${tab}update${tab}" states
{ row fixext on; row fixcap on; } > "$ST/pending"
check_out "a pending part is on with the flag" "^fixext${tab}extension${tab}on${tab}pending${tab}" states
check_eq "--kind keeps one kind" "2" "$(states --kind recipe | wc -l)"
check_eq "the output is sorted by name" "$(states | cut -f1)" "$(states | cut -f1 | sort)"
check_eq "every row has nine fields" "0" "$(states | awk -F'\t' 'NF != 9' | wc -l)"
finish
