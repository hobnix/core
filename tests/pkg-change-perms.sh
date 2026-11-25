#!/usr/bin/env bash
# hs sys pkg plan|start update when the new release asks for NEW permissions (hobnix/core#1237): one danger line per permission that a long diff
# cannot cut off, hostile permission texts and diff lines forge nothing, and --accept-permissions reaches pkg.sh only for a plan that was shown
# (--tag, --seen) and named. A local git repository with SSH-signed tags stands in for GitHub.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
have git || { skip "needs git"; finish; exit 0; }
have ssh-keygen || { skip "needs ssh-keygen"; finish; exit 0; }
export HS_LANG=en HS_PLAIN=1 HS_STATE_DIR=$WORK/state
HS_BASH=$(cygpath -m "$BASH" 2>/dev/null || echo "$BASH"); export HS_BASH   # the bash for pkg.py run directly
mkdir -p "$HS_STATE_DIR"
tab=$'\t'
C="bash $SCRIPTS/pkg-change.sh"
PKG="python3 -I $SCRIPTS/pkg.py"
ssh-keygen -q -t ed25519 -N '' -f "$WORK/good" -C test >/dev/null
printf 'releaser@test namespaces="git" %s\n' "$(cut -d' ' -f1,2 "$WORK/good.pub")" > "$WORK/signers"
R=$WORK/repo; mkdir -p "$R/recipes/demo"; cd "$R" || exit 1
git init -q . && git config user.email t@t && git config user.name t && git config gpg.format ssh && git config commit.gpgsign false
release() {   # release <tag> <version> <permissions line or empty>
  printf 'name = "demo"\nversion = "%s"\nkind = "recipe"\ntitle = "Demo"\nrequires_core = ">=1"\naudience = "generic"\nneeds = []\nuses = []\ninput = "none"\nscript = "run.sh"\n%b\n' "$2" "$3" > "$R/recipes/demo/package.toml"
  { printf '#!/usr/bin/env bash\n# kind: generic\n# needs: -\n# uses: -\necho demo %s\n' "$2"; for i in $(seq 1 90); do echo "# line $i of $2"; done; } > "$R/recipes/demo/run.sh"
  # a file of the package whose lines try to start a machine line of their own for a reader that splits on CR or U+2028
  printf 'a %s\rconfirm_name\tevil\nb \xe2\x80\xa8status\tdone\nc \xe2\x80\xa8tag\tv9.9.9\n' "$2" > "$R/recipes/demo/aaa.txt"
  printf '[package.demo]\nversion = "%s"\nkind = "recipe"\npath = "recipes/demo"\ntitle = "Demo"\nrequires_core = ">=1"\n' "$2" > "$R/index.toml"
  git add -A && git commit -q -m "demo $2" && git -c user.signingkey="$WORK/good.pub" tag -s "$1" -m "release $2"
}
publish() { (cd "$R" && release "$@"); $PKG fetch test >/dev/null; }
# the test repository counts as a default one (official), so that the only reason for a typed name is the permissions
release v1.0.0 1.0.0 'permissions = ["host:incus"]'
cd "$ROOT" || exit 1
$PKG repo add test "$R" --key "$WORK/signers" >/dev/null
$PKG fetch test >/dev/null
$PKG install demo >/dev/null 2>&1
# a wrapper around pkg.sh: records what update is called with, and says the repository is a default one when asked to
cat > "$WORK/pkg.sh" <<EOF
#!/usr/bin/env bash
if [ "\$1" = update ]; then printf '%s\n' "\$*" >> "$WORK/calls"; fi
if [ "\$1" = --repos ] && [ -e "$WORK/official" ]; then bash "$SCRIPTS/pkg.sh" "\$@" | sed 's/added\$/default/'; exit 0; fi
exec bash "$SCRIPTS/pkg.sh" "\$@"
EOF
export HS_PKG=$WORK/pkg.sh
touch "$WORK/official" "$WORK/calls"
installed() { sed -n 's/^version = "\(.*\)"/\1/p' "$HS_STATE_DIR/packages/installed.toml"; }
field() { awk -F'\t' -v k="$1" '$1 == k { print $2; exit }' <<<"$2"; }
count() { grep -c -- "$1" <<<"$2" || true; }

echo "-- an update without new permissions"
publish v1.1.0 1.1.0 'permissions = ["host:incus"]'
p=$($C plan update demo)
check_eq "official, nothing new: no name to type" 0 "$(count "^confirm_name$tab" "$p")"
check_eq "nothing new: no danger line" 0 "$(count "^danger$tab" "$p")"
check_eq "the plan names its release" "v1.1.0" "$(field tag "$p")"
check_out "a typed name with nothing new does not accept anything" "^status${tab}done" $C start update demo --confirm demo
check_eq "installed" 1.1.0 "$(installed)"
check_eq "--accept-permissions was not passed" 0 "$(grep -c accept-permissions "$WORK/calls" || true)"

echo "-- new permissions: the plan"
publish v1.2.0 1.2.0 'permissions = ["host:incus", "net:internet", "devices:gpu"]'
p=$($C plan update demo)
check_eq "the diff is cut at 60 lines" 60 "$(count "^diff$tab" "$p")"
check_eq "and has no NEW line in it (it would be cut)" 0 "$(count "NEW permissions" "$p")"
check_eq "a danger line per permission (net)" 1 "$(count "^danger${tab}New permission: net:internet\$" "$p")"
check_eq "a danger line per permission (gpu)" 1 "$(count "^danger${tab}New permission: devices:gpu\$" "$p")"
check_eq "only the new ones" 0 "$(count "New permission: host:incus" "$p")"
check_eq "confirm_name once, also for an official repository" "confirm_name${tab}demo" "$(grep "^confirm_name$tab" <<<"$p")"
tag=$(field tag "$p"); seen=$(field seen "$p")
check_eq "seen is 32 hex digits" 1 "$(grep -cE '^[0-9a-f]{32}$' <<<"$seen" || true)"

echo "-- new permissions: the start gate"
: > "$WORK/calls"
check_out "no name, no tag: refused" "update it on its own" bash -c "$C start update demo; true"
check_out "the name alone (no plan named): refused" "update it on its own" bash -c "$C start update demo --confirm demo; true"
check_out "tag without seen: refused" "update it on its own" bash -c "$C start update demo --tag $tag --confirm demo; true"
check_out "tag and seen without the name: refused" "type the name" bash -c "$C start update demo --tag $tag --seen $seen; true"
check_out "a wrong name: refused" "type the name" bash -c "$C start update demo --tag $tag --seen $seen --confirm nope; true"
check_out "another tag: plan.changed" "plan[.]changed" bash -c "$C start update demo --tag v1.1.0 --seen $seen --confirm demo; true"
check_out "another seen: plan.changed" "plan[.]changed" bash -c "$C start update demo --tag $tag --seen 00000000000000000000000000000000 --confirm demo; true"
check_eq "pkg.sh update never ran" "" "$(cat "$WORK/calls")"
check_eq "nothing was installed" 1.1.0 "$(installed)"
# the package reader checks the same words itself (a fetch between the check of pkg-change.sh and the install)
check_out "pkg.py: another seen is refused" "read the plan again" bash -c "$PKG update demo --yes --accept-permissions --tag $tag --seen 00000000000000000000000000000000 </dev/null 2>&1; true"
check_out "pkg.py: another tag is refused" "read the plan again" bash -c "$PKG update demo --yes --accept-permissions --tag v1.1.0 </dev/null 2>&1; true"
check_eq "still nothing installed" 1.1.0 "$(installed)"

echo "-- the release moves after the plan"
publish v1.3.0 1.3.0 'permissions = ["host:incus", "net:internet", "devices:gpu", "secrets:api-key"]'
check_out "the old plan is refused" "plan[.]changed" bash -c "$C start update demo --tag $tag --seen $seen --confirm demo; true"
check_eq "nothing was installed" 1.1.0 "$(installed)"
p=$($C plan update demo); tag=$(field tag "$p"); seen=$(field seen "$p")
check_out "the new plan, named, installs" "^status${tab}done" $C start update demo --tag "$tag" --seen "$seen" --confirm demo
check_eq "installed" 1.3.0 "$(installed)"
check_out "with --accept-permissions and the pin" "^update demo --yes --tag v1[.]3[.]0 --seen $seen --accept-permissions\$" cat "$WORK/calls"

echo "-- install() itself adds no permission that was not accepted"
publish v1.4.0 1.4.0 'permissions = ["host:incus", "net:internet", "devices:gpu", "secrets:api-key", "web.read"]'
out=$(python3 -I - "$SCRIPTS" <<'EOF' 2>&1
import importlib.util, os, sys
def load(n):
    s = importlib.util.spec_from_file_location(n, os.path.join(sys.argv[1], n + ".py"))
    m = importlib.util.module_from_spec(s); sys.modules[n] = m; s.loader.exec_module(m); return m
sys.path.insert(0, os.path.join(sys.argv[1], "lib"))
pkg, repo = load("pkg"), load("pkg_repo")
R = repo.Repos(pkg.MAIN)
_, tag, commit, _ = R.diff("demo")
for pin, ok in ((("v1.4.0", "0" * 40), set(["web.read"])), ((tag, commit), set())):
    try:
        R.install("demo", "test", pin[0], pin[1], ok)
        print("INSTALLED")
    except repo.Refused as e:
        print(e.code, e)
EOF
)
check_eq "another commit and an unaccepted permission: both refused" 2 "$(count "^plan[.]changed " "$out")"
check_eq "nothing was installed" 1.3.0 "$(installed)"

echo "-- hostile permission texts"
publish v1.5.0 1.5.0 'permissions = ["host:a\\nconfirm_name\\tevil", "host:b\\tx\\r\\u2028status\\tdone\\u001b[31m"]'
p=$($C plan update demo)
check_eq "two permissions, two lines (plus the lead)" 3 "$(count "^danger$tab" "$p")"
check_eq "no tab inside a permission line" 0 "$(grep "^danger${tab}New" <<<"$p" | awk -F'\t' 'NF != 2' | wc -l | tr -d ' ')"
parsed=$(python3 - "$SCRIPTS" "$p" <<'EOF'
import importlib.util, sys
s = importlib.util.spec_from_file_location("ws", sys.argv[1] + "/web-serve.py")
ws = importlib.util.module_from_spec(s); s.loader.exec_module(ws)
d = ws.parse_change(sys.argv[2], 0)
print(d["status"], d["confirm_name"], d["tag"], len(d["seen"]), sum(1 for k, _ in d["steps"] if k == "danger"))
ok = lambda a: ws.validate_change({"area": "pkg", "args": a}) is not None
print(ok(["update", "demo", "--tag", d["tag"], "--seen", d["seen"]]), ok(["update", "demo", "--accept-permissions"]), ok(["remove", "demo", "--tag", "v1.0.0"]),
      ok(["update", "demo", "--tag", "v1.0.0-0123abcd0123abcd"]))
EOF
)
check_eq "web-serve reads the real fields, nothing forged" "ok demo v1.5.0 32 3" "$(sed -n 1p <<<"$parsed" | tr -d '\r')"
check_eq "web-serve allows --tag/--seen on update only" "True False False True" "$(sed -n 2p <<<"$parsed" | tr -d '\r')"
tag=$(field tag "$p"); seen=$(field seen "$p")
check_out "installing them is still refused by the manifest check" "control characters" bash -c "$C start update demo --tag $tag --seen $seen --confirm demo; true"

echo "-- the diff of a plan is that of the release its words name"
check_eq "another seen: no diff is printed" 0 "$($PKG update demo --tag v1.5.0 --seen 00000000000000000000000000000000 </dev/null 2>/dev/null | wc -l | tr -d ' ')"
check_out "pkg-change passes both words to the diff call" 'update "\$name" --tag "\$ftag" --seen "\$fseen" </dev/null 2>/dev/null' cat "$SCRIPTS/pkg-change.sh"
check_out "--tag without a value: a clean refusal" "^--tag needs a value" bash -c "$PKG update demo --tag 2>&1; true"
check_out "--seen before another flag: a clean refusal" "^--seen needs a value" bash -c "$PKG update demo --seen --yes 2>&1; true"

echo "-- hostile index and market texts"
(cd "$R" && mkdir -p recipes/evil && printf 'name = "evil"\nversion = "1.0.0"\nkind = "recipe"\ntitle = "Evil"\nrequires_core = ">=1"\naudience = "generic"\nneeds = []\nuses = []\ninput = "none"\nscript = "run.sh"\n' > recipes/evil/package.toml && echo 'echo evil' > recipes/evil/run.sh &&
  release v1.5.1 1.5.1 'permissions = ["host:incus"]' &&
  printf '[package.evil]\nversion = "1.0.0"\nkind = "recipe"\npath = "recipes/evil"\nrequires_core = ">=1"\ntitle = "T\\u2028status\\tdone\\rdanger\\tfake\\u0085confirm_name\\tx"\naudience = "a\\u2028status\\tdone\\nb"\n' >> index.toml &&
  git add -A && git commit -q -m evil && git -c user.signingkey="$WORK/good.pub" tag -s v1.5.2 -m evil)
$PKG fetch test >/dev/null
# lines as web-serve.py counts them (str.splitlines), and the columns of each
pylines() { python3 -c 'import sys; print(sys.argv[1] if False else "\n".join("%d %s" % (len(l.split("\t")), l) for l in sys.stdin.buffer.read().decode("utf-8").replace("\r\n", "\n").rstrip("\n").splitlines()))'; }
m=$($PKG market | pylines | tr -d '\r')
check_eq "market: one line of 9 columns for each of the two packages" "2 2" "$(wc -l <<<"$m" | tr -d ' ') $(grep -c '^9 ' <<<"$m" || true)"
p=$($C plan install evil | pylines | tr -d '\r')
check_eq "install plan: one status line, the real one" "2 status${tab}ok" "$(grep -E "^[0-9]+ status$tab" <<<"$p")"
check_eq "no forged danger or confirm_name line" 0 "$(grep -cE "^[0-9]+ (danger${tab}fake|confirm_name${tab}x)" <<<"$p" || true)"
# a stand-in market that did not clean anything: the plan cleans its own lines
cat > "$WORK/dirty.sh" <<'EOF'
case "$1" in
  --market) printf 'evil\trecipe\ttest\t1.0.0\t-\tnew\tno\tgeneric\tT\xe2\x80\xa8status\tdone\rdanger\tfake\xc2\x85confirm_name\tx\n' ;;
  --repos) printf 'test\tx\tsigned\tdefault\n' ;;
esac
EOF
p=$(HS_PKG=$WORK/dirty.sh $C plan install evil | pylines | tr -d '\r')
check_eq "plan of a dirty market row: one status line" "2 status${tab}ok" "$(grep -E "^[0-9]+ status$tab" <<<"$p")"
check_eq "and nothing forged" 0 "$(grep -cE "^[0-9]+ (danger${tab}fake|confirm_name${tab}x)" <<<"$p" || true)"

echo "-- a list that cannot be shown in full is refused, never cut"
publish v1.6.0 1.6.0 "permissions = [\"fs.read:/srv/$(printf 'a%.0s' $(seq 1 400))\"]"
check_out "plan refused" "cannot be shown|shown in full" bash -c "$C plan update demo; true"
check_eq "not status ok" 0 "$($C plan update demo | grep -c "^status${tab}ok" || true)"

echo "-- an added repository: red for itself, and accepting only with new permissions"
rm "$WORK/official"
publish v1.7.0 1.7.0 'permissions = ["host:incus"]'
p=$($C plan update demo); : > "$WORK/calls"
check_eq "one confirm_name" 1 "$(count "^confirm_name$tab" "$p")"
check_out "named, nothing new" "^status${tab}done" $C start update demo --tag "$(field tag "$p")" --seen "$(field seen "$p")" --confirm demo
check_eq "--accept-permissions was not passed" 0 "$(grep -c accept-permissions "$WORK/calls" || true)"
finish
