#!/usr/bin/env bash
# help: what happens when an app has an update: show or set the policy of an installed app (notify or pinned)
# help.de: was bei einem App-Update passiert: die Regel einer installierten App zeigen oder setzen (notify oder pinned)
# args: <instance> [notify|pinned]
# The terminal side of `hs sys apps policy` (apps-version.sh policy): the same work, spoken through ui.sh. notify = an offered update is mentioned in
# the weekly summary; pinned = it is never offered. Nothing is updated by itself. Test knobs: those of apps-version.sh.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib/ui.sh"
[ $# -ge 1 ] && [ $# -le 2 ] || fail "usage: hs apps policy <instance> [notify|pinned]"
inst=$1
err=$(mktemp); trap 'rm -f "$err"' EXIT
rc=0; out=$(bash "$here/apps-version.sh" policy "$@" 2>"$err") || rc=$?
[ "$rc" -eq 0 ] || fail "$(cat "$err")"
if [ $# -eq 1 ]; then
  kv "App" "$inst"
  kv "Update policy" "$out"
else
  ok "$(t 'The update policy of %s is now %s.' "$inst" "$2")"
fi
