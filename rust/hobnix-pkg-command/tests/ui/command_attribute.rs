// Refused keys of #[command]: each function is refused at its own tokens.
use hobnix_pkg_command::{Ctx, Failure, Success, command};

#[command(name = "a", help = "x")]
fn no_access(_ctx: &dyn Ctx) -> Result<Success, Failure> {
    Ok(Success::text("a"))
}

#[command(name = "Big", reads, help = "x")]
fn bad_name(_ctx: &dyn Ctx) -> Result<Success, Failure> {
    Ok(Success::text("a"))
}

#[command(name = "a", reads, changes, help = "x")]
fn both(_ctx: &dyn Ctx) -> Result<Success, Failure> {
    Ok(Success::text("a"))
}

#[command(name = "a", reads, help = "two\tcolumns")]
fn tab(_ctx: &dyn Ctx) -> Result<Success, Failure> {
    Ok(Success::text("a"))
}

#[command(name = "a", reads, help = "x", help_de = "a\u{1b}[31mred")]
fn escape(_ctx: &dyn Ctx) -> Result<Success, Failure> {
    Ok(Success::text("a"))
}

#[command(name = "a", reads, help = "x", sys = "two\u{2028}lines")]
fn separator(_ctx: &dyn Ctx) -> Result<Success, Failure> {
    Ok(Success::text("a"))
}

#[command(name = "a", reads, help = "x", timeout = 7200)]
fn long(_ctx: &dyn Ctx) -> Result<Success, Failure> {
    Ok(Success::text("a"))
}

#[command(name = "a", reads, help = "x", colour = "red")]
fn unknown(_ctx: &dyn Ctx) -> Result<Success, Failure> {
    Ok(Success::text("a"))
}

fn main() {}
