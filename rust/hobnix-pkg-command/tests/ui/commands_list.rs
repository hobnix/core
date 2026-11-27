// Refused input of commands!.
use hobnix_pkg_command::{Commands, Ctx, Failure, Success, command, commands};

#[command(name = "a", reads, help = "x")]
fn a(_ctx: &dyn Ctx) -> Result<Success, Failure> {
    Ok(Success::text("a"))
}

fn no_script() -> Commands {
    commands!(package = "demo", a)
}

fn bad_script() -> Commands {
    commands!(package = "demo", script = "bin/demo", a)
}

fn twice() -> Commands {
    commands!(package = "demo", script = "@/bin/demo", a, a)
}

fn none() -> Commands {
    commands!(package = "demo", script = "@/bin/demo")
}

fn main() {}
