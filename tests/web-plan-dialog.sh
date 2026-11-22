#!/usr/bin/env bash
# PlanDialog.go() closes the dialog (ui.dialog = null) and then still needs its arguments: everything read from `dialog` or from the
# derived `args` must be captured BEFORE close(), else Start throws "Cannot read properties of null (reading 'args')" and no job spawns.
# Plain static check, no node needed.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
out=$(python3 - "$ROOT/web/src/shell/PlanDialog.svelte" <<'PY'
import re, sys
s = open(sys.argv[1], encoding='utf-8').read()
m = re.search(r'async function go\(\) \{(.*?)\n  \}\n', s, re.S)
body = m.group(1)
i = body.index('close();')
after = body[i:]
before = body[:i]
bad = []
if 'startArgs' not in before: bad.append('go() does not capture the arguments before close()')
if re.search(r'\bdialog\.', after): bad.append('go() reads dialog.* after close()')
if re.search(r'(?<![\w.])args\b', after): bad.append('go() reads the derived args after close()')
print('\n'.join(bad))
PY
)
[ -z "$out" ] || echo "$out"
check_eq "PlanDialog.go() reads dialog and args before close()" "" "$out"
finish
