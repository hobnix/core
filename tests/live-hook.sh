#!/usr/bin/env bash
# The live-state hooks: the dispatcher (scripts/lib/hs.sh) asks the collector for the group of a `changes` row after any exit code (HS_LIVE_LOG records
# the call instead of the count), a failed change asks too (rule 8 of docs/adr/0005-events.md), a read asks for nothing; live_refresh counts the topics up in the state database (the collector wakes on it, no socket).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
wp() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else echo "$1"; fi; }
T=$'\t'
cat > "$WORK/ok.sh" <<'S'
#!/usr/bin/env bash
echo "ran $*"
S
cat > "$WORK/fail.sh" <<'S'
#!/usr/bin/env bash
exit 3
S
printf 'user%szok%s%s/ok.sh%s-%s-%s-%stopic:disks,changes\n' "$T" "$T" "$WORK" "$T" "$T" "$T" "$T" > "$WORK/reg.tsv"
printf 'user%szfail%s%s/fail.sh%s-%s-%s-%stopic:disks,changes\n' "$T" "$T" "$WORK" "$T" "$T" "$T" "$T" >> "$WORK/reg.tsv"
printf 'user%szplain%s%s/ok.sh%s-%s-%s-%schanges\n' "$T" "$T" "$WORK" "$T" "$T" "$T" "$T" >> "$WORK/reg.tsv"
printf 'user%sext zz go%s%s/ok.sh%s-%s-%s-%stopic:system,changes
' "$T" "$T" "$WORK" "$T" "$T" "$T" "$T" >> "$WORK/reg.tsv"
printf 'user%szmulti%s%s/ok.sh%s-%s-%s-%stopic:system,topic:instances,changes
' "$T" "$T" "$WORK" "$T" "$T" "$T" "$T" >> "$WORK/reg.tsv"
printf 'user%szread%s%s/ok.sh%s-%s-%s-%stopic:disks,reads\n' "$T" "$T" "$WORK" "$T" "$T" "$T" "$T" >> "$WORK/reg.tsv"
export HS_REGISTRY=$(wp "$WORK/reg.tsv") HS_LIVE_LOG=$(wp "$WORK/live.log") HS_PLAIN=1 HS_LANG=en HS_CALLER=test
HS="bash $SCRIPTS/lib/hs.sh"
: > "$WORK/live.log"
out=$($HS zok a b); check_eq "a change: the script's output stays" "ran a b" "$out"
check_eq "a change that succeeds asks for its group" "@disks" "$(cat "$WORK/live.log")"
: > "$WORK/live.log"; $HS zfail >/dev/null 2>&1; rc=$?
check_eq "a failed change keeps its exit code" "3" "$rc"
check_eq "...and still asks for its group (rule 8)" "@disks" "$(cat "$WORK/live.log")"
: > "$WORK/live.log"; $HS zplain >/dev/null; check_eq "a change without topic: asks for @system" "@system" "$(cat "$WORK/live.log")"
: > "$WORK/live.log"; $HS zmulti >/dev/null; check_eq "a row with two topic: words asks for both groups" "@system @instances" "$(cat "$WORK/live.log")"
: > "$WORK/live.log"; $HS zread >/dev/null
check_eq "a read asks for nothing" "0" "$(grep -c . "$WORK/live.log")"

: > "$WORK/live.log"; $HS ext zz go >/dev/null 2>&1
check_eq "an extension change also asks for @ext-<name>" "@system,@ext-zz" "$(paste -sd, "$WORK/live.log")"

echo "-- hooks outside the dispatcher ask for their topics (the scripts run with HS_LIVE_LOG)"
mkdir -p "$WORK/fb"
printf '#!/usr/bin/env bash
exit 0
' > "$WORK/fb/systemctl"; cp "$WORK/fb/systemctl" "$WORK/fb/ok"; chmod +x "$WORK/fb/systemctl" "$WORK/fb/ok"
: > "$WORK/live.log"
HS_UPS_CONF=$(wp "$WORK/ups.conf") HS_NOTIFY="$WORK/fb/ok" HS_SYSTEMCTL="$WORK/fb/systemctl" NOTIFYTYPE=ONLINE bash "$SCRIPTS/ups.sh" event "UPS online" >/dev/null 2>&1
check_eq "ups.sh event asks for ups, deck, status" "ups deck status" "$(cat "$WORK/live.log")"
: > "$WORK/live.log"
PATH="$WORK/fb:$PATH" bash "$SCRIPTS/jobs.sh" stop hs-job-x.service >/dev/null 2>&1
check_eq "jobs.sh stop asks for @jobs" "@jobs" "$(cat "$WORK/live.log")"
: > "$WORK/live.log"
PATH="$WORK/fb:$PATH" bash "$SCRIPTS/jobs.sh" stop >/dev/null 2>&1
check_eq "jobs.sh stop without a unit asks for nothing" "0" "$(grep -c . "$WORK/live.log")"
# these need git, root or a whole health run: the call is checked in the text
hook() { grep -E "^ *(trap .*|[^#]*)live_refresh $2" "$SCRIPTS/$1" >/dev/null 2>&1 && echo yes || echo no; }
check_eq "health-check.sh refreshes the health topics" "yes" "$(hook health-check.sh 'health-next health-list status deck')"
check_eq "update.sh refreshes system-updates after the pull" "yes" "$(hook update.sh 'system-updates')"
check_eq "update-preview.sh refreshes system-updates after the fetch" "yes" "$(hook update-preview.sh 'system-updates')"
check_eq "pkg.sh refreshes the package topics after a fetch" "yes" "$(hook pkg.sh 'pkg-market pkg-states apps-list apps-health pkg-repos recipes-list recipes-versions parts-list')"
check_eq "...and after install, remove, update and repo add|remove (pkg_changed; six: rollback changes the installed copy too)" "6" "$(grep -cE 'pkg_changed(;|$)' "$SCRIPTS/pkg.sh")"
mkdir -p "$WORK/pkgstate"
: > "$WORK/live.log"
HS_STATE_DIR=$(wp "$WORK/pkgstate") bash "$SCRIPTS/pkg.sh" repo remove nope >/dev/null 2>&1
check_eq "pkg.sh repo remove that fails asks for nothing" "0" "$(grep -c . "$WORK/live.log")"
: > "$WORK/live.log"
HS_STATE_DIR=$(wp "$WORK/pkgstate") bash "$SCRIPTS/pkg.sh" fetch nope >/dev/null 2>&1; rc=$?
check_eq "pkg.sh fetch nope exits 0" "0" "$rc"
check_eq "...and asks for the package topics" "pkg-market pkg-states apps-list apps-health pkg-repos recipes-list recipes-versions parts-list" "$(cat "$WORK/live.log")"
: > "$WORK/live.log"
HS_STATE_DIR=$(wp "$WORK/pkgstate") bash "$SCRIPTS/pkg.sh" --repos >/dev/null 2>&1; HS_STATE_DIR=$(wp "$WORK/pkgstate") bash "$SCRIPTS/pkg.sh" --market >/dev/null 2>&1
check_eq "the pkg reads ask for nothing" "0" "$(grep -c . "$WORK/live.log")"

echo "-- the real registry rows of the network reads' changes reach the dispatcher hook (script swapped for a stub, capability flags dropped)"
for w in "net setup" "gateway acme-token" "dns clean" "services apply" "ct add" "remote add" "config set" "rebuild"; do
  awk -F'	' -v w="$w" -v s="$WORK/ok.sh" -v OFS='	' '$1=="user" && $2==w { n=split($NF, a, ","); f=""; for (i=1;i<=n;i++) if (a[i]=="changes" || a[i] ~ /^topic:/) f=f (f==""?"":",") a[i]; $3=s; $NF=f; print }' "$SCRIPTS/lib/registry.tsv" >> "$WORK/real.tsv"
done
check_eq "all eight real rows were found" "8" "$(grep -c . "$WORK/real.tsv")"
for w in "net setup:@network" "gateway acme-token:@network" "dns clean:@network" "services apply:@network" "ct add:@instances" "remote add:@shares" "config set:@system" "rebuild:@system"; do
  : > "$WORK/live.log"
  HS_REGISTRY=$(wp "$WORK/real.tsv") bash "$SCRIPTS/lib/hs.sh" ${w%%:*} x >/dev/null 2>&1
  check_eq "hs ${w%%:*} asks for ${w##*:}" "${w##*:}" "$(cat "$WORK/live.log")"
done

echo "-- the real registry rows of the identity and backup reads' changes reach the dispatcher hook"
: > "$WORK/real2.tsv"
for w in "user add" "user <user> unlock" "user flush" "group <group> remove" "backup now" "backup init" "backup offsite" "backup drill" "backup <share> on" "backup ct <ct> on" "dc cert install" "vault header-backup"; do
  awk -F'	' -v w="$w" -v s="$WORK/ok.sh" -v OFS='	' '$1=="user" && $2==w { n=split($NF, a, ","); f=""; for (i=1;i<=n;i++) if (a[i]=="changes" || a[i] ~ /^topic:/) f=f (f==""?"":",") a[i]; $3=s; $NF=f; print }' "$SCRIPTS/lib/registry.tsv" >> "$WORK/real2.tsv"
done
check_eq "all twelve real rows were found" "12" "$(grep -c . "$WORK/real2.tsv")"
for w in "user add:@users" "user bob unlock:@users" "user flush:@users" "group g remove:@users" "backup now:@backup" "backup init:@backup" "backup offsite:@backup" "backup drill:@backup" "backup docs on:@backup" "backup ct web on:@backup" "dc cert install:@users" "vault header-backup:@security"; do
  : > "$WORK/live.log"
  HS_REGISTRY=$(wp "$WORK/real2.tsv") bash "$SCRIPTS/lib/hs.sh" ${w%%:*} >/dev/null 2>&1
  check_eq "hs ${w%%:*} asks for ${w##*:}" "${w##*:}" "$(cat "$WORK/live.log")"
done
check_eq "the backup timers (backup, drill, drill ct) refresh @backup after a run" "3" "$(grep -c 'live.sh refresh @backup' "$SCRIPTS/../capabilities/backup/module.nix")"
check_eq "disk-event.sh asks for the named event disk.<plugged|removed>" "yes" "$(grep -q 'refresh "event:disk\.' "$SCRIPTS/disk-event.sh" && echo yes || echo no)"
check_eq "...and event-topics.tsv lists backup-state for both (backup disk plugged or removed)" "2" "$(grep -E '^disk\.(plugged|removed)'"$T" "$SCRIPTS/lib/event-topics.tsv" | grep -c backup-state)"

echo "-- live_refresh counts the topics up in the state database (no Redis, no socket)"
if command -v python3 >/dev/null; then
  mkdir -p "$WORK/cnt"
  export HS_STATE_DB=$(wp "$WORK/cnt/state.db") HS_STATE_DIR=$(wp "$WORK/cnt")
  env -u HS_LIVE_LOG bash -c '. "$1/lib/live.sh"; live_refresh status ct-list; live_refresh status' _ "$SCRIPTS"; rc=$?
  check_eq "live_refresh returns 0" "0" "$rc"
  got=$(python3 - "$HS_STATE_DB" <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
print(",".join("%s=%d" % r for r in c.execute("SELECT topic, gen FROM topics ORDER BY topic")))
PY
)
  check_eq "each call counts its topics one up" "ct-list=1,status=2" "$got"
  : > "$WORK/live.log"
else skip "python3 missing"; fi
finish
