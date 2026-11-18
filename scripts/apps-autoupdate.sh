#!/usr/bin/env bash
# help: EXPERIMENTAL and hidden: update the apps whose policy is automatic (timer; off unless appsAutoupdateEnabled is true)
# help.de: EXPERIMENTELL und versteckt: Apps mit der Regel automatic aktualisieren (Timer; aus, solange appsAutoupdateEnabled nicht true ist)
# args: [--dry-run] [--any-time]
# Run by the timer hs-apps-autoupdate. Does nothing while the setting appsAutoupdateEnabled is not true or outside the quiet window (appsAutoupdateWindow,
# default 03:00-05:00). See scripts/app_autoupdate.py for the rules (patch/minor only, default repositories only, snapshot, health check, rollback,
# one message per failure). Not tested on hardware yet. Exit 0 always. Test knobs: those of app_autoupdate.py.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib/ui.sh"
out=$(python3 -I "$here/app_autoupdate.py" "$@" 2>&1) || true
while IFS= read -r line; do
  [ -n "$line" ] || continue
  case "$line" in failed:*|error:*) warn "$line" ;; *) note "$line" ;; esac
done <<<"$out"
exit 0
