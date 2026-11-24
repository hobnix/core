#!/usr/bin/env bash
# shellcheck shell=bash
# The rows of a package that is staged but not installed yet (#1072): scripts/pkg_repo.py runs this before the copy replaces the old one, so a
# refused package leaves nothing behind (no vendored module, no events, the old copy stays). A library script, not a command: no registry row.
#
#   pkg-stage-check.sh <name> <staged folder> <repository>
#
# Prints one `row <words> TAB <reason>` line per refused row (control characters become ?) and exits 1 when there is any; exit 0 = fine.
set -u -o pipefail
[ "$#" -eq 3 ] || exit 2
HS_STAGE_PKG=$1
HS_STAGE_REPO=$3
export HS_STAGE_PKG HS_STAGE_REPO
. "${BASH_SOURCE[0]%/*}/registry-load.sh" || exit 2   # fails closed: a loader that cannot be read is exit 2, never "fine"
type _ext_filter >/dev/null 2>&1 || exit 2
# every failure of the check itself (no registry, no temp file, an awk that stops) is exit 2 = refused, never "no findings"
out=$(_ext_filter "$1" "$2" 1 2>/dev/null) || exit 2
found=$(printf '%s\n' "$out" | LC_ALL=C tr '\001-\010\013-\037\177' '?' | awk -F'\t' '$1 == "REFUSED" { print "row " $3 "\t" $4 }') || exit 2
[ -n "$found" ] || exit 0
printf '%s\n' "$found"
exit 1
