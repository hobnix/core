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
- A row with the flag `confine` in `commands.tsv` runs through `systemd-run` with the properties of your `permissions` (writes only under `fs.write`, no new privileges, no devices unless `devices:gpu`). It needs `protocol = [1]` and a `permissions` list. It is partial: reads, the network and calls to `hs`, `incus` and `systemctl` are not limited. Not tested on hardware yet.

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

The crate `rust/hobnix-ext-sdk` has the same message types, a command runner and a service runner (ADR 0011). Its examples are
`rust/hobnix-ext-sdk/examples/hello.rs` and `ticker.rs`.

For a service that talks to an integration (Jellyfin, Plex, ...) the crate has three helpers:

- `hobnix_ext_sdk::integrations::parse(text)` turns the output of `hs pkg integrations` (package, integration, source, api_url, key_file, extras, key_header) into typed rows; `-` becomes `None`.
- `hobnix_ext_sdk::service::credential("<name>")` reads the key (see "Events and snapshots" below).
- `hobnix_ext_sdk::http::Client` is a small blocking client built on the standard library: `Client::new().timeout(..).header(key_header, key).get_json(url)`, also `post_json`. It has no dependencies of its own, so a build for `x86_64-unknown-linux-musl` needs no OpenSSL and no C toolchain. **It speaks plain `http://` only**: `https://` is refused with `HttpError::TlsUnsupported`. A TLS stack (rustls with `ring`) brings C and assembly code and many crates, and the core's Nix build of `rust/` has not been checked with them. Media servers on the same host or LAN are reached over http; for an https-only API put a local proxy in front.

`examples/apiprobe.rs` uses all three. A static binary: `rustup target add x86_64-unknown-linux-musl`, then `cargo build --release --target x86_64-unknown-linux-musl --example apiprobe` in `rust/`. Not tested on hardware yet.

## Events and snapshots (services)

A service (`[service]` in package.toml) gets the events it subscribed to as `event` messages and acknowledges each with `ack` once it has handled it. The core
keeps the last acknowledged id in `/var/lib/hs/ext-cursors/<name>`. After a crash or a restart it delivers what was not acknowledged again, exactly once more, so
handle an event idempotently. A service that starts for the first time gets the events from now on, not the log of the past.

A service sends `emit` for an event of its own. The kind must be `pkg.<name>.<what>`; any other kind is dropped with a warning. At most 50 emits a minute
count; the 51st is dropped and one warning goes to the journal. `snapshot` replaces the live topic `ext-<name>-<topic>`; only changed data makes a new
generation. Not tested on hardware yet.

A confined service cannot write `state.db` or read `/var/lib/hs` (ADR 0014): it asks the bridge. `rollup` adds to the monthly rollup below (`{"v":1,"type":"rollup","kind":"pkg.<name>.<what>","user":"anna","n":1,"sum":0}`); the kind must be one of yours declared with `retention = "metric"`, anything else is dropped with one warning, and it counts against the 50 a minute. `n` and `sum` are numbers of 0 or more; the table stores whole numbers, so a fraction is rounded (90.5 becomes 91). A refused rollup (negative, not stored) is warned in the journal. The Rust crate has `Ctx::rollup`.

## Keys of integrations (services)

A service that declares `permissions = ["integration:<name>"]` finds the key of that integration in the file `$CREDENTIALS_DIRECTORY/integration-<name>` (a systemd credential: not in argv, not in the environment). The key file stays hidden from the service. Python: `ext_sdk.credential("<name>")`; Rust: `hobnix_ext_sdk::service::credential("<name>")`. They return `None` when there is none (not declared, the vault is locked, the file is missing). Not tested on hardware yet.

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

## Next

- [Containers and apps](containers-and-apps.md)
- [PLAN-extensions-access](PLAN-extensions-access.md)
