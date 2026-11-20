#!/usr/bin/env bash
# help: the live state the web interface shows: ask the collector to read again, see its topics, check them
# help.de: der Live-Zustand der Weboberfläche: den Sammler neu lesen lassen, seine Themen sehen, sie prüfen
# args: refresh <topic>...|--all | status | check | inspect | raw <topic>
# Front end of scripts/live_state.py (sys-only: plain tab separated lines, no ui.sh). Reads the state database (live_state.py db_read); refresh counts topics up. Test knobs: HS_STATE_DB, HS_STATE_DIR.
set -uo pipefail
here=$(dirname "$0")
exec python3 "$here/live_state.py" "$@"
