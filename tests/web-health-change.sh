#!/usr/bin/env bash
# hs sys health list|plan|start (scripts/health-change.sh): acknowledge a problem, take it back and lift the pause from the web interface, against
# the real health-ack.sh with a stand-in health check and temporary files. No root.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
export HS_PLAIN=1 HS_LANG=en
unset HS_CALLER HS_GUIDED_TTY
export HS_ACK_FILE=$WORK/ack HS_BULK_PAUSE=$WORK/paused
fake=$WORK/hc.sh
cat > "$fake" <<'EOS'
#!/usr/bin/env bash
# stand-in for health-check.sh --list: key TAB text TAB acked|-
ack=${HS_ACK_FILE:-/nonexistent}
for k in "backup:stale" "zfs:tank:scrub-old"; do
  a=-; [ -r "$ack" ] && grep -q -F -x -e "$k" <(cut -f1 "$ack") && a=acked
  printf '%s\ttext of %s\t%s\n' "$k" "$k" "$a"
done
EOS
export HS_HEALTH_CHECK=$fake
run() { rc=0; out=$(timeout 20 bash "$SCRIPTS/health-change.sh" "$@" </dev/null 2>/dev/null) || rc=$?; }
has() { grep -q -- "$1" <<<"$out"; }

echo "-- registry rows"
reg=$SCRIPTS/lib/registry.tsv
check "sys health list row" grep -q "^sys.sys health list.health-check.sh.--list." "$reg"
check "sys health plan row" grep -q "^sys.sys health plan <action>.health-change.sh.plan {1} {rest}" "$reg"
check "sys health start row" grep -q "^sys.sys health start <action>.health-change.sh.start {1} {rest}" "$reg"

echo "-- ack"
run plan ack backup:stale
check_eq "plan: exit 0" 0 "$rc"
has '^status	ok$' && has '^heading	acknowledge backup:stale$' && has 'text of backup:stale' && pass "plan names the problem" || fail "plan: $out"
run plan ack nothere
check_eq "an unknown id: refused" 1 "$rc"
run plan ack 'a;b'
check_eq "a bad id: refused" 1 "$rc"
run plan ack
check_eq "no id: refused" 1 "$rc"
run plan unack backup:stale
check_eq "unack of an open problem: refused" 1 "$rc"
run start ack backup:stale
check_eq "start: exit 0" 0 "$rc"
has '^status	done$' && pass "status done" || fail "start: $out"
check_eq "the ack file has the id" backup:stale "$(cut -f1 "$HS_ACK_FILE")"
run plan ack backup:stale
check_eq "ack twice: refused" 1 "$rc"

echo "-- unack"
run plan unack backup:stale
check_eq "unack plan: exit 0" 0 "$rc"
run start unack backup:stale
check_eq "unack start: exit 0" 0 "$rc"
check_eq "the ack file is empty again" "" "$(cat "$HS_ACK_FILE")"

echo "-- ack with --for and --note, list-acks"
run plan ack backup:stale --for 7d --note "waiting for the new disk"
check_eq "plan with --for and --note: exit 0" 0 "$rc"
run plan ack backup:stale --for soon
check_eq "a bad --for: refused" 1 "$rc"
run plan ack backup:stale --frob 1
check_eq "an unknown option: refused" 1 "$rc"
run start ack backup:stale --for 7d --note "waiting for the new disk"
check_eq "start with --for and --note: exit 0" 0 "$rc"
check_eq "five columns" 5 "$(awk -F'	' '{ print NF }' "$HS_ACK_FILE")"
check_eq "the note is kept" "waiting for the new disk" "$(cut -f5 "$HS_ACK_FILE")"
check "until is about 7 days away" test "$(( $(cut -f3 "$HS_ACK_FILE") - $(cut -f2 "$HS_ACK_FILE") ))" -ge 604790
la=$(HS_PLAIN=1 bash "$SCRIPTS/health-ack.sh" list-acks)
check_eq "list-acks is one tab row" 1 "$(grep -c '^backup:stale	[0-9]*	[0-9]*	[^	]*	waiting for the new disk$' <<<"$la")"
check "sys health acks row" grep -q "^sys.sys health acks.health-ack.sh.list-acks" "$reg"
printf 'old:row	100
' >> "$HS_ACK_FILE"
check_eq "a two column row (older file) is listed with - for the rest" 1 "$(HS_PLAIN=1 bash "$SCRIPTS/health-ack.sh" list-acks | grep -c '^old:row	100	-	-	-$')"
printf 'gone:row	100	200	x	-
' >> "$HS_ACK_FILE"
check_eq "an ended row is not listed" 0 "$(HS_PLAIN=1 bash "$SCRIPTS/health-ack.sh" list-acks | grep -c '^gone:row')"
: > "$HS_ACK_FILE"

echo "-- resume"
run plan resume
check_eq "nothing paused: refused" 1 "$rc"
printf 'keys=backup:stale,zfs:tank:scrub-old\n' > "$HS_BULK_PAUSE"
run plan resume
check_eq "resume plan: exit 0" 0 "$rc"
has '^heading	lift the pause' && pass "resume plan" || fail "resume plan: $out"
check "plan lifts nothing" test -e "$HS_BULK_PAUSE"
run start resume
check_eq "resume start: exit 0" 0 "$rc"
check "the pause file is gone" test ! -e "$HS_BULK_PAUSE"
check_eq "the causes are acknowledged" "backup:stale,zfs:tank:scrub-old" "$(cut -f1 "$HS_ACK_FILE" | paste -sd, -)"
run plan resume extra
check_eq "extra argument: refused" 1 "$rc"
run plan frobnicate x
check_eq "unknown action: refused" 1 "$rc"

finish
