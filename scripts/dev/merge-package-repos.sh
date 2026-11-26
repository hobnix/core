#!/usr/bin/env bash
# Builds the repository hobnix/official LOCALLY out of hobnix/recipes, hobnix/extensions and hobnix/capabilities (hobnix/core#1074, decisions 2-4).
# Not an `hs` command. It never pushes, never adds a remote and never changes the sources: it only fetches their develop branch.
#
#   bash <core>/scripts/dev/merge-package-repos.sh <out dir> [--recipes <url|dir>] [--extensions <url|dir>] [--capabilities <url|dir>]
#                                                  [--branch develop] [--not-moved a,b,c] [--plan]
#       <out dir> must not exist. The sources default to https://github.com/hobnix/<name>.git. The history is merged without rewriting:
#       a root commit, then per source `git merge -s ours --allow-unrelated-histories` of its branch and one commit that checks out its folders
#       into the layout (every original commit, author and Signed-off-by stays; `git log -- recipes/x` follows through the merge parent).
#       Then one commit with the root files: index.toml (publish = "index" and the [package.*] blocks of the three, minus --not-moved),
#       README.md, LICENSE (AGPL-3.0, the core's), tests/run-all.sh (runs the three old ones, kept as tests/run-<source>.sh).
#       Layout: recipes/ extensions/ capabilities/ blueprints/ (as in the sources), tests/ (files must not collide), examples/ (the capabilities
#       example becomes examples/capability), scripts/, rust-toolchain.toml, recipes/LICENSE (the MIT licence of recipes).
#       Left for the scaffold of hobnix/official (O1): .github/, CONTRIBUTING.md, SECURITY.md, .gitignore. Tags are not imported.
#       --not-moved: packages left out (default docker,sunshine,catalyst-node,catalyst-panel; decision of 2026-11-22).
#       --plan prints the plan and stops. Without a git identity (user.name, user.email) it refuses.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
core=$(cd "$here/../.." && pwd)
export HS_LANG=${HS_LANG:-en}
# shellcheck source=scripts/lib/ui.sh
. "$core/scripts/lib/ui.sh"

out="" branch=develop plan=false not_moved="docker,sunshine,catalyst-node,catalyst-panel"
declare -A src=([recipes]=https://github.com/hobnix/recipes.git [extensions]=https://github.com/hobnix/extensions.git [capabilities]=https://github.com/hobnix/capabilities.git)
while [ $# -gt 0 ]; do
  case $1 in
    --recipes|--extensions|--capabilities) k=${1#--}; shift; src[$k]=${1:-} ;;
    --branch) shift; branch=${1:-} ;;
    --not-moved) shift; not_moved=${1:-} ;;
    --plan) plan=true ;;
    -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) fail "Unknown argument: $1 (see --help)" ;;
    *) [ -z "$out" ] || fail "Only one output directory."; out=$1 ;;
  esac
  shift
done
[ -n "$out" ] || fail "Name the output directory: merge-package-repos.sh <out dir> (see --help)."
[ -n "$branch" ] || fail "--branch wants a name."
[ ! -e "$out" ] || fail "$(t '%s exists already: this script never writes into an existing directory.' "$out")"
for k in recipes extensions capabilities; do [ -n "${src[$k]}" ] || fail "--$k wants a URL or a directory."; done
for k in "${!src[@]}"; do
  # a relative directory means the one beside the caller, not the output repository
  [ ! -d "${src[$k]}" ] || src[$k]=$(cd "${src[$k]}" && pwd)
done
git config user.name >/dev/null 2>&1 && git config user.email >/dev/null 2>&1 || [ -n "${GIT_AUTHOR_NAME:-}" ] || fail "Set user.name and user.email of git first: the merge commits need an identity."
[ -f "$core/LICENSE" ] || fail "There is no LICENSE in $core."
python3 - "$not_moved" <<'EOF' || fail "--not-moved wants package names separated by commas."
import re, sys
sys.exit(0 if all(re.fullmatch(r"[a-z0-9][a-z0-9-]*", n) for n in sys.argv[1].split(",") if n) else 1)
EOF
IFS=, read -r -a skip <<<"$not_moved"
is_skipped() { local n; for n in "${skip[@]}"; do [ "$n" = "$1" ] && return 0; done; return 1; }

order=(recipes extensions capabilities)
step "Plan"
for k in "${order[@]}"; do kv "$k" "${src[$k]} ($branch)"; done
kv "Output" "$out"
kv "Not moved" "${not_moved:--}"
note "Nothing is pushed, no remote is added, the sources are only read."
$plan && exit 0

created=false
cleanup_failed() { $created && [ -d "$out" ] && rm -rf "$out"; }
die() { cleanup_failed; fail "$*"; }
git_o() { git -C "$out" -c commit.gpgsign=false "$@"; }   # signing off: a commit per source would ask for the key each time
mkdir -p "$out" || fail "Could not make $out."
created=true
git_o init -q -b develop || die "git init failed."
# the clone is private to the script: no hook of the user's template may run
git_o config core.hooksPath /dev/null

step "Fetch"
declare -A tip=()
for k in "${order[@]}"; do
  git_o fetch -q "${src[$k]}" "refs/heads/$branch:refs/import/$k" 2>/dev/null || die "$(t 'Could not fetch %s of %s.' "$branch" "${src[$k]}")"
  tip[$k]=$(git_o rev-parse "refs/import/$k")
  ok "$k ${tip[$k]:0:10}"
done

git_o commit -q -s --allow-empty -m "Start of hobnix/official: the histories of recipes, extensions and capabilities are merged into this one" || die "The first commit failed."

# take <source> <path>: the files of <path> from the source tip, refused when one exists here with other content
take() {
  local k=$1 p=$2 f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [ -e "$out/$f" ]; then die "$(t '%s of %s collides with %s that is in the result already.' "$f" "$k" "$f")"; fi
  done < <(git_o ls-tree -r --name-only "${tip[$k]}" -- "$p")
  git_o checkout -q "${tip[$k]}" -- "$p" || die "$(t 'Could not take %s of %s.' "$p" "$k")"
}

skipped=""
for k in "${order[@]}"; do
  step "$(t 'Merge %s' "$k")"
  git_o merge -q -s ours --no-commit --allow-unrelated-histories "refs/import/$k" >/dev/null 2>&1 || die "$(t 'The merge of %s failed.' "$k")"
  while IFS= read -r top; do
    case $top in
      recipes|extensions|capabilities|blueprints|scripts|rust-toolchain.toml)
        take "$k" "$top"
        if [ "$top" = recipes ] || [ "$top" = extensions ] || [ "$top" = capabilities ] || [ "$top" = blueprints ]; then
          for n in "${skip[@]}"; do
            [ -n "$n" ] && [ -d "$out/$top/$n" ] && { git_o rm -rqf -- "$top/$n" && skipped="$skipped $top/$n"; }
          done
        fi ;;
      examples)
        while IFS= read -r e; do
          [ -n "$e" ] || continue
          take "$k" "examples/$e"
          if [ "$k" = capabilities ] && [ "$e" = example ]; then
            [ ! -e "$out/examples/capability" ] || die "examples/capability exists already."
            git_o mv "examples/example" "examples/capability" || die "Could not rename examples/example."
          fi
        done < <(git_o ls-tree --name-only "${tip[$k]}" -- examples/ | sed 's#^examples/##') ;;
      tests)
        while IFS= read -r f; do
          [ -n "$f" ] || continue
          take "$k" "$f"
          [ "$f" != tests/run-all.sh ] || git_o mv tests/run-all.sh "tests/run-$k.sh" || die "Could not keep tests/run-all.sh of $k."
        done < <(git_o ls-tree -r --name-only "${tip[$k]}" -- tests) ;;
    esac
  done < <(git_o ls-tree --name-only "${tip[$k]}")
  if [ "$k" = recipes ] && git_o cat-file -e "${tip[$k]}:LICENSE" 2>/dev/null; then
    mkdir -p "$out/recipes" && git_o show "${tip[$k]}:LICENSE" > "$out/recipes/LICENSE" && git_o add recipes/LICENSE || die "Could not keep the licence of recipes."
  fi
  git_o commit -q -s -m "Import hobnix/$k $branch (${tip[$k]:0:10}) into the layout of hobnix/official" || die "$(t 'The commit of %s failed.' "$k")"
  ok "$(t '%s: %s commit(s) joined' "$k" "$(git_o rev-list --count "${tip[$k]}")")"
done

step "Root files"
{
  printf 'publish = "index"\n'
  for k in "${order[@]}"; do
    git_o cat-file -e "${tip[$k]}:index.toml" 2>/dev/null || continue
    printf '\n'
    git_o show "${tip[$k]}:index.toml" | awk -v skip="$not_moved" '
      BEGIN { n = split(skip, a, ","); for (i = 1; i <= n; i++) bad[a[i]] = 1 }
      /^\[/ { on = 1; drop = 0; h = $0
        if (h ~ /^\[package\./) { sub(/^\[package\./, "", h); sub(/[].].*$/, "", h); drop = (h in bad) } }
      on && !drop { print }'
  done
} > "$out/index.toml"
dups=$(grep -o '^\[package\.[^]]*\]' "$out/index.toml" | sort | uniq -d | paste -sd' ' -)
[ -z "$dups" ] || die "$(t 'A package name is in two of the repositories: %s' "$dups")"
cp "$core/LICENSE" "$out/LICENSE"
cat > "$out/README.md" <<'EOF'
# hobnix/official

The packages of the Hobnix server that its team maintains, in one repository: recipes (apps), extensions and capabilities. The `kind` in
each `package.toml` tells them apart, the folder says the same: `recipes/`, `extensions/`, `capabilities/`, `blueprints/`.

Servers read the signed `index.json` that is built from `main`; `develop` is where the work happens. A release is the merge of `develop` into
`main`, there are no tags.

Licence: AGPL-3.0 (`LICENSE`) for everything except `recipes/`, which is MIT (`recipes/LICENSE`). The extensions were MIT before this
repository existed: copies that were released stay MIT.

This tree was built by `scripts/dev/merge-package-repos.sh` of hobnix/core from the histories of hobnix/recipes, hobnix/extensions and
hobnix/capabilities, which stay in the history unchanged.
EOF
mkdir -p "$out/tests"
{
  printf '#!/usr/bin/env bash\n# Runs the tests of the three repositories this one was merged from (HS_CORE: the checkout of hobnix/core).\n'
  printf 'set -uo pipefail\nhere=$(cd "$(dirname "$0")" && pwd)\nrc=0\n'
  for k in "${order[@]}"; do
    [ ! -f "$out/tests/run-$k.sh" ] || printf 'bash "$here/run-%s.sh" || rc=1\n' "$k"
  done
  printf 'exit "$rc"\n'
} > "$out/tests/run-all.sh"
chmod +x "$out/tests/run-all.sh"
git_o add index.toml LICENSE README.md tests/run-all.sh || die "git add failed."
git_o commit -q -s -m "hobnix/official: index.toml, README, LICENSE and tests/run-all.sh of the merged repository" || die "The commit of the root files failed."
ok "index.toml, README.md, LICENSE, tests/run-all.sh"

git_o for-each-ref --format='%(refname)' refs/import | while IFS= read -r r; do git_o update-ref -d "$r"; done
git_o config --unset core.hooksPath

step "Check"
for k in "${order[@]}"; do
  git_o merge-base --is-ancestor "${tip[$k]}" HEAD || die "$(t '%s is not in the history of the result.' "$k")"
done
ok "$(t 'All three tips are ancestors of the result (%s commits)' "$(git_o rev-list --count HEAD)")"
rc_log=$(mktemp)
if python3 -I "$core/scripts/pkg.py" repo-check "$out" >"$rc_log" 2>&1; then
  ok "pkg.py repo-check passes"
else
  warn "pkg.py repo-check reports problems (fix them in the new repository before the first push):"
  head -n 12 "$rc_log" | trail
fi
rm -f "$rc_log"

step "Result"
kv "Repository" "$out"
kv "Branch" "develop ($(git_o rev-parse --short HEAD))"
kv "Packages" "$(grep -c '^\[package\.' "$out/index.toml")"
[ -z "$skipped" ] || kv "Left out" "${skipped# }"
note "Not pushed. Next: add the scaffold (.github/, CONTRIBUTING.md, SECURITY.md) and push by hand."
