# Plan: one SDK for packages

Design record. Contributor document, not a guide. Written 2026-11-24 during 0.13. Builds on ADR 0010 (command protocol), ADR 0011 (service lifecycle), ADR 0014 (permissions), ADR 0015 (Wasm: deferred) and docs/PLAN-packages.md, PLAN-extensions-access.md (SDK #240). Step 2 (the split) is built in 0.14 (#1262, #1309), and so are the commands registered from code (#1263); the rest is planned. Not tested on hardware yet.

## Where we are

- Before 0.14, `rust/hobnix-ext-sdk` was the extension side of two protocols: `command` (one process per call, one JSON line in, JSON Lines out) and `service` (long-running, init/event/shutdown), plus `http`, `integrations` and `Event`. Shell and Python helpers and a Go example exist for authors in other languages (docs/extensions-sdk.md).
- A command lives in two places: a row in the package's `commands.tsv` (name, flags, help; a `proto` flag when a program speaks the protocol) and a `match req.words()` in the program. Nothing checks that they agree (observed in `command.rs` and PLAN-packages.md; not tested).
- Recipes and capabilities do not use an SDK. A recipe is a `package.toml` plus a shell script; a capability is a `module.nix` plus its contract.
- ADR 0010 already allows any executable that speaks the protocol, so commands written in Rust are possible today. The bash commands of existing extensions are history and convenience, not a limit of the protocol. (Check with the authors before changing them.)

- ADR 0031 (Rust extensions, hobnix/core#1129, accepted 2026-11-24) already fixes how a Rust extension is built and shipped: `[[binary]]` in the package, one Cargo workspace per crate, built by the release preparation (not by Nix), the SDK pinned by git `rev` (a core `vX.Y.Z` tag on `main`), a dynamic user and hardening for services, and no `hs` calls from a service. This plan stays inside those rules. Because crates pin the SDK by `rev`, the 0.14 rename reaches a crate only when it bumps its pin; older pins keep working.

## Goals

1. A package author writes the program and gets the manifest, help, schema and tests from it, not by hand in four places.
2. Our own packages (`hobnix/official`) are the reference for the practices (docs/CODE-PRACTICES.md).
3. A community author in Rust, Go or shell can build a package without reading the core, from the protocol schemas and the SDK docs.
4. The API is shaped so a Wasm backend can come later without a change for authors (ADR 0015).

## Design

### Crates

One shared base and one crate per package kind. The current `hobnix-ext-sdk` is split and renamed; this is the only breaking step and happens once, in 0.14.

| Crate | Content |
|---|---|
| `hobnix-pkg` | Manifest types, error type, `Ctx`, `Event`, logging, `Secret`, line limits, the version constant; the wire messages of both protocols (`wire`) |
| `hobnix-pkg-command` | The command runner and the `#[command]` macro (from `hobnix-pkg-macros`, feature `macros`) |
| `hobnix-pkg-service` | The service lifecycle (init, event, health, snapshot, rollup, shutdown) |
| `hobnix-pkg-recipe` | Hooks for install, configure, update and remove; instance helpers; `docs_hint` |
| `hobnix-pkg-test` | A fake core for tests (dev dependency) |
| `hobnix-ext-sdk` | Re-exports the new crates and is marked deprecated for one release, then removed |

`hobnix-pkg-recipe` is written only after two or three Rust recipes exist in `hobnix/official`; before that its API would be a guess.

### Commands registered from code

The code is the source and the manifest is generated from it, like `schema.toml` produces `defaults.nix`.

```rust
#[command(name = "status", reads, help = "Show the sync state", help_de = "Zeigt den Sync-Zustand")]
fn status(ctx: &Ctx, args: StatusArgs) -> Result<Output, Error> { ... }
```

From the attributes and the argument struct, the build produces:
- the `commands.tsv` rows, including `proto`, `reads|changes` and the help texts
- the argument schema (names, types, defaults, required) for help, completion and, later, web forms
- the dispatch: the `match` is generated, so a command without a handler cannot exist

`hs pkg validate` fails when the committed `commands.tsv` differs from the generated one (drift). Generation is at build time, not at run time, because the core must know a package's commands, hash and permissions before it starts the program (PLAN-packages.md `binary.undeclared`). The macro lives behind a feature so a package can still write rows by hand.

Built in 0.14 (#1263), as an attribute crate `hobnix-pkg-macros` behind the feature `macros` of `hobnix-pkg-command` (usage: docs/extensions-sdk.md "Write it in Rust"):
- `#[command(...)]` keeps the function and adds a hidden constant; `#[derive(Args)]` makes the schema and the reader of the arguments (positional: required, then `Option<T>`, then one `Vec<T>`); `commands!(package = "...", script = "@/...", f, g)` lists the functions and is the dispatch.
- The rows are built by const evaluation into one byte string in the program (`TABLE_START`, then the rows, then a NUL). `python3 scripts/pkg.py validate` reads it from the `[[binary]]` file without running the program and refuses a `commands.tsv` whose rows for that program differ (`binary.drift`, in order; comment lines and rows of other programs are ignored). Because no program is committed on `develop` (ADR 0031), `Commands::check(include_str!("../commands.tsv"))` in `cargo test` is the drift check there. A program without the table is not checked.
- Not built: the argument schema is not written to any file (only `Command::args()` in the program), so `hs help`, completion and web forms do not use it yet; the rows carry `-` as their argument field. Permissions in code are not part of it.
- Measured 2026-11-26 in WSL (32 CPUs), from an empty target dir, `cargo build --release`: the example without the macros (`hello`) 5.4 s, with them (`hello_macro`) 5.7 s; with `-j 1` 26.2 s and 26.6 s. syn, quote and proc-macro2 are built in both cases (serde_derive needs them); the macros add syn's `full` feature and the macro crate. `nix-build pkgs/hobnix.nix` (it builds every workspace member, the macro crate too, and runs the tests) took 20 s before and 22 s after, with the vendored crates already in the store. The attribute crate stays; the `build.rs` fallback is not needed.

### `Ctx`: everything a package asks of the host

`Ctx` is a trait with one implementation per runtime. A package calls `ctx.credential(...)`, `ctx.integrations()`, `ctx.emit(event)`, `ctx.log(...)`, `ctx.progress(...)`: only what the protocol already carries (ADR 0010, 0011, 0031). It has **no** host-command call: ADR 0031 decisions 7 and 8 say a service never calls `hs` and that no broker is chosen; a host action is event-driven. A command is a root process today and may use the OS; a `Ctx::run_host_command` is added only if a later record chooses the broker of ADR 0014 step 3.

- Native runtime: implemented over the protocol and, where ADR 0014 allows, `std`.
- Test runtime (`hobnix-pkg-test`): a fake with recorded answers.
- Wasm runtime (later): the same trait, backed by host functions.

A Wasm backend would also need the host surface a command uses (the spike of ADR 0015 point 4 measures it); with no host-command call in `Ctx` that surface is small for services and open for commands, which is one more reason to start Wasm with commands that only transform data. This is the one decision that must be made in 0.13 even though the build is later: designing `Ctx` as a trait from the start is cheap, and it is what keeps a Wasm backend possible without changing package code.

### Permissions in code

ADR 0014 declares permissions in the manifest (`fs.*`, `net`, `host`, `secrets`, `events.*`). The SDK can derive the declaration from the `Ctx` calls a package uses (an attribute lists them; a lint or test checks the code does not use more). Optional in 0.14; useful before third-party packages exist.

### Test harness

`hobnix-pkg-test` runs a command against a fake core: give it a request and recorded host answers, get the result lines and the events. Today `docs/extensions-sdk.md` ("Try it without a server") shows a shell way only.

### Templates and checks

- `hs pkg new --template` gets Rust variants for command and service extensions with the macro, tests and a CI file in place. Today only the recipe template and the shell and Python extension templates exist.
- A CI template for package repositories: `fmt`, `clippy -D warnings`, tests, `hs pkg validate`, drift check.
- A `requires_core` range in the manifest, beside the protocol `"v": 1`, so a package says which core it works with.

## What the SDK does not do

- It does not hide the protocol. A shell or Go author must still be able to implement it from `docs/api/ext-protocol-v1.schema.json` and `ext-service-v1.schema.json`. The SDK is a convenience, not the contract.
- It does not weaken a rule: a command still declares its permissions and its binary hash.

## Wasm for commands (later)

ADR 0015 defers Wasm with named triggers (third-party packages, a broker, a portable binary). This plan keeps that decision and adds only what is cheap now:

- keep ADR 0010 transport-neutral (rule of ADR 0015, unchanged);
- build `Ctx` as a trait (above);
- when a trigger fires, the first candidate is a Wasm *command*, not a service: a command is short-lived and stateless, so start-up time and sandboxing both favour it, and the host surface to expose is small. The manifest field is `runtime = "wasm"` on the command (ADR 0015 open point 2), run by `wasmtime run` with the JSON Lines contract. A service follows only after commands have proved the host interface.
- the spike in ADR 0015 (closure size, cold start, UDP, host call cost) has not been run and comes first.

A new ADR amends ADR 0015 when this is picked up; this plan does not.

## Steps

| Step | Release | Content |
|---|---|---|
| 1 | 0.13 | This document; `Ctx` as a trait inside the current SDK without renaming (small, internal) |
| 2 | 0.14 | Split and rename to `hobnix-pkg*`; `hobnix-ext-sdk` re-exports; migrate `hobnix/official` extensions (built, see "Step 2 as built"; the migration of `hobnix/official` is open) |
| 3 | 0.14 | `#[command]` macro, generated `commands.tsv`, drift check in `hs pkg validate` |
| 4 | 0.14 | `hobnix-pkg-test`, Rust templates, CI template |
| 5 | when two Rust recipes exist | `hobnix-pkg-recipe` |
| 6 | when a trigger of ADR 0015 fires | Wasm spike, then a Wasm command pilot |

## Step 2 as built (0.14)

- `hobnix-pkg` holds `Ctx` (credential now returns `Secret`; `&C` and `Arc<C>` of a `Ctx` are one), `Event`, `LogLevel`, `EventLevel`, `Lang`,
  `Secret`, `Error` (a kind that maps to the command codes, a message, a cause), `credentials`, `integrations`, `http` (header values made
  from a `Secret` are never printed) and `testing::FakeCtx`. No manifest types yet: they come with the macro (step 3).
- `hobnix_pkg::wire` (#1309, step P1 "shared protocol types" of docs/PLAN-core-daemon.md pulled forward): every message of both protocols is
  a type with `Serialize` and `Deserialize`, grouped by direction (`command::FromCore`, `command::FromExtension`, `service::FromCore`,
  `service::FromService`). `encode` writes sorted keys (the bytes do not depend on `serde_json/preserve_order`), `decode` checks `v` and
  returns `Decoded::Unknown` for a type it does not know; `Writer` and `read_line` keep the 1 MiB limit. The runners are built on them, and
  a later host in the core uses the same types. No host is in this step and no dependency was added. Tests pin the bytes of every
  extension line and the round trip of the lines the Python host writes (keys sorted).
- Growable types are `#[non_exhaustive]` with constructors; `Lang::Other`, `Caller::Other` and `ResultCode::Other` take values a newer core
  sends. `Integration` and `Health` are not `#[non_exhaustive]` yet: extensions of 0.13 (media-hub) build them with struct literals, and they
  are the same types through the shim. They get the attribute when `hobnix-ext-sdk` is removed.
- `hobnix-ext-sdk` keeps the 0.13 signatures where the new ones differ: its own `Ctx` trait (credential as `String`, `event`, a blanket
  implementation for every `hobnix_pkg::Ctx`), its own `Service` trait with `Result<(), String>` and an adapter, its own `Request` struct,
  `service::credential_for` as `String`. Its entry points are `#[deprecated]`. Its test file is the one of 0.13, unchanged but for the
  attribute; the examples of 0.13 and the crates of `hobnix/official` build against it.
- **Decided by the owner, 2026-11-26:** the old name does not promise an unchanged build. The types it re-exports are the new ones, so some code of
  0.13 needs an edit (the list is in [extensions-sdk](extensions-sdk.md)). Copies of the 0.13 types for one release were rejected as too much
  throwaway code. A crate that keeps its old pin is not affected.

## Open points

Decided 2026-11-24:

1. **Macro:** start with the attribute macro (proc-macro crate) and measure the build time under Nix; fall back to a `build.rs` generator if the cost is high.
2. **`requires_core`** is a range of `api-level` only (6 today, scripts/lib/api-level), not of the core version.
3. **Publishing:** the SDK stays in the repository and is used through Nix (`publish = false`). crates.io is reconsidered after the API has survived one release and an outside author has used it; a published crate cannot be withdrawn.
4. **Helpers:** the shell helper stays for small glue; the Python helper is deprecated together with Python; the Go example stays as documentation.
5. **`hobnix-pkg-recipe`** is written only after two or three Rust recipes exist in `hobnix/official`.
6. **Rename:** `hobnix-ext-sdk` to `hobnix-pkg*` in 0.14 is announced in the 0.13 release notes (breaking change, one release of re-exports).
