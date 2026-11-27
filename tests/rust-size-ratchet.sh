#!/usr/bin/env bash
# The file size ratchet of rust/ (scripts/dev/rust-size-ratchet.sh): counting stops at `#[cfg(test)]`, a new file over 400 lines and a
# listed file that grew fail, `lower` only lowers, and the real tree passes against tests/rust-size-ratchet.tsv. No root, no cargo.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
R="bash $SCRIPTS/dev/rust-size-ratchet.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/rust/a/src" "$T/rust/a/tests" "$T/rust/target/x"
lines() { local i; for ((i = 0; i < $1; i++)); do echo "// $i"; done; }
{ lines 10; echo '#[cfg(test)]'; lines 900; } > "$T/rust/a/src/small.rs"
lines 401 > "$T/rust/a/src/big.rs"
lines 900 > "$T/rust/a/tests/integration.rs"
lines 900 > "$T/rust/target/x/gen.rs"
printf '500\trust/a/src/big.rs\n' > "$T/base.tsv"
export HS_RUST_SIZE_ROOT=$T HS_RUST_SIZE_BASELINE=$T/base.tsv

check_eq "lines before the test module, integration tests and build output not counted" \
  "$(printf '401\trust/a/src/big.rs\n10\trust/a/src/small.rs')" "$($R list)"
check "a listed file under its ratchet passes" $R check
check_out "a listed file that shrank asks for lower" "rust-size-ratchet.sh lower" $R check
lines 501 > "$T/rust/a/src/big.rs"
if $R check >/dev/null 2>&1; then fail "a listed file that grew passed"; else pass "a listed file that grew fails"; fi
lines 450 > "$T/rust/a/src/big.rs"
lines 401 > "$T/rust/a/src/new.rs"
if $R check >/dev/null 2>&1; then fail "a new file over 400 lines passed"; else pass "a new file over 400 lines fails"; fi
rm "$T/rust/a/src/new.rs"
$R lower >/dev/null
check_eq "lower takes the baseline down to the file" "$(printf '450\trust/a/src/big.rs')" "$(cat "$T/base.tsv")"
lines 300 > "$T/rust/a/src/big.rs"
$R lower >/dev/null
check_eq "lower drops a file back under the limit" "" "$(cat "$T/base.tsv")"
unset HS_RUST_SIZE_ROOT HS_RUST_SIZE_BASELINE
check "the real tree passes against tests/rust-size-ratchet.tsv" $R check
finish
