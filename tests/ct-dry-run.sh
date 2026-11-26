#!/usr/bin/env bash
# What a person types after `hs ct <name> ...` is never dropped (#1345: `hs ct <name> stop --dry-run` really stopped the instance).
# Every changing word is run through the REAL dispatcher and registry, with stand-ins for incus, unifi.sh and create-share.sh that
# log every call: --dry-run changes nothing, an unknown option is refused, --keep-off works, remove never skips the typed name.
# The last part checks every registry row with an argument template: it takes the extra words or the dispatcher refuses them.
# Needs jq, no root, no Incus.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
export HS_LANG=en HS_PLAIN=1 HS_CALLER=test HS_AUDIT_OFF=1 HS_LIVE_LOG=$WORK/live.log

if ! command -v jq >/dev/null 2>&1; then skip "jq is not installed: container tests not run"; finish; exit $?; fi

BIN=$WORK/bin; mkdir -p "$BIN"
export LOG=$WORK/calls.log
cp -r "$SCRIPTS" "$WORK/scripts"
cat > "$WORK/scripts/unifi.sh" <<'FAKE'
echo "unifi $*" >> "$LOG"
FAKE
cat > "$WORK/scripts/create-share.sh" <<'FAKE'
echo "create-share $*" >> "$LOG"
FAKE
cat > "$BIN/incus" <<'FAKE'
#!/usr/bin/env bash
echo "incus $*" >> "$LOG"
case "$1" in
  info) [ "$2" = web ] ;;
  query) case "$2" in
           */snapshots*) echo '[{"name":"s1","created_at":"2026-01-01T00:00:00Z"},{"name":"s2","created_at":"2026-01-02T00:00:00Z"}]' ;;
           *) echo '{"type":"container","config":{},"expanded_devices":{"eth0":{"hwaddr":"00:16:3e:00:00:01"}}}' ;;
         esac ;;
  storage) [ "$3" != show ] || exit 1 ;;
  config) case "$2 ${3:-}" in "device get") exit 1 ;; esac ;;
esac
FAKE
chmod +x "$BIN/incus"
export PATH=$BIN:$PATH
H="bash $WORK/scripts/lib/hs.sh"

# the calls that change something: everything the stand-ins logged, without the reading ones and without a dry run of unifi.sh
changed() {
  grep -Ev '^incus (info|query|list|config get|config device (get|show)|storage volume show)( |$)|^incus exec web -- sh -c command -v update$|^(unifi|create-share) .*--dry-run' "$LOG" || true
}
RC=0; OUT=""
run() { : > "$LOG"; RC=0; OUT=$($H "$@" 2>&1 </dev/null) || RC=$?; }
dry() {   # dry "what" <regex of the shown command> <hs words...>
  local what=$1 re=$2; shift 2
  run "$@" --dry-run
  if [ "$RC" = 0 ] && [ -z "$(changed)" ] && grep -Eq -- "$re" <<<"$OUT"; then pass "$what --dry-run shows the plan and changes nothing"
  else fail "$what --dry-run (exit $RC, changed: $(changed | tr '\n' ';') output: $(head -c 300 <<<"$OUT" | tr '\n' ' '))"; fi
}
refused() {   # refused "what" <hs words...>: a non-zero exit, a message, nothing changed
  local what=$1; shift
  run "$@"
  if [ "$RC" != 0 ] && [ -z "$(changed)" ] && [ -n "$OUT" ]; then pass "$what is refused and changes nothing"
  else fail "$what must be refused (exit $RC, changed: $(changed | tr '\n' ';'))"; fi
}

echo "-- --dry-run on every changing hs ct <name> command"
dry "start"          "incus start web"                       ct web start
dry "stop"           "incus stop web"                        ct web stop
dry "restart"        "incus restart web"                     ct web restart
dry "remove"         "incus delete -f web"                   ct web remove
dry "autostart on"   "incus config set web boot.autostart"   ct web autostart on
dry "autostart off"  "incus config unset web boot.autostart" ct web autostart off
dry "update"         "incus snapshot create web"             ct web update
dry "set"            "limits.memory=2048MiB"                 ct web set ram=2048
dry "set ip"         "incus restart web"                     ct web set ip=192.0.2.5
dry "restore"        "incus snapshot restore web s1"         ct web restore s1
dry "ip"             "incus restart web"                     ct web ip 192.0.2.5
dry "snapshot"       "incus snapshot create web lbl"         ct web snapshot lbl
dry "snapshot --create"  "incus snapshot create web"         ct web snapshot --create
dry "snapshot --restore" "incus snapshot restore web s2"     ct web snapshot --restore s2
dry "snapshot --delete"  "incus snapshot delete web s1"      ct web snapshot --delete s1
dry "edit"           "limits.memory=512MiB"                  ct web edit --ram 512
dry "storage"        "incus storage volume attach"           ct web storage --kind fast --name data --path /data -s fast
dry "storage add"    "incus storage volume attach"           ct web storage add fast data /data -s fast
dry "storage remove" "incus config device remove web data"   ct web storage remove data

echo "-- options that are honoured"
run ct web stop --keep-off
check_eq "stop --keep-off stops and takes the instance out of the boot start" "incus stop web
incus config unset web boot.autostart" "$(changed)"
run ct web stop --keep-off --dry-run
check_eq "stop --keep-off --dry-run changes nothing" "" "$(changed)"
check_match "stop --keep-off --dry-run shows both steps" "incus config unset web boot.autostart" "$OUT"
run ct web update --foreground --dry-run
check_eq "update --foreground is taken" "0" "$RC"
run ct web start
check_eq "a plain start still starts" "incus start web" "$(changed)"
run ct web autostart on
check_eq "a plain autostart still sets the key" "incus config set web boot.autostart=true" "$(changed)"

echo "-- an unknown or misspelled option is refused, never ignored"
for w in start stop restart remove update; do refused "$w --dryrun" ct web "$w" --dryrun; done
refused "stop --keepoff"                    ct web stop --keepoff
refused "stop --help"                       ct web stop --help
refused "start --keep-off"                  ct web start --keep-off
refused "restart with a second name"        ct web restart db
refused "stop --yes"                        ct web stop --yes
refused "autostart on --dryrun"             ct web autostart on --dryrun
refused "autostart with a second setting"   ct web autostart on ram=100
refused "set with a typo after a setting"   ct web set ram=2048 --dryrun
refused "set with an unknown key"           ct web set ram=2048 rma=1
refused "restore with a typo"               ct web restore s1 --dryrun
refused "restore --yes"                     ct web restore s1 --yes
refused "storage add with a typo"           ct web storage add fast data /data --dryrun
refused "storage add --as on a volume"      ct web storage add fast data /data -s fast --as 1000:100
refused "storage remove with a typo"        ct web storage remove data --dryrun
refused "ip with a typo"                    ct web ip 192.0.2.5 --dryrun
refused "snapshot with a typo as the label" ct web snapshot --dryrun
refused "snapshot with a one-dash typo"     ct web snapshot -dry-run
refused "snapshot --create with a typo"     ct web snapshot --create --dryrun
refused "snapshot with label and --delete"  ct web snapshot lbl --delete s1 --yes
refused "edit with a typo as a value"       ct web edit --ram 512 --cpu --dryrun --yes
refused "edit with a typo"                  ct web edit --ram 512 --dryrun --yes
refused "storage with a typo"               ct web storage --kind fast --name data --path /data --yes --dryrun
refused "storage --source on a volume"      ct web storage --kind fast --source media --name data --path /data --yes
refused "shell with an extra word"          ct web shell --dry-run
refused "console with an extra word"        ct web console --dry-run
run ct web stop --dryrun
check_match "the refusal names the option" "'--dryrun'" "$OUT"

echo "-- remove keeps the typed name"
refused "remove --yes" ct web remove --yes
check_match "it says that the name is typed" "typing the name" "$OUT"
: > "$LOG"; OUT=$(echo wrong | $H ct web remove 2>&1) || true
check_eq "remove with a wrong name deletes nothing" "" "$(changed)"
: > "$LOG"; OUT=$(echo web | $H ct web remove 2>&1) || true
check_eq "remove with the typed name deletes" "incus delete -f web" "$(changed)"
: > "$LOG"; bash "$WORK/scripts/manage-ct.sh" web --delete --yes >/dev/null 2>&1 || true
check_eq "a job that calls manage-ct.sh --delete --yes still works" "incus delete -f web" "$(changed)"

echo "-- no registry row drops what was typed"
REG=$SCRIPTS/lib/registry.tsv
check_eq "every changing hs ct word of manage-ct.sh is marked --hs-words and takes {rest}" "" "$(awk -F'\t' '$1 == "user" && $2 ~ /^ct <ct>/ && $3 == "manage-ct.sh" && $7 ~ /(^|,)changes(,|$)/ && ($4 !~ /--hs-words/ || $4 !~ /\{rest\}/) { print $2 }' "$REG" | paste -sd, -)"
# the real dispatcher and registry, every script a stand-in that says it ran: a template without {rest} must refuse an extra word
G=$WORK/guard; mkdir -p "$G/lib"
cp "$SCRIPTS"/lib/{hs.sh,capability.sh,registry-load.sh,ui.sh,i18n.sh,setting.sh,refuse-code.sh,live.sh,audit.sh,job.sh,registry.tsv} "$G/lib/"
awk -F'\t' '!/^#/ && $4 ~ /\{/ && $4 !~ /\{rest\}/ && $3 !~ /^rust:/' "$REG" > "$WORK/templates.tsv"
while IFS=$'\t' read -r _ _ script _; do printf 'echo RAN\n' > "$G/$script"; done < "$WORK/templates.tsv"
bad=""; n=0
while IFS=$'\t' read -r _ path _; do
  n=$((n + 1))
  # a longer row with one more <value> takes the word as that value: not a template matter
  awk -F'\t' -v p="$path <" 'index($2, p) == 1 { found = 1 } END { exit !found }' "$REG" && continue
  words=$(sed -E 's/<[^>]*>/x/g' <<<"$path")
  # shellcheck disable=SC2086
  out=$(bash "$G/lib/hs.sh" $words --not-an-option 2>&1 </dev/null) && rc=0 || rc=$?
  { [ "$rc" != 0 ] && ! grep -qx RAN <<<"$out" && grep -q -- '--not-an-option' <<<"$out"; } || bad="$bad$path; "
done < "$WORK/templates.tsv"
check_eq "each of the $n template rows without {rest} refuses an extra word" "" "$bad"
check_eq "such a row still runs without extra words" "RAN" "$(bash "$G/lib/hs.sh" ct x shell </dev/null 2>&1)"
check_eq "a long row takes --foreground" "RAN" "$(bash "$G/lib/hs.sh" backup drill ct x --foreground </dev/null 2>&1)"

finish
