//! Example service extension: publishes a snapshot with a counter on every tick and counts the events it is subscribed to.
//!
//! ```sh
//! cargo build --example ticker
//! python3 ../../scripts/lib/ext_service.py run --name ticker --health-interval 1 --run-for 3 -- target/debug/examples/ticker
//! ```
use hobnix_pkg::{Ctx, Error};
use hobnix_pkg_service::{EventRow, Health, Init, Service, run};
use serde_json::json;
use std::io::{self, Write};
use std::process::ExitCode;

#[derive(Default)]
struct Ticker {
    ticks: u64,
    seen: u64,
}

impl Service for Ticker {
    // What `ctx` writes here is held until `ready` is out, and is not sent when the start fails or hangs: a diagnostic about the
    // start itself goes to stderr. Never write to stdout directly.
    fn start(&mut self, init: &Init, _ctx: &dyn Ctx) -> Result<(), Error> {
        let (name, subscribe) = (&init.name, &init.subscribe);
        writeln!(
            io::stderr(),
            "ticker starting as {name} (subscribed to {subscribe:?})"
        )?;
        Ok(())
    }
    fn on_event(&mut self, _event: &EventRow, _ctx: &dyn Ctx) -> Result<(), Error> {
        // idempotent enough for an example: a repeated event only counts twice
        self.seen += 1;
        Ok(())
    }
    fn tick(&mut self, ctx: &dyn Ctx) -> Health {
        self.ticks += 1;
        match ctx.snapshot(
            "ticks",
            json!({ "ticks": self.ticks, "events_seen": self.seen }),
        ) {
            Ok(()) => Health::ok(),
            Err(e) => Health::degraded(format!("cannot publish: {e}")),
        }
    }
}

fn main() -> ExitCode {
    run(Ticker::default())
}
