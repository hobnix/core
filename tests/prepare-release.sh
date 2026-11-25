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
mkpkg() { mkdir -p "extensions/$1"; printf 'name = "%s"\nversion = "%s"\nkind = "extension"\ntitle = "T"\nrequires_core = ">=1"\npermissions = []\n' "$1" "$2" > "extensions/$1/package.toml"
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

echo "-- a repository that publishes an index: no tags, the reference is origin/main"
git init -q --bare "$WORK/remote2.git"
R2=$WORK/repo2; mkdir -p "$R2"; cd "$R2" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
git remote add origin "$WORK/remote2.git"
printf 'publish = "index"

' > index.toml
mkpkg alpha 1.0.0; mkpkg beta 2.3.4
git add -A && git commit -q -m first && git push -q origin main && git checkout -q -b develop
check_out "nothing newer than origin/main" "nothing to release" plan
a=$(change alpha one); change beta one >/dev/null
printf '%s	bump: minor
' "$a" > "$WORK/labels"
out=$(plan)
check_eq "the bump level comes from the labels as before" "alpha	1.0.0	1.1.0	minor" "$(grep '^alpha' <<<"$out")"
check_eq "and no tag level is printed" "0" "$(grep -c '^tag' <<<"$out")"
check_out "the branch names origin/main, not a tag" "against origin/main" bash -c "$PR --no-push 2>&1"

echo "-- several package folders in one repository (hobnix/official): a package is bumped in whichever folder it is"
git checkout -q develop
mkdir -p recipes/rec; printf 'name = "rec"\nversion = "1.0.0"\nkind = "recipe"\ntitle = "T"\nrequires_core = ">=1"\npermissions = []\n' > recipes/rec/package.toml
printf '[package.rec]\nversion = "1.0.0"\nkind = "recipe"\npath = "recipes/rec"\nrequires_core = ">=1"\n' >> index.toml
git add -A && git commit -q -m rec && git push -q origin develop:main && git fetch -q origin
echo one > recipes/rec/note.txt; git add -A && git commit -q -m "rec one"
change alpha three >/dev/null
out=$(plan)
check_eq "the recipe is planned" "rec	1.0.0	1.0.1	patch" "$(grep '^rec' <<<"$out")"
check_eq "and the extension beside it" "alpha" "$(grep '^alpha' <<<"$out" | cut -f1)"
git for-each-ref --format='%(refname:short)' 'refs/heads/release/*' | xargs -r git branch -D -q
check_out "it makes the branch" "Branch release/prepare-.* made" bash -c "$PR --no-push 2>&1"
git checkout -q "$(git for-each-ref --format='%(refname:short)' 'refs/heads/release/*' | head -n1)"
check_eq "both folders were raised" "2" "$(git diff --name-only develop HEAD | grep -cE '^(extensions/alpha|recipes/rec)/package[.]toml$')"

echo "-- [meta] changes from the titles of the merged pull requests (hostile titles included)"
git init -q --bare "$WORK/remote3.git"
R3=$WORK/repo3; mkdir -p "$R3"; cd "$R3" || exit 1
git init -q -b develop . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
git remote add origin "$WORK/remote3.git"
mkpkg alpha 1.0.0; mkpkg beta 2.3.4; mkpkg gamma 0.1.0; mkpkg delta 0.2.0
printf '[meta]\nauthor = "A"\nchanges = "old text"\ntags = ["t"]\n' >> extensions/delta/package.toml
mkpkg eps 0.3.0; mkpkg zeta 0.4.0; mkpkg eta 0.5.0; mkpkg theta 0.6.0
printf '[meta]\r\nauthor = "A"\r\n' >> extensions/eps/package.toml
printf '  [meta]\n  author = "A"\n' >> extensions/zeta/package.toml
printf 'meta = { author = "A", changes = "old inline" }\n' >> extensions/eta/package.toml
printf '[meta]\nauthor = "A"\nbuilt = 2020-01-02\n' >> extensions/theta/package.toml
git add -A && git commit -q -m first && git tag v1.0.0
x=$(change alpha one)
echo two >> extensions/alpha/note.txt; echo two >> extensions/beta/note.txt; git add -A && git commit -q -m both; y=$(git rev-parse HEAD)
z=$(change beta three); change gamma one >/dev/null; d=$(change delta one)
e=$(change eps one); zz=$(change zeta one); h=$(change eta one); th=$(change theta one)
: > "$WORK/labels"
python3 -I - "$x" "$y" "$z" "$d" "$e" "$zz" "$h" "$th" > "$WORK/titles" <<'PY'
import json, sys
x, y, z, d, e, zz, h, th = sys.argv[1:]
hostile = 'evil"\nchanges = "pwned"\n[web]\nx=1 @octocat   \u0085 \x1b[31m `code` [link](http://e) \\ end'
rows = [(x, 1, hostile), (x, 1, hostile), (y, 2, "Add the shared thing"), (z, 3, "Fix beta"), (d, 4, "@everyone " + "x" * 400)]
rows += [(z, n, "many %d" % n) for n in range(10, 40)]
rows += [(e, 5, "Crlf title"), (zz, 6, "Indented title"), (h, 7, "Inline title"), (th, 8, "Date title"), (x, 9, "Entities &commat;x &#64;y")]
rows.append((x, 99, "Back merge of main"))
for sha, n, t in rows:
    print(json.dumps({"sha": sha, "number": n, "title": t, "base": "main" if n == 99 else "develop"}))
PY
export HS_PREPARE_TITLES=$WORK/titles
check_out "it makes the branch" "Branch release/prepare-.* made" bash -c "$PR --no-push 2>&1"
git checkout -q "$(git for-each-ref --format='%(refname:short)' 'refs/heads/release/*' | head -n1)"
meta() { python3 -I -c 'import sys,tomllib; d=tomllib.load(open(sys.argv[1],"rb")); print(d.get("meta",{}).get(sys.argv[2],"-"))' "extensions/$1/package.toml" "$2"; }
a=$(meta alpha changes)
check_out "alpha lists the title that touched alpha and beta" "Add the shared thing" echo "$a"
check_eq "the hostile title adds no key and no table" "name,version,kind,title,requires_core,permissions,meta" "$(python3 -I -c 'import tomllib; print(",".join(tomllib.load(open("extensions/alpha/package.toml","rb"))))')"
check_eq "no @, backtick, bracket, backslash, control or line separator is left" "0" "$(printf '%s' "$a" | python3 -I -c 'import sys,unicodedata; s=sys.stdin.read(); print(sum(1 for c in s if c in "@`[]\\<>" or (unicodedata.category(c)[0] in "CZ" and c != " ")))')"
check_eq "it is one line" "1" "$(grep -c '^changes = ' extensions/alpha/package.toml)"
check_eq "a pull request that came twice is listed once" "1" "$(grep -o 'evil' <<<"$a" | wc -l)"
check_eq "one commit per package still" "8" "$(git rev-list --count develop..HEAD)"
check_eq "a package of several pull requests lists them" "1" "$(meta beta changes | grep -c 'Add the shared thing; Fix beta')"
check_eq "the count is bounded" "1" "$(meta beta changes | grep -c 'and [0-9]* more')"
check_eq "the length is bounded" "ok" "$([ "$(meta beta changes | wc -c)" -le 1001 ] && [ "$(meta delta changes | wc -c)" -le 105 ] && echo ok)"
check_eq "a package without a pull request keeps the field" "-" "$(meta gamma changes)"
check_eq "an old changes value is replaced, the rest stays" "A|['t']" "$(meta delta author)|$(meta delta tags)"
check_eq "@everyone pings nobody" "0" "$(meta delta changes | grep -c '@')"
check_eq "a pull request into main is not listed" "0" "$(meta alpha changes | grep -c 'Back merge')"
check_eq "no HTML entity can be spelled" "0" "$(meta alpha changes | grep -cE '&[#a-z0-9]+;')"
check_eq "a CRLF file gets the line, one [meta], every line still CRLF" "Crlf title|1|0" "$(meta eps changes)|$(grep -c '^\[meta\]' extensions/eps/package.toml)|$(grep -vc $'\r$' extensions/eps/package.toml)"
check_eq "an indented [meta] header works" "Indented title" "$(meta zeta changes)"
check_eq "a date value does not crash it" "Date title" "$(meta theta changes)"
check_eq "an inline meta table keeps its text, the run goes on" "old inline" "$(meta eta changes)"
before=$(meta alpha changes)
grep -e "\"sha\": \"$x\"" -e "\"sha\": \"$y\"" "$WORK/titles" | grep -v "\"base\": \"main\"" | python3 -I -c 'import sys,json
for l in sys.stdin: o=json.loads(l); print(json.dumps({"number":o["number"],"title":o["title"]}))' > "$WORK/again"
python3 -I "$SCRIPTS/dev/release-changes.py" extensions/alpha/package.toml < "$WORK/again" >/dev/null
check_eq "the same input again writes the same text" "$before" "$(meta alpha changes)"

echo "-- bump: none"
git init -q --bare "$WORK/remote4.git"
R4=$WORK/repo4; mkdir -p "$R4"; cd "$R4" || exit 1
git init -q -b develop . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
git remote add origin "$WORK/remote4.git"
mkpkg alpha 1.0.0; mkpkg beta 2.3.4; mkpkg gamma 0.1.0; mkpkg delta 0.2.0
git add -A && git commit -q -m first && git tag v1.0.0
a1=$(change alpha one); a2=$(change alpha two)      # none + none
b1=$(change beta one); b2=$(change beta two)        # none + no label (patch)
g1=$(change gamma one); g2=$(change gamma two)      # none + minor
d1=$(change delta one)                              # only none, and the only change that is not alone
printf '%s\tbump: none\n%s\tbump: none\n%s\tbump: none\n%s\tbump: none\n%s\tbump: minor\n%s\tbump: none\n' "$a1" "$a2" "$b1" "$g1" "$g2" "$d1" > "$WORK/labels"
python3 -I - "$a1" "$b1" "$b2" > "$WORK/titles" <<'PY'
import json, sys
for sha, n, t in zip(sys.argv[1:], (1, 2, 3), ("Comment in alpha", "Comment in beta", "Real fix in beta")):
    print(json.dumps({"sha": sha, "number": n, "title": t, "base": "develop"}))
PY
export HS_PREPARE_TITLES=$WORK/titles
out=$(plan)
check_eq "only none pull requests: no bump" "0" "$(grep -c '^alpha' <<<"$out")"
check_eq "a package of only none pull requests is not planned at all" "0" "$(grep -c '^delta' <<<"$out")"
check_eq "none plus an unlabelled pull request is patch" "beta	2.3.4	2.3.5	patch" "$(grep '^beta' <<<"$out")"
check_eq "none plus minor is minor" "gamma	0.1.0	0.2.0	minor" "$(grep '^gamma' <<<"$out")"
check_out "the branch is made" "Branch release/prepare-.* made" bash -c "$PR --no-push 2>&1"
git checkout -q "$(git for-each-ref --format='%(refname:short)' 'refs/heads/release/*' | head -n1)"
check_eq "only the two bumped packages get a commit" "2" "$(git rev-list --count develop..HEAD)"
check_eq "alpha keeps its version and has no changes text" "1.0.0|0" "$(sed -n 's/^version = "\(.*\)"$/\1/p' extensions/alpha/package.toml)|$(grep -c '^changes' extensions/alpha/package.toml)"
check_eq "beta lists only the pull request that is not none" "1" "$(grep -c 'Real fix in beta' extensions/beta/package.toml)"
check_eq "and not the none one" "0" "$(grep -c 'Comment in beta' extensions/beta/package.toml)"
git checkout -q develop
for l in "$a1" "$a2" "$b1" "$b2" "$g1" "$g2" "$d1"; do printf '%s\tbump: none\n' "$l"; done > "$WORK/labels"
check_out "every change none: nothing to release" "nothing to release" plan
finish
