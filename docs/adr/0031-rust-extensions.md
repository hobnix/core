# 0031: Rust extensions: build, ship, test and run

Status: Accepted (2026-11-24), design only
Issue: hobnix/core#1129. Related: ADR 0010, 0011, 0014, docs/PLAN-registry.md, docs/PLAN-extensions.md, #1134, #1138.

This record is a design. Nothing in it was built or run for the record itself; the parts called "built" were checked in the files named. Not tested on hardware yet.

## Context

A Rust extension is a program, not a script, so it needs a path from source to a confined, unprivileged service on the server. Most of the shipping path exists: the
core manifest `[[binary]]` (path, sha256, bin, target; `scripts/lib/pkg_binary.py`, checked by `pkg.py validate`, `repo-check [--release]` and on the staged copy at
install and update), the SDK `rust/hobnix-ext-sdk` (command and service runners, `http::Client`, `integrations::parse`, `credential_for`), the bridge `hs-ext-svc@<name>`
(a transient unit `hs-ext-run-<name>`, keys as `LoadCredential=`), and in hobnix/extensions a pinned toolchain and a build that runs twice and compares hashes. The signed
index pins `commit` plus `tree`, and `tree` hashes every file of the package folder, so the binary bytes are already under the index signature.

Gaps found: a service calls `hs` (`hs sys pkg integrations`, `hs sys ext posters start`) from inside the confined unit, where `/var/lib/hs` is an empty tmpfs; `hs pkg update`
and `rollback` do not restart a running service; services run as uid 0 (#1134); the CI job `ext-crates` builds the extension crates of hobnix/official against the SDK of a core pull request.

## Decision

1. **Shipping path.** The program is shipped as a `[[binary]]` of the package. Its sha256 is checked at install and update on the staged copy (with the executable bit and
   the architecture) before the old copy is replaced. A binary is never committed on `develop` (`sha256 = ""` passes validate and repo-check as `binary.unbuilt`, and is
   refused by `--release` and by install) and is never a release asset. The release preparation builds it and commits it on the pull request into `main`, the only branch
   signed into the index. Extension binaries are not built by Nix.
2. **One Cargo workspace per crate.** Each crate (`extensions/<name>/{Cargo.toml, Cargo.lock, src/, tests/}`) is its own workspace root, so an SDK bump rebuilds only what
   changed. Shared crates, if any, are path dependencies outside the package tree. Rust extensions are AGPL-3.0 like the SDK.
3. **SDK pin.** The SDK stays in the core (`rust/hobnix-ext-sdk`, the owner of the protocol). A crate pins it by git `rev` on `develop`; `repo-check --release` requires a
   core `vX.Y.Z` tag for the pin on `main`.
4. **Service identity and state.** A service runs as a transient unit with `DynamicUser=yes`, `User=hsx-<name>` (at most 31 characters; a longer name is cut to 14 and gets
   `_<12 hex of sha256(name)>`), `StateDirectory=ext-hs/<name>`, `UMask=0077`. `fs.write:/var/lib/hs/<own name>` is mapped onto the state directory with
   `BindPaths=/var/lib/ext-hs/<name>:/var/lib/hs/<name>`, so the service keeps its path; any other `fs.write` is refused with the new code `ext.dynamic-write`. The first start
   moves an existing `/var/lib/hs/<name>` once. The same identity covers the `confine` command rows, in the same step, with a plan for both paths; that step needs its own
   hardware-test box.

   Built for the services (#1134), Not tested on hardware yet. The user-name cut above was corrected to the code: `_` cannot be in a package name, so a cut
   name never equals a short one (24 characters plus `-<6 hex>` could). The old folder is moved by ONE atomic rename to `/var/lib/ext-hs/<name>` (systemd takes
   it into `/var/lib/private/ext-hs/<name>`) and `/var/lib/hs/<name>` becomes a link, so root tools keep the old path; two folders at once, a wrong link or
   another file system refuse the start (`ext.state-conflict`, `ext.state-move-failed`) and nothing is merged, copied or deleted. Before each start, files a
   root command left behind get the service's user again (a file with a second hard link is left alone). The bridge state `/var/lib/hs/ext-svc` is no longer
   bound into the unit, `fs.read` of server or other extensions' state is refused (`ext.dynamic-read`), and the host backup includes `/var/lib/ext-hs` and
   `/var/lib/private/ext-hs`. Of decision 5 the unit has `ProtectProc=invisible`; `ProcSubset=pid` and the allow list `SystemCallFilter=@system-service` are
   not set (reasons in `scripts/lib/ext_confine.py`). What systemd itself does with these lines (bind source through the link, mount order, credential,
   user) is checked only by the VM stage `confine` (step list `dynamic`), which has never run.
5. **Hardening without the user.** `ProtectKernelTunables`, `ProtectKernelModules`, `ProtectKernelLogs`, `ProtectControlGroups`, `ProtectClock`, `ProtectHostname`,
   `ProtectProc=invisible`, `ProcSubset=pid`, `RestrictNamespaces`, `RestrictRealtime`, `RestrictSUIDSGID`, `LockPersonality`, `SystemCallArchitectures=native`,
   `SystemCallFilter=@system-service`, and `RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6`. `devices:gpu` adds `SupplementaryGroups=render video`. Kept as today: an empty
   `CapabilityBoundingSet`, `NoNewPrivileges`, `ProtectSystem=strict`, `TemporaryFileSystem=/var/lib/hs`, `InaccessiblePaths` for the secret locations, keys only in
   `$CREDENTIALS_DIRECTORY`. `MemoryDenyWriteExecute` stays off (Python services may need it). No host socket is granted.
6. **Network.** Only `RestrictAddressFamilies`. No `IPAddressAllow` or `IPAddressDeny`: that is a firewall decision, so `net` stays a declared permission only.
7. **Talking to the core.** Only the stdin/stdout protocol (ADR 0011). A service never calls `hs` and has no HTTP API. What it needs comes as protocol data: the integration
   listing in `init` (new field `integrations`, rows without keys, `v` stays 1). The core restarts a service when a provider of a declared integration is installed or
   removed, because keys are loaded only at start.
8. **Poster trigger, no broker.** A host action from a service is event-driven: the posters extension handles `pkg.media-hub.imported` itself. A `run` message limited by a
   `host:` permission (ADR 0014 step 3) is not chosen.
9. **Index.** The index entry gets an informational `binaries = [{bin, target, sha256, size}]`, so the client can say "contains a prebuilt program (x86_64)" before it
   downloads. Integrity needs no new field: the tree hash covers the bytes.
10. **Restart.** After `hs pkg update` or `rollback` of a package with `[service]` whose unit is active, the core restarts `hs-ext-svc@<name>` (best effort, `--no-block`, a
    `note` line).
11. **Test.** `cargo test` with fixtures in the package; the built program is driven through the reference supervisor `scripts/lib/ext_service.py`. Core CI adds the musl
    target to the rust job and, after #1074, a job that builds the Rust crates of the package repository against the SDK of the pull request (`[patch]` onto
    `rust/hobnix-ext-sdk`).

## Consequences

- media-hub moves to the listing from `init` and to the event trigger. The `init` field, the hardening, the dynamic user, the restart and the index field are separate core
  steps (issue #1129).
- A toolchain bump changes every binary hash, so every binary package needs a version bump. The binary is not reviewable; reproducibility depends on the pinned toolchain.
- Restart on provider change couples `hs pkg` to the services; it stays best effort.
- Risk, not run anywhere: the namespace order of `DynamicUser`, `StateDirectory` and `TemporaryFileSystem=/var/lib/hs`. Run the VM stage `confine` before the hardware test.
- Commands (`proto` rows) keep root and unconfined unless the row has `confine`; with decision 4 the `confine` rows get the dynamic user too.
