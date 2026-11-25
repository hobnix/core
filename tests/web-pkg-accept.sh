#!/usr/bin/env bash
# The plan dialog and a package update with new permissions (hobnix/core#1237): Start sends --tag and --seen of the plan that was shown, the typed
# name goes as the confirm word, danger lines are drawn. The server side: tests/pkg-change-perms.sh.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
d=$ROOT/web/src/shell
# the dialog sends the bound args, built before close(), and asks for the typed name whenever the plan has a confirm_name
check "the dialog builds its start with planstart.js" grep -q 'const req = startRequest(area, startArgs, p, typed);' "$d/PlanDialog.svelte"
check "and sends those args and that word" grep -q 'doStart(area, req.args, req.confirm, ' "$d/PlanDialog.svelte"
check "planstart.js binds a package update to the shown plan" grep -q 'args: boundArgs(area, args, p), confirm' "$d/planstart.js"
check "it draws a danger line" grep -q "kind === 'danger'" "$d/PlanSteps.svelte"
if have node; then
  check "pkgbind.js (node)" node "$ROOT/tests/web-pkg-accept.mjs"
else
  skip "needs node"
fi
finish
