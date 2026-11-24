#!/usr/bin/env bash
# hs pkg repo migrate (hobnix/core#1074): an installed package whose repository has no row any more moves to the ONE default row that names
# it in `replaces`; a package that row does not list stays; nothing is downgraded; a removed ADDED repository never gains the trust of a default
# one. A fixture root with its own config/package-repos.toml stands in for the core; a local git repository and a throwaway key stand in for
# GitHub and the CI key.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
have git || { skip "needs git"; finish; exit 0; }
have ssh-keygen || { skip "needs ssh-keygen"; finish; exit 0; }
export HS_LANG=en HS_PLAIN=1 HS_STATE_DIR=$WORK/state HS_NIXOS_DIR=$WORK/nixos HS_PACKAGES_ROOT=$WORK/root
mkdir -p "$HS_STATE_DIR/packages" "$HS_NIXOS_DIR/vendor" "$HS_PACKAGES_ROOT/config/trusted-keys"
PKG="python3 -I $SCRIPTS/pkg.py"
IDX="python3 -I $SCRIPTS/lib/pkg_index.py"
tab=$'\t'
INST=$HS_STATE_DIR/packages/installed.toml
LOCK=$HS_NIXOS_DIR/vendor/capabilities.lock
ssh-keygen -q -t ed25519 -N '' -f "$WORK/good" -C ci >/dev/null
printf 'ci@test namespaces="hobnix-index" %s\n' "$(cut -d' ' -f1,2 "$WORK/good.pub")" > "$HS_PACKAGES_ROOT/config/trusted-keys/hub.allowed_signers"
R=$WORK/repo; OUT=$WORK/pub; mkdir -p "$OUT"
for p in demo newer; do mkdir -p "$R/recipes/$p"; done
cd "$R" || exit 1
git init -q . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
for p in demo newer; do
  printf 'name = "%s"\nversion = "1.0.0"\nkind = "recipe"\ntitle = "T"\nrequires_core = ">=1"\naudience = "generic"\nneeds = []\nuses = []\ninput = "none"\nscript = "run.sh"\n' "$p" > "recipes/$p/package.toml"
  printf '#!/usr/bin/env bash\n# kind: generic\n# needs: -\n# uses: -\necho %s\n' "$p" > "recipes/$p/run.sh"
done
git add -A && git commit -q -m one
$IDX build "$R" --repo hub --out "$WORK/b" --serial 1 --skip-assets >/dev/null
cp "$WORK/b/index.json" "$OUT/index.json"
$IDX sign "$OUT/index.json" --key-file "$WORK/good" >/dev/null
cd "$ROOT" || exit 1

rows() {   # rows <index address> <replaces list>: the default repository of the fixture core
  printf '[[repo]]\nname = "hub"\nurl = "%s"\nindex = "%s"\nreplaces = %s\n' "$R" "$1" "$2" > "$HS_PACKAGES_ROOT/config/package-repos.toml"
}
fresh() {   # installed.toml and the lock as a server of the old repositories has them
  cat > "$INST" <<EOT
[package.demo]
version = "1.0.0"
repo = "old"
commit = "abc"
tag = "v1.0.0"

[package.newer]
version = "2.0.0"
repo = "old"
commit = "def"

[package.gone]
version = "1.0.0"
repo = "old"

[package.third]
version = "1.0.0"
repo = "removedadded"

[package.kept]
version = "1.0.0"
repo = "hub"
EOT
  printf '[demo]\nversion = "1.0.0"\nrepo = "old"\ntag = "v1.0.0"\ncommit = "abc"\n\n[demo.nix]\n' > "$LOCK"
}
in_entry() {   # in_entry <package> <text>: the entry of the package in installed.toml has this line
  awk -v h="[package.$1]" '$0 == h {on = 1; next} /^\[/ {on = 0} on' "$INST" | grep -qxF "$2"
}

echo "-- the index is not fetched yet: waits, nothing is written"
rows "$OUT/index.json" '["old"]'; fresh
before=$(cat "$INST")
check_out "waits names the row" "^waits${tab}demo${tab}old${tab}hub" $PKG repo migrate
check_eq "nothing was written" "$before" "$(cat "$INST")"

echo "-- fetch, plan, migrate"
check_out "fetch verifies the index" "^hub${tab}serial-1${tab}-${tab}ok" $PKG fetch hub
check_out "the plan shows the move" "^migrated${tab}demo${tab}old${tab}hub" $PKG repo migrate --dry-run
check_eq "the plan wrote nothing" "$before" "$(cat "$INST")"
out=$($PKG repo migrate)
check_match "demo migrated" "migrated${tab}demo${tab}old${tab}hub" "$out"
check_match "a newer installed one moves its repository too" "migrated${tab}newer${tab}old${tab}hub" "$out"
check_match "a package the row does not list is unmoved" "unmoved${tab}gone${tab}old${tab}-" "$out"
check "the repository of a removed added repo is not in the output" bash -c "! grep -q third <<<'$out'"
check "demo has the new repository" in_entry demo 'repo = "hub"'
check "its version is kept" in_entry demo 'version = "1.0.0"'
check "its commit is kept" in_entry demo 'commit = "abc"'
check "its tag is kept" in_entry demo 'tag = "v1.0.0"'
check "the server's newer version is not downgraded" in_entry newer 'version = "2.0.0"'
check "an unknown package stays where it was" in_entry gone 'repo = "old"'
check "a removed added repository is untouched" in_entry third 'repo = "removedadded"'
check "a package of an existing row is untouched" in_entry kept 'repo = "hub"'
check "the lock line follows" bash -c "grep -A5 '^\[demo\]' '$LOCK' | grep -qx 'repo = \"hub\"'"
check "no temporary file is left" test ! -e "$INST.new"

echo "-- idempotent"
once=$(cat "$INST"); lock1=$(cat "$LOCK")
$PKG repo migrate >/dev/null
check_eq "a second run changes nothing" "$once" "$(cat "$INST")"
check_eq "nor the lock" "$lock1" "$(cat "$LOCK")"
check_out "gone is still unmoved" "^unmoved${tab}gone" $PKG repo migrate
check "a server newer than the index is offered no update" bash -c "! $PKG updates 2>&1 | grep -q '^newer'"

echo "-- revert: the old rows come back with replaces on the other side"
printf '[[repo]]\nname = "old"\nurl = "%s"\nindex = "%s"\nreplaces = ["hub"]\n' "$R" "$OUT/index.json" > "$HS_PACKAGES_ROOT/config/package-repos.toml"
check_out "the same rule maps hub to old" "^migrated${tab}demo${tab}hub${tab}old|^waits${tab}demo${tab}hub${tab}old" $PKG repo migrate --dry-run

echo "-- a malformed entry does not crash"
rows "$OUT/index.json" '["old"]'; fresh
{ printf '[package]\nweird = "x"\n\n'; cat "$INST"; } > "$INST.t"; mv "$INST.t" "$INST"
rc=0; msg=$($PKG repo migrate 2>&1) || rc=$?
check_eq "refused with exit 1" 1 "$rc"
check_match "says why" "not a table" "$msg"
check "and prints no traceback" bash -c "! grep -q Traceback <<<'$msg'"

echo "-- the index host is down"
rows "http://127.0.0.1:9/index.json" '["old"]'; fresh
rm -rf "$HS_STATE_DIR/packages/index"
rc=0; $PKG fetch hub >/dev/null 2>&1 || rc=$?
check "the fetch fails" test "$rc" -ne 0
before=$(cat "$INST")
check_out "migrate waits and exits 0" "^waits${tab}demo${tab}old${tab}hub" $PKG repo migrate
check_eq "and writes nothing" "$before" "$(cat "$INST")"

echo "-- hs update: the fetch and the migration never fail the update"
check "update.sh guards the fetch" bash -c "grep -q 'if ! fetched=.*pkg.py\" fetch' '$SCRIPTS/update.sh'"
check "and the migration" bash -c "grep -n 'repo migrate' '$SCRIPTS/update.sh' | grep -q '||'"
finish
