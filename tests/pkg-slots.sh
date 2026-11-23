#!/usr/bin/env bash
# The slots of a package (#472, scripts/lib/pkg_slots.py): `pkg validate` names an unknown slot and checks [[web.actions]], [[health]] and `requires`;
# a slot whose `requires` is off shows nothing; a health read becomes a problem that names the package. No root.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
export HS_LANG=en HS_PLAIN=1
PKG="python3 -I $SCRIPTS/pkg.py"
SL="python3 -I $SCRIPTS/lib/pkg_slots.py"
T=$WORK/tree/capabilities/slotext
mkdir -p "$T"
printf 'name = "slotext"\nversion = "1.0.0"\nkind = "extension"\ntitle = "Slot ext"\nrequires_core = ">=1"\naudience = "generic"\n' > "$T/package.toml"
cap() {   # cap <tables after the capability header>
  printf 'name = "slotext"\nkind = "feature"\nrequires = []\nprovides = []\nneeds = []\nextension = true\ntitle = "Slot ext"\n%b\n' "$1" > "$T/capability.toml"
}
validate() { HS_PACKAGES_ROOT=$WORK/tree $PKG validate 2>&1; }
good() { cap "$2"; if validate >/dev/null; then pass "$1"; else fail "$1: $(validate)"; fi; }
bad() {   # bad <what> <word> <capability tables>
  cap "$3"
  local out rc=0
  out=$(validate) || rc=$?
  if [ "$rc" = 1 ] && printf '%s' "$out" | grep -q "$2"; then pass "$1"; else fail "$1 (rc $rc: $out)"; fi
}
RD='[[web.reads]]\nwords = "checks"\nkind = "tsv"\nttl = 30\n'
ACT='[[web.actions]]\nid = "sync"\nlabel = "Start sync"\nplan = ["ext/slotext", "sync"]\nrole = "app-manager"\nmain = true\n'

good "no slot is fine" ''
good "an action, a health check and requires pass" "${RD}${ACT}requires = \"docker\"\n[[health]]\nid = \"stale\"\nread = \"checks\"\nrequires = \"docker\"\n[web.page]\ntitle = \"P\"\nrequires = \"docker\""
bad "an unknown slot is refused and the known ones are named" "unknown slot 'cards'.*known slots: page, tab, action, health, state" "[[web.cards]]\nid = \"x\""
bad "an unknown slot as a plain table is refused" "unknown slot 'tiles'" "[web.tiles]\nid = \"x\""
bad "an action plans only its own area" 'must be a list that starts with "ext/slotext"' "[[web.actions]]\nid = \"a\"\nlabel = \"A\"\nplan = [\"ext/other\", \"x\"]"
bad "an action role is checked" "role must be one of" "[[web.actions]]\nid = \"a\"\nlabel = \"A\"\nplan = [\"ext/slotext\"]\nrole = \"root\""
bad "an unknown action key is named" "no key colour" "[[web.actions]]\nid = \"a\"\nlabel = \"A\"\nplan = [\"ext/slotext\"]\ncolour = \"red\""
bad "two main actions are refused" "only one action is the main action" "[[web.actions]]\nid = \"a\"\nlabel = \"A\"\nplan = [\"ext/slotext\"]\nmain = true\n[[web.actions]]\nid = \"b\"\nlabel = \"B\"\nplan = [\"ext/slotext\"]\nmain = true"
bad "a health check names a declared read" "is not a \[\[web.reads\]\] of this package" "[[health]]\nid = \"h\"\nread = \"nope\""
bad "a health read is a tsv without arguments" "must be kind tsv" "[[web.reads]]\nwords = \"checks\"\nkind = \"json\"\nttl = 30\n[[health]]\nid = \"h\"\nread = \"checks\""
bad "requires must be a name" "requires must be the name" "${RD}[[health]]\nid = \"h\"\nread = \"checks\"\nrequires = \"Not A Name\""
bad "requires may not name the package itself" "names the package itself" "${ACT}requires = \"slotext\""

# --- what is shown: requires off -> nothing; on -> the slot ---
out=$($SL requires "$T/capability.toml" 2>&1 || true)
cap "${ACT}requires = \"zzz\"\n[web.page]\ntitle = \"P\"\n[[web.page.tabs]]\ntitle = \"T\"\nrequires = \"zzz\"\n[web.page.state]\nread = \"checks\"\ndot = 0\nline = 1\nrequires = \"zzz\""
out=$(HS_CAPABILITIES_FILE=$WORK/none HS_STATE_DIR=$WORK/state $SL requires "$T/capability.toml" 2>&1)
for w in "action	zzz" "tab	zzz" "state card	zzz"; do
  if grep -qF "$w" <<<"$out"; then pass "install dialog lists the off requires: ${w%%	*}"; else fail "requires lists $w ($out)"; fi
done
printf 'zzz\n' > "$WORK/caps"
out=$(HS_CAPABILITIES_FILE=$WORK/caps HS_STATE_DIR=$WORK/state $SL requires "$T/capability.toml" 2>&1)
check_eq "nothing is listed once the required part is on" "" "$out"

shown=$(python3 -I - "$SCRIPTS/lib" <<'EOF'
import importlib.util, sys, tomllib, json
spec = importlib.util.spec_from_file_location("s", sys.argv[1] + "/pkg_slots.py"); s = importlib.util.module_from_spec(spec); spec.loader.exec_module(s)
doc = tomllib.loads("""
title = "X"
[[web.actions]]
id = "a"
label = "A"
plan = ["ext/x", "a"]
requires = "off"
[[web.actions]]
id = "b"
label = "B"
plan = ["ext/x", "b"]
[[health]]
id = "h"
read = "r"
requires = "off"
[[web.reads]]
words = "r"
kind = "tsv"
ttl = 5
[web.page]
title = "P"
[[web.page.tabs]]
id = "t0"
label = "Keep"
[[web.page.tabs]]
id = "t1"
label = "Drop"
requires = "off"
""")
d = s.declared("x", doc, {"on"})
print(json.dumps([[a["id"] for a in d["actions"]], d["actions"][0].get("main"), [h["id"] for h in d["health"]]]))
g = s.gate_page({"tabs": doc["web"]["page"]["tabs"], "blocks": [{"tab": "t1"}, {"tab": "t0"}]}, {"on"})
print(json.dumps([[t["id"] for t in g["tabs"]], g["blocks"]]))
print(s.gate_page({"requires": "off"}, {"on"}))
EOF
)
check_eq "an action that requires something off is dropped, the next one is the main action" '[["b"], true, []]' "$(sed -n 1p <<<"$shown")"
check_eq "a tab that requires something off is dropped with its blocks" '[["t0"], [{"tab": "t0"}]]' "$(sed -n 2p <<<"$shown")"
check_eq "a page that requires something off is None" "None" "$(sed -n 3p <<<"$shown")"

# --- a health read: warn and bad rows are problems that name the package; ok rows are not ---
P=$WORK/pk/hx
mkdir -p "$P"
printf 'name = "hx"\nkind = "feature"\ntitle = "Hx tool"\nextension = true\n[[web.reads]]\nwords = "checks"\nkind = "tsv"\nttl = 30\n[[health]]\nid = "stale"\nread = "checks"\n' > "$P/capability.toml"
printf 'hx\n' > "$WORK/caps2"
cat > "$WORK/fakehs" <<'EOF'
#!/usr/bin/env bash
# fake hs: `hs sys ext hx checks`
[ "$*" = "sys ext hx checks" ] || exit 2
printf 'ok\tfine\ninfo\tpc is off\nwarn\tsync is 3 days old\nbad\t-\n'
EOF
env_h="HS_PACKAGES_DIR=$WORK/pk HS_CAPABILITIES_FILE=$WORK/caps2 HS_STATE_DIR=$WORK/state HS_BIN=$WORK/fakehs"
out=$(env $env_h $SL problems 2>&1)
check_eq "a warn and a bad row make one problem that names the package" "ext:hx:stale	Hx tool: sync is 3 days old; needs attention" "$out"
check_eq "list shows an info row" "hx	stale	info	pc is off" "$(env $env_h $SL list 2>&1 | grep info)"
check_eq "info lists the info rows with the package named" "hx	stale	Hx tool	pc is off" "$(env $env_h $SL info 2>&1)"
check_eq "hs sys health info runs it" "hx	stale	Hx tool	pc is off" "$(env $env_h bash $SCRIPTS/health-check.sh --info 2>&1)"
printf '#!/usr/bin/env bash\nprintf "info\\tpc is off\\nok\\tfine\\n"\n' > "$WORK/fakehs"
check_eq "an info row alone is no problem" "" "$(env $env_h $SL problems 2>&1)"
printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/fakehs"
out=$(env $env_h $SL problems 2>&1)
check_eq "a read that fails is a problem, not silence" "ext:hx:stale	Hx tool: the health check stale could not be read" "$out"
printf 'other\n' > "$WORK/caps3"
out=$(env HS_PACKAGES_DIR=$WORK/pk HS_CAPABILITIES_FILE=$WORK/caps3 HS_STATE_DIR=$WORK/state HS_BIN=$WORK/fakehs $SL problems 2>&1)
check_eq "a package that is off adds no problem" "" "$out"
finish
