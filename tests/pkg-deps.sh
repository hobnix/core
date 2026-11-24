#!/usr/bin/env bash
# Dependents of a package (scripts/lib/pkg-deps.sh, #1072): `requires` by name, by an interface with one or two providers, a recipe's `needs`,
# and `hs ext disable` refusing without changing anything. Throwaway packages folder and state. No root.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
export HS_LANG=en HS_PLAIN=1 HS_CALLER=test HS_STATE_DIR=$WORK/state HS_CAPABILITIES_FILE=$WORK/caps HS_MACHINE_FILE=$WORK/machine.toml
export HS_SETTINGS_DIR=$WORK/settings HS_PACKAGES_DIR=$WORK/packages
mkdir -p "$HS_STATE_DIR/packages" "$HS_PACKAGES_DIR"
printf 'hostName = "t"\n' > "$HS_MACHINE_FILE"
HS="bash $SCRIPTS/lib/hs.sh"
# shellcheck source=scripts/lib/pkg-deps.sh
. "$SCRIPTS/lib/pkg-deps.sh"

cap() {   # cap <name> <requires> <provides>: an extension package, the lists as `"a", "b"` or empty
  mkdir -p "$HS_PACKAGES_DIR/$1"
  printf 'name = "%s"\ntitle = "%s"\nkind = "feature"\nrequires = [%s]\nprovides = [%s]\nextension = true\n' "$1" "$1" "$2" "$3" > "$HS_PACKAGES_DIR/$1/capability.toml"
  : > "$HS_PACKAGES_DIR/$1/commands.tsv"
}
on() { printf '%s\n' "$@" > "$HS_CAPABILITIES_FILE"; }

echo "-- requires by name"
cap base "" ""; cap byname '"base"' ""; cap lone "" ""
on base byname lone
check_eq "a package that requires it by name is a dependent" "byname" "$(pkg_dependents base)"
check_eq "a package nobody requires has none" "" "$(pkg_dependents lone)"
on base lone
check_eq "a dependent that is off does not count" "" "$(pkg_dependents base)"

echo "-- requires by interface"
cap prova "" '"mail"'; cap provb "" '"mail"'; cap user '"mail"' ""
on prova user
check_eq "the only provider of an interface is needed" "user" "$(pkg_dependents prova)"
on prova provb user
check_eq "not while another provider is on (A)" "" "$(pkg_dependents prova)"
check_eq "not while another provider is on (B)" "" "$(pkg_dependents provb)"
on prova user
check_eq "a second provider that is off does not help" "user" "$(pkg_dependents prova)"

echo "-- recipe needs"
mkdir -p "$HS_PACKAGES_DIR/rec"
printf 'name = "rec"\nkind = "recipe"\nneeds = ["mail"]\n' > "$HS_PACKAGES_DIR/rec/package.toml"
: > "$HS_PACKAGES_DIR/rec/commands.tsv"
printf '[package.rec]\nversion = "1.0.0"\nrepo = "recipes"\n' > "$HS_STATE_DIR/packages/installed.toml"
on prova
check_eq "an applied recipe needing an interface depends on its provider" "rec" "$(pkg_dependents prova)"
on prova provb
check_eq "and not while a second provider is on" "" "$(pkg_dependents prova)"
: > "$HS_STATE_DIR/packages/installed.toml"
on prova
check_eq "a recipe that is not applied does not count" "" "$(pkg_dependents prova)"

echo "-- hs ext disable"
printf '[package.rec]\nversion = "1.0.0"\nrepo = "recipes"\n' > "$HS_STATE_DIR/packages/installed.toml"
on base byname prova
before=$(cat "$HS_CAPABILITIES_FILE")
check_out "refused while a package that is on requires it" "byname needs it" $HS ext disable base
check_out "refused for a recipe's interface" "rec needs it" $HS ext disable prova
check_eq "nothing changed on refusal" "$before" "$(cat "$HS_CAPABILITIES_FILE")"
check_eq "base is still on" "on" "$($HS sys ext list | awk -F'\t' '$1 == "base" { print $2 }')"
on base prova provb
check "allowed while another provider is on" $HS ext disable prova
check_eq "and it is off" "off" "$($HS sys ext list | awk -F'\t' '$1 == "prova" { print $2 }')"

finish
