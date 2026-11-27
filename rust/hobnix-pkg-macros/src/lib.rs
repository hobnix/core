//! The macros of the Hobnix package SDK. Use them through `hobnix-pkg-command` with its feature `macros`, which re-exports them and holds
//! the types the generated code names (`::hobnix_pkg_command::__private`); the documentation with examples is there.
//!
//! Each entry point only converts the token stream; the logic is on `proc_macro2` and has unit tests. A refused input is a
//! `compile_error!` at the offending tokens, never a panic.

mod args;
mod command;
mod commands;
mod text;

use proc_macro::TokenStream;

/// A command of a command extension: `#[command(name = "status", reads, help = "...", help_de = "...")]` on a function
/// `fn status(ctx: &dyn Ctx, args: StatusArgs) -> Result<Success, E>` (`E: Into<Failure>`; the arguments may be left out, and a third
/// parameter `&Request` added). Keys: `name` (the command words), `reads` or `changes`, `help`, `help_de`, `topic`, `timeout` (seconds,
/// 1 to 3600), `sys` (the help of a `sys` row for the web interface). List the function in `commands!`.
#[proc_macro_attribute]
pub fn command(attr: TokenStream, item: TokenStream) -> TokenStream {
    command::expand(attr.into(), item.into()).into()
}

/// The commands of a program: `commands!(package = "demo", script = "@/bin/demo", status, sync)` is a `Commands` with the dispatch and
/// the `commands.tsv` rows.
#[proc_macro]
pub fn commands(input: TokenStream) -> TokenStream {
    commands::expand(input.into()).into()
}

/// The arguments of a command, read from the request's `argv` in field order: a required field, then `Option<T>` fields, then at most one
/// `Vec<T>` as the last field. A field's doc comment is its help.
#[proc_macro_derive(Args)]
pub fn derive_args(input: TokenStream) -> TokenStream {
    args::expand(input.into()).into()
}
