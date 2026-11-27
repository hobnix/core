//! The example `hello` written with the command macros (feature `macros`): `hs ext hello greet [name]` and `hs ext hello count <n>`.
//! The dispatch and the `commands.tsv` rows come from the attributes; print the rows with `--commands-tsv`:
//! ```sh
//! cargo run --features macros --example hello_macro -- --commands-tsv
//! python3 ../../scripts/lib/ext_proto.py call --command greet --arg Ada -- target/debug/examples/hello_macro
//! ```
use std::process::ExitCode;

use hobnix_pkg::{Event, LogLevel};
use hobnix_pkg_command::{Args, Commands, Ctx, Failure, Success, command, commands};
use serde_json::json;

#[derive(Args)]
struct GreetArgs {
    /// who to greet (default: world)
    name: Option<String>,
}

#[command(
    name = "greet",
    reads,
    help = "greet someone",
    help_de = "grüßt jemanden",
    topic = "system"
)]
fn greet(ctx: &dyn Ctx, GreetArgs { name }: GreetArgs) -> Result<Success, Failure> {
    let name = name.unwrap_or_else(|| "world".to_owned());
    let _ = ctx.log(LogLevel::Info, "greeting");
    ctx.emit(&Event::new("pkg.hello.greeted", &name))
        .map_err(|e| Failure::failed(e.to_string()))?;
    let greeting = format!("hello {name}");
    Ok(Success::data(json!({ "greeting": greeting })).with_text(greeting))
}

#[derive(Args)]
struct CountArgs {
    /// a number from 1 to 10
    n: u32,
}

#[command(
    name = "count",
    reads,
    help = "count to n with progress",
    sys = "count to n, as data"
)]
fn count(ctx: &dyn Ctx, CountArgs { n }: CountArgs) -> Result<Success, Failure> {
    if !(1..=10).contains(&n) {
        return Err(Failure::bad_request("count needs a number from 1 to 10"));
    }
    for i in 1..=n {
        let _ = ctx.progress(
            Some(f64::from(i) / f64::from(n)),
            &format!("step {i} of {n}"),
        );
    }
    Ok(Success::data(json!({ "counted": n })))
}

fn table() -> Commands {
    commands!(package = "hello", script = "@/bin/hello", greet, count)
}

fn main() -> ExitCode {
    // for the author, never used by the core (it starts the program without arguments): the rows commands.tsv must hold
    if std::env::args().nth(1).as_deref() == Some("--commands-tsv") {
        let _ = std::io::Write::write_all(&mut std::io::stdout(), table().tsv().as_bytes());
        return ExitCode::SUCCESS;
    }
    table().run()
}
