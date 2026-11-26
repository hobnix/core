#!/usr/bin/env bash
# scripts/dev/merge-package-repos.sh (hobnix/core#1074): three tiny local repositories with colliding root files (README, LICENSE, index.toml,
# tests/run-all.sh) become one: every original commit is an ancestor, `git log -- recipes/x` follows the history, a not-moved package is absent,
# the result passes `pkg.py repo-check`, an existing output directory is refused, nothing of the sources changes.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
have git || { skip "needs git"; finish; exit 0; }
export HS_LANG=en HS_PLAIN=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
MP="bash $SCRIPTS/dev/merge-package-repos.sh"
PKG="python3 -I $SCRIPTS/pkg.py"
FX=$ROOT/tests/fixtures/pkgtree

mkrepo() {   # mkrepo <name>: an empty repository on develop under $WORK/src/<name>
  mkdir -p "$WORK/src/$1" && git -C "$WORK/src/$1" init -q -b develop && git -C "$WORK/src/$1" config commit.gpgsign false
}
commit() { git -C "$WORK/src/$1" add -A && git -C "$WORK/src/$1" commit -q -s -m "$2"; git -C "$WORK/src/$1" rev-parse HEAD; }
common() {   # common <name> <licence word>: the root files every repository has
  local d=$WORK/src/$1
  printf '# %s\n' "$1" > "$d/README.md"; printf '%s licence of %s\n' "$2" "$1" > "$d/LICENSE"
  printf 'sources of %s\n' "$1" > "$d/CONTRIBUTING.md"
  mkdir -p "$d/tests"; printf '#!/usr/bin/env bash\necho tests of %s\n' "$1" > "$d/tests/run-all.sh"; chmod +x "$d/tests/run-all.sh"
  printf 'echo %s\n' "$1" > "$d/tests/$1-only.sh"
}

mkrepo recipes
mkdir -p "$WORK/src/recipes/recipes/x" "$WORK/src/recipes/recipes/docker"
for n in x docker; do
  printf 'name = "%s"\nversion = "1.0.0"\nkind = "recipe"\ntitle = "T"\nrequires_core = ">=1"\naudience = "generic"\npermissions = []\nneeds = []\nuses = []\ninput = "none"\nscript = "run.sh"\n' "$n" > "$WORK/src/recipes/recipes/$n/package.toml"
  printf '#!/usr/bin/env bash\n# kind: generic\n# needs: -\n# uses: -\n' > "$WORK/src/recipes/recipes/$n/run.sh"
done
common recipes "MIT License:"
printf '[package.x]\nversion = "1.0.0"\nkind = "recipe"\npath = "recipes/x"\nrequires_core = ">=1"\n\n[package.docker]\nversion = "1.0.0"\nkind = "recipe"\npath = "recipes/docker"\nrequires_core = ">=1"\n' > "$WORK/src/recipes/index.toml"
r1=$(commit recipes "recipes: first")
echo more >> "$WORK/src/recipes/recipes/x/run.sh"; r2=$(commit recipes "recipes: x changes")

mkrepo extensions
mkdir -p "$WORK/src/extensions/extensions" "$WORK/src/extensions/examples/rust-hello" "$WORK/src/extensions/scripts"
cp -r "$FX/capabilities/fixext" "$WORK/src/extensions/extensions/fixext"
printf 'permissions = []
' >> "$WORK/src/extensions/extensions/fixext/package.toml"
common extensions "MIT License:"
printf 'fn main() {}\n' > "$WORK/src/extensions/examples/rust-hello/main.rs"; printf 'build\n' > "$WORK/src/extensions/scripts/build.sh"
printf '[toolchain]\n' > "$WORK/src/extensions/rust-toolchain.toml"
printf '[package.fixext]\nversion = "1.0.0"\nkind = "extension"\npath = "extensions/fixext"\nrequires_core = ">=1"\n' > "$WORK/src/extensions/index.toml"
e1=$(commit extensions "extensions: first")

mkrepo capabilities
mkdir -p "$WORK/src/capabilities/capabilities" "$WORK/src/capabilities/examples/example"
cp -r "$FX/capabilities/fixcap" "$WORK/src/capabilities/capabilities/fixcap"
printf 'permissions = []
' >> "$WORK/src/capabilities/capabilities/fixcap/package.toml"
common capabilities "GNU AFFERO GENERAL PUBLIC LICENSE:"
printf 'example\n' > "$WORK/src/capabilities/examples/example/package.toml"
printf '[package.fixcap]\nversion = "1.0.0"\nkind = "capability"\npath = "capabilities/fixcap"\nrequires_core = ">=1"\n' > "$WORK/src/capabilities/index.toml"
c1=$(commit capabilities "capabilities: first")
heads_before=$(for n in recipes extensions capabilities; do git -C "$WORK/src/$n" rev-parse HEAD; done | paste -sd' ' -)

S="--recipes $WORK/src/recipes --extensions $WORK/src/extensions --capabilities $WORK/src/capabilities"
OUT=$WORK/official

echo "-- plan and refusals"
check_out "--plan shows the sources and writes nothing" "Not moved" bash -c "$MP $OUT $S --plan 2>&1"
check "and the output directory does not exist" test ! -e "$OUT"
check_out "no output directory is named" "Name the output directory" bash -c "$MP $S 2>&1; true"
check_out "a source that cannot be fetched is named, and nothing is left" "Could not fetch" bash -c "$MP $WORK/never $S --extensions $WORK/nosuch 2>&1; true"
check "the failed run left no directory" test ! -e "$WORK/never"

echo "-- the merge"
check_out "the run succeeds and reports the result" "Not pushed" bash -c "$MP $OUT $S 2>&1"
for pair in "recipes $r1" "recipes $r2" "extensions $e1" "capabilities $c1"; do
  set -- $pair
  check "$1 commit ${2:0:7} is an ancestor of the result" git -C "$OUT" merge-base --is-ancestor "$2" HEAD
done
check_out "git log -- recipes/x reaches the original commit" "recipes: x changes" bash -c "git -C $OUT log --format=%s -- recipes/x"
check_out "and the first one" "recipes: first" bash -c "git -C $OUT log --format=%s -- recipes/x"
check_out "git log -- extensions/fixext reaches its source commit" "extensions: first" bash -c "git -C $OUT log --format=%s -- extensions/fixext"
check_eq "the commits keep their sign-off" "Signed-off-by: t <t@t>" "$(git -C "$OUT" log -1 --format=%B "$r1" | grep Signed-off)"
check_eq "the layout has the folders of the three" "capabilities/fixcap extensions/fixext recipes/x" "$(cd "$OUT" && ls -d recipes/* extensions/* capabilities/* | grep -v LICENSE | sort | paste -sd' ' -)"
check "a not-moved package is absent" test ! -e "$OUT/recipes/docker"
check_eq "and not in index.toml" "0" "$(grep -c docker "$OUT/index.toml")"
check_eq "index.toml publishes an index" 'publish = "index"' "$(head -n1 "$OUT/index.toml")"
check_eq "and lists the three packages" "3" "$(grep -c '^\[package\.' "$OUT/index.toml")"
check "the examples are in place (the capability one renamed)" test -f "$OUT/examples/rust-hello/main.rs" -a -f "$OUT/examples/capability/package.toml"
check "scripts and the toolchain file came with the extensions" test -f "$OUT/scripts/build.sh" -a -f "$OUT/rust-toolchain.toml"
check "the tests of every source are there" test -f "$OUT/tests/recipes-only.sh" -a -f "$OUT/tests/extensions-only.sh" -a -f "$OUT/tests/capabilities-only.sh"
check_out "the three run-all.sh were kept under their source" "tests of extensions" bash -c "cat $OUT/tests/run-extensions.sh"
check_out "and tests/run-all.sh runs all of them" "tests of capabilities" bash -c "bash $OUT/tests/run-all.sh"
check_match "the root LICENSE is AGPL" "AFFERO" "$(cat "$OUT/LICENSE")"
check_match "recipes/ keeps its own licence" "MIT License" "$(cat "$OUT/recipes/LICENSE")"
check "CONTRIBUTING of a source is left for the scaffold" test ! -e "$OUT/CONTRIBUTING.md"
check "no tag and no remote came with it" test -z "$(git -C "$OUT" tag)$(git -C "$OUT" remote)"
check "no import refs are left" test -z "$(git -C "$OUT" for-each-ref refs/import)"
check "pkg.py repo-check passes on the result" $PKG repo-check "$OUT"
check_eq "the sources were not changed" "$heads_before" "$(for n in recipes extensions capabilities; do git -C "$WORK/src/$n" rev-parse HEAD; done | paste -sd' ' -)"
check "and their working trees are clean" test -z "$(git -C "$WORK/src/recipes" status --porcelain)"

echo "-- a second run"
check_out "an existing output directory is refused" "exists already" bash -c "$MP $OUT $S 2>&1; true"
check_out "and it fails" "exists already" bash -c "$MP $OUT $S 2>&1 || echo failed-exit"
check "the result is untouched" git -C "$OUT" diff --quiet

echo "-- collisions"
cp "$WORK/src/extensions/tests/extensions-only.sh" "$WORK/src/capabilities/tests/extensions-only.sh"; echo different >> "$WORK/src/capabilities/tests/extensions-only.sh"
commit capabilities "collides" >/dev/null
check_out "a test file in two sources is refused" "collides" bash -c "$MP $WORK/second $S 2>&1; true"
check "and the half-built result is removed" test ! -e "$WORK/second"
finish
