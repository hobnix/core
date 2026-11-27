# The build and test environment of rust/ from the nixpkgs pin (config/nixpkgs-pin.toml): the rustc of rust/rust-toolchain.toml and the SQLite
# that hobnix-core links (it refuses a SQLite with the WAL-reset bug, which the SQLite of a distribution may still have). CI (job `rust`),
# tests/rust-cargo.sh and tests/event-writer-concurrent.sh use it; by hand: `nix-shell scripts/dev/rust-shell.nix`.
let
  pin = builtins.fromTOML (builtins.readFile ../../config/nixpkgs-pin.toml);
  pkgs = import (builtins.fetchTarball "https://github.com/NixOS/nixpkgs/archive/${pin.rev}.tar.gz") { };
in
pkgs.mkShell {
  nativeBuildInputs = with pkgs; [ cargo rustc clippy rustfmt pkg-config python3 ];
  buildInputs = [ pkgs.sqlite ];
  # cargo looks for `cargo clippy` and `cargo fmt` in $CARGO_HOME/bin before the PATH: a home of its own keeps rustup's out
  shellHook = ''
    export CARGO_HOME="''${HOBNIX_CARGO_HOME:-$HOME/.cache/hobnix-cargo}"
    export HOBNIX_RUST_SHELL=1
  '';
}
