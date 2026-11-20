#!/usr/bin/env bash
# The option of a capability package installed on this machine is a normal option (docs/PLAN-capabilities-repo.md, Q4, step 6b): `hs config
# list|set|check|sync` and `hs sys config plan set` know it from the generated overlay, the core keys stay as they are. No root, no server.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
export HS_LANG=en HS_PLAIN=1 HS_CALLER=test
export HS_STATE_DIR=$WORK/state HS_MACHINE_FILE=$WORK/machine.toml HS_MACHINE_EXAMPLE=$ROOT/machine.toml.example
export HS_GENERATED_DIR=$WORK/generated HS_PACKAGES_DIR=$WORK/packages
mkdir -p "$HS_STATE_DIR" "$HS_PACKAGES_DIR/pkgx"
M=$HS_MACHINE_FILE
CFG="bash $SCRIPTS/config.sh"; CHG="bash $SCRIPTS/config-change.sh"; SYNC="bash $SCRIPTS/machine-sync.sh"
GEN="python3 $SCRIPTS/schema-gen.py"
cp "$HS_MACHINE_EXAMPLE" "$M"; sed -i 's/CHANGEME/deadbeef/' "$M"
printf 'name = "pkgx"\nversion = "1.0.0"\nkind = "capability"\ntype = "feature"\ntitle = "Pkgx"\nrequires_core = ">=1"\naudience = "generic"\noptions = "options.toml"\n' > "$HS_PACKAGES_DIR/pkgx/package.toml"
cat > "$HS_PACKAGES_DIR/pkgx/options.toml" <<'T'
[[item]]
key = "pkgxHost"
capability = "pkgx"
store = "machine"
type = "string"
default = "pkgx.lan"
description = "Host name of pkgx."
settable = true
pattern = "^[a-z.]+$"
hint = "lower case letters and dots"

[[item]]
key = "pkgxPort"
capability = "pkgx"
store = "machine"
type = "int"
default = 8123
description = "Port of pkgx."
settable = true
min = 1024

[[item]]
key = "pkgxOn"
capability = "pkgx"
store = "machine"
type = "bool"
default = false
description = "Switch pkgx on."
T

echo "-- before the overlay: the key is unknown"
check_out "check warns about it" "pkgxHost.*unknown option" bash -c "printf 'pkgxHost = \"a.lan\"\n' >> '$M'; bash '$SCRIPTS/config-read.sh' check"
sed -i '/^pkgxHost/d' "$M"
check "the example is the core one" bash -c '[ "$(. "$1/lib/machine.sh"; machine_example)" = "$HS_MACHINE_EXAMPLE" ]' _ "$SCRIPTS"

echo "-- after overlay write"
check "write" $GEN overlay write --packages "$HS_PACKAGES_DIR" --out "$HS_GENERATED_DIR" --example "$HS_MACHINE_EXAMPLE"
check "the merged example starts with the core example" bash -c 'cmp -s -n "$(wc -c < "$1")" "$1" "$2"' _ "$HS_MACHINE_EXAMPLE" "$HS_GENERATED_DIR/machine.toml.example"
check "machine_example gives it" bash -c '[ "$(. "$1/lib/machine.sh"; machine_example)" = "$HS_GENERATED_DIR/machine.toml.example" ]' _ "$SCRIPTS"
check_out "sync puts the options in their section, off" "New options" $SYNC sync
check "the key is in machine.toml, commented out" grep -q '^# pkgxHost = "pkgx.lan"' "$M"
check_out "set a string" "is set" $CFG set pkgxHost a.lan
check "the line is active" grep -q '^pkgxHost = "a.lan"' "$M"
check_out "a value that breaks the pattern is refused" "must be lower case letters and dots" bash -c "$CFG set pkgxHost A_B 2>&1; true"
check_out "min is checked" "1024 or more" bash -c "$CFG set pkgxPort 80 2>&1; true"
check_out "a bool must be a bool" "true or false" bash -c "$CFG set pkgxOn maybe 2>&1; true"
check_out "set an int" "is set" $CFG set pkgxPort 9000
check_eq "the value is a number in the file" "pkgxPort = 9000" "$(grep '^pkgxPort' "$M")"
check_out "check knows the key and its type" "machine.toml is fine" bash "$SCRIPTS/config-read.sh" check
check_out "list shows it in a section of the package" "Package pkgx.pkgxPort.9000" bash -c "bash '$SCRIPTS/config-read.sh' list | awk -F'\t' '\$2 ~ /^pkgx/ { print \$1\".\"\$2\".\"\$3 }' | grep pkgxPort"
check_out "the web path (plan set) accepts it" "status.ok" bash -c "$CHG plan set pkgxHost b.lan | tr '\t' '.'"
check_out "and refuses a wrong type" "refused" bash -c "$CHG plan set pkgxPort abc; true"
sed -i 's/^pkgxPort = 9000/pkgxPort = "text"/' "$M"
check_out "check finds a wrong type" "pkgxPort.*must be" bash -c "bash '$SCRIPTS/config-read.sh' check 2>&1; true"
sed -i 's/^pkgxPort = "text"/pkgxPort = 9000/' "$M"

echo "-- the core keys are unchanged"
check_out "a core key is still set the old way" "is set" $CFG set keyMap de
check_out "a core key is still refused when wrong" "must be" bash -c "$CFG set syncEveryHours x 2>&1; true"
check "the core example is untouched" git -C "$ROOT" diff --quiet -- machine.toml.example

echo "-- the package goes away"
cp -r "$HS_PACKAGES_DIR/pkgx" "$WORK/pkgx.keep"
check "retire remembers the keys" $GEN overlay retire pkgx --packages "$HS_PACKAGES_DIR" --out "$HS_GENERATED_DIR"
rm -r "${HS_PACKAGES_DIR:?}/pkgx"
check "overlay write" $GEN overlay write --packages "$HS_PACKAGES_DIR" --out "$HS_GENERATED_DIR" --example "$HS_MACHINE_EXAMPLE"
check "the merged example is gone" test ! -e "$HS_GENERATED_DIR/machine.toml.example"
check "the option is not settable any more" bash -c "! $CFG set pkgxHost c.lan >/dev/null 2>&1"

check_eq "retired-keys.tsv lists the three keys" "pkgxHost pkgxOn pkgxPort" "$(grep -v '^#' "$HS_GENERATED_DIR/retired-keys.tsv" | cut -f1 | paste -sd' ')"
check_eq "with capability and version" "pkgx	1.0.0" "$(grep '^pkgxHost' "$HS_GENERATED_DIR/retired-keys.tsv" | cut -f2,3)"
echo "-- a removed package's key is a note, not an error"
sed -i 's/^# pkgxHost = .*/pkgxHost = "a.lan"/' "$M"
grep -q '^pkgxHost' "$M" || printf 'pkgxHost = "a.lan"
' >> "$M"
out=$(bash "$SCRIPTS/config-read.sh" check 2>&1); rc=$?
check_eq "check exits 0" 0 "$rc"
check "it says note, with the capability" bash -c 'grep -q "^note: pkgxHost: unused, capability pkgx removed" <<<"$1"' _ "$out"
check "and not unknown option" bash -c '! grep -q "unknown option" <<<"$1"' _ "$out"
check "a real typo is still a warning" bash -c "printf 'pkgxTypo = 1
' >> '$M'; bash '$SCRIPTS/config-read.sh' check 2>&1 | grep -q 'warning: pkgxTypo.*unknown option'"
echo "-- installed again: no longer retired"
cp -r "$WORK/pkgx.keep" "$HS_PACKAGES_DIR/pkgx"
check "overlay write" $GEN overlay write --packages "$HS_PACKAGES_DIR" --out "$HS_GENERATED_DIR" --example "$HS_MACHINE_EXAMPLE"
check "the retired list is gone" test ! -e "$HS_GENERATED_DIR/retired-keys.tsv"

echo "-- a machine.toml from before 0.10 (liveState, ADR 0026): ignored with a note, never an error"
for v in redis off db bogus; do
  cp "$HS_MACHINE_EXAMPLE" "$M"; sed -i 's/CHANGEME/deadbeef/' "$M"
  printf 'liveState = "%s"\n' "$v" >> "$M"
  out=$(bash "$SCRIPTS/config-read.sh" check 2>&1); rc=$?
  check_eq "liveState = $v: the check passes" "0" "$rc"
  check "liveState = $v: it says note, no warning" bash -c 'grep -q "^note: liveState: no longer used, live state is always on" <<<"$1" && ! grep -q "warning: liveState" <<<"$1"' _ "$out"
done
cp "$HS_MACHINE_EXAMPLE" "$M"; sed -i 's/CHANGEME/deadbeef/' "$M"
out=$(bash "$SCRIPTS/config-read.sh" check 2>&1)
check "without the key there is no note" bash -c '! grep -q liveState <<<"$1"' _ "$out"
check "the generated example no longer has the option" bash -c '! grep -q liveState "$1"' _ "$HS_MACHINE_EXAMPLE"

finish
