# Write an extension

Write a command for an extension in shell, Python, Go or Rust. The core starts your program once per call, sends one JSON request and reads
JSON lines back. Not tested on hardware yet; the examples below run in the test suite against the reference runner of the core.

## Before you start

- A checkout of a package repository (`index.toml` and an `extensions/` folder). See [Containers and apps](containers-and-apps.md).
- A server at API level 10 or newer: the extension asks for it with `requires_core = ">=10"`.
- Shell needs `bash` and `jq`; Python needs `python3` (standard library only); Go needs the Go toolchain; Rust needs `cargo`.

## Start an extension

```bash
hs pkg new my-ext --template extension --protocol python --dir <repository>
```

`--protocol` is `shell` or `python`. It writes a package that passes the checks as it is: `package.toml` with `protocol = [1]`, a
`commands.tsv` whose rows run `list.py` (or `list.sh`), and a guide. Without `--protocol` the template keeps the older contract (arguments
in, text out, exit status for failure). Go and Rust are not templates: copy an example.

## How a call works

- The core writes one line to your stdin: `{"v":1,"type":"request","id":...,"command":["greet"],"argv":["Ada"],"lang":"en","caller":"cli","timeout_ms":30000}`.
  `command` holds the words after the extension name, `argv` the rest.
- You write lines to stdout, each a JSON object with `"v":1` and a `type`: `progress` (`fraction` 0 to 1, `text`), `log` (`level`, `text`),
  `event` (`kind` like `pkg.<name>.<what>`, `subject`) and, last and once, `result`.
- A `result` is `{"ok":true,"data":...,"text":...}` and exit status 0, or `{"ok":false,"error":{"code":...,"message":...}}` and exit status 1.
  Codes: `failed`, `not_found`, `bad_request`, `cancelled`. An unknown `v` is answered `unsupported_version` with `"supported":[1]`.
- Nothing else goes to stdout; diagnostics go to stderr. The core prints `data` as tab-separated lines (a list of lists is one line per
  inner list, an empty cell is `-`), or `text` for a person at a terminal.
- A call ends at its limit (30 s; a `timeout:<seconds>` flag in `commands.tsv` raises it to at most 3600). Stop on SIGTERM.
- A row with the flag `confine` in `commands.tsv` runs through `systemd-run` with the properties of your `permissions`, as the unprivileged user `hsx-<name>` and not as root (no new privileges, no devices unless `devices:gpu`). It may write only its state folder, shared with your service (declare `fs.write:/var/lib/hs/<name>`; in the command it is `$STATE_DIRECTORY`, `/var/lib/hs-ext/<name>`); any other `fs.write` is refused (`ext.dynamic-write`, exit 69). It needs `protocol = [1]` and a `permissions` list. It is partial: reads (as far as the file modes allow) and the network are not limited, and calls to `hs`, `incus` and `systemctl` are not blocked (they get what that user may do). Not tested on hardware yet.

The exact format is [docs/api/ext-protocol-v1.schema.json](api/ext-protocol-v1.schema.json); the decision is ADR 0010.

## Write it in shell

Source the helper `scripts/lib/ext_sdk.sh`; the core sets `HS_SCRIPTS` to the folder of its scripts.

```bash
. "${HS_SCRIPTS:?}/lib/ext_sdk.sh"
ext_init
case "${EXT_WORDS[0]:-}" in
  greet) ext_ok "hello ${EXT_ARGV[0]:-world}" ;;
  *) ext_fail not_found "no such command" ;;
esac
```

`ext_init` fills `EXT_WORDS`, `EXT_ARGV`, `EXT_LANG`, `EXT_CALLER`. The others are `ext_progress <fraction|-> <text>`,
`ext_log <level> <text>`, `ext_event <kind> <subject> [text]`, `ext_ok [text] [data-json]` and `ext_fail <code> <message>`; the last two
end the script. The full example is `sdk/examples/shell/hello.sh`.

## Write it in Python

The core starts a `.py` file with `python3 -I`, which does not search the script's folder, so add the helper's folder yourself:

```python
import os, sys
sys.path.insert(0, os.path.join(os.environ["HS_SCRIPTS"], "lib"))
import ext_sdk

def handle(req, ctx):
    if req.words == ["greet"]:
        ctx.progress(0.5, "halfway")
        return ext_sdk.ok({"greeting": "hello"}, text="hello")
    raise ext_sdk.Failure("not_found", "no such command")

ext_sdk.run(handle)
```

`ctx` has `progress`, `log` and `event`. A `Failure` becomes an error result; any other exception becomes `failed` with the traceback on
stderr. The full example is `sdk/examples/python/hello.py`.

## Write it in Go

Go has no library on purpose: the protocol is five message types and the example is the whole of it, standard library only. Copy
`sdk/examples/go/main.go`, build it with `go build`, and point the row of `commands.tsv` at the binary.

## Write it in Rust

The SDK is three crates in `rust/` (0.14; docs/PLAN-package-sdk.md):

| Crate | What it has |
|---|---|
| `hobnix-pkg` | `Ctx`, `Event`, `LogLevel`, `Secret`, `Error`, the wire messages of both protocols (`wire`), `integrations`, `credentials`, `http`, `testing::FakeCtx` |
| `hobnix-pkg-command` | the command runner (`run`, `Request`, `Success`, `Failure`); with the feature `macros` also `#[command]`, `commands!` and `#[derive(Args)]` (from the crate `hobnix-pkg-macros`) |
| `hobnix-pkg-service` | the service runner (`Service`, `run`, `Init`, `EventRow`, `Health`) |

A command extension depends on `hobnix-pkg` and `hobnix-pkg-command`, a service on `hobnix-pkg` and `hobnix-pkg-service`, each by the same core tag
(ADR 0031): `hobnix-pkg = { git = "https://github.com/hobnix/core", tag = "vX.Y.Z" }`. The examples are `rust/hobnix-pkg-command/examples/hello.rs`
and `apiprobe.rs`, and `rust/hobnix-pkg-service/examples/ticker.rs`.

**Moving from `hobnix-ext-sdk` (breaking change in 0.14).** The crate `hobnix-ext-sdk` is deprecated: in 0.14 it re-exports the new crates under
the old paths and keeps the old `Ctx` and `Service` traits and the old command `Request` struct; it is removed after 0.14. A crate that pins an older
tag or rev keeps building against that one. When you move the pin, **not every extension of 0.13 builds unchanged, also under the old name.** These
need an edit:

- A struct literal of `Event`, `Success`, `Failure`, `EventRow`, `Init` or `http::Response`: use the constructors.
- A `match` that names every variant of `Lang`, `Caller`, `LogLevel`, `EventLevel`, `ErrorCode`, `HttpError` or `testing::Call`: add a `_` arm.
- `row.credential()` of an integration row returns `Option<Secret>`: take the value with `key.expose()`.
- The old `command::Request` no longer implements `Deserialize`.

An extension that does none of these builds with a deprecation warning at `run`. To move to the new crates: replace the dependency by the two crates
above, then

- `hobnix_ext_sdk::command::{run, Request, Success, Failure}` becomes `hobnix_pkg_command::...`; `hobnix_ext_sdk::service::{run, Service, Init, EventRow, Health}` becomes `hobnix_pkg_service::...`; `Ctx`, `Event`, `LogLevel`, `http`, `integrations`, `testing` come from `hobnix_pkg`.
- `Service::start` and `on_event` return `Result<(), hobnix_pkg::Error>` instead of `Result<(), String>`. `?` still works on a `Result<_, String>`, an `io::Error`, a `serde_json::Error` and an `HttpError`; `Error::with_cause(kind, "text", e)` keeps the cause, and the log line shows the whole chain.
- `ctx.credential(..)`, `row.credential()` and `hobnix_pkg::credentials::credential_for(..)` return `Option<Secret>`: `Debug` and `Display` print `***`, `key.expose()` is the value. `Client::header` takes a `Secret` as it is.
- `ctx.event(..)` is `ctx.emit(..)`.
- `Request`, `Init`, `EventRow`, `Event`, `Success` and `Failure` are `#[non_exhaustive]`: build them with their constructors (`Request::new(id, command, argv)`, `Init::new(..)`, `EventRow::new(..)`), not with a struct literal. `Integration` and `Health` still take a literal in 0.14.
- An unknown `lang` or `caller` from a newer core is `Lang::Other` or `Caller::Other` instead of a `bad_request`.

**Commands from code (feature `macros`).** Instead of a `match req.words()` and hand-written `commands.tsv` rows, take
`hobnix-pkg-command = { git = "...", tag = "vX.Y.Z", features = ["macros"] }` and write each command as a function:

```rust
use hobnix_pkg_command::{Args, Commands, Ctx, Failure, Success, command, commands};

#[derive(Args)]
struct CountArgs {
    /// a number from 1 to 10
    n: u32,
}

#[command(name = "count", reads, help = "count to n", help_de = "zählt bis n", sys = "count to n, as data")]
fn count(ctx: &dyn Ctx, CountArgs { n }: CountArgs) -> Result<Success, Failure> { /* ... */ }

fn table() -> Commands {
    commands!(package = "hello", script = "@/bin/hello", count)
}

fn main() -> std::process::ExitCode {
    table().run()
}
```

- `#[command]` keys: `name` (the command words), `reads` or `changes`, `help`, `help_de`, `topic`, `timeout` (seconds, 1 to 3600) and `sys` (the help of a `sys` row for the web interface). The function takes `(ctx)`, `(ctx, args)` or `(ctx, args, req: &Request)` and returns `Result<Success, E>` where `E` turns into a `Failure` (`hobnix_pkg::Error` does).
- `#[derive(Args)]`: the fields are the arguments in order: required ones first, then `Option<T>`, then at most one `Vec<T>` as the last. A value that cannot be read, a missing or an extra argument is a `bad_request` with a usage line. Take the struct apart in the parameter (`CountArgs { n }: CountArgs`), or clippy's `needless_pass_by_value` asks for it.
- `commands!` lists the functions and makes the dispatch: a command without a handler cannot exist, and an unknown command is `not_found`. Two functions with the same words do not compile.
- `table().tsv()` gives the rows that `commands.tsv` must hold for the program (every row has the flag `proto`); `rust/hobnix-pkg-command/examples/hello_macro.rs` prints them with `--commands-tsv`. The build puts the same rows into the program, and `python3 scripts/pkg.py validate` reads them from the `[[binary]]` file, without running it, and refuses a `commands.tsv` whose rows for that program differ (`binary.drift`). A help text holds no control character (tab, line break, ESC, ...) and no U+2028 or U+2029: the macro refuses it. `validate` refuses a program whose table is damaged or that carries a second one (`binary.table`). On `develop` no program is committed, so add the check to `cargo test`: `table().check(include_str!("../commands.tsv"))` must be `Ok`.
- The argument schema (`Command::args()`: names, kinds, types, help) is in the program only; no file carries it yet.

Without the feature nothing changes: `run(handler)` and rows written by hand, and the macro crates are not built. Not tested on hardware yet.

For a service that talks to an integration (Jellyfin, Plex, ...) `hobnix-pkg` has three helpers:

- `hobnix_pkg::integrations::parse(text)` turns the output of `hs pkg integrations` (package, integration, source, api_url, key_file, extras, key_header) into typed rows; `-` becomes `None`.
- `hobnix_pkg::credentials::credential_for("<name>", "<provider>")` reads the key of one provider as a `Secret`, and `row.credential()` does the same for a row (see "Keys of integrations (services)" below).
- `hobnix_pkg::http::Client` is a small blocking client built on the standard library: `Client::new().timeout(..).header(key_header, &key).get_json(url)`, also `post_json`. It has no dependencies of its own, so a build for `x86_64-unknown-linux-musl` needs no OpenSSL and no C toolchain. **It speaks plain `http://` only**: `https://` is refused with `HttpError::TlsUnsupported`. A TLS stack (rustls with `ring`) brings C and assembly code and many crates, and the core's Nix build of `rust/` has not been checked with them. Media servers on the same host or LAN are reached over http; for an https-only API put a local proxy in front.

`hobnix_pkg::Ctx` is a trait: what a handler asks of the host (`credential`, `integrations`, `emit`, `log`, `progress`; a service also `rollup` and `snapshot`). The runners hand the handler a `&dyn Ctx`, so write `fn handle(req: &Request, ctx: &dyn Ctx)` and `use hobnix_pkg::Ctx`. In a test, call the handler with `hobnix_pkg::testing::FakeCtx`, which records every call (`calls()`) and answers `credential` and `integrations` from what the test set. `ctx.shared()` gives an `Arc<dyn Ctx>` for another thread. There is no call that runs a host command: a service never does (ADR 0031).

`hobnix_pkg::wire` holds every message of both protocols as a type that can be read and written (`wire::decode`, `wire::encode`, `wire::Writer`): the runners use it, and so can a test or a host. A message type this version does not know is `Decoded::Unknown` and is ignored. The wire output of 0.14 is byte for byte the one of 0.13.

**The user of a service.** A service does not run as root: it runs as its own unprivileged user `hsx-<name>` (systemd `DynamicUser`; #1134). It may write only
its own folder (declare it as `fs.write:/var/lib/hs/<name>`): any other `fs.write` is refused (`ext.dynamic-write`), and so is `fs.read` of the server's state or of another extension
(`ext.dynamic-read`); in both cases the service does not start. The files it writes are mode 0600. A root command of the same package that writes into that
folder gives each file back to the service, with `chown -h --reference="$dir" "$file"` (`-h`: never the target of a link); the server also repairs the owners before each start. A root tool must never open or write by name in a service-owned folder without refusing links (`O_NOFOLLOW`, `open(..., dir_fd=)`): the service can plant a link there. **Inside the unit the folder is `/var/lib/hs-ext/<name>`, and `$STATE_DIRECTORY` holds that path: use the variable, not `/var/lib/hs/<name>`, which does not exist there (`/var/lib/hs` is empty and read-only).** On disk the real folder is `/var/lib/private/hs-ext/<name>`, owned by `nobody` (65534) with mode 0700; systemd shows it to the service user only inside the unit, so root tools see `nobody` as the right owner. An existing `/var/lib/hs/<name>` is moved there once and stays on the host as a link for root tools. A package that reads or writes `/var/lib/hs/<name>` in its service or its confined commands must change to `$STATE_DIRECTORY`. Not tested on hardware yet.

A service never calls `hs` (inside its confined unit `hs` cannot see the package registry); it gets what it needs through the protocol. Build, shipping and run rules of a Rust extension: ADR 0031 (docs/adr/0031-rust-extensions.md).

`rust/hobnix-pkg-command/examples/apiprobe.rs` uses all three. A static binary: `rustup target add x86_64-unknown-linux-musl`, then `cargo build --release --target x86_64-unknown-linux-musl -p hobnix-pkg-command --example apiprobe` in `rust/`. Not tested on hardware yet.

### Ship the program: `[[binary]]`

Put the built static program in your package folder and declare it in `package.toml`:

```toml
[[binary]]
path   = "bin/media-svc"                 # inside the package folder, no "..", no symbolic link
sha256 = "<64 hex digits>"               # sha256sum bin/media-svc; leave it empty and commit no file until the release preparation
bin    = "media-svc"                     # default: the file name of path
target = "x86_64-unknown-linux-musl"     # the only target for now
```

Point `[service] exec = "@/bin/media-svc"` (or the third column of a `commands.tsv` row) at it, and set the executable bit. `python3 scripts/pkg.py validate`
and `repo-check` refuse a wrong hash, a path that leaves the folder, a symbolic link, another target, an unknown key and a program that nothing refers to
(codes `binary.*` in docs/errors.md). `hs pkg install` and `update` check the hash and the executable bit of the installed copy and keep the old version
when they do not match. An aarch64 server refuses the package with `binary.arch`. Not tested on hardware yet.

## Events and snapshots (services)

A service (`[service]` in package.toml) gets the events it subscribed to as `event` messages and acknowledges each with `ack` once it has handled it. The core
keeps the last acknowledged id in `/var/lib/hs/ext-cursors/<name>`. After a crash or a restart it delivers what was not acknowledged again, exactly once more, so
handle an event idempotently. A service that starts for the first time gets the events from now on, not the log of the past.

A service sends `emit` for an event of its own. The kind must be `pkg.<name>.<what>`; any other kind is dropped with a warning. At most 50 emits a minute
count; the 51st is dropped and one warning goes to the journal. `snapshot` replaces the live topic `ext-<name>-<topic>`; only changed data makes a new
generation. Not tested on hardware yet.

A confined service cannot write `state.db` or read `/var/lib/hs` (ADR 0014): it asks the bridge. `rollup` adds to the monthly rollup below (`{"v":1,"type":"rollup","kind":"pkg.<name>.<what>","user":"anna","n":1,"sum":0}`); the kind must be one of yours declared with `retention = "metric"`, anything else is dropped with one warning, and it counts against the 50 a minute. `n` and `sum` are numbers of 0 or more; the table stores whole numbers, so a fraction is rounded (90.5 becomes 91). A refused rollup (negative, not stored) is warned in the journal. The Rust crate has `Ctx::rollup`.

## Keys of integrations (services)

A service that declares `permissions = ["integration:<name>"]` gets one key per provider of that integration: the provider `radarr` of `media` is the file `$CREDENTIALS_DIRECTORY/integration-media-radarr` (a systemd credential: not in argv, not in the environment). The provider is the `package` column of the row in `hs pkg integrations` (the `integration` column is `<name>`), so a row names its credential and a service never has to guess whose key it holds: `integration-<integration>-<package>`. A provider that offers the integration without a `key_file` gives no credential and no failure. Only integrations the package declared are handed over, never a key of an integration it did not declare, and never the key of its own provider block. Every key goes through the same strict check (registered provider, key file below that provider's folder, read once on the open descriptor, private 0600 copy). The key files stay hidden from the service. Python: `ext_sdk.credential("<name>", "<provider>")`; Rust: `hobnix_pkg::credentials::credential_for("<name>", "<provider>")`, or `row.credential()` on a row of `integrations::parse` (both a `Secret`). They return `None` when there is none (not declared, the provider has no key, the vault is locked, the file is missing). A confined service cannot run `hs pkg integrations` (the vault is an empty tmpfs there), so the core sends the rows of the declared integrations in `init`: Rust `Init::integrations: Vec<Integration>`, Python `ext_sdk.init_integrations(init)`. The rows hold no key and no key path; call `row.credential()` for the key. An undeclared integration is never in the list. Not tested on hardware yet. The rows may change while the service is on (a provider app stops, restarts, gets another address, or has none yet at boot): the core then stops the process (`shutdown`) and starts it again with a new `init`, after an event of the provider instance or within 30 minutes without one, so a service only reads the rows at start; it must not poll a row without an `api_url`. Not tested on hardware yet. The one-name form (`ext_sdk.credential("<name>")`, Rust `hobnix_ext_sdk::service::credential("<name>")`, the file `integration-<name>`) is deprecated: it was the key of the first provider with a key, without the owner. The core still hands that file over for one release; move to the provider form. Not tested on hardware yet.

## Keep a monthly rollup instead of raw ticks

An event that is only counted (a play, a request, a bandwidth sample) is declared with `retention = "metric"` in `[[events]]`: the core deletes
its raw rows after 35 days (see docs/events.md "Retention"). To keep the history, add each tick to a monthly rollup. The rollup is one row per
(month, user, kind) in the table `rollups` of `state.db`, so five years of one user and one kind are 60 rows; it is never pruned.

```
hs sys state rollup-add <kind> <user> [--n N] [--sum S] [--time T]   # n counts up by N (default 1), sum by S (default 0), month of T (default now, UTC)
hs sys state rollups [kind] [user]                                    # month TAB user TAB kind TAB n TAB sum, oldest month first
```

A second add in the same month changes the same row (an upsert). A Python caller inside the core uses `state-db.py` `rollup_add(c, t, user, kind, n, total)`.
Not tested on hardware yet.

## Try it without a server

```bash
python3 scripts/lib/ext_proto.py call --command greet --arg Ada -- sdk/examples/python/hello.py
```

The runner starts the program as the core does and prints what it answered. `tests/ext-sdk-examples.sh` does this for the shell, Python and
Go examples (the Go part prints a skip line where `go` is missing); `tests/ext-sdk-rust.sh` does it for Rust.

## Use the key of an app

An app can offer an API key through `[integrations.<name>]` in its `package.toml`. To read it, declare `permissions = ["integration:<name>"]` and ask for one provider by name, because one integration can have several (jellyfin and radarr under `media`):

    . "$HS_SCRIPTS/lib/integration.sh"
    integration_key media radarr my-ext > "$keyfile"     # the key of radarr only

- `hs pkg integrations media` lists the providers: `api_url`, the state of the key, and `key_header` as the last column (`-` = not set: send `X-Api-Key`).
- `api_url` arrives complete: the core fills `{host}` and `{port}` ([PLAN-packages.md](PLAN-packages.md#integrations-integrationsname-hobnixcore926)). `-` means it is not known, for example because the instance is stopped. A service reads its rows once, at start; when they change, the core restarts its process with the new ones. Do not poll a row without an `api_url`. Not tested on hardware yet.
- An unknown provider is refused with `integration.unknown`, a provider without a key file with `integration.nokey`, a missing permission with `integration.denied`.
- Read the key from stdout into a file or a pipe; never put it in an argument or an environment variable, and never print it.
- The old form `integration_key <name> <caller>` (the first provider with a key) works for one more release; use the three-argument form.
- The permission is a declared check, not enforced yet. Not tested on hardware yet.

## Check that it worked

- `python3 -I scripts/pkg.py repo-check <repository>` passes.
- `hs ext enable my-ext`, then `hs ext my-ext list` prints your entries.

## If something goes wrong

| Symptom | Cause | Fix |
| --- | --- | --- |
| `protocol_error`: no result line | the program ended without a `result`, often a crash | read its stderr: run it with `ext_proto.py call` |
| `protocol_error`: not valid JSON | something else was printed to stdout | print diagnostics to stderr |
| Python: `No module named ext_sdk` | `python3 -I` does not search the script's folder | add `$HS_SCRIPTS/lib` to `sys.path` as shown above |
| Shell: `jq: command not found` | the helper needs jq | install `jq` on the server |
| the call ends with `timeout` | it ran past its limit | answer sooner or raise `timeout:<seconds>` in `commands.tsv` |
| `ext.state-conflict`: both folders exist | the data of a service is in `/var/lib/hs/<name>` and in `/var/lib/hs-ext/<name>` | look at both, keep the one you need, move the other one away yourself, then start the service; the server never merges or deletes. Not tested on hardware yet. |
| `ext.state-move-failed` | `/var/lib/hs` is on another file system than `/var/lib/hs-ext` | put both on one file system; the server never copies the data. Not tested on hardware yet. |
| `ext.state-link-failed` | the server could not make `/var/lib/hs/<name>` a link | check that `/var/lib/hs` is writable and has free inodes; no data was deleted |
| `ext.state-reserved` | the package has the name of a folder of the server itself | rename the package |

## Next

- [Containers and apps](containers-and-apps.md)
- [PLAN-extensions-access](PLAN-extensions-access.md)
