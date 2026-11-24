#!/usr/bin/env bash
# Pin-only manifests of hobnix/community (hobnix/core#1076): `pkg.py index assemble` fetches every pinned commit, checks it against the reviewed
# manifest and policy.toml and writes the pins commit; the index is built from it and verified. The "upstream" repositories are made here with
# git init and fetched by path (HS_COMMUNITY_ALLOW_LOCAL=1): no network, no key of ours.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
have ssh-keygen || { skip "needs ssh-keygen"; finish; exit 0; }
have git || { skip "needs git"; finish; exit 0; }
IDX="python3 -I $SCRIPTS/lib/pkg_index.py"
PKG="python3 -I $SCRIPTS/pkg.py"
export HS_COMMUNITY_ALLOW_LOCAL=1 HS_PACKAGES_ROOT=$WORK/none
G() { local d=$1; shift; git -C "$d" -c user.name=t -c user.email=t@t.invalid -c commit.gpgsign=false "$@"; }
ZERO=sha256:0000000000000000000000000000000000000000000000000000000000000000

POLICY='licences = ["MIT", "Apache-2.0"]
hosts = ["github.com", "gitlab.com", "codeberg.org"]
kinds = ["recipe", "extension", "blueprint"]
max_folder_bytes = 4000
max_file_bytes = 1500
max_files = 12
max_binary_bytes = 3000
'

mkpkg() {   # mkpkg <dir> <name> <kind> <version>: a valid small package in <dir>
  mkdir -p "$1"
  printf 'name = "%s"\nversion = "%s"\nkind = "%s"\ntitle = "T %s"\nrequires_core = ">=1"\npermissions = []\n[meta]\nlicense = "MIT"\n' "$2" "$4" "$3" "$2" > "$1/package.toml"
  printf 'MIT License\n' > "$1/LICENSE"
}
commit_all() { [ -d "$1/.git" ] || git init -q "$1"; G "$1" add -A && G "$1" commit -q -m c && G "$1" rev-parse HEAD; }
write_manifest() {   # write_manifest <checkout> <name> <kind> <source> <commit> <path> <tree> [status]
  mkdir -p "$1/manifests"
  printf 'name = "%s"\nkind = "%s"\nsource = "%s"\ncommit = "%s"\npath = "%s"\ntree = "%s"\nlicense = "MIT"\nmaintainers = ["alice"]\nstatus = "%s"\n' \
    "$2" "$3" "$4" "$5" "$6" "$7" "${8:-active}" > "$1/manifests/$2.toml"
}
new_checkout() { mkdir -p "$1"; printf '%s' "$POLICY" > "$1/policy.toml"; }

echo "-- a good pin assembles, builds, signs and verifies"
U=$WORK/up/demo; mkpkg "$U/pkg" demo recipe 1.0.0; mkpkg "$WORK/up/ext" ext extension 0.1.0
C1=$(commit_all "$U"); CE=$(commit_all "$WORK/up/ext")
T1=$($IDX tree "$U/pkg"); TE=$($IDX tree "$WORK/up/ext")
CO=$WORK/co; new_checkout "$CO"
write_manifest "$CO" demo recipe "$U" "$C1" pkg "$T1"
write_manifest "$CO" ext extension "$WORK/up/ext" "$CE" . "$TE"
printf '{"packages":{"taken":{}}}' > "$WORK/official.json"
OUT=$WORK/out
check_out "assemble prints the pins commit" '^commit	[0-9a-f]{40}$' $IDX assemble "$CO" --out "$OUT" --official-index "$WORK/official.json"
P1=$(cat "$OUT/pins.commit")
check "the pins tree holds the generated index.toml" test -f "$OUT/tree/index.toml"
check "the folder sits at <kind>s/<name>" test -f "$OUT/tree/recipes/demo/package.toml"
check_eq "an archive of the pins commit has the manifest's tree hash" "$T1" "$(git --git-dir "$OUT/pins.git" archive "$P1:recipes/demo" | { mkdir "$WORK/arch" && tar -x -C "$WORK/arch" && $IDX tree "$WORK/arch"; })"
check "repo-check accepts the pins tree (per-package licences)" $PKG repo-check "$OUT/tree"
check "index build from the pins tree" $IDX build "$OUT/tree" --repo community --out "$WORK/site" --commit "$P1" --serial 1 --skip-assets
check_out "the entry names the source and the pinned commit" "\"source_commit\": \"$C1\"" cat "$WORK/site/index.json"
check_out "the entry carries the manifest's tree hash" "\"tree\": \"$T1\"" cat "$WORK/site/index.json"
check "the index validates (strict)" $IDX validate "$WORK/site/index.json"
ssh-keygen -q -t ed25519 -N '' -f "$WORK/key" >/dev/null
printf 'ci@test namespaces="hobnix-index" %s\n' "$(cut -d' ' -f1,2 "$WORK/key.pub")" > "$WORK/signers"
check "sign" $IDX sign "$WORK/site/index.json" --key-file "$WORK/key"
check_out "verify names the signer" 'signer.*ci@test' $IDX verify "$WORK/site/index.json" --signers "$WORK/signers"

echo "-- the previous pins commit"
git init -q "$WORK/pinned"; G "$WORK/pinned" fetch -q "$OUT/pins.bundle" pins:refs/heads/pins
cp -r "$CO" "$WORK/co2"
cp -r "$WORK/pinned/.git" "$WORK/co2/.git"
check_out "unchanged input reuses the pins tip (tip fetched from the checkout)" "^commit	$P1\$" $IDX assemble "$WORK/co2" --out "$WORK/out3" --pins-tip "$P1"
printf '#!/bin/sh\n' > "$U/pkg/run.sh"
C2=$(commit_all "$U")
write_manifest "$WORK/co2" demo recipe "$U" "$C2" pkg "$($IDX tree "$U/pkg")"
check_out "a changed tree with the same version is refused" 'not higher than 1.0.0' $IDX assemble "$WORK/co2" --out "$WORK/out4" --pins-tip "$P1"
sed -i 's/1.0.0/1.1.0/' "$U/pkg/package.toml"; C3=$(commit_all "$U")
write_manifest "$WORK/co2" demo recipe "$U" "$C3" pkg "$($IDX tree "$U/pkg")"
check "a raised version gives a new pins commit" $IDX assemble "$WORK/co2" --out "$WORK/out5" --pins-tip "$P1"
check "the new commit has the old tip as parent" test "$(git --git-dir "$WORK/out5/pins.git" rev-parse "$(cat "$WORK/out5/pins.commit")^")" = "$P1"
write_manifest "$WORK/co2" demo recipe "$U" "$C3" pkg "$($IDX tree "$U/pkg")" suspended
$IDX assemble "$WORK/co2" --out "$WORK/out6" >/dev/null
check "a suspended package is left out" test ! -e "$WORK/out6/tree/recipes/demo"

echo "-- refusals"
refuse() {   # refuse <label> <regex> <mutate function> [name] [kind]: a pin the check must refuse
  local label=$1 re=$2 mut=$3 name=${4:-bad} kind=${5:-recipe} d=$WORK/up/$1 co=$WORK/co-$1 sha tree
  mkpkg "$d" "$name" "$kind" 1.0.0
  "$mut" "$d"
  sha=$(commit_all "$d"); tree=$($IDX tree "$d" 2>/dev/null || echo $ZERO)
  new_checkout "$co"; write_manifest "$co" "$name" "$kind" "$d" "$sha" . "$tree"
  check_out "$label" "$re" $IDX assemble "$co" --out "$WORK/o-$label" --official-index "$WORK/official.json"
}
m_symlink() { ln -s package.toml "$1/link"; }
m_attr() { printf '*.md export-ignore\n' > "$1/.gitattributes"; }
m_nul() { printf 'a\0b' > "$1/data.bin"; }
m_big() { head -c 2000 /dev/zero | tr '\0' x > "$1/big.txt"; }
m_many() { for i in $(seq 1 14); do echo "$i" > "$1/f$i"; done; }
m_nolicence() { rm "$1/LICENSE"; sed -i '/^license/d' "$1/package.toml"; }
m_nix() { echo '{}' > "$1/module.nix"; }
m_tree() { :; }
refuse symlink 'only regular files' m_symlink
refuse gitattributes '\.gitattributes' m_attr
refuse nulbyte 'binary file that is not a \[\[binary\]\]' m_nul
refuse bigfile 'larger than 1500' m_big
refuse manyfiles 'files, the limit is 12' m_many
refuse nolicence 'no LICENSE' m_nolicence
refuse nix 'Nix modules are not accepted' m_nix
refuse capability 'kind is not one of' m_tree bad capability
refuse reserved 'is reserved' m_tree community
refuse official-name 'taken by a package of the official index' m_tree taken
# a tree hash that is not the folder's
d=$WORK/up/mismatch; mkpkg "$d" mm recipe 1.0.0; sha=$(commit_all "$d"); new_checkout "$WORK/co-mm"
write_manifest "$WORK/co-mm" mm recipe "$d" "$sha" . "$ZERO"
check_out "a tree hash that differs is refused" 'tree hash of the fetched folder' $IDX assemble "$WORK/co-mm" --out "$WORK/o-mm"
# a commit that is not there
write_manifest "$WORK/co-mm" mm recipe "$d" 1111111111111111111111111111111111111111 . "$ZERO"
check_out "a commit that cannot be fetched is refused" 'cannot fetch' $IDX assemble "$WORK/co-mm" --out "$WORK/o-mm2"
# source rules
write_manifest "$WORK/co-mm" mm recipe "https://evil.example.com/a/b" "$sha" . "$ZERO"
check_out "a host that is not on the list is refused" 'host evil.example.com is not allowed' $IDX assemble "$WORK/co-mm" --out "$WORK/o-mm3"
write_manifest "$WORK/co-mm" mm recipe "http://github.com/a/b" "$sha" . "$ZERO"
check_out "http is refused" 'must be an https address' $IDX assemble "$WORK/co-mm" --out "$WORK/o-mm4"
write_manifest "$WORK/co-mm" mm recipe "$d" "$sha" . "$ZERO"
check_out "a local source is refused without the test flag" 'must be an https address' env -u HS_COMMUNITY_ALLOW_LOCAL python3 -I "$SCRIPTS/lib/pkg_index.py" assemble "$WORK/co-mm" --out "$WORK/o-mm5"
sed -i 's/^license = "MIT"/license = "WTFPL"/' "$WORK/co-mm/manifests/mm.toml"
check_out "a licence that is not on the list is refused" 'not on the list' $IDX assemble "$WORK/co-mm" --out "$WORK/o-mm6"
write_manifest "$WORK/co-mm" mm recipe "$d" "$sha" . "$ZERO"
check_out "an unreadable official index fails the check" 'official index could not be read' $IDX assemble "$WORK/co-mm" --out "$WORK/o-mm7" --official-index "$WORK/missing.json"

echo "-- pin rewrites the manifest"
write_manifest "$CO" demo recipe "$U" "$C1" pkg "$ZERO"
check_eq "pin prints the tree hash of the commit" "$T1" "$($IDX pin "$CO/manifests/demo.toml" "$C1")"
check "pin wrote the tree line" grep -q "^tree = \"$T1\"" "$CO/manifests/demo.toml"

echo "-- per-package licences in repo-check, meta.source in validate"
mkdir -p "$WORK/lic/recipes/x"; cp "$OUT/tree/index.toml" "$WORK/lic/index.toml"
cp -r "$OUT/tree/recipes/demo" "$WORK/lic/recipes/demo"; rm "$WORK/lic/recipes/demo/LICENSE"
check_out "a licence only in [meta] is a warning" 'only \[meta\] license' $PKG repo-check "$WORK/lic"
sed -i '/^license/d' "$WORK/lic/recipes/demo/package.toml"
check_out "no licence at all is an error" 'neither a LICENSE file nor' $PKG repo-check "$WORK/lic"
sed 's#"source_commit": "[0-9a-f]*"#"source_commit": "nope"#' "$WORK/site/index.json" > "$WORK/bad.json"
check_out "a malformed meta.source_commit is refused" 'source_commit is not a 40-digit' $IDX validate "$WORK/bad.json"

finish
