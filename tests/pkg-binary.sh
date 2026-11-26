#!/usr/bin/env bash
# [[binary]] of a package.toml (scripts/lib/pkg_binary.py, hobnix/core#1138): repo-check accepts a good program and refuses the hostile ones
# (path with .., absolute path, symlink, wrong hash, wrong target, missing file, program nothing refers to, unknown key, duplicate), and
# hs pkg install and update verify the INSTALLED copy: a wrong hash, a missing executable bit or a server that is not x86_64 refuses with a
# code and the old version stays. No root.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
have git || { skip "needs git"; finish; exit 0; }
have ssh-keygen || { skip "needs ssh-keygen"; finish; exit 0; }
export HS_TESTING=1 HS_LANG=en HS_PLAIN=1 HS_CALLER=test HS_STATE_DIR=$WORK/state
mkdir -p "$HS_STATE_DIR"
PKG="python3 -I $SCRIPTS/pkg.py"
tab=$'\t'
BODY=$'#!/bin/sh\necho hi\n'
SUM=$(printf '%s' "$BODY" | sha256sum | cut -d' ' -f1)
ZERO=$(printf '0%.0s' $(seq 64))

echo "-- repo-check"
base() {   # base <dir> [path] [sha256] [target]: a repository with one extension "svc" that has a program and a row that runs it
  rm -rf "$1"; mkdir -p "$1/extensions"
  printf '# index\n' > "$1/index.toml"
  bash "$SCRIPTS/pkg.sh" new svc --template extension --dir "$1" >/dev/null
  P=$1/extensions/svc
  mkdir -p "$P/bin"; printf '%s' "$BODY" > "$P/bin/svc"; chmod 755 "$P/bin/svc"
  printf 'user\text svc run\t@/bin/svc\trun\tRun the program\tDas Programm starten\treads,proto\n' >> "$P/commands.tsv"
  printf '\n[[binary]]\npath = "%s"\nsha256 = "%s"\nbin = "%s"\ntarget = "%s"\n' "${2:-bin/svc}" "${3-$SUM}" "${5:-svc}" "${4:-x86_64-unknown-linux-musl}" >> "$P/package.toml"
}
rc() { python3 -I "$SCRIPTS/pkg.py" repo-check "$1" 2>&1; true; }
R=$WORK/r1; base "$R"
check "a good [[binary]] passes repo-check" $PKG repo-check "$R"
B=$WORK/rb
bad() {   # bad "what" regex <path> <sha> <target>
  local what=$1 re=$2; shift 2
  base "$B" "$@"
  check_out "$what" "$re" rc "$B"
}
bad "a path with .. is refused" "binary.path" "../x" "$SUM"
bad "an absolute path is refused" "binary.path" "/bin/sh" "$SUM"
bad "a wrong hash is refused" "binary.hash" bin/svc "$ZERO"
bad "a short hash is a shape error" "binary.shape" bin/svc "abc"
bad "a wrong target is refused" "binary.target" bin/svc "$SUM" aarch64-unknown-linux-musl
bad "a missing file is refused" "binary.missing" bin/none "$SUM"
base "$B" bin/svc ""; rm "$B/extensions/svc/bin/svc"
check "not built yet (empty sha256, no file) passes repo-check" $PKG repo-check "$B"
check_out "and --release refuses it" "binary.unbuilt" python3 -I "$SCRIPTS/pkg.py" repo-check --release "$B"
base "$B"; check "built and matching passes --release" $PKG repo-check --release "$B"

echo "-- repo-check --release: the SDK pin of a crate is a core release tag (ADR 0031)"
pin() { printf '[package]\nname = "svc"\n[dependencies]\nhobnix-ext-sdk = { %s }\n' "$1" > "$B/extensions/svc/Cargo.toml"; }
rel() { python3 -I "$SCRIPTS/pkg.py" repo-check --release "$B" 2>&1; true; }
git_core='git = "https://github.com/hobnix/core"'
base "$B"; pin "$git_core, tag = \"v0.13.0\""
check "a release tag passes --release" $PKG repo-check --release "$B"
for t in v0.13.0-beta.1 v0.13.0-rc.2; do
  pin "$git_core, tag = \"$t\""; check "a prerelease tag $t passes --release" $PKG repo-check --release "$B"
done
pin "$git_core, tag = \"v0.13.0\""
pin "$git_core, rev = \"0123456789012345678901234567890123456789\""
check "a rev passes without --release" $PKG repo-check "$B"
check_out "and --release refuses it" "binary.sdk-pin" rel
for spec in "$git_core, tag = \"v0.13.0-\"" "$git_core, tag = \"v0.13\"" "$git_core, tag = \"V0.13.0\"" "$git_core, tag = \"v0.13.0-alpha.1\"" "$git_core, branch = \"develop\"" 'git = "https://example.org/core", tag = "v0.13.0"' 'path = "../../sdk"'; do
  pin "$spec"; check_out "--release refuses: $spec" "binary.sdk-pin" rel
done
pin "$git_core, tag = \"v0.13.0\""
printf "[patch.'https://github.com/hobnix/core']\nhobnix-ext-sdk = { path = \"x\" }\n" >> "$B/extensions/svc/Cargo.toml"
check_out "a [patch] of the SDK is refused" "binary.sdk-pin" rel
printf '[package]\nname = "svc"\n[dependencies]\nsdk = { package = "hobnix-ext-sdk", version = "1" }\n' > "$B/extensions/svc/Cargo.toml"
check_out "a renamed dependency is checked too" "binary.sdk-pin" rel
for k in hobnix-pkg hobnix-pkg-command hobnix-pkg-service; do   # the crates of 0.14 (hobnix-ext-sdk is their deprecated re-export)
  printf '[package]\nname = "svc"\n[dependencies]\n%s = { %s, tag = "v0.14.0" }\n' "$k" "$git_core" > "$B/extensions/svc/Cargo.toml"
  check "$k by a release tag passes --release" $PKG repo-check --release "$B"
  printf '[package]\nname = "svc"\n[dependencies]\n%s = { %s, branch = "develop" }\n' "$k" "$git_core" > "$B/extensions/svc/Cargo.toml"
  check_out "$k by a branch is refused" "binary.sdk-pin" rel
done
base "$B" bin/svc ""
check_out "a file that is there with an empty sha256 is refused" "binary.hash" rc "$B"
base "$B" bin/none "$SUM"
check_out "a sha256 that is set with no file is refused" "binary.missing" rc "$B"
base "$B" bin/svc "$ZERO"
check_out "a hash mismatch is refused" "binary.hash" rc "$B"
base "$B" bin/svc ""; rm "$B/extensions/svc/bin/svc"; sed -i 's#@/bin/svc#@/bin/nothing#' "$B/extensions/svc/commands.tsv"
check_out "not built but unreferenced is refused" "binary.unreferenced" rc "$B"
bad "a path with a trailing newline is refused" "binary.path" 'bin/svc\n' "$SUM"
bad "a bin name with a trailing newline is refused" "binary.shape" bin/svc "$SUM" x86_64-unknown-linux-musl 'svc\n'
bad "a bin name with a control character is refused" "binary.shape" bin/svc "$SUM" x86_64-unknown-linux-musl 'sv\u0001c'
bad "a sha256 with a trailing newline is refused" "binary.shape" bin/svc "${SUM}\n"
base "$B"; sed -i 's#reads,proto#reads#' "$B/extensions/svc/commands.tsv"
check_out "a row without the flag proto naming the program is refused" "binary.runner" rc "$B"
base "$B"; sed -i '/^\[\[binary\]\]/,$d' "$B/extensions/svc/package.toml"
printf '\177ELF\002\001' > "$B/extensions/svc/bin/svc"
check_out "a compiled program started without a [[binary]] is refused" "binary.undeclared" rc "$B"
printf '#!/bin/sh\n' > "$B/extensions/svc/bin/svc"
check_out "a script without a [[binary]] stays valid" "^$" bash -c "$PKG repo-check '$B' 2>/dev/null; echo"
check_eq "HS_UNAME_M is ignored without HS_TESTING" "$(uname -m)" "$(env -u HS_TESTING HS_UNAME_M=aarch64 python3 -I -c "import importlib.util as u;s=u.spec_from_file_location('x','$SCRIPTS/lib/pkg_binary.py');m=u.module_from_spec(s);s.loader.exec_module(m);print(m.host_arch())")"
base "$B"; sed -i 's#^bin = "svc"#bin = "svc"\ncolor = "red"#' "$B/extensions/svc/package.toml"
check_out "an unknown key is refused" "unknown key color" rc "$B"
base "$B"; printf '\n[[binary]]\npath = "bin/svc"\nsha256 = "%s"\ntarget = "x86_64-unknown-linux-musl"\n' "$SUM" >> "$B/extensions/svc/package.toml"
check_out "the same program twice is refused" "binary.duplicate" rc "$B"
base "$B"; rm "$B/extensions/svc/bin/svc"
if ln -s /bin/sh "$B/extensions/svc/bin/svc" 2>/dev/null && [ -L "$B/extensions/svc/bin/svc" ]; then
  check_out "a symbolic link as the program is refused" "binary.path" rc "$B"
else skip "symbolic links are not available here"; fi
base "$B"; mv "$B/extensions/svc/bin" "$B/real"
if ln -s ../../real "$B/extensions/svc/bin" 2>/dev/null && [ -L "$B/extensions/svc/bin" ]; then
  check_out "a symbolic link in front of the program is refused" "binary.path" rc "$B"
else skip "symbolic links are not available here"; fi
base "$B"; sed -i 's#@/bin/svc#@/bin/nothing#' "$B/extensions/svc/commands.tsv"
check_out "a program that no row refers to is refused" "binary.unreferenced" rc "$B"
base "$B"; sed -i 's#^\[\[binary\]\]#binary = 5\n[x]#' "$B/extensions/svc/package.toml"
check_out "a binary that is not a list of tables is a shape error" "binary.shape" rc "$B"

echo "-- install and update"
ssh-keygen -q -t ed25519 -N '' -f "$WORK/good" -C test >/dev/null
printf 'releaser@test namespaces="git" %s\n' "$(cut -d' ' -f1,2 "$WORK/good.pub")" > "$WORK/signers"
G=$WORK/repo; mkdir -p "$G/extensions/svc/bin"; cd "$G" || exit 1
git init -q . && git config user.email t@t && git config user.name t && git config gpg.format ssh && git config commit.gpgsign false
release() {   # release <tag> <version> <body> <sha> [+x|-x]: one extension with a program, committed and tagged with a signature
  printf 'name = "svc"\nversion = "%s"\nkind = "extension"\ntitle = "Svc"\nrequires_core = ">=1"\npermissions = []\n\n[[binary]]\npath = "bin/svc"\nsha256 = "%s"\ntarget = "x86_64-unknown-linux-musl"\n' "$2" "$4" > extensions/svc/package.toml
  printf '%s' "$3" > extensions/svc/bin/svc
  printf 'user\text svc run\t@/bin/svc\trun\tRun\tStart\treads,proto\n' > extensions/svc/commands.tsv
  printf '[package.svc]\nversion = "%s"\nkind = "extension"\npath = "extensions/svc"\nrequires_core = ">=1"\n' "$2" > index.toml
  git add -A && git update-index --chmod="${5:-+x}" extensions/svc/bin/svc && git commit -q -m "svc $2"
  git -c user.signingkey="$WORK/good.pub" tag -s "$1" -m "release $2"
}
release v1.0.0 1.0.0 "$BODY" "$SUM"
cd "$ROOT" || exit 1
check "the repository is added" $PKG repo add test "$G" --key "$WORK/signers"
$PKG fetch test >/dev/null 2>&1
export HS_UNAME_M=x86_64
check_out "a good program installs" "svc 1[.]0[.]0 from test" $PKG install svc
CUR=$HS_STATE_DIR/packages/current/svc
check_eq "the installed program is the one that was hashed" "$SUM" "$(sha256sum "$CUR/bin/svc" | cut -d' ' -f1)"
check "and it is executable" test -x "$CUR/bin/svc"

cd "$G" || exit 1
release v1.1.0 1.1.0 "${BODY}changed" "$SUM"
cd "$ROOT" || exit 1
$PKG fetch test >/dev/null 2>&1
check_out "a wrong hash is refused with its code" "binary.hash" bash -c "$PKG install svc 2>&1; true"
check_out "hs pkg install shows it the ADR 0028 way" "(^|$tab)status${tab}refused" bash -c "bash $SCRIPTS/pkg.sh install svc 2>&1; true"
check_out "with the code line" "code${tab}binary[.]hash" bash -c "bash $SCRIPTS/pkg.sh install svc 2>&1; true"
check_out "and the old version stays installed" 'version = "1[.]0[.]0"' cat "$HS_STATE_DIR/packages/installed.toml"
check_out "with its files in place" 'name = "svc"' cat "$CUR/package.toml"
check "and no half copy is left" test ! -e "$HS_STATE_DIR/packages/current/.new-svc"

cd "$G" || exit 1
release v1.2.0 1.2.0 "$BODY" "$SUM" -x
cd "$ROOT" || exit 1
$PKG fetch test >/dev/null 2>&1
check_out "a program without the executable bit is refused" "binary.exec" bash -c "$PKG install svc 2>&1; true"
check_out "an update refuses too and the old version stays" 'version = "1[.]0[.]0"' bash -c "$PKG update svc --yes >/dev/null 2>&1; cat '$HS_STATE_DIR/packages/installed.toml'"

cd "$G" || exit 1
release v1.3.0 1.3.0 "$BODY" ""
git rm -q -f extensions/svc/bin/svc && git commit -q -m "not built" && git -c user.signingkey="$WORK/good.pub" tag -sf v1.3.0 -m "release 1.3.0"
cd "$ROOT" || exit 1
$PKG fetch test >/dev/null 2>&1
check_out "a package that is not built yet cannot be installed" "binary.unbuilt" bash -c "$PKG update svc --yes 2>&1; true"
check_out "and the old version stays" 'version = "1[.]0[.]0"' cat "$HS_STATE_DIR/packages/installed.toml"

echo "-- another architecture"
rm -rf "$HS_STATE_DIR/packages/current" "$HS_STATE_DIR/packages/previous" "$HS_STATE_DIR/packages/installed.toml"
check_out "an aarch64 server refuses a package with a program" "binary.arch" bash -c "HS_UNAME_M=aarch64 $PKG install svc 2>&1; true"
check "and installs nothing" test ! -e "$HS_STATE_DIR/packages/current/svc"

cd "$G" || exit 1
mkdir -p extensions/svc/bin
release v1.4.0 1.4.0 "$BODY" ""
sed -i '/^\[\[binary\]\]/,$d' extensions/svc/package.toml
printf '\177ELF\002\001' > extensions/svc/bin/svc
git add -A && git commit -q -m "elf without a table" && git -c user.signingkey="$WORK/good.pub" tag -sf v1.4.0 -m "release 1.4.0"
cd "$ROOT" || exit 1
$PKG fetch test >/dev/null 2>&1
check_out "a program with no [[binary]] is refused at install" "binary.undeclared" bash -c "$PKG install svc 2>&1; true"
check "and installs nothing" test ! -e "$HS_STATE_DIR/packages/current/svc"

finish
