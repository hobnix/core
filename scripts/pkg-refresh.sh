#!/usr/bin/env bash
# help: fetch the package index now, say when it changed or could not be fetched (the timer hs-pkg-refresh does it daily): hs pkg refresh
# help.de: den Paket-Index jetzt holen und sagen, wenn er sich geändert hat oder nicht geholt werden konnte (der Timer hs-pkg-refresh tut es täglich): hs pkg refresh
# args: [--state | --warn]
# Runs `pkg.py fetch`, compares the kept index files before and after, and writes $HS_STATE_DIR/pkg-index-state (key TAB value lines: repo, last_ok,
# last_try, error (- = none), expires, notified; epoch seconds). Changed index: event index.changed; failed fetch: event index.failed. Never fails for
# a host that is down (exit 0, the error is in the state); exit 1 only for a broken setup. --state prints the file (hs sys pkg index), --warn the
# user-visible warning (no fetch for 3 days, or the index expired). One push message when `expires` is less than 3 days away (notified=<expires>).
# Not tested on hardware yet. Test knobs: HS_PKG_PY (a program that replaces `python3 -I pkg.py`), HS_NOW (epoch), HS_STATE_DIR, HS_PKG_NOTIFY (replaces notify.sh).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib/ui.sh"
. "$here/lib/live.sh"
. "$here/lib/event.sh"
st=${HS_STATE_DIR:-/var/lib/hs}
file=$st/pkg-index-state
now=${HS_NOW:-$(date +%s)}
day=86400
get() { sed -n "s/^$1\t//p" "$file" 2>/dev/null | head -n1 || true; }
fmt() { date -u -d "@$1" +%Y-%m-%d 2>/dev/null || printf '%s' "$1"; }
digest() { { cat "$st"/packages/index/*/live/index.json 2>/dev/null || true; } | sha256sum | cut -d' ' -f1; }
pkgpy() { if [ -n "${HS_PKG_PY:-}" ]; then "$HS_PKG_PY" "$@"; else python3 -I "$here/pkg.py" "$@"; fi; }
notify() { if [ -n "${HS_PKG_NOTIFY:-}" ]; then "$HS_PKG_NOTIFY" "$@"; else bash "$here/notify.sh" "$@"; fi; }

case "${1:-}" in
  --state) [ ! -f "$file" ] || cat "$file"; exit 0 ;;
  --warn)
    [ -f "$file" ] || exit 0
    ok_at=$(get last_ok); exp=$(get expires); err=$(get error)
    if [ -n "$exp" ] && [ "$exp" != - ] && [ "$now" -gt "$exp" ]; then
      warn "$(t 'The package index expired on %s. Fetch a new one: hs pkg refresh' "$(fmt "$exp")")"
    elif [ "${ok_at:--}" = - ] && [ "${err:--}" != - ]; then
      warn "$(t 'The package index has not been fetched yet: %s. Installed packages keep running.' "$err")"
    elif [ "${ok_at:--}" != - ] && [ $((now - ok_at)) -gt $((3 * day)) ]; then
      warn "$(t 'The package index could not be fetched since %s: %s. Installed packages keep running.' "$(fmt "$ok_at")" "${err:--}")"
    fi
    exit 0 ;;
  "") ;;
  *) fail "$(t 'usage: hs pkg refresh')"; exit 1 ;;
esac

if [ -z "${HS_PKG_PY:-}" ] && [ ! -f "$here/pkg.py" ]; then fail "$(t 'pkg.py is missing')"; exit 1; fi
before=$(digest)
# stdout is the result table (name, release, commit, result: tab separated); stderr carries warnings (an index past its grace, a commit that cannot be
# fetched) and goes to the journal as notes. A fetch that finds the lock held (the timer sets HS_PKG_LOCK_WAIT=0; hs update and hs pkg refresh wait as usual) is not a failure: this run is skipped quietly.
errf=$(mktemp); trap 'rm -f "$errf"' EXIT
rc=0; out=$(pkgpy fetch 2>"$errf") || rc=$?
while IFS= read -r l; do [ -z "$l" ] || note "$l"; done < "$errf"
if grep -q 'another pkg fetch is running' "$errf" <(printf '%s
' "$out"); then note "$(t 'Another package fetch is running: skipped.')"; exit 0; fi
after=$(digest)
rows=$(awk -F'	' 'NF >= 4' <<< "$out")
repo=""; err=""
while IFS=$'	' read -r rname _ _ rerr; do
  [ -n "${rname:-}" ] || continue
  [ -n "$repo" ] || repo=$rname
  if [ "${rerr:-ok}" != ok ] && [ -z "$err" ]; then repo=$rname; err=$rerr; fi
done <<< "$rows"
[ "$rc" -eq 0 ] || [ -n "$err" ] || err=$(head -n1 < <(cat "$errf"; printf '%s
' "$out") | head -c 200)
[ -n "$err" ] || [ "$rc" -eq 0 ] || err="exit $rc"
[ -n "$repo" ] || repo=official

last_ok=$(get last_ok); notified=$(get notified)
[ -n "$err" ] || last_ok=$now
exp=-
idx=$st/packages/index/$repo/live/index.json
if [ -f "$idx" ]; then
  e=$(sed -n 's/.*"expires"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$idx" | head -n1)
  [ -z "$e" ] || exp=$(date -u -d "$e" +%s 2>/dev/null || echo -)
fi
if [ "$exp" != - ] && [ $((exp - now)) -lt $((3 * day)) ] && [ "${notified:--}" != "$exp" ]; then
  if notify --category info "$(hostname): package index expires" "The package index expires on $(fmt "$exp"). Run: hs pkg refresh" low; then notified=$exp; fi
fi
mkdir -p "$st"
printf 'repo\t%s\nlast_ok\t%s\nlast_try\t%s\nerror\t%s\nexpires\t%s\nnotified\t%s\n' \
  "$repo" "${last_ok:--}" "$now" "${err:--}" "$exp" "${notified:--}" > "$file.tmp"
mv "$file.tmp" "$file"

if [ -n "$err" ]; then
  warn "$(t 'The package index could not be fetched: %s. Installed packages keep running.' "$err")"
  event_emit index.failed "$repo" "$err"
  live_refresh event:index.failed
elif [ "$before" != "$after" ]; then
  ok "$(t 'The package index changed.')"
  event_emit index.changed "$repo" "The package index changed"
  live_refresh event:index.changed
else
  ok "$(t 'The package index is up to date.')"
fi
exit 0
