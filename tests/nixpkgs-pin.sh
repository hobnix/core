#!/usr/bin/env bash
# The nixpkgs pin (config/nixpkgs-pin.toml, scripts/dev/nixpkgs-pin.sh): reading, the malformed file, bump to a given revision, and that the
# real file is well formed and written in one place only. No root, no network (bump --rev needs none).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
P="bash $SCRIPTS/dev/nixpkgs-pin.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
A=1111111111111111111111111111111111111111
B=2222222222222222222222222222222222222222
printf '# comment\nchannel = "nixos-26.05"\nrev = "%s"\n' "$A" > "$T/pin.toml"
export HS_NIXPKGS_PIN_FILE=$T/pin.toml

check_eq "get channel" "nixos-26.05" "$($P get channel)"
check_eq "get rev" "$A" "$($P get rev)"
check_eq "get url" "https://github.com/NixOS/nixpkgs/archive/$A.tar.gz" "$($P get url)"
check_eq "github-env" "NIXPKGS_REV=$A NIXPKGS_CHANNEL=nixos-26.05" "$($P github-env | paste -sd' ')"
check_eq "bump to a given revision prints old and new" "$A $B" "$($P bump --rev $B)"
check_eq "the file holds the new revision, the comment stays" "$B 1" "$($P get rev) $(grep -c '^# comment' "$T/pin.toml")"
check_eq "bump to the same revision changes nothing" "unchanged" "$($P bump --rev $B)"
if $P bump --rev nothex >/dev/null 2>&1; then fail "a malformed revision was accepted"; else pass "a malformed revision is refused"; fi
printf 'channel = "stable"\nrev = "%s"\n' "$A" > "$T/pin.toml"
if $P get rev >/dev/null 2>&1; then fail "a malformed channel was accepted"; else pass "a malformed channel is refused"; fi
printf 'channel = "nixos-26.05"\n' > "$T/pin.toml"
if $P get rev >/dev/null 2>&1; then fail "a missing revision was accepted"; else pass "a missing revision is refused"; fi
printf 'channel = "nixos-26.05"\nrev = "%s"\n' "$A" > "$T/pin.toml"
# the toolchain follows the rustc of the pin (HS_NIXPKGS_RUSTC stands in for the nix evaluation)
printf '# keep\n[toolchain]\nchannel = "1.95.0"\ncomponents = ["clippy"]\n' > "$T/tc.toml"
export HS_RUST_TOOLCHAIN_FILE=$T/tc.toml
check_eq "toolchain-check passes when the channel is the rustc of the pin" 0 "$(HS_NIXPKGS_RUSTC=1.95.0 $P toolchain-check >/dev/null 2>&1; echo $?)"
check_eq "toolchain-check fails when they differ" 1 "$(HS_NIXPKGS_RUSTC=1.96.1 $P toolchain-check >/dev/null 2>&1; echo $?)"
check_eq "toolchain-sync prints old and new" "1.95.0 1.96.1" "$(HS_NIXPKGS_RUSTC=1.96.1 $P toolchain-sync)"
check_eq "the toolchain file holds the new channel, the rest stays" 'channel = "1.96.1" 1 1' \
  "$(grep '^channel' "$T/tc.toml") $(grep -c '^# keep' "$T/tc.toml") $(grep -c '^components' "$T/tc.toml")"
check_eq "toolchain-sync to the same version changes nothing" "unchanged" "$(HS_NIXPKGS_RUSTC=1.96.1 $P toolchain-sync)"
if HS_NIXPKGS_RUSTC=stable $P toolchain-sync >/dev/null 2>&1; then fail "a version that is not x.y.z was written"; else pass "a version that is not x.y.z is refused"; fi
unset HS_NIXPKGS_PIN_FILE HS_RUST_TOOLCHAIN_FILE
check "the real pin file is well formed and written in one place only" $P check
# a line at column 0 inside a `run: |` block ends the block and becomes a top-level key; GitHub then rejects the whole file
stray=$(grep -nvE '^($|#|---|(name|run-name|on|permissions|env|defaults|concurrency|jobs):|[[:space:]])' .github/workflows/*.yml || true)
if [ -z "$stray" ]; then pass "every workflow file has only workflow keys at the top"; else printf '%s\n' "$stray"; fail "a workflow file has a stray line at column 0"; fi
finish
