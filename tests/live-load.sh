#!/usr/bin/env bash
# hs live load: reads the file the collector writes (scripts/live-collect.py write_stats). Temp files only.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
export HS_LANG=en HS_PLAIN=1 HS_CALLER=test HS_LIVE_LOAD_FILE=$WORK/load.json
L="bash $SCRIPTS/live-load.sh"
check_out "no file: says where to look" "systemctl status hs-live" $L
now=$(date +%s)
printf '{"time": %s, "window": 60, "cpu_s": 12.5, "since": %s, "busy": 0.21, "stretch": 1.0, "reads": 30, "topics": {"gateway-routes": {"reads": 9, "ms": 840}, "status": {"reads": 4, "ms": 120}}}' "$now" "$((now - 600))" >"$WORK/load.json"
check_out "the CPU seconds" "12.5 s since the collector started" $L
check_out "the reads of the last minute" "30 started in the last 60 s" $L
check_out "the busiest topic first" "gateway-routes +9 +840" $L
check_eq "gateway-routes before status" "gateway-routes" "$($L | grep -E '^ *(gateway-routes|status) ' | head -n 1 | awk '{print $1}')"
check_out "--top 1 cuts the list" "gateway-routes" $L --top 1
check "--top 1 leaves out the second" bash -c "! $L --top 1 | grep -q '^ *status '"
finish
