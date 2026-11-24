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
version = "%s"
kind = "recipe"
title = "Shots"
requires_core = ">=1"
audience = "generic"
needs = []
uses = []
input = "none"
script = "run.sh"
screenshots = ["../../../x.png"]
' "${3:-1.0.0}" > "$R/recipes/shots/package.toml"
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

echo "-- a pinned commit that no branch reaches any more is fetched by hs pkg fetch"
git -C "$R" config uploadpack.allowAnySHA1InWant true
PINNED=$(git -C "$R" rev-parse HEAD)
git -C "$R" reset -q --hard HEAD~1
export HS_STATE_DIR=$WORK/state3; mkdir -p "$HS_STATE_DIR"
$PKG repo add hub "$R" --key "$WORK/signers" --index "$OUT/index.json" >/dev/null
check_out "fetch ok although the history was rewritten" "^hub${tab}serial-6${tab}-${tab}ok" $PKG fetch hub
check "the pinned commit is in the clone" git -C "$HS_STATE_DIR/packages/repos/hub" cat-file -e "$PINNED^{commit}"
check_out "show works from the local clone" "^tag${tab}v1[.]0[.]0-" $PKG show shots

echo "-- the index is accepted but the git address fails: a parseable row, exit 1"
mv "$R" "$R.gone"; rm -rf "$HS_STATE_DIR/packages/repos/hub" "$HS_STATE_DIR/packages/index-cache"
$PKG fetch hub > "$WORK/row.out" 2>/dev/null; rc=$?
check "fetch exits 1" test "$rc" = 1
check "the row has four tab fields with - for release and commit" awk -F'\t' 'NF==4 && $1=="hub" && $2=="-" && $3=="-" && $4!="ok" && $4!="" {f=1} END{exit !f}' "$WORK/row.out"
check_out "the accepted index is still listed" "^hub${tab}" $PKG available
check "updates still runs" $PKG updates
mv "$R.gone" "$R"; git -C "$R" reset -q --hard "$PINNED"

echo "-- the fetch lock covers the git part too"
LK=$HS_STATE_DIR/packages/index/hub/.lock
python3 - "$LK" "$WORK/release" <<'PYEOF' &
import fcntl, os, sys, time
f = open(sys.argv[1], "w"); fcntl.flock(f, fcntl.LOCK_EX)
open(sys.argv[2] + ".held", "w").close()
for _ in range(100):
    if os.path.exists(sys.argv[2]): break
    time.sleep(0.1)
PYEOF
HOLDER=$!
for _ in $(seq 50); do [ -e "$WORK/release.held" ] && break; sleep 0.1; done
$PKG fetch hub > "$WORK/lock.out" 2>&1 &
FETCH=$!
sleep 1
check "a second fetch waits for the lock" kill -0 $FETCH
touch "$WORK/release"; wait $HOLDER; wait $FETCH; rc=$?
check "and then runs through" test "$rc" = 0
check_out "with its normal row" "^hub${tab}serial-6${tab}[0-9a-f-]*${tab}ok|^hub${tab}serial-6${tab}-${tab}ok" cat "$WORK/lock.out"

echo "-- the cache: no race between reads, prune keeps what is in use"
python3 -I - "$SCRIPTS" <<'PYEOF'
import importlib.util, os, sys, tempfile, time
S = sys.argv[1]
def load(n, f):
    sp = importlib.util.spec_from_file_location(n, os.path.join(S, f)); m = importlib.util.module_from_spec(sp); sys.modules[n] = m; sp.loader.exec_module(m); return m
pkg = load("pkg", "pkg.py"); R = load("pkg_repo", "pkg_repo.py").Repos(pkg)
e = {"commit": "a" * 40, "path": "recipes/x", "tree": "sha256:" + "1" * 64}
cached = R.cache_path("racehub", e)
os.makedirs(os.path.join(cached, "pkg")); open(os.path.join(cached, "pkg", "mine"), "w").close()
open(os.path.join(cached, "tree"), "w").write(e["tree"] + "\n")
tmp = tempfile.mkdtemp(dir=os.path.dirname(cached)); os.makedirs(os.path.join(tmp, "pkg")); open(os.path.join(tmp, "pkg", "other"), "w").close()
R.cache_store(cached, tmp, e)            # the miss that lost the race
assert os.path.exists(os.path.join(cached, "pkg", "mine")), "the folder of the first read was replaced"
d = os.path.dirname(cached)
old = os.path.join(d, "b" * 40 + "-old"); os.makedirs(old); t = time.time() - 7200; os.utime(old, (t, t))
fresh = os.path.join(d, "c" * 40 + "-new"); os.makedirs(fresh)
R.prune_cache("racehub", {"packages": {}})
assert not os.path.exists(old), "an old unused folder stays"
assert os.path.exists(fresh), "a folder created a moment ago was pruned"
assert os.path.exists(cached), "a folder just used was pruned"
PYEOF
check "cache_store keeps the first folder, prune keeps recent ones" test $? = 0
rm -rf "$HS_STATE_DIR/packages/index-cache/racehub"

echo "-- a damaged floor file fails closed"
IDXD=$HS_STATE_DIR/packages/index/hub
printf 'garbage' > "$IDXD/serial"
rm -rf "$IDXD/live" "$IDXD/.old"
check_out "refused with the way out" "damaged.*rm " $PKG fetch hub
check "nothing was written" test ! -e "$IDXD/live"
rm -f "$IDXD/serial"
check_out "a missing floor with no copy is the first fetch" "^hub${tab}serial-6.*ok" $PKG fetch hub
printf 'garbage' > "$IDXD/serial"
check_out "a damaged floor with a kept index is repaired" "^hub${tab}serial-6.*ok" $PKG fetch hub
check "the floor is rewritten" grep -qE '^6 [0-9a-f]{64}$' "$IDXD/serial"
rm -f "$IDXD/serial"; mkdir "$IDXD/serial"
check_out "a floor that cannot be written is a clean refusal" "serial floor cannot be written" $PKG fetch hub
check "without a traceback" bash -c "! $PKG fetch hub 2>&1 | grep -q Traceback"
rmdir "$IDXD/serial"
export HS_STATE_DIR=$S1

echo "-- a stalled git remote does not hold the lock"
STUB=$WORK/stub; mkdir -p "$STUB"; REALGIT=$(command -v git)
cat > "$STUB/git" <<'STUBEOF'
#!/bin/sh
case "$1" in fetch|clone)
  [ -n "$STUB_HANG" ] && exec sleep 30
  case "$*" in "fetch --quiet origin "[0-9a-f]*) [ -n "$STUB_HANGID" ] && exec sleep 30;; esac
  echo "$*" >> "${STUB_LOG:-/dev/null}"; echo "$GIT_HTTP_LOW_SPEED_LIMIT|$GIT_HTTP_LOW_SPEED_TIME|$GIT_SSH_COMMAND" >> "${STUB_ENVLOG:-/dev/null}";;
esac
exec REALGIT_PATH "$@"
STUBEOF
sed -i "s#REALGIT_PATH#$REALGIT#" "$STUB/git"; chmod +x "$STUB/git"
export HS_STATE_DIR=$WORK/state4; mkdir -p "$HS_STATE_DIR"
$PKG repo add hub "$R" --key "$WORK/signers" --index "$OUT/index.json" >/dev/null
check_out "a hanging git is stopped and named" "^hub${tab}-${tab}-${tab}.*timed out" env PATH="$STUB:$PATH" STUB_HANG=1 HS_PKG_GIT_TIMEOUT=2 timeout 60 $PKG fetch hub
check_out "the next fetch is not blocked" "^hub${tab}serial-6${tab}-${tab}ok" timeout 60 $PKG fetch hub
python3 - "$HS_STATE_DIR/packages/index/hub/.lock" "$WORK/release2" <<'PYEOF' &
import fcntl, os, sys, time
f = open(sys.argv[1], "w"); fcntl.flock(f, fcntl.LOCK_EX)
open(sys.argv[2] + ".held", "w").close()
for _ in range(100):
    if os.path.exists(sys.argv[2]): break
    time.sleep(0.1)
PYEOF
HOLDER=$!
for _ in $(seq 50); do [ -e "$WORK/release2.held" ] && break; sleep 0.1; done
check_out "waiting for the lock is bounded and says why" "another pkg fetch is running" env HS_PKG_LOCK_WAIT=1 timeout 30 $PKG fetch hub
touch "$WORK/release2"; wait $HOLDER

echo "-- the plan of an update never runs git fetch"
export HS_STATE_DIR=$WORK/state6; mkdir -p "$HS_STATE_DIR"
$PKG repo add hub "$R" --key "$WORK/signers" --index "$OUT/index.json" >/dev/null
$PKG fetch hub >/dev/null; $PKG install shots >/dev/null
mkshots three 7 1.1.0; $PKG fetch hub >/dev/null
rm -rf "$HS_STATE_DIR/packages/repos/hub" "$HS_STATE_DIR/packages/index-cache"
check_out "a missing commit says hs pkg fetch (no hang, no fetch)" "hs pkg fetch" env PATH="$STUB:$PATH" STUB_HANG=1 timeout 30 $PKG update shots
check "and no clone was made" test ! -e "$HS_STATE_DIR/packages/repos/hub"
$PKG fetch hub >/dev/null
check_out "after hs pkg fetch the update shows its diff" "echo three" $PKG update shots --yes --accept-permissions

echo "-- one commit that cannot be fetched does not fail the others"
python3 - "$OUT/index.json" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
d["packages"]["demo"]["commit"] = "d" * 40
json.dump(d, open(sys.argv[1], "w"), indent=1, sort_keys=True)
PYEOF
$IDX sign "$OUT/index.json" --key-file "$WORK/good" >/dev/null
export HS_STATE_DIR=$WORK/state7; mkdir -p "$HS_STATE_DIR"
$PKG repo add hub "$R" --key "$WORK/signers" --index "$OUT/index.json" >/dev/null
: > "$WORK/fetch.log"
env PATH="$STUB:$PATH" STUB_LOG="$WORK/fetch.log" $PKG fetch hub > "$WORK/f.out" 2> "$WORK/f.err"; rc=$?
check "fetch succeeds (exit 0)" test "$rc" = 0
check_out "with the normal row" "^hub${tab}serial-7${tab}-${tab}ok" cat "$WORK/f.out"
check_out "the unfetchable package is named on stderr" "demo is not available" cat "$WORK/f.err"
check "the clone was fetched once (plus one fetch by id)" test "$(grep -c -- '--tags' "$WORK/fetch.log")" = 1
check_out "the other package is available" "^hub${tab}shots" $PKG available
check "the unfetchable one is not" bash -c "! $PKG available | grep -q '${tab}demo${tab}'"
check_out "show gives the reason" "demo is not available.*cannot be fetched" $PKG show demo
check "the clone is fetched without a terminal prompt and with a low-speed limit" bash -c "env PATH='$STUB:$PATH' STUB_ENVLOG='$WORK/env.log' $PKG fetch hub >/dev/null 2>&1; grep -q '^1000|60|ssh .*ConnectTimeout' '$WORK/env.log'"
check "a git ssh command of the person is left alone" bash -c "env PATH='$STUB:$PATH' STUB_ENVLOG='$WORK/env2.log' GIT_SSH_COMMAND=mine $PKG fetch hub >/dev/null 2>&1; grep -q '|mine\$' '$WORK/env2.log'"

echo "-- an installed package whose new commit cannot be fetched is still known"
git -C "$R" rev-parse HEAD > "$WORK/head.sha"
python3 - "$OUT/index.json" "$(cat "$WORK/head.sha")" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1])); d["packages"]["demo"]["commit"] = sys.argv[2]; json.dump(d, open(sys.argv[1], "w"), indent=1, sort_keys=True)
PYEOF
$IDX sign "$OUT/index.json" --key-file "$WORK/good" >/dev/null
export HS_STATE_DIR=$WORK/state9; mkdir -p "$HS_STATE_DIR"
$PKG repo add hub "$R" --key "$WORK/signers" --index "$OUT/index.json" >/dev/null
$PKG fetch hub >/dev/null; $PKG install shots >/dev/null
python3 - "$OUT/index.json" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1])); d["serial"] += 1
d["packages"]["shots"]["commit"] = "e" * 40; d["packages"]["shots"]["version"] = "1.2.0"
json.dump(d, open(sys.argv[1], "w"), indent=1, sort_keys=True)
PYEOF
$IDX sign "$OUT/index.json" --key-file "$WORK/good" >/dev/null
check_out "fetch is still ok (exit 0 row)" "^hub${tab}serial-8${tab}-${tab}ok" $PKG fetch hub
check_out "market shows the installed copy as current with the note" "^shots${tab}recipe${tab}hub${tab}1[.]2[.]0${tab}1[.]1[.]0${tab}current${tab}no${tab}generic${tab}.*update not available.*could not be fetched" $PKG market
check "and not as an orphan" bash -c "! $PKG market | grep -q 'orphan'"
check "every market row has nine fields" bash -c "$PKG market | awk -F'\t' 'NF!=9{bad=1} END{exit bad}'"
check_out "update gives the reason" "could not be fetched" $PKG update shots --yes
check "available does not offer it" bash -c "! $PKG available | grep -q shots"
rm -rf "$HS_STATE_DIR/packages/current/shots"
$PKG install --core > "$WORK/core.out" 2> "$WORK/core.err"; rc=$?
check "install --core fails when a package cannot be had" test "$rc" != 0
check_out "and names it" "shots: .*could not be fetched" cat "$WORK/core.err"

echo "-- fetches of commits by id share one time budget"
python3 - "$OUT/index.json" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1])); d["serial"] += 1
d["packages"]["demo"]["commit"] = "a" * 40; d["packages"]["shots"]["commit"] = "b" * 40
json.dump(d, open(sys.argv[1], "w"), indent=1, sort_keys=True)
PYEOF
$IDX sign "$OUT/index.json" --key-file "$WORK/good" >/dev/null
SECONDS=0
env PATH="$STUB:$PATH" STUB_HANGID=1 HS_PKG_GIT_TIMEOUT=3 timeout 60 $PKG fetch hub > /dev/null 2> "$WORK/b.err"
check "two hanging fetches by id end within one budget" test "$SECONDS" -lt 6
check_out "both packages are recorded" "demo is not available.*shots is not available|shots is not available.*demo is not available" tr '\n' ' ' < "$WORK/b.err"
check_out "the one that got no time says it is tried again" "tries again" cat "$WORK/b.err"

export HS_STATE_DIR=$S1

echo "-- a missing key file is a refusal, not a traceback"
check_out "repo add with a missing key" "does not exist" $PKG repo add nokey "$R" --key /missing/signers --index "$OUT/index.json"
check "no traceback" bash -c "! $PKG repo add nokey '$R' --key /missing/signers --index '$OUT/index.json' 2>&1 | grep -q Traceback"
check "and nothing was added" bash -c "! $PKG repo list | grep -q '^nokey'"

echo "-- a repository without index keeps the tag path"
check "list still works" $PKG list
finish
