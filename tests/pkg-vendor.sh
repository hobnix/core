#!/usr/bin/env bash
# Vendoring of capability modules (docs/PLAN-capabilities-repo.md, Q3, step 3): `hs pkg install|update|remove` of a capability package that has a
# Nix module copy it to <checkout>/vendor/capabilities/<name>/ and write vendor/capabilities.lock; a repository that is not a default one, a name of
# the core and a .nix file outside the package folder are refused; `pkg.py vendor-check` finds a changed byte. A local git repository with SSH-signed
# tags stands in for GitHub; the default repository "caps" is declared in a stand-in checkout.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
have git || { skip "needs git"; finish; exit 0; }
have ssh-keygen || { skip "needs ssh-keygen"; finish; exit 0; }
export HS_LANG=en HS_PLAIN=1 HS_STATE_DIR=$WORK/state HS_NIXOS_DIR=$WORK/nixos
mkdir -p "$HS_STATE_DIR" "$HS_NIXOS_DIR"
PKG="python3 -I $SCRIPTS/pkg.py"
tab=$'\t'
ssh-keygen -q -t ed25519 -N '' -f "$WORK/good" -C test >/dev/null
printf 'releaser@test namespaces="git" %s\n' "$(cut -d' ' -f1,2 "$WORK/good.pub")" > "$WORK/signers"

# the stand-in core checkout: one default repository "caps", its trusted key, and a capability folder of the core called corecap
ROOT_FAKE=$WORK/core; mkdir -p "$ROOT_FAKE/config/trusted-keys" "$ROOT_FAKE/capabilities/corecap"
R=$WORK/repo; mkdir -p "$R"
printf '[[repo]]\nname = "caps"\nurl = "%s"\n' "$R" > "$ROOT_FAKE/config/package-repos.toml"
cp "$WORK/signers" "$ROOT_FAKE/config/trusted-keys/caps.allowed_signers"
printf 'name = "corecap"\n' > "$ROOT_FAKE/capabilities/corecap/capability.toml"
export HS_PACKAGES_ROOT=$ROOT_FAKE

cd "$R"
git init -q . && git config user.email t@t && git config user.name t && git config gpg.format ssh && git config commit.gpgsign false
release() {   # release <tag> <version> <name> [extra files: nested]: a capability package <name> with a module, an options file, a helper, a script
  local d="$R/capabilities/$3"
  rm -rf "$R/capabilities"; mkdir -p "$d"
  printf 'name = "%s"\nversion = "%s"\nkind = "capability"\ntype = "feature"\ntitle = "Vend"\nrequires = ["corecap"]\nrequires_core = ">=1"\nmodule = "module.nix"\noptions = "options.toml"\nrequires_nix_api = 1\n' "$3" "$2" > "$d/package.toml"
  printf '{ ... }: { imports = [ ./helper.nix ]; } # %s\n' "$2" > "$d/module.nix"
  printf '{ ... }: { }\n' > "$d/helper.nix"
  printf '[[item]]\nkey = "x"\ncapability = "%s"\nstore = "machine"\ntype = "string"\ndefault = "a"\ndescription = "x"\n' "$3" > "$d/options.toml"
  printf '#!/usr/bin/env bash\necho %s\n' "$2" > "$d/run.sh"
  if [ "${4:-}" = nested ]; then mkdir -p "$d/sub"; printf '{ }\n' > "$d/sub/x.nix"; fi
  printf '[package.%s]\nversion = "%s"\nkind = "capability"\npath = "capabilities/%s"\nrequires_core = ">=1"\n' "$3" "$2" "$3" > "$R/index.toml"
  git add -A && git commit -q -m "$3 $2" && git -c user.signingkey="$WORK/good.pub" tag -s "v$2" -m "release $2"
}
release 1.0.0 1.0.0 fixmod
cd "$ROOT"

echo "-- install"
$PKG fetch >/dev/null 2>&1
check_out "the capabilities read lists the package with requires" "^fixmod${tab}caps${tab}1[.]0[.]0${tab}-${tab}new${tab}corecap${tab}feature${tab}Vend$" $PKG capabilities
check_out "install of a capability package with a module works" "fixmod" bash -c "$PKG install fixmod 2>&1"
check_out "the capabilities read shows it installed" "^fixmod${tab}caps${tab}1[.]0[.]0${tab}1[.]0[.]0${tab}current${tab}corecap${tab}feature${tab}Vend$" $PKG capabilities
V=$HS_NIXOS_DIR/vendor
check "the module is vendored" test -f "$V/capabilities/fixmod/module.nix"
check "and its helper and script too" test -f "$V/capabilities/fixmod/run.sh"
check "the lock exists" test -f "$V/capabilities.lock"
check_out "the lock names the repository and the tag" 'tag = "v1[.]0[.]0"' cat "$V/capabilities.lock"
check_out "and the commit" 'commit = "[0-9a-f]{40}"' cat "$V/capabilities.lock"
check_out "and the tree id" 'tree = "[0-9a-f]{40}"' cat "$V/capabilities.lock"
want=$(sha256sum "$V/capabilities/fixmod/module.nix" | cut -d' ' -f1)
check_out "and the sha256 of module.nix" "\"module.nix\" = \"$want\"" cat "$V/capabilities.lock"
check_out "and the one of the helper" '"helper.nix" = "[0-9a-f]{64}"' cat "$V/capabilities.lock"
check_eq "the committed tree id is the git tree of the folder" "$(git -C "$R" rev-parse v1.0.0:capabilities/fixmod)" "$(sed -n 's/^tree = "\(.*\)"/\1/p' "$V/capabilities.lock")"
check "vendor-check agrees" $PKG vendor-check --to "$HS_NIXOS_DIR"
cp "$V/capabilities.lock" "$WORK/lock1"; (cd "$V/capabilities" && find . -type f | sort | xargs sha256sum) > "$WORK/tree1"
$PKG install fixmod >/dev/null 2>&1 || true
check_eq "a second install gives the same lock, byte for byte" "$(sha256sum < "$WORK/lock1")" "$(sha256sum < "$V/capabilities.lock")"
check_eq "and the same tree" "$(sha256sum < "$WORK/tree1")" "$( (cd "$V/capabilities" && find . -type f | sort | xargs sha256sum) | sha256sum)"
check "no .new left behind" bash -c "! ls '$V/capabilities.lock.new' '$V/capabilities'/.new-* 2>/dev/null"

echo "-- the check before a rebuild"
check "an enabled vendored package and a core capability pass" $PKG vendor-verify fixmod corecap
check_out "a name that is nowhere is named, with the way out" "^nowhere${tab}is neither a part of the core nor an installed package${tab}hs ext disable nowhere" bash -c "$PKG vendor-verify nowhere; true"
mv "$V/capabilities/fixmod" "$WORK/fixmod.away"
check_out "a package whose vendored folder is gone is named" "^fixmod${tab}vendor/ differs from the lock: in the lock but not vendored${tab}hs pkg install fixmod" bash -c "$PKG vendor-verify fixmod; true"
mv "$WORK/fixmod.away" "$V/capabilities/fixmod"
cp "$V/capabilities.lock" "$WORK/lock.keep"; sed -i 's/^version = "1.0.0"/version = "0.9.0"/' "$V/capabilities.lock"
check_out "a lock of another release is named" "^fixmod${tab}vendor/ holds another release" bash -c "$PKG vendor-verify fixmod; true"
cp "$WORK/lock.keep" "$V/capabilities.lock"

echo "-- a changed byte is found"
printf '# changed\n' >> "$V/capabilities/fixmod/helper.nix"
check_out "vendor-check names the package and the file" "^fixmod${tab}helper.nix differs from the lock" bash -c "$PKG vendor-check --to $HS_NIXOS_DIR; true"
printf '{ }\n' > "$V/capabilities/fixmod/extra.nix"
check_out "a .nix file the lock does not name is found" "^fixmod${tab}extra.nix is not in the lock" bash -c "$PKG vendor-check --to $HS_NIXOS_DIR; true"
rm -f "$V/capabilities/fixmod/extra.nix"

echo "-- update"
cd "$R"; release 1.1.0 1.1.0 fixmod; cd "$ROOT"
$PKG fetch >/dev/null 2>&1
check_out "update installs the new release" "1[.]1[.]0" bash -c "$PKG update fixmod --yes 2>&1"
check_out "the lock says 1.1.0" 'version = "1[.]1[.]0"' cat "$V/capabilities.lock"
check_out "and the module is the new one" "1[.]1[.]0" cat "$V/capabilities/fixmod/module.nix"
check "vendor-check agrees again (the changed byte is gone)" $PKG vendor-check --to "$HS_NIXOS_DIR"

echo "-- remove"
check "remove works" bash -c "$PKG remove fixmod >/dev/null 2>&1"
check "the vendored folder is gone" test ! -e "$V/capabilities/fixmod"
check "and the lock" test ! -e "$V/capabilities.lock"
check "vendor-check has nothing to say" $PKG vendor-check --to "$HS_NIXOS_DIR"

echo "-- refusals"
cd "$R"; release 1.2.0 1.2.0 corecap; cd "$ROOT"
$PKG fetch >/dev/null 2>&1
check_out "the name of a capability of the core is refused" "capability of the core" bash -c "$PKG install corecap 2>&1; true"
check "and nothing was vendored" test ! -e "$V"
cd "$R"; release 1.3.0 1.3.0 nest nested; cd "$ROOT"
$PKG fetch >/dev/null 2>&1
check_out "a .nix file outside the package folder is refused" "only .nix files of its own folder" bash -c "$PKG install nest 2>&1; true"
check "and nothing was vendored" test ! -e "$V"
check "and not installed" test ! -e "$HS_STATE_DIR/packages/current/nest"
# the same package from an added repository: no Nix module allowed
cd "$R"; release 1.4.0 1.4.0 addedmod; cd "$ROOT"
check "an added repository can be registered" bash -c "$PKG repo add other '$R' --key '$WORK/signers' >/dev/null 2>&1"
sed -i 's/^name = "caps"/name = "caps-off"/' "$ROOT_FAKE/config/package-repos.toml"
$PKG fetch >/dev/null 2>&1
check_out "a module from an added repository is refused" "only the default repositories may ship" bash -c "$PKG install addedmod --repo other 2>&1; true"
check "and nothing was vendored" test ! -e "$V"

echo "-- a release that waits for a newer core"
mkdir -p "$HS_STATE_DIR/packages/current/fixmod"; printf 'name = "fixmod"
version = "1.1.0"
kind = "capability"
requires_core = ">=1"
' > "$HS_STATE_DIR/packages/current/fixmod/package.toml"
printf '[package.fixmod]
version = "1.1.0"
repo = "other"
commit = "abc"
tag = "v1.1.0"
' > "$HS_STATE_DIR/packages/installed.toml"
cd "$R"; release 1.5.0 1.5.0 fixmod
printf '[package.fixmod]
version = "1.5.0"
kind = "capability"
path = "capabilities/fixmod"
requires_core = ">=1"
requires_nix_api = 9
' > index.toml
git add -A && git commit -q -m "needs 9" && git -c user.signingkey="$WORK/good.pub" tag -s v1.5.1 -m r; cd "$ROOT"
$PKG fetch >/dev/null 2>&1
check_out "updates --waits names the release and what it needs" "^fixmod${tab}1[.]5[.]0${tab}Nix API level 9" bash -c "$PKG updates --waits"
check "updates does not list what cannot be taken" bash -c "! $PKG updates | grep -q fixmod"
check_out "the market marks it as waits" "fixmod${tab}capability${tab}other${tab}1[.]5[.]0${tab}1[.]1[.]0${tab}waits" bash -c "$PKG market"
check "core-check is quiet for a package without a module" $PKG core-check
printf 'name = "fixmod"
version = "1.1.0"
kind = "capability"
module = "module.nix"
requires_core = ">=1"
requires_nix_api = 9
' > "$HS_STATE_DIR/packages/current/fixmod/package.toml"
check_out "core-check names an installed module package the core does not suit" "^fixmod${tab}needs Nix API level 9" bash -c "$PKG core-check; true"

finish
