#!/usr/bin/env bash
# Prepares a release of a package repository (hobnix/recipes, hobnix/extensions, hobnix/capabilities; hobnix/server#615): nobody raises a package
# version by hand. Run it INSIDE the checkout, on `develop`; the workflow `prepare-release` does exactly this.
#
#   bash <core>/scripts/dev/prepare-release.sh [--plan] [--no-push]
#       Finds the package folders (recipes/, extensions/, capabilities/, blueprints/) that changed since the newest vX.Y.Z tag, takes the highest bump label (`bump: major`, `bump: minor`, none =
#       patch; `bump: none` = no bump: a package whose merged pull requests are all `bump: none` stays as it is, with no [meta] changes) of the merged pull requests that touched each one, raises `version` in package.toml and index.toml (release.sh bump), runs
#       `pkg.py repo-check`, pushes the branch release/prepare-<date> and opens a pull request into develop with the list
#       "package: old -> new" and the tag level (the highest bump of the release, the input of the release workflow). The release pull
#       request develop -> main (merge commit) follows once that one is merged.
#       --plan prints "package<TAB>old<TAB>new<TAB>level" and the tag level and changes nothing.
#       A repository that publishes a signed index (`publish = "index"` at the top of index.toml, hobnix/official) has no tags: the
#       reference is origin/main (HS_RELEASE_REMOTE replaces origin) and no tag level is printed or put in the pull request. A pull request with both bump labels is refused.
#
#       Each bumped package also gets `[meta] changes` = the titles of the merged pull requests that touched it (scripts/dev/release-changes.py cleans
#       them: titles are untrusted text); no pull request found leaves the field alone. The owner edits the text in the release pull request.
#
# Where the labels come from: `gh api repos/<repo>/commits/<sha>/pulls`; HS_PREPARE_LABELS=<file> (lines "<sha><TAB><label>") replaces that in tests; HS_PREPARE_TITLES=<file> (JSON lines {sha, number, title}) replaces the pull request titles.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
core=$(cd "$here/../.." && pwd)
export HS_LANG=${HS_LANG:-en}
# shellcheck source=scripts/lib/ui.sh
. "$core/scripts/lib/ui.sh"
plan=false push=true
while [ $# -gt 0 ]; do
  case $1 in
    --plan) plan=true ;;
    --no-push) push=false ;;
    -h|--help) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) fail "Unknown argument: $1 (see --help)" ;;
  esac
  shift
done

git rev-parse --show-toplevel >/dev/null 2>&1 || fail "Run this inside the checkout of a package repository."
cd "$(git rev-parse --show-toplevel)" || exit 1
[ -f index.toml ] || fail "There is no index.toml here: this is not a package repository."
# every folder that holds packages: hobnix/official has several of them
dirs=()
for d in recipes extensions capabilities blueprints; do [ -d "$d" ] && dirs+=("$d"); done
[ ${#dirs[@]} -gt 0 ] || fail "None of recipes/, extensions/, capabilities/, blueprints/ is here."
repo="${dirs[*]}"
$plan || [ "$(git branch --show-current)" = develop ] || fail "Switch to develop first: a release is prepared from develop."
[ -z "$(git status --porcelain)" ] || fail "The tree has uncommitted changes."

# A repository that publishes a signed index (`publish = "index"` at the top of index.toml, hobnix/official) has no tags: the reference is what
# main holds, and there is no tag level.
index_repo=false
awk '/^\[/ { exit } /^publish[[:space:]]*=[[:space:]]*"index"/ { found = 1 } END { exit !found }' index.toml && index_repo=true
if $index_repo; then
  last=${HS_RELEASE_REMOTE:-origin}/main
  git rev-parse -q --verify "$last" >/dev/null || fail "There is no $last: git fetch first."
else
  last=$(git tag -l 'v[0-9]*' --sort=-v:refname | head -n1)
  [ -n "$last" ] || fail "There is no tag yet: the first release keeps the versions as they are. Use release.sh --version vX.Y.Z."
fi
range=$last..HEAD

labels_of() {   # labels_of <sha>: the bump labels of the pull requests that brought the commit in, one per line
  if [ -n "${HS_PREPARE_LABELS:-}" ]; then awk -F'\t' -v s="$1" '$1 == s { print $2 }' "$HS_PREPARE_LABELS"; return 0; fi
  local out
  out=$(gh api "repos/{owner}/{repo}/commits/$1/pulls" --jq '.[].labels[].name') || fail "gh api failed for commit ${1:0:7} (login, rate limit?): without the labels a bump: major would be lost."
  grep '^bump: ' <<<"$out" || true
}
prs_of() {   # prs_of <sha>: the merged pull requests of the commit as JSON lines {"number","title"}; empty (and a note) when they cannot be read
  if [ -n "${HS_PREPARE_TITLES:-}" ]; then
    python3 -I -c 'import json,sys
for l in open(sys.argv[2], encoding="utf-8"):
    try: o = json.loads(l)
    except ValueError: continue
    if isinstance(o, dict) and o.get("sha") == sys.argv[1] and o.get("base", "develop") == "develop": print(json.dumps({"number": o.get("number"), "title": o.get("title")}))' "$1" "$HS_PREPARE_TITLES"
    return 0
  fi
  gh api "repos/{owner}/{repo}/commits/$1/pulls" --jq '.[] | select(.merged_at != null and .base.ref == "develop") | {number, title}' 2>/dev/null || note "The pull requests of commit ${1:0:7} could not be read: [meta] changes stays as it is." >&2
  return 0
}
rank() { case $1 in major) echo 2 ;; minor) echo 1 ;; *) echo 0 ;; esac; }

declare -A level=()
bad="" skipped=0
prdir=$(mktemp -d) || fail "No temporary folder."
trap 'rm -rf "$prdir"' EXIT
for sha in $(git rev-list --reverse "$range" -- "${dirs[@]}"); do
  labs=$(labels_of "$sha" | sort -u)
  prs=$(prs_of "$sha")
  case $(printf '%s\n' "$labs" | grep -c '^bump: ') in 0|1) ;; *) bad="$bad ${sha:0:7}" ;; esac
  l=patch
  grep -qx 'bump: none' <<<"$labs" && l=none
  grep -qx 'bump: minor' <<<"$labs" && l=minor
  grep -qx 'bump: major' <<<"$labs" && l=major
  for dir in $(git diff-tree -m --no-commit-id --name-only -r "$sha" -- "${dirs[@]}" | sed -n 's#^\([^/]*/[^/]*\)/.*#\1#p' | sort -u); do
    [ -f "$dir/package.toml" ] || continue
    # `bump: none` (a comment, a doc): no bump and no title from this pull request; another pull request of the package still decides
    [ "$l" != none ] || { skipped=$((skipped + 1)); continue; }
    [ "$(rank "$l")" -ge "$(rank "${level[$dir]:-patch}")" ] && level[$dir]=$l
    # the titles go to a file per package (never argv): release-changes.py cleans them
    [ -z "$prs" ] || printf '%s\n' "$prs" >> "$prdir/${dir#*/}.jsonl"
  done
done
[ -z "$bad" ] || fail "Pull requests with more than one bump label ($bad ): leave one label and run this again."
[ ${#level[@]} -gt 0 ] || [ "$skipped" -eq 0 ] || fail "Every change since $last is labelled bump: none: there is nothing to release."
[ ${#level[@]} -gt 0 ] || fail "No package changed since $last: there is nothing to release."

bump_next() {   # bump_next <x.y.z> <level>
  local a b c; IFS=. read -r a b c <<<"$1"
  case $2 in major) echo "$((a + 1)).0.0" ;; minor) echo "$a.$((b + 1)).0" ;; *) echo "$a.$b.$((c + 1))" ;; esac
}
top=patch rows=""
for dir in $(printf '%s\n' "${!level[@]}" | sort -t/ -k2); do
  pkg=${dir#*/}
  old=$(sed -n 's/^version = "\(.*\)"$/\1/p' "$dir/package.toml" | head -n1)
  # a package whose version was already raised since the tag keeps it: nothing is raised twice
  if [ "$(git show "$last:$dir/package.toml" 2>/dev/null | sed -n 's/^version = "\(.*\)"$/\1/p' | head -n1)" != "$old" ]; then continue; fi
  rows="$rows$pkg	$old	$(bump_next "$old" "${level[$dir]}")	${level[$dir]}
"
  [ "$(rank "${level[$dir]}")" -le "$(rank "$top")" ] || top=${level[$dir]}
done
[ -n "$rows" ] || fail "Every changed package has a new version already."
if $plan; then printf '%s' "$rows"; $index_repo || echo "tag	$top"; exit 0; fi

if $index_repo; then step "Prepare the release ($repo, against $last)"; else step "Prepare the release ($repo, tag level $top)"; fi
branch=release/prepare-$(date -u +%Y%m%d-%H%M)
git checkout -q -b "$branch" || fail "Could not make the branch $branch."
body="Raises the versions of the packages that changed since $last."
$index_repo || body="$body Tag level for the release workflow: **$top**."
body="$body
"
while IFS=$'\t' read -r pkg old new lv; do
  [ -n "$pkg" ] || continue
  bash "$here/release.sh" bump "$pkg" "$lv" --no-push >/dev/null || fail "release.sh bump $pkg failed; the branch $branch holds what was done."
  ok "$pkg: $old -> $new ($lv)"
  # [meta] changes from the titles of the merged pull requests, into the bump commit; no pull request found keeps the field
  if [ -s "$prdir/$pkg.jsonl" ]; then
    pdir=$(ls -d ./*/"$pkg" 2>/dev/null | head -n1)
    res=$(python3 -I "$here/release-changes.py" "$pdir/package.toml" < "$prdir/$pkg.jsonl") || { warn "$pkg: [meta] changes was not written (see above); the old text stays, edit it by hand."; res=kept; }
    if [ "$res" = written ] && ! git diff --quiet -- "$pdir/package.toml"; then
      git add -- "$pdir/package.toml" && git commit -q --amend --no-edit || fail "Could not commit [meta] changes of $pkg."
    fi
  fi
  body="$body
- $pkg: $old -> $new"
done <<<"$rows"
python3 -I "$core/scripts/pkg.py" repo-check . >/dev/null 2>&1 || fail "repo-check fails after the bumps; the branch $branch holds them."
$push || { note "$(t 'Branch %s made, not pushed' "$branch")"; exit 0; }
git push -q -u "${HS_RELEASE_REMOTE:-origin}" "$branch" || fail "The push failed."
command -v gh >/dev/null 2>&1 || fail "gh is not installed: open the pull request $branch -> develop by hand."
gh pr create --base develop --head "$branch" --title "Prepare release: $(printf '%s' "$rows" | cut -f1 | paste -sd, | sed 's/,/, /g')" --body "$body" || fail "gh could not open the pull request."
