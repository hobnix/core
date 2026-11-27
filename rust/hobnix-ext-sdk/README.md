# hobnix-ext-sdk (deprecated)

The Rust extension SDK before 0.14. It is now the crates `hobnix-pkg`, `hobnix-pkg-command` and `hobnix-pkg-service` (see
[../hobnix-pkg/README.md](../hobnix-pkg/README.md) and docs/extensions-sdk.md "Write it in Rust"). This crate re-exports them under the old
paths for one release, keeps the 0.13 signatures where the new ones differ, and is removed after 0.14. `tests/protocol.rs` is the test file of
0.13 and must keep passing until then.
