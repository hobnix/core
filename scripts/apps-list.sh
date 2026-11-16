#!/usr/bin/env bash
# help: the apps (recipes) of this server with their stage and flags
# help.de: die Apps (Rezepte) dieses Servers mit Stufe und Markierungen
# args: [--list]
# System command (hs sys apps list), read only, plain, never translated, never asks. The recipe rows of `hs sys pkg states` (pkg.sh --states --kind recipe),
# same columns: name, kind, stage (available|installed|on|running), flags (comma list, - = none), repo, available, installed, instances, title.
# A stub for now: the health of an app is added by the app contract (docs/PLAN-app-lifecycle.md, step 10). Words: docs/adr/0027-package-lifecycle-states.md.
# Test knobs: those of pkg.sh.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
case "${1:---list}" in
  --list) exec bash "$here/pkg.sh" --states --kind recipe ;;
  *) echo "usage: apps-list.sh [--list]" >&2; exit 1 ;;
esac
