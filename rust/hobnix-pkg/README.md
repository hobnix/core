# hobnix-pkg

Rust SDK for Hobnix packages (docs/PLAN-package-sdk.md; epic #197, issues #240, #1262). It is the extension side of two protocols, so an
extension in Rust does not hand-write JSON lines. Three crates:

| Crate | Content | Protocol | Schema |
| --- | --- | --- | --- |
| `hobnix-pkg` | `Ctx`, `Event`, `Secret`, `Error`, the wire messages of both protocols, `integrations`, `credentials`, `http`, `testing` | both | both |
| `hobnix-pkg-command` | command runner (one process per call) | [ADR 0010](../../docs/adr/0010-extension-command-protocol.md) | `docs/api/ext-protocol-v1.schema.json` |
| `hobnix-pkg-service` | service runner (one supervised process) | [ADR 0011](../../docs/adr/0011-extension-service-lifecycle.md) | `docs/api/ext-service-v1.schema.json` |

`hobnix-ext-sdk` is the name before 0.14: it re-exports these crates under the old paths for one release and is then removed.

Status: both ADRs are Accepted and built in the core (`scripts/lib/ext_proto.py`, `scripts/lib/ext_service.py`, the unit `hs-ext-svc@`). The SDK speaks version 1
as the ADRs and schemas define it and is tested against the reference runners, not against `hs` on a server. Not tested on hardware yet. How a Rust extension is built, shipped and run: ADR 0031.

## A command extension

```rust
use hobnix_pkg_command::{run, Failure, Success};
use std::process::ExitCode;

fn main() -> ExitCode {
    run(|req, ctx| match req.words().as_slice() {
        ["greet"] => {
            ctx.progress(Some(0.5), "thinking").ok();
            Ok(Success::text(format!("hello {}", req.argv.join(" "))))
        }
        _ => Err(Failure::not_found("no such command")),
    })
}
```

`run` reads the one request line, answers `unsupported_version` for a `v` it does not know, calls your closure, and writes exactly one
`result` (exit status 0 for `ok`, 1 otherwise). A panic becomes `failed`. The handler gets a `&dyn Ctx` that sends `progress`, `log` and `event` messages; free
text is cut to the schema limits and an event kind that is not `pkg.<package>.<kind>` is refused before it is written. The example is
`../hobnix-pkg-command/examples/hello.rs`.

## A service extension

Implement `hobnix_pkg_service::Service` (`start`, `on_event`, `tick`, all optional; errors are `hobnix_pkg::Error`) and call
`hobnix_pkg_service::run(MyService)`. The runner sends `ready` after `start`, calls `tick` and sends `health` every half `health_interval`, sends
the `ack` after `on_event` returns `Ok`, and returns on `shutdown` or end of stdin. Delivery is at least once: `on_event` must be idempotent
(key: `EventRow::id`). `Ctx` is a trait (`&dyn Ctx`; `ctx.shared()` gives an `Arc<dyn Ctx>` for another thread) and offers `log`, `emit`,
`rollup` and `snapshot`; `testing::FakeCtx` stands in for it in a test. The example is `../hobnix-pkg-service/examples/ticker.rs`.

## Rules for the author

- **stdout is the protocol.** Never `println!`; diagnostics go to stderr. The core keeps a command's stderr on failure; today it discards
  a service's stderr (hobnix/core issue #1368).
  Before `ready` the protocol allows nothing else, so the service runner holds back what `start` and its threads write through `ctx`
  and sends it after `ready` (at most 1000 messages and 4 MiB; a newer one that does not fit is dropped and counted in a log line). A
  direct write to stdout is not held back. What is held is not sent when `start` fails or hangs.
- **No secrets** in `argv`, `data`, snapshots or logs (ADR 0010 rule 9). A key is a `Secret`: it prints as `***`.
- **Cancel and timeout are SIGTERM** to the process group, then SIGKILL after the grace time. The SDK installs no signal handler (it
  would need `unsafe` or a crate); the default action ends the process, which is a valid answer within the rules. A command that
  needs cleanup can add its own handler and send `ErrorCode::Cancelled`.
- A slow `on_event` or `tick` delays the heartbeat; do long work on your own threads.
- Shape of `data` is yours, per command; the core renders it (ADR 0010 open point).

## Build and test

```bash
cd rust
cargo test -p hobnix-pkg -p hobnix-pkg-command -p hobnix-pkg-service -p hobnix-ext-sdk   # unit tests: wire format in memory, no processes
cargo build -p hobnix-pkg-command -p hobnix-pkg-service --examples
python3 -I ../scripts/lib/ext_proto.py call --command greet --arg Ada -- "$PWD/target/debug/examples/hello"
bash ../scripts/dev/t quick ext-sdk-rust        # the examples against both reference runners; skipped without cargo
```

An extension package that uses the SDK depends on it by git tag (ADR 0031; `publish = false`, nothing is on crates.io), and ships its
binary built for the server; building on the server is not part of the package contract yet. Not tested on hardware yet.
