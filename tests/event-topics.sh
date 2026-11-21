#!/usr/bin/env bash
# Named events (docs/PLAN-live-interface.md step 13, D12): scripts/lib/event-topics.tsv maps an event kind to the live-state topics it wakes.
# Every kind exists in event-kinds.tsv, every topic exists in live-topics.tsv; `event:<kind>` wakes exactly the listed topics (state-db.py topic-bump,
# fake state database) and fewer than the group it replaces; an unknown kind wakes @system; the groups still work as aliases.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
command -v python3 >/dev/null || { echo "python3 missing: skipped"; exit 0; }
wp() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else echo "$1"; fi; }
export HS_PLAIN=1 HS_LANG=en HS_CALLER=test
T=$'\t'
ET=$SCRIPTS/lib/event-topics.tsv
kinds=$(grep -v '^#' "$ET" | cut -f1)
check "the table lists kinds" test -n "$kinds"
bad=""
for k in $kinds; do grep -q "^$k$T" "$SCRIPTS/lib/event-kinds.tsv" || bad="$bad $k"; done
check_eq "every kind of event-topics.tsv is in event-kinds.tsv" "" "$bad"
bad=""
for t in $(grep -v '^#' "$ET" | cut -f2 | tr ',' '\n' | sort -u); do grep -q "^$t$T" "$SCRIPTS/lib/live-topics.tsv" || bad="$bad $t"; done
check_eq "every topic of event-topics.tsv is a live-state topic" "" "$bad"
check_eq "no kind is listed twice" "" "$(grep -v '^#' "$ET" | cut -f1 | sort | uniq -d)"

mkdir -p "$WORK/d"
export HS_STATE_DB=$(wp "$WORK/d/state.db") HS_LIVE_WAKE_LOG=$(wp "$WORK/wake.log")
q() { python3 -c 'import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); print(",".join(r[0] for r in c.execute("SELECT topic FROM topics ORDER BY topic")))' "$HS_STATE_DB"; }
sdb() { python3 "$SCRIPTS/state-db.py" "$@"; }
want=$(grep "^ct.created$T" "$ET" | cut -f2 | tr ',' '\n' | sort | paste -sd,)
sdb topic-bump event:ct.created
check_eq "ct.created wakes exactly the listed topics (fake feed: the real tables)" "$want" "$(q)"
n_event=$(cut -f2 "$WORK/wake.log" | tail -1)
: > "$WORK/wake.log"; rm -f "$WORK/d/state.db"
sdb topic-bump @instances
n_group=$(cut -f2 "$WORK/wake.log" | tail -1)
echo "topics woken: event:ct.created $n_event, @instances $n_group"
check "a named event wakes fewer topics than the group it replaces" test "$n_event" -lt "$n_group"
rm -f "$WORK/d/state.db"; : > "$WORK/wake.log"
sdb topic-bump event:disk.plugged
check_eq "disk.plugged keeps the five topics disk-event.sh woke before" "backup-state,disk-inventory,fm-locations,monitor-disks,temp-disks" "$(q)"
check_eq "the wake log says how many" "event:disk.plugged${T}5" "$(cat "$WORK/wake.log")"
rm -f "$WORK/d/state.db"
sdb topic-bump event:no.such-kind
check "an unknown kind wakes the @system topics" test "$(q | tr ',' '\n' | grep -c .)" -gt 3
check_eq "...among them status" "1" "$(q | tr ',' '\n' | grep -c '^status$')"
rm -f "$WORK/d/state.db"
sdb topic-bump event:ct.started status
check_eq "a named event and a plain topic mix" "1" "$(q | tr ',' '\n' | grep -c '^ct-list$')"
check_eq "live_refresh passes event:<kind> through (HS_LIVE_LOG)" "event:ct.stopped" "$(HS_LIVE_LOG=$(wp "$WORK/l.log") bash -c '. "$1/lib/live.sh"; live_refresh event:ct.stopped; cat "$HS_LIVE_LOG"' _ "$SCRIPTS")"
finish
