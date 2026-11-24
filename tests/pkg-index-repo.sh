#!/usr/bin/env bash
# hs pkg reads the signed index (docs/PLAN-registry.md, hobnix/core#1070): signature, serial (no rollback), expiry, the tree hash of the fetched
# commit, the per-package version as the available one, yanked versions, the diff before an update. A local git repository and a throwaway key
# stand in for GitHub and the CI key; the index is a file.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
have git || { skip "needs git"; finish; exit 0; }
have ssh-keygen || { skip "needs ssh-keygen"; finish; exit 0; }
export HS_LANG=en HS_PLAIN=1 HS_STATE_DIR=$WORK/state
mkdir -p "$HS_STATE_DIR"
PKG="python3 -I $SCRIPTS/pkg.py"
IDX="python3 -I $SCRIPTS/lib/pkg_index.py"
tab=$'\t'
ssh-keygen -q -t ed25519 -N '' -f "$WORK/good" -C ci >/dev/null
ssh-keygen -q -t ed25519 -N '' -f "$WORK/evil" -C ci >/dev/null
printf 'ci@test namespaces="hobnix-index" %s\n' "$(cut -d' ' -f1,2 "$WORK/good.pub")" > "$WORK/signers"
R=$WORK/repo; mkdir -p "$R/recipes/demo"; cd "$R"
git init -q . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
OUT=$WORK/pub; mkdir -p "$OUT"
release() {   # release <version> [serial] [key]: package.toml + run.sh at that version committed, the index built from it and signed
  printf 'name = "demo"\nversion = "%s"\nkind = "recipe"\ntitle = "Demo"\nrequires_core = ">=1"\naudience = "generic"\nneeds = []\nuses = []\ninput = "none"\nscript = "run.sh"\n' "$1" > "$R/recipes/demo/package.toml"
  printf '#!/usr/bin/env bash\n# kind: generic\n# needs: -\n# uses: -\necho demo %s\n' "$1" > "$R/recipes/demo/run.sh"
  git add -A && git commit -q -m "demo $1"
  publish "${2:-1}" "${3:-$WORK/good}"
}
publish() {   # publish <serial> <key>: build the index of HEAD and sign it
  $IDX build "$R" --repo hub --out "$WORK/b" --serial "$1" --skip-assets >/dev/null
  cp "$WORK/b/index.json" "$OUT/index.json"
  $IDX sign "$OUT/index.json" --key-file "$2" >/dev/null
}
release 1.0.0 1
cd "$ROOT"

echo "-- add and fetch"
check "an index repository is added with a key" $PKG repo add hub "$R" --key "$WORK/signers" --index "$OUT/index.json"
check "an unsigned index repository is refused" bash -c "! $PKG repo add hub2 '$R' --unsigned --index '$OUT/index.json' 2>/dev/null"
check "an index address must be https or a path" bash -c "! $PKG repo add hub3 '$R' --key $WORK/signers --index ftp://x/index.json 2>/dev/null"
printf 'ci@test namespaces="git" %s
' "$(cut -d' ' -f1,2 "$WORK/good.pub")" > "$WORK/git-signers"
check_out "a key that is not trusted for indexes is refused" "hobnix-index" $PKG repo add hub4 "$R" --key "$WORK/git-signers" --index "$OUT/index.json"
check_out "--index without an address is a usage error" "needs a value" $PKG repo add hub5 "$R" --key "$WORK/signers" --index
check_out "repo list is unchanged in shape" "^hub${tab}.*${tab}signed${tab}added" $PKG repo list
check_out "fetch verifies the index" "^hub${tab}serial-1${tab}-${tab}ok" $PKG fetch hub
check_out "available takes the version of the index" "^hub${tab}demo${tab}recipe${tab}1[.]0[.]0${tab}-" $PKG available
echo "-- an index of another repository"
check "the same index under another name is added" $PKG repo add other "$R" --key "$WORK/signers" --index "$OUT/index.json"
check_out "is refused: it names another repository" "index of 'hub', not of other" $PKG fetch other
check "and nothing of it is available" bash -c "! $PKG available | grep -q '^other'"
$PKG repo remove other
echo "-- install"
check_out "install says where it came from" "demo 1[.]0[.]0 from hub" $PKG install demo
check_out "installed.toml has the commit" 'commit = "[0-9a-f]{40}"' cat "$HS_STATE_DIR/packages/installed.toml"
check "the package is in current/" test -f "$HS_STATE_DIR/packages/current/demo/package.toml"

echo "-- a crash in the swap keeps the old pair readable"
mv "$HS_STATE_DIR/packages/index/hub/live" "$HS_STATE_DIR/packages/index/hub/.old"
check_out "the old index is still read" "^hub${tab}demo${tab}recipe${tab}1[.]0[.]0" $PKG available
check_out "the next fetch repairs it" "^hub${tab}serial-1${tab}-${tab}ok" $PKG fetch hub
check "live is back" test -f "$HS_STATE_DIR/packages/index/hub/live/index.json.sig"

echo "-- signature"
cp "$OUT/index.json" "$WORK/keep.json"; cp "$OUT/index.json.sig" "$WORK/keep.json.sig"
cd "$R"; publish 2 "$WORK/evil"; cd "$ROOT"
check_out "an index signed by an untrusted key is refused" "refused" $PKG fetch hub
check_out "the kept index is still the old one" "^hub${tab}demo${tab}recipe${tab}1[.]0[.]0" $PKG available
cp "$WORK/keep.json" "$OUT/index.json"; cp "$WORK/keep.json.sig" "$OUT/index.json.sig"
sed -i 's/"serial": 1/"serial": 7/' "$OUT/index.json"
check_out "a changed byte is refused" "refused" $PKG fetch hub
cp "$WORK/keep.json" "$OUT/index.json"

echo "-- update shows the diff"
cd "$R"; release 1.1.0 2; cd "$ROOT"
cp "$OUT/index.json" "$WORK/s2.json"; cp "$OUT/index.json.sig" "$WORK/s2.json.sig"
check_out "fetch takes the higher serial" "^hub${tab}serial-2" $PKG fetch hub
check_out "updates names the new version" "^demo${tab}1[.]0[.]0${tab}1[.]1[.]0" $PKG updates
check_out "update shows the diff first" "echo demo 1[.]1[.]0" $PKG update demo --yes --accept-permissions
check_out "and installs the new version" 'version = "1.1.0"' cat "$HS_STATE_DIR/packages/installed.toml"

echo "-- serial: no rollback"
cp "$WORK/keep.json" "$OUT/index.json"; cp "$WORK/keep.json.sig" "$OUT/index.json.sig"
check_out "an older index (lower serial) is refused" "no rollback" $PKG fetch hub
check_out "the newer one is kept" "^hub${tab}demo${tab}recipe${tab}1[.]1[.]0" $PKG available

echo "-- serial floor survives a crash in the swap"
IDXD=$HS_STATE_DIR/packages/index/hub
check "the floor is a separate file" test -s "$IDXD/serial"
mv "$IDXD/live" "$IDXD/.old"
check_out "with only .old an older index is refused" "no rollback" $PKG fetch hub
check "and .old is still there" test -f "$IDXD/.old/index.json"
rm -rf "$IDXD/.old"
check_out "with live and .old both gone the floor refuses it" "no rollback" $PKG fetch hub
cp "$WORK/s2.json" "$OUT/index.json"; cp "$WORK/s2.json.sig" "$OUT/index.json.sig"
check_out "the same index as the floor is accepted again" "^hub${tab}serial-2" $PKG fetch hub
check "live is back" test -f "$IDXD/live/index.json"
check "the lock file is kept" test -e "$IDXD/.lock"

echo "-- tree hash"
cd "$R"; release 1.2.0 3; cd "$ROOT"
python3 - "$OUT/index.json" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
d["packages"]["demo"]["tree"] = "sha256:" + "0" * 64
json.dump(d, open(sys.argv[1], "w"), indent=1, sort_keys=True)
EOF
$IDX sign "$OUT/index.json" --key-file "$WORK/good" >/dev/null
check_out "fetch accepts it (the signature is right)" "^hub${tab}serial-3" $PKG fetch hub
check_out "a tree that does not match is refused before install" "tree hash" $PKG install demo
check_out "nothing was installed over the old copy" 'version = "1.1.0"' cat "$HS_STATE_DIR/packages/installed.toml"
check "no half-copy is left" test ! -e "$HS_STATE_DIR/packages/current/.new-demo"
check_out "update refuses the same way" "tree hash" $PKG update demo --yes --accept-permissions

echo "-- yanked"
cd "$R"; printf '[[yanked]]\nname = "demo"\nversion = "1.2.0"\nreason = "broken"\n' > yanked.toml
git add -A && git commit -q -m yank; publish 4 "$WORK/good"; cd "$ROOT"
check_out "fetch ok" "^hub${tab}serial-4" $PKG fetch hub
check "a yanked version is not offered" bash -c "! $PKG available | grep -q demo"
check "and gives no update" bash -c "! $PKG updates | grep -q demo"
check_out "install refuses it with the reason" "withdrawn.*broken" $PKG install demo
check_out "update refuses it with the reason" "withdrawn.*broken" $PKG update demo --yes --accept-permissions

echo "-- the plan is bound to the commit and tree"
mkshots() {   # mkshots <text>: a second package whose run.sh says <text> (same version), committed, indexed and signed
  mkdir -p "$R/recipes/shots"
  printf 'name = "shots"
version = "1.0.0"
kind = "recipe"
title = "Shots"
requires_core = ">=1"
audience = "generic"
needs = []
uses = []
input = "none"
script = "run.sh"
screenshots = ["../../../x.png"]
' > "$R/recipes/shots/package.toml"
  printf '#!/usr/bin/env bash
# kind: generic
# needs: -
# uses: -
echo %s
' "$1" > "$R/recipes/shots/run.sh"
  git -C "$R" add -A && git -C "$R" commit -q -m "shots $1"
  (cd "$R" && publish "$2" "$WORK/good")
}
mkshots one 5; $PKG fetch hub >/dev/null
T1=$($PKG show shots | awk -F'	' '$1=="tag"{print $2}')
check_out "the tag of the plan names commit and tree" '^v1[.]0[.]0-[0-9a-f]{16}$' echo "$T1"
mkshots two 6; $PKG fetch hub >/dev/null
check_out "the same version with other files is another tag" "plan was made" $PKG install shots --tag "$T1"
T2=$($PKG show shots | awk -F'	' '$1=="tag"{print $2}')
check "so the tag differs" test "$T1" != "$T2"
check_out "the new tag installs" "shots 1[.]0[.]0 from hub" $PKG install shots --tag "$T2"

echo "-- asset paths stay inside the package"
check_out "a screenshot path with .. is refused" "outside the package" $PKG asset shots ../../../x.png

echo "-- fetch clones; reads stay local and are cached"
S1=$HS_STATE_DIR; export HS_STATE_DIR=$WORK/state2; mkdir -p "$HS_STATE_DIR"
$PKG repo add hub "$R" --key "$WORK/signers" --index "$OUT/index.json" >/dev/null
check "a read before the first fetch does not clone" bash -c "$PKG show shots >/dev/null 2>&1; test ! -e '$HS_STATE_DIR/packages/repos/hub'"
check_out "fetch" "^hub${tab}serial-6${tab}-${tab}ok" $PKG fetch hub
check "fetch cloned the repository" test -d "$HS_STATE_DIR/packages/repos/hub"
mv "$R" "$R.gone"
check_out "show reads without touching the source" "^tag${tab}v1[.]0[.]0-" $PKG show shots
check "the checked folder is cached by commit" bash -c "ls '$HS_STATE_DIR'/packages/index-cache/hub/*/tree >/dev/null"
mv "$HS_STATE_DIR/packages/repos/hub" "$HS_STATE_DIR/packages/repos/hub.gone"
check_out "a second read comes from the cache (no clone needed)" "^tag${tab}v1[.]0[.]0-" $PKG show shots
rm -rf "$HS_STATE_DIR/packages/index-cache"
check_out "an uncached commit is not cloned by a read" "hs pkg fetch" $PKG show shots
check "and still no clone" test ! -e "$HS_STATE_DIR/packages/repos/hub"
mv "$HS_STATE_DIR/packages/repos/hub.gone" "$HS_STATE_DIR/packages/repos/hub"; mv "$R.gone" "$R"
export HS_STATE_DIR=$S1

echo "-- a missing key file is a refusal, not a traceback"
check_out "repo add with a missing key" "does not exist" $PKG repo add nokey "$R" --key /missing/signers --index "$OUT/index.json"
check "no traceback" bash -c "! $PKG repo add nokey '$R' --key /missing/signers --index '$OUT/index.json' 2>&1 | grep -q Traceback"
check "and nothing was added" bash -c "! $PKG repo list | grep -q '^nokey'"

echo "-- a repository without index keeps the tag path"
check "list still works" $PKG list
finish
