#!/usr/bin/env bash
# The package index warning of the web interface (web/src/pages/pkgindex.js) and the topics the index events wake, run with node.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
if ! command -v node >/dev/null 2>&1; then skip "node is not installed"; finish; exit 0; fi
node "$SCRIPTS/../tests/web-pkg-index.mjs"
rc=$?
check_eq "the package index web tests pass" 0 "$rc"
finish
