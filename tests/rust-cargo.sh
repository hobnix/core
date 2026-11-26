#!/usr/bin/env bash
# The local routine for rust/ (docs/CODE-PRACTICES.md "Rust: checks"): cargo fmt --check, clippy and test with all features, the SDK built
# alone. `scripts/dev/t changed` picks it for any change under rust/ (scripts/dev/tests-for.sh). Skipped (77) without cargo, off Linux, and in
# CI, where the job `rust` runs the same commands on the pinned toolchain. Set CARGO_TARGET_DIR to keep builds out of the worktree.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
[ -z "${CI:-}" ] || { echo "  skip  CI runs these in the job rust"; exit 77; }
command -v cargo >/dev/null || { echo "  skip  cargo missing"; exit 77; }
[ "$(uname -s)" = Linux ] || { echo "  skip  needs Linux (WSL)"; exit 77; }
cd "$ROOT/rust" || exit 1
cargo_ok() {   # cargo_ok "what" args...: the last lines of the output on failure
  local what=$1; shift
  if cargo "$@" > "$WORK/cargo.log" 2>&1 </dev/null; then pass "$what"; else fail "$what: $(tail -n 8 "$WORK/cargo.log" | tr '\n' ' ')"; fi
}
cargo_ok "cargo fmt --check" fmt --check
cargo_ok "clippy, all targets and features, warnings are errors" clippy --locked --all-targets --all-features -- -D warnings
cargo_ok "tests, all features" test --locked --all-features
cargo_ok "tests of the SDK built alone" test --locked -p hobnix-ext-sdk
finish
