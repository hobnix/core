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
echo "-- the app contract and store fields (API level 9, docs/Package-API.md)"
AF=$ROOT/tests/fixtures/pkgapp
APPT=$WORK/apptree
appcase() {   # appcase <label> <expected text | ""> <python snippet that changes the text t of package.toml; p is its path>
  rm -rf "$APPT"; mkdir -p "$APPT/packages"; cp -r "$AF/packages/fixstore" "$APPT/packages/fixstore"
  python3 - "$APPT/packages/fixstore/package.toml" "$3" <<'PY'
import os, sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read()
exec(sys.argv[2])
open(p, "w", encoding="utf-8").write(t)
PY
  if [ -z "$2" ]; then check "$1" bash -c "HS_PACKAGES_ROOT=$APPT $PKG validate"
  else check_out "$1" "$2" bash -c "HS_PACKAGES_ROOT=$APPT $PKG validate; true"; fi
}
appcase "the good fixture package passes" "" 'pass'
check_eq "the API level is 10" "10" "$($PKG api)"
appcase "an old manifest (requires >=1, no app fields) is unchanged" "" 't = "name = \"fixstore\"\nversion = \"1.0.0\"\nkind = \"recipe\"\ntitle = \"x\"\nrequires_core = \">=1\"\nscript = \"run.sh\"\n"'
appcase "app fields on an older requires_core are named" 'need requires_core' 't = t.replace(">=9", ">=8")'
appcase "an unknown category is named" 'category is not one of' 't = t.replace("tools", "stuff")'
appcase "an unknown [app] key is named" 'unknown key' 't = t.replace("autostart = true", "autostart = true\nfoo = 1")'
appcase "instances other than one or many is named" 'instances is not one or many' 't = t.replace("many", "two")'
appcase "an http health check without a port is named" 'needs a port' 't = t.replace("port = 8080\npath", "path")'
appcase "backup mode paths without paths is named" 'needs paths' 't = t.replace("paths = [\"/var/lib/fixstore\"]\n", "")'
appcase "a default route that does not exist is named" 'default must name' 't = t.replace("default = \"web\"", "default = \"nope\"")'
appcase "a public admin route is refused" 'admin page is never public' 't = t.replace("private-ok\" }", "public-ok\", admin = true }")'
appcase "update kind is checked" 'kind is not pin, os or manual' 't = t.replace("kind = \"pin\"", "kind = \"x\"")'
appcase "http-json without a pointer is named" 'needs a path and a JSON pointer' 't = t.replace("pointer = \"/version\"\n", "")'
appcase "more than five screenshots are refused" 'at most 5' 't = t.replace("[\"shots/one.png\"]", "[" + ",".join("\"shots/one.png\"" for _ in range(6)) + "]")'
appcase "a screenshot that is not in the package is named" 'is not in the package' 't = t.replace("shots/one.png", "shots/gone.png")'
appcase "a screenshot outside the package is refused" 'relative png or webp' 't = t.replace("shots/one.png", "../x.png")'
appcase "a screenshot that is not png or webp is refused" 'relative png or webp' 't = t.replace("shots/one.png", "shots/one.gif")'
appcase "a screenshot over 300 KB is refused" 'larger than 300 KB' 'f = open(os.path.join(os.path.dirname(p), "shots/one.png"), "ab"); f.write(b"0" * 307201); f.close()'
appcase "a Phosphor icon name is accepted" "" 't = t.replace("icon = \"icon.svg\"", "icon = \"ph:image\"")'
appcase "an icon that is neither a name nor an svg is named" 'icon must be' 't = t.replace("icon.svg", "icon.png")'
appcase "an svg icon with a script is refused" 'contains <script' 'open(os.path.join(os.path.dirname(p), "icon.svg"), "w").write("<svg><script>1</script></svg>")'
appcase "an svg icon with an event handler is refused" 'handler' 'open(os.path.join(os.path.dirname(p), "icon.svg"), "w").write("<svg onload=\"x()\"></svg>")'
appcase "an svg icon with an external reference is refused" 'external reference' 'open(os.path.join(os.path.dirname(p), "icon.svg"), "w").write("<svg><image href=\"https://x.test/a.png\"/></svg>")'
appcase "app_version with spaces is named" 'app_version must be' 't = t.replace("2.3.4", "two point")'
appcase "an upstream that is not https is named" 'upstream must be' 't = t.replace("https://example.org", "http://example.org")'
appcase "a store package without an icon only gets a warning" "" 't = t.replace("icon = \\"icon.svg\\"\n", "")'
appcase "a list as a route port does not crash" 'port [(]1 to 65535[)] missing' 't = t.replace("port = 8080, scheme", "port = [1], scheme").replace("private-ok", "public-ok")'
appcase "an svg animation is refused" 'animation' 'open(os.path.join(os.path.dirname(p), "icon.svg"), "w").write("<svg><set attributeName=a to=b/></svg>")'
appcase "an unknown key with a control character stays on one line" 'unknown key a.b' 'k = "a" + chr(9) + "b"; t = t.replace("autostart = true", "autostart = true" + chr(10) + chr(34) + k + chr(34) + " = 1")'

echo "-- repo-check: index keys, core recipes and warnings"
RC=$WORK/repo; rm -rf "$RC"; mkdir -p "$RC/recipes"; cp -r "$AF/packages/fixstore" "$RC/recipes/fixstore"
idx() { printf '[package.fixstore]\npath = "recipes/fixstore"\nkind = "recipe"\nversion = "1.0.0"\nrequires_core = ">=9"\n%b' "$1" > "$RC/index.toml"; }
idx 'icon = "icon.svg"\ncategory = "tools"\napp_version = "2.3.4"\n'
check "repo-check passes with the three index keys" $PKG repo-check "$RC"
idx 'icon = "icon.svg"\ncategory = "media"\napp_version = "2.3.4"\n'
check_out "an index category that differs is named" "category differs between index and package.toml" bash -c "$PKG repo-check $RC; true"
idx ''
check_out "an index without the keys is named" "icon differs" bash -c "$PKG repo-check $RC; true"
rm -rf "$RC/recipes/fixstore"; mkdir -p "$RC/recipes/fixold"
printf '#!/usr/bin/env bash\n# recipe: Old\n# kind: generic\n# needs: -\n# uses: -\n' > "$RC/recipes/fixold/run.sh"
printf 'name = "fixold"\nversion = "1.0.0"\nkind = "recipe"\ntitle = "Old"\nrequires_core = ">=1"\npermissions = []
script = "run.sh"\n' > "$RC/recipes/fixold/package.toml"
printf '[package.fixold]\npath = "recipes/fixold"\nkind = "recipe"\nversion = "1.0.0"\nrequires_core = ">=1"\n' > "$RC/index.toml"
check "an old package passes repo-check" $PKG repo-check "$RC"
check_out "and gets a warning on stderr" 'warning: fixold: has no \[app\] contract' bash -c "$PKG repo-check $RC 2>&1"
printf 'core = true\n' >> "$RC/index.toml"
check_out "a core recipe written before level 9 only gets a warning" 'warning: fixold: missing: \[app.health\]' bash -c "$PKG repo-check $RC 2>&1"
check "and repo-check still passes" $PKG repo-check "$RC"
sed -i 's/>=1/>=9/' "$RC/recipes/fixold/package.toml" "$RC/index.toml"
check_out "a core recipe at level 9 without the contract is an error" 'missing: \[app.health\]' bash -c "$PKG repo-check $RC; true"

echo "-- check-draft sees the fields"
check_out "a draft with a bad category is an error" "error${tab}category${tab}category is not one of" bash -c "sed 's/tools/stuff/' $AF/packages/fixstore/package.toml | $PKG check-draft; true"

echo "-- protocol, service and timeout keys (0.8 step 1: parse and validate only)"
PT=$WORK/prototree; mkdir -p "$PT/capabilities"
protocase() {   # protocase <label> <expected text | ""> <lines appended to package.toml> [commands.tsv flags for the row]
  rm -rf "$PT/capabilities/fixext"; cp -r "$FIX/capabilities/fixext" "$PT/capabilities/fixext"
  printf '%b' "$3" >> "$PT/capabilities/fixext/package.toml"
  if [ -n "$4" ]; then printf 'user\text fixext one\t@/one.sh\t-\thelp\t-\t%s\n' "$4" >> "$PT/capabilities/fixext/commands.tsv"; fi
  if [ -z "$2" ]; then check "$1" bash -c "HS_PACKAGES_ROOT=$PT $PKG validate"
  else check_out "$1" "$2" bash -c "HS_PACKAGES_ROOT=$PT $PKG validate; true"; fi
}
protocase "an old manifest validates unchanged" "" ''
protocase "protocol [1] below the required level is named" 'protocol needs requires_core = ">=10"' 'protocol = [1]\n'
protocase "protocol [2] is refused" 'protocol must be \[1\]' 'protocol = [2]\n'
protocase "protocol [1, 2] is refused" 'protocol must be \[1\]' 'protocol = [1, 2]\n'
protocase "protocol that is a string is refused" 'protocol must be a list of numbers' 'protocol = "1"\n'
protocase "an empty protocol list is refused" 'protocol must be a list of numbers' 'protocol = []\n'
protocase "a service without exec is named" 'service: exec missing' '[service]\nsubscribe = []\n'
protocase "a service exec that leaves the package is refused" 'service: exec must be' '[service]\nexec = "@/../x.sh"\n'
protocase "a service with an unknown key is refused" 'service: unknown key restart' '[service]\nexec = "@/s.py"\nrestart = true\n'
protocase "a health_interval out of range is refused" 'health_interval must be' '[service]\nexec = "@/s.py"\nhealth_interval = 1\n'
protocase "a subscribe that is not a list of globs is refused" 'subscribe must be a list' '[service]\nexec = "@/s.py"\nsubscribe = "all"\n'
protocase "a service below the required level is named" '\[service\] needs requires_core = ">=10"' '[service]\nexec = "@/s.py"\n'
protocase "a service that is not a table is refused" 'service must be a' 'service = 3\n'
protocase "a timeout of 0 is refused" 'timeout must be a whole number' '' 'reads,timeout:0'
protocase "a timeout of 3601 is refused" 'timeout must be a whole number' '' 'reads,timeout:3601'
protocase "a timeout that is not a number is refused" 'timeout must be a whole number' '' 'timeout:soon'
protocase "a timeout twice on one row is refused" 'timeout is given twice' '' 'timeout:5,timeout:6'
protocase "a timeout of 3600 is valid" "" '' 'reads,timeout:3600'
check_eq "a valid protocol and service pass at the level that allows them" "" "$(python3 -I -c "
import importlib.util
s = importlib.util.spec_from_file_location('p', '$SCRIPTS/lib/pkg_protocol.py'); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
print(m.manifest_problems({'requires_core': '>=10', 'protocol': [1], 'service': {'exec': '@/s.py', 'subscribe': ['pkg.*'], 'health_interval': 30}}))" | sed 's/^\[\]$//')"

finish
