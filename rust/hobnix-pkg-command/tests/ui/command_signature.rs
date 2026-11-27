// Refused shapes of a command function.
use hobnix_pkg_command::{Ctx, Failure, Success, command};

#[command(name = "a", reads, help = "x")]
async fn not_async(_ctx: &dyn Ctx) -> Result<Success, Failure> {
    Ok(Success::text("a"))
}

#[command(name = "b", reads, help = "x")]
fn no_result(_ctx: &dyn Ctx) {}

#[command(name = "c", reads, help = "x")]
fn no_ctx() -> Result<Success, Failure> {
    Ok(Success::text("a"))
}

#[command(name = "d", reads, help = "x")]
fn generic<T>(_ctx: &dyn Ctx) -> Result<Success, Failure> {
    Ok(Success::text("a"))
}

#[command(name = "e", reads, help = "x")]
struct NotAFunction;

fn main() {}
