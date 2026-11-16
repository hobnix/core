#!/usr/bin/env bash
# help: the version of each installed app (package, offered, running) and its update policy (notify or pinned)
# help.de: die Version jeder installierten App (Paket, angeboten, laufend) und ihre Update-Regel (melden oder festgesetzt)
# args: --list | policy <instance> [notify|pinned] | plan update <name> | --summary
# System command (hs sys apps versions, hs sys apps policy), read only except `policy`, plain, never translated, never asks.
#   --list     one line per installed app instance, tab separated, an empty field is -: name, instance, package version (package.toml), app version the
#              release offers (app_version), app version running now (read on this server by [app.version]: image-tag, http-json or exec), policy
#              (notify|pinned), state (current | update | pinned). A pinned app is never offered an update.
#   policy     no value prints the policy of the instance; a value writes `policy = "<value>"` into its app record (/var/lib/hs/apps/<instance>.toml,
#              the [[created]] blocks stay as they are). `automatic` is refused: it is not available yet.
#   plan update <name>   what an update would do, as data like `hs sys apps plan install`: status, heading, package, version, piece <name> <old> <new>,
#              package_version <installed> -> <available>, app <running> -> <offered>, policy, note, step. Nothing runs, nothing is written. Exit 0 ok, 1 refused.
#              (reached through apps-change.sh plan update; `start update` comes with the update step: it is refused until then)
#   --summary  one push message ("N apps have an update offered: a, b") for the apps in state update; silent when there is none; always exit 0.
# Test knobs: HS_RECIPES_DIR, HS_STATE_DIR, HS_INCUS, HS_APP_HEALTH_HOST, HS_APP_IMAGE_TAG_CMD, HS_RECIPE_CMD, HS_NOTIFY_CMD, HS_RECIPES_LIST.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
py() { python3 -I "$here/app_version.py" "$@"; }
case "${1:---list}" in
  --list)    py list ;;
  policy)    shift; py policy "$@" ;;
  plan)      shift; py plan "$@" ;;
  start)     printf 'status\trefused\nreason\tstarting an update from here comes later\n'; exit 1 ;;
  --summary) py summary || true ;;
  *) echo "usage: apps-version.sh --list | policy <instance> [notify|pinned] | plan update <name> | --summary" >&2; exit 1 ;;
esac
