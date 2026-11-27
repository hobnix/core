#!/usr/bin/env bash
# Automatic app updates (scripts/apps-autoupdate.sh, app_autoupdate.py, docs/PLAN-app-lifecycle.md step 13, #470): hidden, off by default.
# Stand-ins (all executable): incus, hs pkg, manage-ct (snapshot/restore), hs recipe, the health read and the push message.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
have python3 || { skip "needs python3"; finish; exit 0; }
tab=$'\t'
export HS_LANG=en HS_PLAIN=1 HS_STATE_DIR=$WORK/state HS_SETTINGS_DIR=$WORK/state/settings HS_RECIPES_DIR=$WORK/recipes HS_INCUS=$WORK/incus
export HS_PKG_CMD=$WORK/pkg HS_MANAGE_CT=$WORK/ct HS_RECIPE_CMD=$WORK/recipe HS_HEALTH_CMD=$WORK/health HS_NOTIFY_CMD=$WORK/notify HS_AUTOUPDATE_WAIT=0
mkdir -p "$HS_STATE_DIR/apps" "$HS_STATE_DIR/packages" "$HS_SETTINGS_DIR" "$HS_RECIPES_DIR"
CALLS=$WORK/calls.log; : > "$CALLS"; NOTES=$WORK/notes.log; : > "$NOTES"
apps="good bad maj added"
for a in $apps; do
  mkdir -p "$HS_RECIPES_DIR/$a"
  printf '#!/usr/bin/env bash\n# kind: generic\n# recipe: %s: a test app\nct=${RECIPE_NAME:-%s}\necho x\n' "$a" "$a" > "$HS_RECIPES_DIR/$a/run.sh"
  printf 'name = "%s"\nversion = "1.0.0"\nkind = "recipe"\ntitle = "%s"\napp_version = "1.0.0"\n[app]\n[app.version]\nsource = "exec"\ncommand = ["v"]\n' "$a" "$a" > "$HS_RECIPES_DIR/$a/package.toml"
  printf 'app = "%s"\npolicy = "automatic"\n' "$a" > "$HS_STATE_DIR/apps/$a.toml"
  echo 1.0.0 > "$WORK/run-$a"
  printf '1.1.0' > "$WORK/new-$a"
done
printf '2.0.0' > "$WORK/new-maj"
cat > "$HS_STATE_DIR/packages/installed.toml" <<'F'
[package.good]
version = "1.0.0"
repo = "official"
[package.bad]
version = "1.0.0"
repo = "official"
[package.maj]
version = "1.0.0"
repo = "official"
[package.added]
version = "1.0.0"
repo = "mine"
F
cat > "$WORK/incus" <<F
#!/usr/bin/env bash
case "\$1 \$2" in
  "list -f") case "\$*" in *"-c n4"*) printf 'good,"10.0.0.5 (eth0)"\n' ;; *) printf 'good\nbad\nmaj\nadded\n' ;; esac ;;
  "exec "*) cat "$WORK/run-\$2" ;;
  *) exit 1 ;;
esac
F
cat > "$WORK/pkg" <<F
#!/usr/bin/env bash
echo "pkg \$*" >> "$CALLS"
case "\$1" in
  fetch|rollback) exit 0 ;;
  market) for a in $apps; do v=\$(cat "$WORK/new-\$a"); r=official; [ \$a = added ] && r=mine; printf '%s\trecipe\t%s\t%s\t1.0.0\tupdate\tno\tgeneric\t%s\n' \$a \$r "\$v" \$a; done
          # the same name in an added repository: since #933 that row does not carry the installed copy, and it is never the update
          printf 'good\trecipe\tmine\t9.0.0\t-\tnew\tno\tgeneric\tgood\n' ;;
  show) v=\$(cat "$WORK/new-\$2"); r=official; [ "\$2" = added ] && r=mine; printf 'status\tok\nname\t%s\nrepo\t%s\nversion\t%s\napp_version\t%s\n' "\$2" \$r "\$v" "\$v" ;;
  update) case "\$*" in *--yes*) exit 0 ;; esac; cat "$WORK/diff-\$2" 2>/dev/null; exit 1 ;;
esac
F
printf '#!/usr/bin/env bash\necho "ct $*" >> "%s"\n' "$CALLS" > "$WORK/ct"
printf '#!/usr/bin/env bash\necho "recipe $*" >> "%s"\n' "$CALLS" > "$WORK/recipe"
printf '#!/usr/bin/env bash\nprintf "good\thealthy\nbad\tunhealthy\nmaj\thealthy\nadded\thealthy\n"\n' > "$WORK/health"
printf '#!/usr/bin/env bash\necho "$*" >> "%s"\n' "$NOTES" > "$WORK/notify"
chmod +x "$WORK/incus" "$WORK/pkg" "$WORK/ct" "$WORK/recipe" "$WORK/health" "$WORK/notify"
A="bash $SCRIPTS/apps-autoupdate.sh"
calls() { grep -c "$1" "$CALLS" || true; }

# the switch is off (the default): nothing runs, whatever the time
HS_AUTOUPDATE_NOW=03:30 $A >/dev/null 2>&1
check_eq "switch off: no call at all" 0 "$(wc -l < "$CALLS" | tr -d ' ')"
rc=0; bash "$SCRIPTS/apps-version.sh" policy good automatic >/dev/null 2>&1 || rc=$?
rm -f "$HS_SETTINGS_DIR/appsAutoupdateEnabled"
check_eq "switch off: hs apps policy automatic is refused" 1 "$rc"

echo true > "$HS_SETTINGS_DIR/appsAutoupdateEnabled"
rc=0; bash "$SCRIPTS/apps-version.sh" policy good automatic >/dev/null 2>&1 || rc=$?
check_eq "switch on: hs apps policy automatic is accepted" 0 "$rc"
check "the record says automatic" grep -q '^policy = "automatic"' "$HS_STATE_DIR/apps/good.toml"

# outside the quiet window: nothing runs
HS_AUTOUPDATE_NOW=12:00 $A >/dev/null 2>&1
check_eq "outside the window: no call at all" 0 "$(wc -l < "$CALLS" | tr -d ' ')"
echo "22:00-02:00" > "$HS_SETTINGS_DIR/appsAutoupdateWindow"
HS_AUTOUPDATE_NOW=03:30 $A >/dev/null 2>&1
check_eq "a window that passes midnight: 03:30 is outside" 0 "$(wc -l < "$CALLS" | tr -d ' ')"
rm -f "$HS_SETTINGS_DIR/appsAutoupdateWindow"

# inside the window
HS_AUTOUPDATE_NOW=03:30 $A >/dev/null 2>&1
check "good: snapshotted first" grep -q "^ct good --snapshot autoupdate-" "$CALLS"
check "good: package updated" grep -q "^pkg update good --yes" "$CALLS"
check "good: recipe run" grep -q "^recipe good\$" "$CALLS"
check_eq "good: never restored" 0 "$(calls 'ct good --restore')"
check "bad: snapshotted" grep -q "^ct bad --snapshot" "$CALLS"
check "bad: restored after the failed health check" grep -q "^ct bad --restore autoupdate-" "$CALLS"
check "bad: previous package copy put back" grep -q "^pkg rollback bad" "$CALLS"
check_eq "bad: the policy is notify again" 'policy = "notify"' "$(grep '^policy' "$HS_STATE_DIR/apps/bad.toml")"
check_eq "a major version is not applied: no snapshot" 0 "$(calls 'ct maj')"
check_eq "a major version is not applied: no recipe" 0 "$(calls 'recipe maj')"
check_eq "an added repository is skipped: no snapshot" 0 "$(calls 'ct added')"
check_eq "an added repository is skipped: no update" 0 "$(calls 'update added')"
check_eq "one message for the failure, one for the major" 2 "$(wc -l < "$NOTES" | tr -d ' ')"
check_eq "the failure message came once" 1 "$(grep -c 'bad .* did not work' "$NOTES" || true)"

# the next night: bad is on notify, maj is still automatic and stays quiet, no repeat
: > "$CALLS"
HS_AUTOUPDATE_NOW=04:00 $A >/dev/null 2>&1
check_eq "no repeat message" 2 "$(wc -l < "$NOTES" | tr -d ' ')"
check_eq "bad is not tried again" 0 "$(calls 'bad')"
# put bad back on automatic: the same failed version is not announced twice
printf 'app = "bad"\npolicy = "automatic"\n' > "$HS_STATE_DIR/apps/bad.toml"
HS_AUTOUPDATE_NOW=04:00 $A >/dev/null 2>&1
check_eq "the same failure is not announced again" 2 "$(wc -l < "$NOTES" | tr -d ' ')"

# a diff that touches the commands is not applied
printf 'diff --git a/recipes/good/commands.tsv b/recipes/good/commands.tsv\n+x\n' > "$WORK/diff-good"
echo 1.0.0 > "$WORK/run-good"; printf '1.2.0' > "$WORK/new-good"; : > "$CALLS"
printf 'app = "good"\npolicy = "automatic"\n' > "$HS_STATE_DIR/apps/good.toml"
HS_AUTOUPDATE_NOW=04:00 $A >/dev/null 2>&1
check_eq "a changed commands.tsv is not applied automatically" 0 "$(calls 'ct good')"
check_eq "... and says so once" 1 "$(grep -c 'good 1.2.0 is not applied automatically' "$NOTES" || true)"
finish
