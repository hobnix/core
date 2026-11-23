#!/usr/bin/env bash
# The block registry (#473, web/src/shell/block-registry.json): `pkg validate` checks the blocks of a capability.toml [web.page] against it. No root.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
export HS_LANG=en HS_PLAIN=1
PKG="python3 -I $SCRIPTS/pkg.py"
T=$WORK/tree/capabilities/blkext
mkdir -p "$T"
printf 'name = "blkext"\nversion = "1.0.0"\nkind = "extension"\ntitle = "Blk"\nrequires_core = ">=1"\naudience = "generic"\n' > "$T/package.toml"
cap() {   # cap <tables after the capability header>
  printf 'name = "blkext"\nkind = "feature"\nrequires = []\nprovides = []\nneeds = []\nextension = true\ntitle = "Blk"\n%b\n' "$1" > "$T/capability.toml"
}
validate() { HS_PACKAGES_ROOT=$WORK/tree $PKG validate 2>&1; }
good() { cap "$2"; if validate >/dev/null; then pass "$1"; else fail "$1: $(validate)"; fi; }
bad() {   # bad <what> <word> <capability tables>
  cap "$3"
  local out rc=0
  out=$(validate) || rc=$?
  if [ "$rc" = 1 ] && printf '%s' "$out" | grep -q "$2"; then pass "$1"; else fail "$1 (rc $rc: $out)"; fi
}
PG='[web.page]\ntitle = "P"\n'
good "no page is fine" ''
good "known blocks pass" "${PG}[[web.page.blocks]]\ntype = \"text\"\ntext = \"hi\"\n[[web.page.blocks]]\ntype = \"empty\"\ntitle = \"x\"\n[[web.page.blocks]]\ntype = \"kv\"\nitems = []"
good "log and progress blocks pass" "${PG}[[web.page.blocks]]\ntype = \"log\"\nstream = \"/api/logs/stream/ct?target=web\"\nread = \"/api/sys/ct/logs/web\"\nlines = 100\nfollow = true\n[[web.page.blocks]]\ntype = \"progress\"\njob = \"backup\"\n[[web.page.blocks]]\ntype = \"progress\"\nread = \"/api/sys/x\"\nvalue = 0\nmax = 1\nstate = 3\ntopic = \"x\""
bad "a log block needs its stream" "needs stream" "${PG}[[web.page.blocks]]\ntype = \"log\"\nread = \"/api/sys/ct/logs/web\""
bad "log lines must be a number" "lines of block log must be a number" "${PG}[[web.page.blocks]]\ntype = \"log\"\nstream = \"/s\"\nread = \"/r\"\nlines = \"many\""
bad "a progress value must be a number" "value of block progress must be a number" "${PG}[[web.page.blocks]]\ntype = \"progress\"\nread = \"/r\"\nvalue = \"x\""
good "chart and stat pass" "${PG}[[web.page.blocks]]\ntype = \"chart\"\nread = \"/api/sys/x\"\nvalue = 2\nmax = 100\nunit = \"%\"\n[[web.page.blocks]]\ntype = \"stat\"\nread = \"/api/sys/x\"\nitems = [{ label = \"Up\", col = 0 }]"
bad "a chart without a read is named" "block chart needs read" "${PG}[[web.page.blocks]]\ntype = \"chart\"\nvalue = 1"
bad "a chart value must be a number" "value of block chart must be a number" "${PG}[[web.page.blocks]]\ntype = \"chart\"\nread = \"/r\"\nvalue = \"1\""
bad "a stat without items is named" "block stat needs items" "${PG}[[web.page.blocks]]\ntype = \"stat\"\nread = \"/r\""
bad "a stat has no unit key of its own" "has no key unit" "${PG}[[web.page.blocks]]\ntype = \"stat\"\nread = \"/r\"\nitems = []\nunit = \"x\""
bad "an unknown block is named" "unknown block 'sparkle'" "${PG}[[web.page.blocks]]\ntype = \"sparkle\""
bad "a block without a type is named" "unknown block None" "${PG}[[web.page.blocks]]\ntext = \"x\""
bad "a missing required key is named" "needs key" "${PG}[[web.page.blocks]]\ntype = \"table\"\nread = \"/api/sys/x\"\ncolumns = []"
bad "an unknown key is named" "has no key colour" "${PG}[[web.page.blocks]]\ntype = \"text\"\ntext = \"x\"\ncolour = \"red\""
bad "a wrong type is named" "must be a list" "${PG}[[web.page.blocks]]\ntype = \"table\"\nread = \"/r\"\nkey = \"k\"\ncolumns = \"x\""
finish
