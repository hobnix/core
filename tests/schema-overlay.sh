#!/usr/bin/env bash
# The options of capability packages installed on a machine (docs/PLAN-capabilities-repo.md, Q4, step 6a): `schema-gen.py overlay` writes
# schema.overlay.json and config-keys.overlay from options.toml, byte-equal on a second run, and refuses a key that clashes. No root, no server.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
GEN="python3 $SCRIPTS/schema-gen.py"
PK=$WORK/packages; OUT=$WORK/generated
mkpkg() {   # name, then the lines of options.toml
  local n=$1; shift
  mkdir -p "$PK/$n"
  printf 'name = "%s"\nversion = "1.0.0"\nkind = "capability"\ntype = "feature"\ntitle = "%s"\nrequires_core = ">=1"\naudience = "generic"\noptions = "options.toml"\n' "$n" "$n" > "$PK/$n/package.toml"
  printf '%s\n' "$@" > "$PK/$n/options.toml"
}
item() { printf '[[item]]\nkey = "%s"\ncapability = "%s"\nstore = "machine"\ntype = "string"\ndefault = "x"\ndescription = "d"\n' "$1" "$2"; }

echo "-- write and determinism"
mkpkg zeta "$(item zetaHost zeta)"
mkpkg alpha "$(item alphaB alpha)" "$(item alphaA alpha)"
check "write" $GEN overlay write --packages "$PK" --out "$OUT"
for f in schema.overlay.json config-keys.overlay capabilities.tsv layout.overlay.json; do check "$f exists" test -s "$OUT/$f"; done
first=$(cat "$OUT"/schema.overlay.json "$OUT"/config-keys.overlay "$OUT"/capabilities.tsv | cksum)
rm -rf "$OUT"
$GEN overlay write --packages "$PK" --out "$OUT" >/dev/null
check_eq "two runs are byte-equal" "$first" "$(cat "$OUT"/schema.overlay.json "$OUT"/config-keys.overlay "$OUT"/capabilities.tsv | cksum)"
check_eq "a second write changes nothing" "" "$($GEN overlay write --packages "$PK" --out "$OUT")"
check_eq "packages sorted by name, options in file order" "alphaB alphaA zetaHost" "$($GEN overlay keys --packages "$PK" | cut -f1 | paste -sd' ')"
check "check is clean" $GEN overlay check --packages "$PK" --out "$OUT"
check "no time stamp in the JSON" bash -c '! grep -qE "[0-9]{4}-[0-9]{2}-[0-9]{2}" "$1"' _ "$OUT/schema.overlay.json"
check "the JSON has no spaces between its parts" bash -c '! grep -q ", \|: " "$1"' _ "$OUT/schema.overlay.json"

echo "-- the Settings layout of the packages (web, step 6c)"
check_eq "every option is on the page of its package" '{"alphaA":"cap:alpha","alphaB":"cap:alpha","zetaHost":"cap:zeta"}' "$(python3 -c 'import json,sys;print(json.dumps(json.load(open(sys.argv[1]))["keys"],sort_keys=True,separators=(",",":")))' "$OUT/layout.overlay.json")"
check_eq "a package has an entry with its title" "alpha zeta" "$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]))["caps"];print(" ".join(sorted(k for k,v in d.items() if v["entry"] and v["title"]==k)))' "$OUT/layout.overlay.json")"

echo "-- clashes are refused and the previous overlay stays"
before=$(cat "$OUT/schema.overlay.json")
refuse() { check "$1" bash -c '! python3 "$1/schema-gen.py" overlay write --packages "$2" --out "$3" >/dev/null 2>&1' _ "$SCRIPTS" "$PK" "$OUT"; }
mkpkg clash "$(item language clash)"
refuse "a key of the core schema"
check_eq "the previous overlay stays" "$before" "$(cat "$OUT/schema.overlay.json")"
mkpkg clash "$(item alphaA clash)"
refuse "a key of another package"
mkpkg clash "$(item clashKey other)"
refuse "an option that names another capability"
mkpkg clash "$(item Bad-Key clash)"
refuse "a key that is not a word"
rm -r "${PK:?}/clash"
check "without the clash it works again" $GEN overlay check --packages "$PK" --out "$OUT"

finish
