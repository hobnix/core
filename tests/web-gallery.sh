#!/usr/bin/env bash
# The component gallery has an entry for every ui component (web/src/pages/Gallery.svelte, tests/web-gallery.mjs), run with node.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
if ! command -v node >/dev/null 2>&1; then skip "node is not installed"; finish; exit 0; fi
node "$SCRIPTS/../tests/web-gallery.mjs"
rc=$?
check_eq "every ui component has a gallery entry" 0 "$rc"
finish
