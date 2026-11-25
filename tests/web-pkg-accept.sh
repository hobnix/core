#!/usr/bin/env bash
# The plan dialog and a package update with new permissions (hobnix/core#1237): Start sends --tag and --seen of the plan that was shown, the typed
# name goes as the confirm word, danger lines are drawn. The server side: tests/pkg-change-perms.sh.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
d=$ROOT/web/src/shell
# the dialog sends the bound args, built before close(), and asks for the typed name whenever the plan has a confirm_name
check "the dialog binds the start to the shown plan" grep -q 'const sent = boundArgs(area, startArgs, p);' "$d/PlanDialog.svelte"
check "and sends those args" grep -q 'doStart(area, sent, ' "$d/PlanDialog.svelte"
check "it draws a danger line" grep -q "kind === 'danger'" "$d/PlanSteps.svelte"
if have node; then
  check "pkgbind.js (node)" node "$ROOT/tests/web-pkg-accept.mjs"
else
  skip "needs node"
fi
finish
