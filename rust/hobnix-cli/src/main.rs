//! Adapter of the strangler: the only place that writes to the terminal.
#![expect(
    clippy::print_stdout,
    clippy::print_stderr,
    reason = "contract output (hs sys lines) is this crate's job"
)]

use hobnix_core::Error;
use hobnix_core::log::{self, Level};
use std::process::ExitCode;

mod events;
mod jobs;
mod pair;
mod secrets;

fn run(args: &[String]) -> hobnix_core::Result<u8> {
    let rest = args.get(1..).unwrap_or_default();
    match args.first().map(String::as_str) {
        None | Some("--version") => {
            println!("hobnix {}", hobnix_core::version());
            Ok(hobnix_core::EXIT_OK)
        }
        Some("event-emit") => events::run(rest),
        Some("job-record") => jobs::run(rest),
        Some("secrets") => secrets::run(rest),
        Some("remote-codes") => pair::codes(rest),
        Some("remote-claim") => pair::claim(rest),
        Some("remote-accept") => pair::accept(rest),
        Some("pair") => pair::run(rest),
        Some(other) => Err(Error::Refused(format!("unknown subcommand: {other}"))),
    }
}

fn main() -> ExitCode {
    let max = Level::from_env();
    if log::enabled(Level::Debug, max) {
        eprintln!(
            "{}",
            log::format(
                Level::Debug,
                "start",
                &[("version", hobnix_core::version())]
            )
        );
    }
    let args: hobnix_core::Result<Vec<String>> = std::env::args_os()
        .skip(1)
        .map(|a| {
            a.into_string()
                .map_err(|_| Error::Refused("argument is not valid UTF-8".to_string()))
        })
        .collect();
    match args.and_then(|a| run(&a)) {
        Ok(code) => ExitCode::from(code),
        Err(e) => {
            eprintln!("hobnix: {e}");
            ExitCode::from(e.exit_code())
        }
    }
}
