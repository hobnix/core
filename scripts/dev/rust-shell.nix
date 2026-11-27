# The build and test environment of rust/ from the nixpkgs pin (config/nixpkgs-pin.toml): the rustc of rust/rust-toolchain.toml and the SQLite
# that hobnix-core links (it refuses a SQLite with the WAL-reset bug, which the SQLite of a distribution may still have). CI (job `rust`),
# tests/rust-cargo.sh and the tests/event-writer-*.sh use it; by hand: `nix-shell scripts/dev/rust-shell.nix`.
# HOBNIX_NIXPKGS_DIR: an unpacked copy of the pinned nixpkgs (CI keeps the tarball in its cache); without it nix fetches the pin.
let
  pin = builtins.fromTOML (builtins.readFile ../../config/nixpkgs-pin.toml);
  unpacked = builtins.getEnv "HOBNIX_NIXPKGS_DIR";
  nixpkgs =
    if unpacked != "" then unpacked
    else builtins.fetchTarball "https://github.com/NixOS/nixpkgs/archive/${pin.rev}.tar.gz";
  pkgs = import nixpkgs { };
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
