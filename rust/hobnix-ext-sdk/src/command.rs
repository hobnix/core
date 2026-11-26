//! The 0.13 paths of `hobnix-pkg-command`: the types are re-exported, [`Request`] and [`run`] keep their old form.
use std::io::{BufRead, Write};
use std::process::ExitCode;

use crate::Ctx;

pub use hobnix_pkg_command::{Caller, ErrorCode, Failure, Lang, Success};

/// The 0.13 request: the same fields as `hobnix_pkg_command::Request`, without `#[non_exhaustive]`, so a test can build it with a
/// struct literal.
#[derive(Debug, Clone, PartialEq)]
pub struct Request {
    /// One id per call, for logs.
    pub id: String,
    /// The words after `hs ext <name>`.
    pub command: Vec<String>,
    /// The arguments after the command words. Never a secret.
    pub argv: Vec<String>,
    /// The language of the person.
    pub lang: Lang,
    /// Who started the call.
    pub caller: Caller,
    /// The limit the core enforces; a hint only.
    pub timeout_ms: u64,
}

impl Request {
    /// The command words as `&str`.
    pub fn words(&self) -> Vec<&str> {
        self.command.iter().map(String::as_str).collect()
    }
}

impl From<&hobnix_pkg_command::Request> for Request {
    fn from(r: &hobnix_pkg_command::Request) -> Self {
        Request {
            id: r.id.clone(),
            command: r.command.clone(),
            argv: r.argv.clone(),
            lang: r.lang,
            caller: r.caller,
            timeout_ms: r.timeout_ms,
        }
    }
}

/// Run the extension against stdin/stdout and return the process exit code (see `hobnix_pkg_command::run`).
#[deprecated(
    since = "0.14.0",
    note = "use hobnix_pkg_command::run (crates hobnix-pkg and hobnix-pkg-command); hobnix-ext-sdk is removed after 0.14"
)]
pub fn run<F>(handler: F) -> ExitCode
where
    F: FnOnce(&Request, &dyn Ctx) -> Result<Success, Failure>,
{
    hobnix_pkg_command::run(adapt(handler))
}

/// [`run`] over any reader and writer (for tests). Returns the exit code.
#[deprecated(
    since = "0.14.0",
    note = "use hobnix_pkg_command::run_with (crates hobnix-pkg and hobnix-pkg-command); hobnix-ext-sdk is removed after 0.14"
)]
pub fn run_with<F>(input: &mut impl BufRead, output: impl Write + Send + 'static, handler: F) -> u8
where
    F: FnOnce(&Request, &dyn Ctx) -> Result<Success, Failure>,
{
    hobnix_pkg_command::run_with(input, output, adapt(handler))
}

/// The old handler as a handler of the new runner.
fn adapt<F>(
    handler: F,
) -> impl FnOnce(&hobnix_pkg_command::Request, &dyn hobnix_pkg::Ctx) -> Result<Success, Failure>
where
    F: FnOnce(&Request, &dyn Ctx) -> Result<Success, Failure>,
{
    move |req: &hobnix_pkg_command::Request, ctx: &dyn hobnix_pkg::Ctx| {
        handler(&Request::from(req), &ctx)
    }
}
