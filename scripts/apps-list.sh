#!/usr/bin/env bash
# help: the apps (recipes) of this server with their stage and flags, or the declared health of each
# help.de: die Apps (Rezepte) dieses Servers mit Stufe und Markierungen, oder die erklärte Gesundheit jeder App
# args: [--list | --health]
# System command (hs sys apps list, hs sys apps health), read only, plain, never translated, never asks.
#   --list    the recipe rows of `hs sys pkg states` (pkg.sh --states --kind recipe), same columns: name, kind, stage (available|installed|on|running),
#             flags (comma list, - = none), repo, available, installed, instances, title. An app whose declared check fails (and whose instances all run)
#             is stage on with the flag unhealthy (docs/PLAN-app-lifecycle.md Q1); an app without [app.health] is as before.
#   --health  name, health (healthy|unhealthy|stopped), one row per app whose package.toml declares [app.health] (Q4): container = the instance runs,
#             tcp = the port accepts a connection, http = any 2xx or 3xx. Apps that declare nothing have no row.
# Words: docs/adr/0027-package-lifecycle-states.md. Test knobs: those of pkg.sh, HS_APP_HEALTH_HOST (send every check to that host).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# the three inputs of the check: recipes, container states, container addresses ("name,10.0.0.5"); a failed call is an empty file
health_rows() {
  local d; d=$(mktemp -d); trap 'rm -rf "$d"' RETURN
  bash "$here/recipes-list.sh" --list >"$d/recipes" 2>/dev/null || : >"$d/recipes"
  ${HS_INCUS:-incus} list -f csv -c ns >"$d/running" 2>/dev/null || : >"$d/running"
  ${HS_INCUS:-incus} list -f csv -c n4 2>/dev/null | sed 's/^\([^,]*\),"\{0,1\}\([^ ,"]*\).*/\1,\2/' >"$d/addr" || : >"$d/addr"
  python3 -I "$here/app_health.py" --recipes "$d/recipes" --running "$d/running" --addr "$d/addr"
}
case "${1:---list}" in
  --list)
    d=$(mktemp -d); trap 'rm -rf "$d"' EXIT
    health_rows >"$d/health" 2>/dev/null || : >"$d/health"
    exec_rc=0; bash "$here/pkg.sh" --states --kind recipe --health "$d/health" || exec_rc=$?
    exit "$exec_rc" ;;
  --health) health_rows ;;
  *) echo "usage: apps-list.sh [--list|--health]" >&2; exit 1 ;;
esac
