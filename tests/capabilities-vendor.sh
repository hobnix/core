#!/usr/bin/env bash
# capabilities/default.nix with vendored capability packages (docs/PLAN-capabilities-repo.md, Q3, step 4): a vendored module is loaded from
# vendor/capabilities/<name>/ after its hashes are checked against vendor/capabilities.lock; a changed, extra or missing file stops the
# evaluation with the package name; without vendor/ the import list is the one of the core. Needs nix-instantiate and nixpkgs (<nixpkgs>).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
have nix-instantiate || { skip "needs nix-instantiate"; finish; exit 0; }
nix-instantiate --eval -E '(import <nixpkgs> {}).lib.version' >/dev/null 2>&1 || { skip "needs <nixpkgs>"; finish; exit 0; }
export HS_LANG=en HS_PLAIN=1
PKG="python3 -I $SCRIPTS/pkg.py"

CO=$WORK/checkout; mkdir -p "$CO"
cp -r "$ROOT/capabilities" "$CO/capabilities"
rm -rf "$CO/capabilities/testlab/tests"          # nothing the evaluation reads
cp -r "$ROOT/tests/fixtures/pkgtree/capabilities/fixcap" "$WORK/fixcap"

# the import list for a set of enabled names, one path per line relative to the checkout
imports() {   # imports <enabled name>...
  local list="" n
  for n in "$@"; do list="$list \"$n\""; done
  nix-instantiate --eval --strict --json -E "let lib = (import <nixpkgs> {}).lib; on = [ $list ]; in map toString (import $CO/capabilities/default.nix { inherit lib; enabled = n: builtins.elem n on; })" 2>&1 \
    | python3 -c 'import json,sys
t = sys.stdin.read()
try:
    for p in json.loads(t): print(p.replace(sys.argv[1] + "/", ""))
except ValueError:
    print("ERROR " + " ".join(t.split()))' "$CO"
}

echo "-- without vendor/"
base=$(imports testlab)
check_out "the core module of an enabled capability is loaded" "^capabilities/testlab/module.nix$" echo "$base"
check_out "options.nix is always there" "^capabilities/options.nix$" echo "$base"
check_eq "nothing else" "2" "$(grep -c . <<<"$base")"
check_eq "an enabled name that is no folder adds nothing" "1" "$(imports nonexistent | grep -c .)"

echo "-- vendored"
check "vendor puts the fixture into the checkout" $PKG vendor --from "$WORK/fixcap" --to "$CO"
check_out "an enabled vendored package is loaded from vendor/" "^vendor/capabilities/fixcap/module.nix$" imports fixcap
check_eq "a vendored package that is off adds nothing" "$(imports)" "$(imports testlab | grep -v testlab)"
check_eq "the core list is the same as without vendor/" "$base" "$(imports testlab)"

echo "-- a changed byte"
printf '# changed\n' >> "$CO/vendor/capabilities/fixcap/module.nix"
check_out "the evaluation names the package and the file" "ERROR.*fixcap.*module.nix does not match vendor/capabilities.lock.*hs pkg install fixcap" imports fixcap
check_eq "while it is off nothing is checked" "$base" "$(imports testlab)"
$PKG vendor --from "$WORK/fixcap" --to "$CO" >/dev/null
check_out "vendoring again repairs it" "^vendor/capabilities/fixcap/module.nix$" imports fixcap
printf '{ }\n' > "$CO/vendor/capabilities/fixcap/extra.nix"
check_out "an extra .nix file is refused" "ERROR.*fixcap.*extra.nix does not match" imports fixcap
rm -f "$CO/vendor/capabilities/fixcap/extra.nix"
rm -rf "$CO/vendor/capabilities/fixcap"
check_out "a folder that is gone is named" "ERROR.*fixcap.*is missing.*hs pkg install fixcap" imports fixcap

finish
