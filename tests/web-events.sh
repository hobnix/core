#!/usr/bin/env bash
# The Events page logic (web/src/pages/events.js) and its wiring, run with node.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
if ! command -v node >/dev/null 2>&1; then skip "node is not installed"; finish; exit 0; fi
node "$SCRIPTS/../tests/web-events.mjs"
rc=$?
check_eq "the events page tests pass" 0 "$rc"
check "event list is a read with source and after" grep -q '("event", "list"):.*"source".*"after"' "$SCRIPTS/web-serve.py"
check "event list takes before" grep -qF '"before": (r"^[0-9]{1,9}$", "--before")' "$SCRIPTS/web-serve.py"
check "the page has the stream topic" grep -q "poll(() => path, 30000, 'event-log')" "$SCRIPTS/../web/src/pages/Events.svelte"
check "the page pages by --before, not a growing limit" grep -q "&before=" "$SCRIPTS/../web/src/pages/Events.svelte"
check "the stream topic is followed in every liveState mode" grep -q "STREAM_TOPICS.has(t)" "$SCRIPTS/../web/src/data.svelte.js"
finish
