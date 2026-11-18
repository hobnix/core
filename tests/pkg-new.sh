#!/usr/bin/env bash
# hs pkg new (scripts/pkg_new.py): both templates write a package that passes pkg.py validate, repo-check, the extension loader and the
# guide rules without edits; the command refuses a bad name, an unknown template, a folder that is no package repository and an
# existing package, and then writes nothing. No root.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
export HS_LANG=en HS_PLAIN=1 HS_CALLER=test HS_STATE_DIR=$WORK/state
mkdir -p "$HS_STATE_DIR"
PKG="python3 -I $SCRIPTS/pkg.py"
NEW="bash $SCRIPTS/pkg.sh new"
tab=$'	'
repo() { mkdir -p "$1/$2"; printf '# The index of this repository\n' > "$1/index.toml"; }

echo "-- the recipe template"
R=$WORK/recipes; repo "$R" recipes
check_out "hs pkg new writes a recipe" "Created run.sh" $NEW demo-app --template recipe --dir "$R" --title "Demo app: an app for the tests"
P=$R/recipes/demo-app
for f in package.toml run.sh guide.md; do check "the recipe has $f" test -s "$P/$f"; done
check "run.sh is executable" test -x "$P/run.sh"
check "run.sh is valid bash" bash -n "$P/run.sh"
T=$WORK/rtree; mkdir -p "$T"; ln -s "$R/recipes" "$T/packages"
check "pkg.py validate passes (as the CI of the recipes repository runs it)" env HS_PACKAGES_ROOT="$T" $PKG validate
check "pkg.py repo-check passes" $PKG repo-check "$R"
check_out "index.toml has the entry" '^\[package\.demo-app\]' cat "$R/index.toml"
check_eq "the title is in the manifest" 'title = "Demo app: an app for the tests"' "$(grep '^title = ' "$P/package.toml")"
check_out "the dry run names the container" "demo-app" env state="$WORK/state" HS_SCRIPTS="$SCRIPTS" bash "$P/run.sh" --dry-run
check_out "the closing text names its guide" 'docs_hint demo-app' cat "$P/run.sh"
check_eq "the guide has one H1" "1" "$(grep -c '^# ' "$P/guide.md")"
check_eq "the guide has no raw HTML" "0" "$(grep -cE '<(p|br|div|span|details|summary|img|a|table|b|i|small|center)[ >/]' "$P/guide.md" || true)"
check_eq "the manifest is at the current API level" "requires_core = \">=$(cat "$SCRIPTS/lib/api-level")\"" "$(grep '^requires_core' "$P/package.toml")"
for k in description description_de icon category app_version; do check "the recipe manifest has $k" grep -q "^$k = " "$P/package.toml"; done
check "the default category is on the list of config/package-categories.toml" grep -q '^category = "tools"' "$P/package.toml"
for t in app app.health app.backup app.update app.remove app.uses; do check "the recipe manifest has [$t]" grep -q "^\[$t\]" "$P/package.toml"; done
check_eq "the index carries icon, category and app_version" "3" "$(sed -n '/^\[package.demo-app\]/,/^$/p' "$R/index.toml" | grep -cE '^(icon|category|app_version) = ')"
check_out "options write the fields" "New package demo-opt" $NEW demo-opt --template recipe --dir "$R" --description "Photos." --description-de "Fotos." --icon ph:image --category media --app-version 1.2.3 --instances many
check_eq "the fields are in the manifest" 'icon = "ph:image" category = "media" app_version = "1.2.3" instances = "many"' "$(grep -E '^(icon|category|app_version|instances) = ' "$R/recipes/demo-opt/package.toml" | paste -sd' ')"
check "repo-check passes with the options" $PKG repo-check "$R"
check "validate passes with the options" env HS_PACKAGES_ROOT="$WORK/rtree" $PKG validate
check_out "the default folder is the current one" "Created run.sh" bash -c "cd '$R' && $NEW demo-two --template recipe"
check "repo-check passes with two new packages" $PKG repo-check "$R"

echo "-- the extension template"
E=$WORK/extensions; repo "$E" extensions
check_out "hs pkg new writes an extension" "Created commands.tsv" $NEW demo-ext --template extension --dir "$E"
X=$E/extensions/demo-ext
for f in package.toml capability.toml commands.tsv list.sh NOTES.md guide.md; do check "the extension has $f" test -s "$X/$f"; done
check "list.sh is executable" test -x "$X/list.sh"
check "list.sh is valid bash" bash -n "$X/list.sh"
T=$WORK/etree; mkdir -p "$T"; ln -s "$E/extensions" "$T/capabilities"
check "pkg.py validate passes (as the CI of the extensions repository runs it)" env HS_PACKAGES_ROOT="$T" $PKG validate
check "pkg.py repo-check passes" $PKG repo-check "$E"
check_eq "the title defaults to the name" 'title = "demo-ext"' "$(grep '^title = ' "$X/package.toml")"
bad=$(python3 -I - "$X" <<'EOF'
import os, sys, tomllib
d = sys.argv[1]
m = tomllib.load(open(os.path.join(d, "capability.toml"), "rb"))
if m.get("name") != os.path.basename(d): print("name")
if not m.get("title") or not m.get("title_de"): print("title")
if m.get("kind") not in ("feature", "provider"): print("kind")
if m.get("extension") is not True: print("extension")
if "notes" in m and not os.path.exists(os.path.join(d, m["notes"])): print("notes")
rows = [l.rstrip("\n").split("\t") for l in open(os.path.join(d, "commands.tsv"), encoding="utf-8") if l.strip() and not l.startswith("#")]
for r in rows:
    if len(r) < 6: print("columns")
paths = {r[1] for r in rows if r[0] == "sys"}
for r in m.get("web", {}).get("reads", []):
    if "sys ext %s %s" % (m["name"], r["words"]) not in paths: print("read " + r["words"])
EOF
)
check_eq "capability.toml follows the rules of tests/capabilities.sh and every web read has a sys row" "" "$bad"
export HS_PACKAGES_DIR=$E/extensions HS_CAPABILITIES_FILE=$WORK/caps HS_MACHINE_FILE=$WORK/machine.toml HS_SETTINGS_DIR=$WORK/settings HS_COMPLETE_DIR=$WORK/complete
printf 'demo-ext\n' > "$HS_CAPABILITIES_FILE"
HS="bash $SCRIPTS/lib/hs.sh"
check "hs help --all lists the command while the extension is on" bash -c "$HS help --all 2>/dev/null | grep -q 'ext demo-ext list'"
check_eq "hs sys ext demo-ext list prints nothing without entries" "" "$($HS sys ext demo-ext list 2>&1)"
mkdir -p "$HS_STATE_DIR/demo-ext"; printf 'one\t1\ntwo\t\n' > "$HS_STATE_DIR/demo-ext/entries"
check_eq "hs sys ext demo-ext list prints the entries, - for an empty value" "one${tab}1 two${tab}-" "$($HS sys ext demo-ext list | paste -sd' ')"
if command -v column >/dev/null 2>&1; then
  check_out "hs ext demo-ext list shows them" "two" $HS ext demo-ext list
else
  skip "hs ext demo-ext list shows them (column is not installed)"
fi

echo "-- the capability template"
C=$WORK/capabilities; repo "$C" capabilities
check_out "hs pkg new writes a capability" "Created package.toml" $NEW demo-cap --template capability --dir "$C"
Y=$C/capabilities/demo-cap
for f in package.toml guide.md; do check "the capability has $f" test -s "$Y/$f"; done
check "the capability stays at level 1" grep -q '^requires_core = ">=1"' "$Y/package.toml"
check_eq "and carries no store field" "0" "$(grep -cE '^(description|icon|category|app_version)' "$Y/package.toml" || true)"
T=$WORK/ctree; mkdir -p "$T"; ln -s "$C/capabilities" "$T/capabilities"
check "pkg.py validate passes" env HS_PACKAGES_ROOT="$T" $PKG validate
check "pkg.py repo-check passes" $PKG repo-check "$C"

echo "-- the store fields of the extension"
check_eq "the extension manifest has all four store fields" "4" "$(grep -cE '^(description|icon|category|app_version) = ' "$X/package.toml")"
check_eq "the extension is at the current API level" "requires_core = \">=$(cat "$SCRIPTS/lib/api-level")\"" "$(grep '^requires_core' "$X/package.toml")"

echo "-- the extension templates that speak the command protocol (--protocol, docs/extensions-sdk.md)"
for lang in shell python; do
  ext=$([ "$lang" = shell ] && echo sh || echo py)
  PE=$WORK/pe-$lang; repo "$PE" extensions
  check_out "hs pkg new --protocol $lang writes an extension" "Created list.$ext" $NEW demo-p$lang --template extension --protocol $lang --dir "$PE"
  Q=$PE/extensions/demo-p$lang
  check "$lang: package.toml says protocol = [1]" grep -q '^protocol = \[1\]' "$Q/package.toml"
  check "$lang: the shell contract's list.sh is gone" test ! -e "$Q/list.sh" -o "$lang" = shell
  check "$lang: the script is executable" test -x "$Q/list.$ext"
  QT=$WORK/pt-$lang; mkdir -p "$QT"; ln -s "$PE/extensions" "$QT/capabilities"
  check "$lang: pkg.py validate passes" env HS_PACKAGES_ROOT="$QT" $PKG validate
  check "$lang: pkg.py repo-check passes" $PKG repo-check "$PE"
  if command -v jq >/dev/null; then
    mkdir -p "$WORK/st-$lang/demo-p$lang"; printf 'one	1
two	
' > "$WORK/st-$lang/demo-p$lang/entries"
    out=$(HS_STATE_DIR="$WORK/st-$lang" HS_SCRIPTS=$SCRIPTS python3 -I "$SCRIPTS/lib/ext_proto.py" call --command list -- "$Q/list.$ext" 2>&1) || true
    check_out "$lang: the generated command answers through the protocol runner" 'one","1"' printf '%s' "$out"
    check_out "$lang: an empty value stays an empty cell" 'two",""' printf '%s' "$out"
  else
    echo "  skip  jq missing: the generated $lang command is not run"
  fi
done
check_out "--protocol is refused for a recipe" "is not allowed" $NEW demo-pr --template recipe --protocol shell --dir "$R"
check_out "--protocol go is refused" "is not allowed" $NEW demo-pg --template extension --protocol go --dir "$E"

echo "-- refusals"
check_out "an unknown category is refused" "category" $NEW demo-c1 --template recipe --dir "$R" --category nonsense
check_out "an icon that is no Phosphor name is refused" "icon" $NEW demo-c2 --template recipe --dir "$R" --icon "<x>"
check_out "an app version with a space is refused" "app-version" $NEW demo-c3 --template recipe --dir "$R" --app-version "1 2"
check_out "instances other than one or many are refused" "instances" $NEW demo-c4 --template recipe --dir "$R" --instances two
check_out "instances on an extension are refused" "instances" $NEW demo-c5 --template extension --dir "$E" --instances many
check_out "store fields on a capability are refused" "description" $NEW demo-c6 --template capability --dir "$C" --description x
check "nothing was written for those" bash -c "[ ! -e '$R/recipes/demo-c1' ] && [ ! -e '$R/recipes/demo-c4' ] && [ ! -e '$C/capabilities/demo-c6' ] && [ ! -e '$E/extensions/demo-c5' ]"
before="$(cksum < "$P/package.toml") $(cksum < "$R/index.toml")"
check_out "the same name again is refused" "already" $NEW demo-app --template recipe --dir "$R"
check_eq "and nothing changed" "$before" "$(cksum < "$P/package.toml") $(cksum < "$R/index.toml")"
check "and the exit code says so" bash -c "! $NEW demo-app --template recipe --dir '$R' >/dev/null 2>&1"
check_out "a name with capitals is refused" "not allowed" $NEW Demo --template recipe --dir "$R"
check_out "a reserved word is refused" "not allowed" $NEW list --template extension --dir "$E"
check_out "a name ending in a newline is refused" "not allowed" $NEW $'demo\n' --template recipe --title X --dir "$R"
check_out "a title holding a placeholder is written literally" "New package demo-ph" $NEW demo-ph --template recipe --title '{title_de}' --title-de 'x"y' --dir "$R"
check "the manifest of that package is valid TOML" python3 -c "import tomllib,sys;tomllib.load(open(sys.argv[1],'rb'))" "$R/recipes/demo-ph/package.toml"
check_out "the message names the package, not an option" "New package demo-ph2" $NEW --template recipe demo-ph2 --dir "$R"
check_out "an unknown template is refused" "Unknown template" $NEW demo-cap --template service --dir "$E"
check_out "a folder that is no package repository is refused" "not a checkout" $NEW demo-x --template recipe --dir "$HS_STATE_DIR"
check_out "a recipe in an extensions checkout is refused" "not a checkout" $NEW demo-x --template recipe --dir "$E"
check_out "a title with a tab is refused" "one line" $NEW demo-y --template recipe --dir "$R" --title "a${tab}b"
check "nothing was written for the refused ones" bash -c "[ ! -e '$R/recipes/Demo' ] && [ ! -e '$E/extensions/list' ] && [ ! -e '$R/recipes/demo-y' ] && [ ! -e '$E/extensions/demo-cap' ] && [ ! -e '$E/recipes' ]"
check_out "without a name it shows the usage" "usage: hs pkg new" $NEW
printf '\n[package.ghost]\nversion = "1.0.0"\nkind = "recipe"\npath = "recipes/ghost"\n' >> "$R/index.toml"
check_out "a name that is only in index.toml is refused" "already" $NEW ghost --template recipe --dir "$R"
check "and no folder is written for it" test ! -e "$R/recipes/ghost"
finish
