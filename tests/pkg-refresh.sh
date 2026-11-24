#!/usr/bin/env bash
# The package index refresh (scripts/pkg-refresh.sh, #1071): an unchanged index makes no event, a changed one makes one, a failed fetch is recorded
# and the script still exits 0, a coming expiry is announced once, --state prints the state, --warn warns after 3 days or when the index expired.
# Stand-ins: pkg.py (HS_PKG_PY), the event writer (HS_PYTHON, logs its arguments), the push message (HS_PKG_NOTIFY).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
tab=$'\t'
export WORK
export HS_LANG=en HS_PLAIN=1 HS_STATE_DIR=$WORK/state HS_EVENT_NOROOT=1 HS_LIVE_LOG=$WORK/live.log
export HS_PKG_PY=$WORK/pkgpy HS_PYTHON=$WORK/py HS_PKG_NOTIFY=$WORK/notify
mkdir -p "$HS_STATE_DIR"
cat > "$WORK/pkgpy" <<'F'
#!/usr/bin/env bash
mode=$(cat "$WORK/mode")
d=$HS_STATE_DIR/packages/index/official/live; mkdir -p "$d"
case "$mode" in
  fail) printf 'official\t-\t-\tcould not be reached\n'; exit 1 ;;
  same) printf 'official\t-\t-\tok\n' ;;
  *) printf '{"expires": "%s"}\n' "$(cat "$WORK/expires")" > "$d/index.json"; printf 'official\t-\t-\tok\n' ;;
esac
F
printf '#!/usr/bin/env bash\necho "$*" >> "$WORK/py.log"\n' > "$WORK/py"
printf '#!/usr/bin/env bash\necho "$*" >> "$WORK/notify.log"\n' > "$WORK/notify"
chmod +x "$WORK/pkgpy" "$WORK/py" "$WORK/notify"
: > "$WORK/py.log"; : > "$WORK/notify.log"
R="bash $SCRIPTS/pkg-refresh.sh"
events() { grep -c "emit $1" "$WORK/py.log" || true; }
st() { $R --state | awk -F'\t' -v a="$1" -v b="$2" '$1==a{x=$2} $1==b{y=$2} END{print x, y}'; }
now=1800000000
export HS_NOW=$now
printf '%s' 2027-12-31T00:00:00Z > "$WORK/expires"   # far away from HS_NOW

echo change > "$WORK/mode"; rc=0; $R >/dev/null 2>&1 || rc=$?
check_eq "a first fetch that brings an index: exit 0" 0 "$rc"
check_eq "... one index.changed event" 1 "$(events index.changed)"
check_eq "... the package topics are asked to refresh" "event:index.changed" "$(cat "$HS_LIVE_LOG")"
check_eq "... last_ok is now, no error" "$now -" "$(st last_ok error)"
echo same > "$WORK/mode"; $R >/dev/null 2>&1
check_eq "an unchanged index makes no second event" 1 "$(events index.changed)"
check_eq "... and no failed event" 0 "$(events index.failed)"

echo fail > "$WORK/mode"; export HS_NOW=$((now + 100)); rc=0; $R >/dev/null 2>&1 || rc=$?
check_eq "a failed fetch: exit 0" 0 "$rc"
check_eq "... one index.failed event" 1 "$(events index.failed)"
check_eq "... the error is in the state, last_ok stays" "could not be reached $now" "$(st error last_ok)"
check_eq "no warning within 3 days" "" "$($R --warn 2>&1)"
export HS_NOW=$((now + 4 * 86400))
check_contains "a warning after 3 days without a fetch" "could not be fetched since" "$($R --warn 2>&1)"

exp=$(date -u -d 2027-12-31T00:00:00Z +%s)
export HS_NOW=$((exp - 2 * 86400)); echo same > "$WORK/mode"
$R >/dev/null 2>&1; $R >/dev/null 2>&1
check_eq "an expiry less than 3 days away: one push message, not two" 1 "$(wc -l < "$WORK/notify.log" | tr -d ' ')"
check_eq "... recorded as notified" "$exp" "$(st notified x | cut -d' ' -f1)"
export HS_NOW=$((exp + 86400))
check_contains "an expired index is warned about" "expired on 2027-12-31" "$($R --warn 2>&1)"
finish
