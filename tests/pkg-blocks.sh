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
# the form block (#473): fields as data, the plan in the package's own area, a secret only on stdin
CH='[[web.reads]]\nargs = ["x"]\n[[web.changes]]\nfixed = ["^go$"]\nstdin = true\n'
FB='[[web.page.blocks]]\ntype = "form"\nplan = ["ext/blkext", "go", "{host}"]\n'
FH='[[web.page.blocks.fields]]\nkey = "host"\nlabel = "Host"\ntype = "text"\nrequired = true\npattern = "^[a-z]+$"\n'
FS='[[web.page.blocks.fields]]\nkey = "token"\nlabel = "Token"\ntype = "secret"\n'
good "a form with a secret on stdin passes" "${CH}${PG}${FB%\\n}\nstdin = \"token\"\n${FH}${FS}"
good "a form with number, select and toggle passes" "${CH}${PG}${FB}${FH}[[web.page.blocks.fields]]\nkey = \"n\"\nlabel = \"N\"\ntype = \"number\"\nmin = 1\nmax = 9\n[[web.page.blocks.fields]]\nkey = \"s\"\nlabel = \"S\"\ntype = \"select\"\noptions = [\"a\", \"b\"]\n[[web.page.blocks.fields]]\nkey = \"t\"\nlabel = \"T\"\ntype = \"toggle\"\ndefault = true"
bad "an unknown field type is named" "unknown field type 'color'" "${CH}${PG}${FB}[[web.page.blocks.fields]]\nkey = \"host\"\nlabel = \"H\"\ntype = \"color\""
bad "a plan of another area is refused" "own area" "${CH}${PG}[[web.page.blocks]]\ntype = \"form\"\nplan = [\"ext/other\", \"go\"]\n${FH}"
bad "a plan the package does not declare is refused" "not allowlisted" "${PG}${FB}${FH}"
bad "a secret field without stdin is refused" "needs stdin" "${CH}${PG}${FB}${FH}${FS}"
bad "stdin that names no secret field is refused" "stdin must name the secret" "${CH}${PG}${FB%\\n}\nstdin = \"host\"\n${FH}"
bad "a secret in the plan arguments is refused" "may not use the secret" "${CH}${PG}[[web.page.blocks]]\ntype = \"form\"\nplan = [\"ext/blkext\", \"go\", \"{token}\"]\nstdin = \"token\"\n${FS}"
bad "a secret needs a change that takes stdin" "stdin = true" "[[web.reads]]\nargs = [\"x\"]\n[[web.changes]]\nfixed = [\"^go\$\"]\n${PG}${FB%\\n}\nstdin = \"token\"\n${FH}${FS}"
bad "two secret fields are refused" "at most one secret" "${CH}${PG}${FB%\\n}\nstdin = \"token\"\n${FH}${FS}[[web.page.blocks.fields]]\nkey = \"t2\"\nlabel = \"T2\"\ntype = \"secret\""
bad "a select without options is refused" "needs options" "${CH}${PG}${FB}${FH}[[web.page.blocks.fields]]\nkey = \"s\"\nlabel = \"S\"\ntype = \"select\""
bad "a bad pattern is refused" "not a valid regular" "${CH}${PG}${FB}[[web.page.blocks.fields]]\nkey = \"host\"\nlabel = \"H\"\ntype = \"text\"\npattern = \"(\""
bad "a plan placeholder that is no field is refused" "not a field" "${CH}${PG}${FB}[[web.page.blocks.fields]]\nkey = \"x\"\nlabel = \"X\"\ntype = \"text\""
bad "a form inside a tab is checked too" "unknown field type" "${CH}${PG}[[web.page.tabs]]\ntitle = \"T\"\n[[web.page.tabs.blocks]]\ntype = \"form\"\nplan = [\"ext/blkext\", \"go\"]\n[[web.page.tabs.blocks.fields]]\nkey = \"a\"\nlabel = \"A\"\ntype = \"blob\""
finish
