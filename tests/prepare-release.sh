#!/usr/bin/env bash
# scripts/dev/prepare-release.sh: the level of each changed package from the bump labels of its pull requests (none = patch, the highest wins),
# the tag level, a pull request with two labels refused, nothing changed since the tag refused, and the branch with one bump commit per package.
# The labels come from a file (HS_PREPARE_LABELS), a local bare repository stands in for GitHub.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
have git || { skip "needs git"; finish; exit 0; }
export HS_LANG=en HS_PLAIN=1
PR="bash $SCRIPTS/dev/prepare-release.sh"
git init -q --bare "$WORK/remote.git"
R=$WORK/repo; mkdir -p "$R"; cd "$R" || exit 1
git init -q -b develop . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
git remote add origin "$WORK/remote.git"
mkpkg() { mkdir -p "extensions/$1"; printf 'name = "%s"\nversion = "%s"\nkind = "extension"\ntitle = "T"\nrequires_core = ">=1"\n' "$1" "$2" > "extensions/$1/package.toml"
  printf '[package.%s]\nversion = "%s"\nkind = "extension"\npath = "extensions/%s"\nrequires_core = ">=1"\n' "$1" "$2" "$1" >> index.toml; }
mkpkg alpha 1.0.0; mkpkg beta 2.3.4; mkpkg gamma 0.1.0
git add -A && git commit -q -m first && git tag v1.0.0
touch "$WORK/labels"; export HS_PREPARE_LABELS=$WORK/labels
change() { echo "$2" >> "extensions/$1/note.txt"; git add -A && git commit -q -m "$1 $2"; git rev-parse HEAD; }
plan() { $PR --plan 2>&1; }

echo "-- plan"
check_out "nothing changed since the tag" "nothing to release" plan
a=$(change alpha one); b=$(change beta one); change beta two >/dev/null; c=$(change gamma one)
printf '%s\tbump: minor\n%s\tbump: major\n' "$a" "$c" > "$WORK/labels"
out=$(plan)
check_eq "no label is patch" "beta	2.3.4	2.3.5	patch" "$(grep '^beta' <<<"$out")"
check_eq "minor" "alpha	1.0.0	1.1.0	minor" "$(grep '^alpha' <<<"$out")"
check_eq "major" "gamma	0.1.0	1.0.0	major" "$(grep '^gamma' <<<"$out")"
check_eq "the tag level is the highest" "tag	major" "$(grep '^tag' <<<"$out")"
printf '%s\tbump: minor\n' "$b" >> "$WORK/labels"
check_eq "the highest label of a package's pull requests wins" "beta	2.3.4	2.4.0	minor" "$(plan | grep '^beta')"
printf '%s\tbump: major\n' "$b" >> "$WORK/labels"
check_out "two bump labels on one pull request are refused" "more than one bump label" plan

echo "-- the branch"
printf '%s\tbump: minor\n%s\tbump: major\n' "$a" "$c" > "$WORK/labels"
check_out "off develop is refused" "Switch to develop" bash -c "git checkout -q -b feature/x; $PR 2>&1; git checkout -q develop; true"
check_out "it makes the branch" "Branch release/prepare-.* made" bash -c "$PR --no-push 2>&1"
git checkout -q "$(git branch --list 'release/prepare-*' | tr -d ' *' | head -n1)"
check_eq "alpha was raised" 'version = "1.1.0"' "$(grep '^version' extensions/alpha/package.toml)"
check_eq "and index.toml agrees" 'version = "1.1.0"' "$(awk '/^\[package.alpha\]/{f=1;next} /^\[/{f=0} f&&/^version/' index.toml)"
check_eq "gamma is 1.0.0" 'version = "1.0.0"' "$(grep '^version' extensions/gamma/package.toml)"
check_eq "one commit per package" "3" "$(git rev-list --count develop..HEAD)"
finish
