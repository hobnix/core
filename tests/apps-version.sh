#!/usr/bin/env bash
# hs sys apps versions|policy, plan update and the weekly summary (scripts/apps-version.sh, app_version.py, docs/PLAN-app-lifecycle.md step 12, #470).
# Stand-ins: incus (list and exec), the image tag, hs recipe --check and the push message; recipes are fixtures with [app.version].
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
have python3 || { skip "needs python3"; finish; exit 0; }
tab=$'\t'
export HS_LANG=en HS_PLAIN=1 HS_STATE_DIR=$WORK/state HS_RECIPES_DIR=$WORK/recipes HS_INCUS=$WORK/incus
mkdir -p "$HS_STATE_DIR/apps" "$HS_RECIPES_DIR"
mk() {   # mk <name> <offered> <[app.version] body>
  mkdir -p "$HS_RECIPES_DIR/$1"
  printf '#!/usr/bin/env bash\n# kind: generic\n# recipe: %s: a test app\nct=${RECIPE_NAME:-%s}\necho x\n' "$1" "$1" > "$HS_RECIPES_DIR/$1/run.sh"
  printf 'name = "%s"\nversion = "1.0.0"\nkind = "recipe"\ntitle = "%s"\napp_version = "%s"\n[app]\n[app.version]\n%s\n' "$1" "$1" "$2" "$3" > "$HS_RECIPES_DIR/$1/package.toml"
}
mk demo 2.4.0 'source = "exec"
command = ["demo-version"]'
mk img 1.5.0 'source = "image-tag"'
mk bad 3.0.0 'source = "exec"
command = ["nope"]'
mk pin 5.0.0 'source = "exec"
command = ["pin-version"]'
mk gone 1.0 'source = "exec"
command = ["x"]'
cat > "$WORK/incus" <<'F'
#!/usr/bin/env bash
case "$1 $2" in
  "list -f") case "$*" in *"-c n4"*) printf 'demo,"10.0.0.5 (eth0)"\n' ;; *) printf 'demo\nimg\nbad\npin\n' ;; esac ;;
  "exec demo") echo 2.3.4 ;;
  "exec pin") echo 9.9.9 ;;
  *) exit 1 ;;
esac
F
printf '#!/usr/bin/env bash\n[ "$1" = img ] && echo 1.5.0\n' > "$WORK/tag.sh"
chmod +x "$WORK/incus" "$WORK/tag.sh"
export HS_APP_IMAGE_TAG_CMD=$WORK/tag.sh
printf 'app = "pin"\n\n[[created]]\nkind = "container"\nid = "pin"\ndetail = "container"\nat = "2026-01-01T00:00:00Z"\n' > "$HS_STATE_DIR/apps/pin.toml"
cp "$HS_STATE_DIR/apps/pin.toml" "$WORK/pin.before"
V="bash $SCRIPTS/apps-version.sh"

out=$($V --list 2>&1)
row() { awk -F'\t' -v n="$1" '$1 == n' <<<"$out"; }
check_eq "exec source: running, offered, package, update" "demo${tab}demo${tab}1.0.0${tab}2.4.0${tab}2.3.4${tab}notify${tab}update" "$(row demo)"
check_eq "image-tag source reads the tag, current" "img${tab}img${tab}1.0.0${tab}1.5.0${tab}1.5.0${tab}notify${tab}current" "$(row img)"
check_eq "a failing source is - and current" "bad${tab}bad${tab}1.0.0${tab}3.0.0${tab}-${tab}notify${tab}current" "$(row bad)"
check_eq "a recipe that is not installed has no row" "" "$(row gone)"
check_eq "no empty field" 0 "$(awk -F'\t' '{for(i=1;i<=NF;i++) if($i=="") n++} END{print n+0}' <<<"$out")"

# policy
check_eq "the default policy is notify" notify "$($V policy demo)"
rc=0; $V policy demo pinned >/dev/null 2>&1 || rc=$?
check_eq "policy pinned is written" "0 pinned" "$rc $($V policy demo)"
check "the record names the app and the policy" grep -q '^policy = "pinned"' "$HS_STATE_DIR/apps/demo.toml"
$V policy demo notify; check_eq "back to notify" notify "$($V policy demo)"
rc=0; $V policy demo automatic >/dev/null 2>&1 || rc=$?
check_eq "automatic is refused" 1 "$rc"
rc=0; $V policy nosuch pinned >/dev/null 2>&1 || rc=$?
check_eq "an unknown instance is refused" 1 "$rc"
rc=0; $V policy pin pinned >/dev/null 2>&1 || rc=$?
check_eq "state pinned for a pinned app" "pin${tab}pin${tab}1.0.0${tab}5.0.0${tab}9.9.9${tab}pinned${tab}pinned" "$($V --list | awk -F'\t' '$1=="pin"')"
check_eq "the [[created]] blocks stay byte for byte" "$(sed -n '/^\[\[created\]\]/,$p' "$WORK/pin.before")" "$(sed -n '/^\[\[created\]\]/,$p' "$HS_STATE_DIR/apps/pin.toml")"
check_eq "the top of the record keeps app and gets the policy" 'app = "pin"|policy = "pinned"' "$(sed -n '1,/^\[\[created\]\]/p' "$HS_STATE_DIR/apps/pin.toml" | grep -v '^$' | grep -v '^\[\[' | paste -sd'|')"

rc=0; $V policy docker pinned >/dev/null 2>&1 || rc=$?
check_eq "policy for the docker host is refused" 1 "$rc"
out=$(HS_LIVE_LOG=$WORK/live.log bash "$SCRIPTS/apps-policy.sh" pin 2>&1)
if grep -q "pinned" <<<"$out"; then pass "hs apps policy shows the policy through ui.sh"; else fail "apps-policy show: $out"; fi
HS_LIVE_LOG=$WORK/live.log bash "$SCRIPTS/apps-policy.sh" img pinned >/dev/null 2>&1; bash "$SCRIPTS/apps-version.sh" policy img notify
check "a policy write asks for an apps-list refresh" grep -q "apps-list" "$WORK/live.log"

# summary: the notify app with an update is named, the pinned one is not
printf '#!/usr/bin/env bash\nprintf "%%s\n" "$*" >> %s/notify.log\n' "$WORK" > "$WORK/notify.sh"; chmod +x "$WORK/notify.sh"
HS_NOTIFY_CMD=$WORK/notify.sh $V --summary
if grep -q "demo" "$WORK/notify.log" && ! grep -q "pin" "$WORK/notify.log"; then pass "the summary names demo and not the pinned app"; else fail "summary: $(cat "$WORK/notify.log" 2>&1)"; fi
check_eq "one message" 1 "$(wc -l < "$WORK/notify.log")"
$V policy demo pinned; rm -f "$WORK/notify.log"
HS_NOTIFY_CMD=$WORK/notify.sh $V --summary
check "nothing to say, nothing sent" test ! -e "$WORK/notify.log"
$V policy demo notify

# plan update
printf '#!/usr/bin/env bash\ncase "$2" in --check) printf "would update   image (1.0 -> 1.1)\ncurrent        config (2)\n" ;; esac\n' > "$WORK/recipe-check.sh"
printf '#!/usr/bin/env bash\necho "current        config (2)"\n' > "$WORK/recipe-current.sh"
chmod +x "$WORK/recipe-check.sh" "$WORK/recipe-current.sh"
rc=0; out=$(HS_RECIPE_CMD="bash $WORK/recipe-check.sh" $V plan update demo 2>&1) || rc=$?
check_eq "plan update: exit 0" 0 "$rc"
has() { grep -Eq "$1" <<<"$out"; }
has "^status${tab}ok" && has "^piece${tab}image${tab}1.0${tab}1.1" && has "^app${tab}2.3.4 -> 2.4.0" && has "^policy${tab}notify" && has "^package_version${tab}" && has "^step${tab}" \
  && pass "plan update lists the piece, the versions and the policy" || fail "plan: $out"
has "starting an update from here comes later" && pass "no start is offered yet" || fail "no start note: $out"
rc=0; out=$(HS_RECIPE_CMD="bash $WORK/recipe-current.sh" $V plan update demo 2>&1) || rc=$?
has "^note${tab}nothing to update" && ! has "^piece" && pass "current: nothing to update" || fail "current: $out"
$V policy demo pinned
out=$(HS_RECIPE_CMD="bash $WORK/recipe-check.sh" $V plan update demo 2>&1)
has "^note${tab}this app is pinned: the update runs only if you start it yourself" && has "^policy${tab}pinned" && pass "pinned: said in the plan" || fail "pinned: $out"
rc=0; out=$($V plan update gone 2>&1) || rc=$?
if [ "$rc" = 1 ] && has "^status${tab}refused"; then pass "not installed: refused"; else fail "gone: $out"; fi
rc=0; out=$($V plan update nosuch 2>&1) || rc=$?
check_eq "unknown app: refused" 1 "$rc"
check "plan wrote nothing new" test ! -e "$HS_STATE_DIR/apps/gone.toml"

# http-json: a fake app answers on 127.0.0.1
if have python3; then
  port=$(free_port)
  mkdir -p "$WORK/www"; printf '{"info":{"version":"7.8.9"}}' > "$WORK/www/v.json"
  python3 -m http.server "$port" --bind 127.0.0.1 -d "$WORK/www" >/dev/null 2>&1 &
  srv=$!; sleep 1
  mk web 7.8.10 "source = \"http-json\"
path = \"/v.json\"
pointer = \"/info/version\""
  printf '[app.health]\ncheck = "http"\nport = %s\n' "$port" >> "$HS_RECIPES_DIR/web/package.toml"
  # the [app.health] table must come before [app.version] is not needed: both are children of [app]
  printf '#!/usr/bin/env bash\ncase "$1 $2" in "list -f") printf "web\n" ;; *) exit 1 ;; esac\n' > "$WORK/incus"
  got=$(HS_APP_HEALTH_HOST=127.0.0.1 $V --list | awk -F'\t' '$1=="web"')
  kill "$srv" 2>/dev/null || true
  check_eq "http-json reads the pointer" "web${tab}web${tab}1.0.0${tab}7.8.10${tab}7.8.9${tab}notify${tab}update" "$got"
fi
finish
