#!/usr/bin/env bash
# The signed package index (docs/PLAN-registry.md, hobnix/core#1069): tree hash, build from package.toml and assets/, schema, signature with a
# throwaway key, serial rule. No secret and no network: the key is made here.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
have ssh-keygen || { skip "needs ssh-keygen"; finish; exit 0; }
IDX="python3 -I $SCRIPTS/lib/pkg_index.py"
R=$WORK/repo; mkdir -p "$R/recipes/demo/assets/screenshots" "$R/extensions/ext"
printf 'name = "demo"\nversion = "1.2.0"\nkind = "recipe"\ntitle = "Demo"\nrequires_core = ">=1"\nneeds = ["docker"]\nrenamed_from = ["old-demo"]\n[meta]\nauthor = "A"\nlicense = "MIT"\ntags = ["media"]\n' > "$R/recipes/demo/package.toml"
printf 'name = "ext"\nversion = "0.1.0"\nkind = "extension"\ntitle = "Ext"\nrequires_core = ">=1"\n' > "$R/extensions/ext/package.toml"
printf '#!/bin/sh\n' > "$R/recipes/demo/run.sh"
C=0123456789abcdef0123456789abcdef01234567

echo "-- tree hash"
T1=$($IDX tree "$R/recipes/demo")
check_out "tree hash looks like sha256:<64 hex>" '^sha256:[0-9a-f]{64}$' echo "$T1"
check_eq "same folder, same hash" "$T1" "$($IDX tree "$R/recipes/demo")"
echo changed >> "$R/recipes/demo/run.sh"
check "a changed file changes the hash" test "$T1" != "$($IDX tree "$R/recipes/demo")"
printf '#!/bin/sh\n' > "$R/recipes/demo/run.sh"
check_eq "restoring the file restores the hash" "$T1" "$($IDX tree "$R/recipes/demo")"

echo "-- build"
O=$WORK/out
check "build without assets" $IDX build "$R" --repo official --out "$O" --serial 5 --commit $C --now 2026-11-22T04:00:00Z --skip-assets
J=$O/index.json
check_out "serial and expiry (14 days)" '"expires": "2026-12-06T04:00:00Z"' cat "$J"
check_out "the tree hash is in the entry" "\"tree\": \"$T1\"" cat "$J"
check_out "needs and rename carried" '"renamed_from"' cat "$J"
check "the index validates" $IDX validate "$J"
check_out "an expired index only warns" 'expired' $IDX validate "$J" --now 2027-01-01T00:00:00Z
check "build takes serial from --prev" $IDX build "$R" --repo official --out "$WORK/out2" --prev "$J" --commit $C --skip-assets
check_out "prev + 1" '"serial": 6' cat "$WORK/out2/index.json"

echo "-- binaries (informational)"
SHA=$(printf 'x' | sha256sum | cut -d' ' -f1)
mkdir -p "$R/extensions/ext/bin"; printf 'x' > "$R/extensions/ext/bin/prog"
printf '[[binary]]
path = "bin/prog"
sha256 = "%s"
bin = "prog"
target = "x86_64-unknown-linux-musl"
' "$SHA" >> "$R/extensions/ext/package.toml"
$IDX build "$R" --repo official --out "$WORK/outb" --serial 6 --commit $C --skip-assets >/dev/null
BJ=$WORK/outb/index.json
check "an index with binaries validates" $IDX validate "$BJ"
check_eq "a package with [[binary]] gets the field" "prog x86_64-unknown-linux-musl $SHA 1" "$(python3 -c "import json; b=json.load(open('$BJ'))['packages']['ext']['binaries'][0]; print(b['bin'],b['target'],b['sha256'],b['size'])")"
check_eq "a package without [[binary]] has no field" "no" "$(python3 -c "import json; print('yes' if 'binaries' in json.load(open('$BJ'))['packages']['demo'] else 'no')")"
check "an index without the field is valid (older indexes)" $IDX validate "$J"
python3 -c "import json; d=json.load(open('$BJ')); d['packages']['ext']['binaries'][0]['sha256']='XYZ'; json.dump(d,open('$WORK/badb.json','w'))"
if $IDX validate "$WORK/badb.json" >/dev/null 2>&1; then fail "a binaries row with a bad sha256 is refused"; else pass "a binaries row with a bad sha256 is refused"; fi
check_eq "a client (non-strict validate) ignores a malformed field" "" "$(python3 -I -c "
import importlib.util as u
s=u.spec_from_file_location('pi','$SCRIPTS/lib/pkg_index.py'); m=u.module_from_spec(s); s.loader.exec_module(m)
import json; print('; '.join(m.validate(json.load(open('$WORK/badb.json')))))")"
check "install and update never read the field" test "$(grep -c "binaries" "$SCRIPTS/pkg_repo.py")" = 0
rm -rf "$R/extensions/ext/bin"
printf 'name = "ext"
version = "0.1.0"
kind = "extension"
title = "Ext"
requires_core = ">=1"
' > "$R/extensions/ext/package.toml"

echo "-- yanked"
printf '[[yanked]]\nname = "demo"\nversion = "1.2.0"\nreason = "broken"\n' > "$R/yanked.toml"
$IDX build "$R" --repo official --out "$WORK/out3" --serial 6 --commit $C --skip-assets >/dev/null
check_out "a yanked version is marked" '"yanked_reason": "broken"' cat "$WORK/out3/index.json"
rm "$R/yanked.toml"

echo "-- schema"
bad() {   # bad "what" python-expression-on-d: the edited index must fail validation
  python3 -c "import json,sys; d=json.load(open('$J')); $2; json.dump(d,open('$WORK/bad.json','w'))"
  if $IDX validate "$WORK/bad.json" >/dev/null 2>&1; then fail "$1 is refused"; else pass "$1 is refused"; fi
}
bad "an unknown format" 'd["format"]=2'
bad "a negative serial" 'd["serial"]=-1'
bad "a short commit" 'd["packages"]["demo"]["commit"]="abc"'
bad "a tree without sha256:" 'd["packages"]["demo"]["tree"]="abc"'
bad "a path with .." 'd["packages"]["demo"]["path"]="../x"'
bad "an asset outside assets/" 'd["packages"]["demo"]["meta"]["icon"]="http://x/y.webp"'
bad "expires before generated" 'd["expires"]=d["generated"]'
bad "the reserved repo name core" 'd["repo"]="core"'
python3 -c "import json; d=json.load(open('$J')); d['future']=1; d['packages']['demo']['x']=2; json.dump(d,open('$WORK/ok.json','w'))"
check "unknown fields are ignored" $IDX validate "$WORK/ok.json"

echo "-- signature"
ssh-keygen -q -t ed25519 -N '' -f "$WORK/good" -C ci >/dev/null
ssh-keygen -q -t ed25519 -N '' -f "$WORK/evil" -C ci >/dev/null
printf 'ci@test namespaces="hobnix-index" %s\n' "$(cut -d' ' -f1,2 "$WORK/good.pub")" > "$WORK/signers"
check "sign with the key file" $IDX sign "$J" --key-file "$WORK/good"
check_out "verify names signer and serial" 'signer.*ci@test' $IDX verify "$J" --signers "$WORK/signers"
cp "$J" "$WORK/tampered.json"; cp "$J.sig" "$WORK/tampered.json.sig"
sed -i 's/"serial": 5/"serial": 9/' "$WORK/tampered.json"
check_out "a changed byte is refused" 'does not match' $IDX verify "$WORK/tampered.json" --signers "$WORK/signers"
$IDX sign "$WORK/out2/index.json" --key-file "$WORK/evil" >/dev/null
check_out "a signer that is not trusted is refused" 'not in the trusted keys' $IDX verify "$WORK/out2/index.json" --signers "$WORK/signers"
printf 'ci@test namespaces="git" %s\n' "$(cut -d' ' -f1,2 "$WORK/good.pub")" > "$WORK/git-signers"
check_out "a key trusted for git tags only is refused" 'not in the trusted keys|does not match' $IDX verify "$J" --signers "$WORK/git-signers"
check_out "no signature file is refused" 'no signature' $IDX verify "$WORK/out3/index.json" --signers "$WORK/signers"

echo "-- serial: no rollback"
$IDX sign "$WORK/out2/index.json" --key-file "$WORK/good" >/dev/null
check "a higher serial than --prev is taken" $IDX verify "$WORK/out2/index.json" --signers "$WORK/signers" --prev "$J"
check_out "a lower serial than --prev is refused" 'below the one already seen' $IDX verify "$J" --signers "$WORK/signers" --prev "$WORK/out2/index.json"

echo "-- assets"
if python3 -c "import PIL" 2>/dev/null; then
  python3 -c "
from PIL import Image
Image.new('RGB',(900,900),(200,30,30)).save('$R/recipes/demo/assets/icon.png')
Image.new('RGB',(3000,1500),(30,30,200)).save('$R/recipes/demo/assets/screenshots/1.png')"
  $IDX build "$R" --repo official --out "$WORK/out4" --serial 1 --commit $C >/dev/null
  check_out "icon is named by hash" '"icon": "assets/[0-9a-f]{16}\.webp"' cat "$WORK/out4/index.json"
  check "the assets validate" $IDX validate "$WORK/out4/index.json"
  check_out "the icon is resized to 256" '256' python3 -c "
import json,glob
from PIL import Image
d=json.load(open('$WORK/out4/index.json'))
print(Image.open('$WORK/out4/'+d['packages']['demo']['meta']['icon']).size[0])"
  $IDX build "$R" --repo official --out "$WORK/out5" --serial 1 --commit $C >/dev/null
  check_eq "same input, same asset names" "$(grep -o 'assets/[0-9a-f]*' "$WORK/out4/index.json" | sort)" "$(grep -o 'assets/[0-9a-f]*' "$WORK/out5/index.json" | sort)"
else
  skip "needs Pillow for the asset resizing"
fi

echo "-- the CI workflow stub"
W=$ROOT/.github/workflows/package-index.yml
check "the workflow exists" test -f "$W"
check "the secret is named in one place only" test "$(grep -c "secrets\." "$W")" = 1
check "only the sign job uses the signing environment" test "$(grep -c "environment: index-signing" "$W")" = 1
finish
