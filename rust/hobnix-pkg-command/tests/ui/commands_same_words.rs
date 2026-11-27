// Two functions with the same command words: refused when the table is built (const evaluation), so no row can be listed twice.
use hobnix_pkg_command::{Commands, Ctx, Failure, Success, command, commands};

#[command(name = "status", reads, help = "x")]
fn a(_ctx: &dyn Ctx) -> Result<Success, Failure> {
    Ok(Success::text("a"))
}

#[command(name = "status", reads, help = "y")]
fn b(_ctx: &dyn Ctx) -> Result<Success, Failure> {
    Ok(Success::text("b"))
}

fn table() -> Commands {
    commands!(package = "demo", script = "@/bin/demo", a, b)
}

fn main() {
    let _ = table();
}
