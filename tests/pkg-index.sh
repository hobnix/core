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
# verified (#477): optional; a day when it is there
bad "a verified value that is not a day" 'd["packages"]["demo"]["verified"]="soon"'
python3 -c "import json; d=json.load(open('$J')); d['packages']['demo']['verified']='2026-01-02'; json.dump(d,open('$WORK/okv.json','w'))"
check "a verified day is valid" $IDX validate "$WORK/okv.json"

echo "-- version history (from the first-parent git history only)"
if have git; then
H=$WORK/hist; git init -q "$H"
HG() { git -C "$H" -c user.name=t -c user.email=t@t.invalid -c commit.gpgsign=false "$@"; }
hv() {   # hv <dir> <version> <date> <message>: write the manifest, commit with a fixed date
  mkdir -p "$H/$1"; printf 'name = "demo"\nversion = "%s"\nkind = "recipe"\ntitle = "Demo"\nrequires_core = ">=1"\n[meta]\nchanges = "notes %s"\n' "$2" "$2" > "$H/$1/package.toml"
  printf 'v%s %s\n' "$2" "$4" > "$H/$1/run.sh"
  HG add -A >/dev/null; GIT_AUTHOR_DATE="$3" GIT_COMMITTER_DATE="$3" HG commit -q -m "$4"
}
hv recipes/old-demo 0.9.0 2026-01-01T00:00:00Z old
HG mv recipes/old-demo recipes/demo
printf 'name = "demo"\nversion = "1.0.0"\nkind = "recipe"\ntitle = "Demo"\nrequires_core = ">=1"\n' > "$H/recipes/demo/package.toml"
HG add -A; GIT_COMMITTER_DATE=2026-02-01T00:00:00Z HG commit -q -m rename
hv recipes/demo 1.0.0 2026-02-15T00:00:00Z same-version; C100=$(HG rev-parse HEAD)
hv recipes/demo 1.1.0 2026-03-01T00:00:00Z minor; C110=$(HG rev-parse HEAD)
printf 'this is [not toml\n' > "$H/recipes/demo/package.toml"; HG add -A; GIT_COMMITTER_DATE=2026-03-10T00:00:00Z HG commit -q -m broken
hv recipes/demo 1.0.5 2026-04-01T00:00:00Z not-monotonic; C105=$(HG rev-parse HEAD)
ln -s run.sh "$H/recipes/demo/link"
hv recipes/demo 1.0.9 2026-05-01T00:00:00Z with-link
HG checkout -q -b side; hv recipes/demo 1.1.7 2026-05-05T00:00:00Z side-branch
HG checkout -q -; rm "$H/recipes/demo/link"; hv recipes/demo 1.2.0 2026-05-10T00:00:00Z patch; C120=$(HG rev-parse HEAD)
GIT_COMMITTER_DATE=2026-06-01T00:00:00Z HG merge -q --no-ff -s ours side -m merge >/dev/null
hv recipes/demo 1.3.0 2026-06-15T00:00:00Z current; TIP=$(HG rev-parse HEAD)
printf '[[yanked]]\nname = "demo"\nversion = "1.1.0"\nreason = "broken"\n' > "$H/yanked.toml"
HJ=$WORK/hist-out
check "build from a repository with history" $IDX build "$H" --repo official --out "$HJ" --serial 1 --skip-assets
check "the index with history validates (strict)" $IDX validate "$HJ/index.json"
hq() { python3 -c "import json; e=json.load(open('$HJ/index.json'))['packages']['demo']; print($1)"; }
hr() { hq "[r['$2'] for r in e['versions'] if r['version']=='$1'][0]"; }   # hr <version> <field>
check_eq "date is the first commit that had the current version" "2026-06-15T00:00:00Z" "$(hq "e['date']")"
check_eq "older versions newest first; a link, a side branch, a broken manifest and the old path are left out" "1.2.0 1.1.0 1.0.5 1.0.0" "$(hq "' '.join(r['version'] for r in e['versions'])")"
check_eq "1.0.0: the newest commit that had it" "$C100" "$(hr 1.0.0 commit)"
check_eq "1.1.0: the commit before the broken manifest" "$C110" "$(hr 1.1.0 commit)"
check_eq "1.0.5 (not monotonic) is found" "$C105" "$(hr 1.0.5 commit)"
check_eq "1.2.0 is found" "$C120" "$(hr 1.2.0 commit)"
check_eq "date is the first commit that had the version" "2026-02-01T00:00:00Z" "$(hr 1.0.0 date)"
rm -rf "$WORK/arch1"; mkdir "$WORK/arch1"; git -C "$H" archive "$C110:recipes/demo" | tar -x -C "$WORK/arch1"
check_eq "the row tree is the tree hash of that commit's folder" "$($IDX tree "$WORK/arch1")" "$(hr 1.1.0 tree)"
check_eq "yanked comes from the current yanked.toml" "True broken" "$(hr 1.1.0 yanked) $(hr 1.1.0 yanked_reason)"
check_eq "a version that is not yanked is marked so" "False" "$(hr 1.2.0 yanked)"
check_eq "changes are carried" "notes 1.2.0" "$(hr 1.2.0 changes)"
# a previous index (downloaded without a signature check) is never a source of history
python3 -c "
import json; d=json.load(open('$HJ/index.json')); d['packages']['demo']['versions']=[{'version':'0.0.1','date':'2020-01-01T00:00:00Z','path':'recipes/demo','commit':'$TIP','tree':'sha256:'+'0'*64,'requires_core':'>=1','yanked':False}]
json.dump(d,open('$WORK/hist-prev.json','w'))"
$IDX build "$H" --repo official --out "$WORK/hist-out2" --prev "$WORK/hist-prev.json" --skip-assets >/dev/null
check_eq "--prev does not feed the history" "$(hq "e['versions']")" "$(python3 -c "import json; print(json.load(open('$WORK/hist-out2/index.json'))['packages']['demo']['versions'])")"
check_eq "a build is deterministic" "$(sed '/generated\|expires/d' "$HJ/index.json")" "$($IDX build "$H" --repo official --out "$WORK/hist-out3" --serial 1 --skip-assets >/dev/null; sed '/generated\|expires/d' "$WORK/hist-out3/index.json")"
$IDX build "$H" --repo official --out "$WORK/hist-out4" --commit $C --skip-assets >/dev/null
check_eq "a commit that is not in the repository gives no history" "no" "$(python3 -c "import json; e=json.load(open('$WORK/hist-out4/index.json'))['packages']['demo']; print('yes' if 'versions' in e or 'date' in e else 'no')")"
PYI="import importlib.util as u, os, json; s=u.spec_from_file_location('pi','$SCRIPTS/lib/pkg_index.py'); m=u.module_from_spec(s); s.loader.exec_module(m)"
check_eq "the walk is bounded by a number of commits" "1.2.0 1.0.5" "$(python3 -I -c "$PYI
m.HISTORY_COMMITS=4
d,rows=m.history_of(os.path.join('$H','.git'),'$TIP','recipes/demo','demo','1.3.0',{})
print(' '.join(r['version'] for r in rows))")"
check_eq "at most 10 older versions in a built entry" "10" "$(python3 -I -c "$PYI
e={'version':'9.0.0','path':'p','versions':[{'version':'1.%d.0'%i,'date':'2026-01-01T00:00:00Z','path':'p','commit':'a'*40,'tree':'sha256:'+'0'*64,'requires_core':'>=1','yanked':False} for i in range(1,15)]}
print(len(m.clean_history(e)['versions']))")"
hbad() {   # hbad "what" python-on-e: the strict validator refuses the edited entry
  python3 -c "import json; d=json.load(open('$HJ/index.json')); e=d['packages']['demo']; $2; json.dump(d,open('$WORK/hbad.json','w'))"
  if $IDX validate "$WORK/hbad.json" >/dev/null 2>&1; then fail "$1 is refused (strict)"; else pass "$1 is refused (strict)"; fi
}
hbad "a row with a short commit" "e['versions'][0]['commit']='abc'"
hbad "a row of a higher version than the entry" "e['versions'][0]['version']='9.0.0'"
hbad "a row with another path" "e['versions'][0]['path']='recipes/x'"
hbad "rows out of order" "e['versions'].reverse()"
hbad "a row without yanked" "del e['versions'][0]['yanked']"
hbad "a bad date" "e['date']='yesterday'"
hbad "more than 10 rows" "e['versions']=[dict(e['versions'][0]) for _ in range(11)]"
echo "-- the client ignores what it does not know"
python3 -c "import json; d=json.load(open('$HJ/index.json')); e=d['packages']['demo']; e['versions'][0]['commit']='abc'; e['versions'].append('junk'); e['date']=5; json.dump(d,open('$WORK/hbad.json','w'))"
check_eq "a non-strict validate (client) accepts malformed history" "" "$(python3 -I -c "$PYI
print('; '.join(m.validate(json.load(open('$WORK/hbad.json')))))")"
check_eq "the client leaves out malformed rows and keeps the good ones" "1.1.0 1.0.5 1.0.0 None" "$(python3 -I -c "$PYI
e=m.clean_history(json.load(open('$WORK/hbad.json'))['packages']['demo'])
print(' '.join(r['version'] for r in e['versions']), e.get('date'))")"
# the one reader of the list is hs sys pkg history (Repos.history, #1251): it shows the rows of an entry that index_entries passed through
# clean_history and installs nothing. A second read anywhere in the client fails here.
reads_versions() { grep -c "\[.versions.\]\|get(.versions.)"; }
check_eq "the client reads the version list in one place only" 1 "$(reads_versions <"$SCRIPTS/pkg_repo.py")"
check_eq "and that place is hs sys pkg history" 1 "$(sed -n '/^    def history(/,/^    def choose_installed(/p' "$SCRIPTS/pkg_repo.py" | reads_versions)"
echo "-- hostile history never breaks a build"
H2=$WORK/hist2; git init -q "$H2"
H2G() { git -C "$H2" -c user.name=t -c user.email=t@t.invalid -c commit.gpgsign=false "$@"; }
hw() {   # hw <version> <extra manifest text>: a commit of recipes/x with this manifest
  mkdir -p "$H2/recipes/x"; printf 'name = "x"\nversion = "%s"\nkind = "recipe"\ntitle = "X"\nrequires_core = ">=1"\n%s\n' "$1" "$2" > "$H2/recipes/x/package.toml"
  H2G add -A >/dev/null; H2G commit -q -m "$1"
}
hw 1.0.0 ""
hw "1$(head -c 5000 /dev/zero | tr '\0' 0).0.0" ""
python3 -c "print('x = ' + '[' * 100000 + ']' * 100000)" > "$WORK/deep.txt"
hw 1.0.1 "$(cat "$WORK/deep.txt")"
hw 1.0.2 "$(python3 -c "print('[meta]'); print('changes = \"' + 'c' * 900000 + '\"')")"
hw 1.0.3 "[meta]
changes = \"$(head -c 900 /dev/zero | tr '\0' d)\""
hw 2.0.0 ""
check "a build with a 5000-digit version, a very deep manifest and a huge changes text in the history" $IDX build "$H2" --repo official --out "$WORK/h2-out" --serial 1 --skip-assets
check "that index validates" $IDX validate "$WORK/h2-out/index.json"
check_eq "only the sane older versions are listed, changes cut to 500 characters" "1.0.3 1.0.2 1.0.0 500 500" "$(python3 -c "
import json; e=json.load(open('$WORK/h2-out/index.json'))['packages']['x']
print(' '.join(r['version'] for r in e['versions']), len(e['versions'][0]['changes']), len(e['versions'][1]['changes']))")"
hw "1$(head -c 5000 /dev/zero | tr '\0' 0).0.0" ""
if $IDX build "$H2" --repo official --out "$WORK/h2-out3" --serial 1 --skip-assets >/dev/null 2>&1; then fail "a 5000-digit current version is refused"; else pass "a 5000-digit current version is refused"; fi
check_eq "the index size limit drops older rows first, the time limit and a huge committer date skip safely" "ok" "$(python3 -I -c "$PYI
import subprocess
m.MAX_INDEX_BUILD=os.path.getsize('$HJ/index.json')-400
m.build('$H', 'official', '$WORK/h2-small', serial=1, commit='$TIP', assets=False)
d=json.load(open('$WORK/h2-small/index.json'))['packages']['demo']
assert 0<len(d.get('versions',[]))<4, d
log=subprocess.CompletedProcess([],0,b'%s 300000000000\n' % b'a'*40,b'')
m._git=lambda *a,**k: log
assert m.history_of('/x','$TIP','recipes/demo','demo','1.3.0',{})==(None,[])
seen=[]
def slow(g,args,local=False,data=None,extra_env=None,timeout=None):
    seen.append(timeout); raise subprocess.TimeoutExpired('git',timeout)
m._git=slow
assert m.history_of('/x','$TIP','recipes/demo','demo','1.3.0',{},seconds=5)==(None,[])
assert seen and all(t is not None and t<=5 for t in seen), seen
print('ok')")"
else
  skip "needs git"
fi

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
check "the reusable workflow has no secret and no signing environment" test "$(grep -v '^ *#' "$W" | grep -c 'secrets\.\|environment: index-signing')" = 0
check "the reusable workflow has the build job only" test "$(grep -c "^  [a-z]*:$" "$W")" = 1
check "the build job has a time limit" grep -q "^    timeout-minutes: " "$W"
check "the assemble steps are optional (inputs.assemble)" test "$(grep -c "if: inputs.assemble" "$W")" -ge 3
check "the workflow never uses pull_request_target" test "$(grep -v '^ *#' "$W" | grep -c pull_request_target)" = 0
A=$ROOT/.github/actions/index-sign/action.yml
check "the sign action exists" test -f "$A"
check "the sign action never reads secrets" test "$(grep -v '^ *#' "$A" | grep -c "secrets\.")" = 0
check "the sign action masks the key" grep -q "add-mask" "$A"
check "the sign action removes the key file always" grep -q "if: always()" "$A"
finish
