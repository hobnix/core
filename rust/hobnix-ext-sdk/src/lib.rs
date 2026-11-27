//! **Deprecated** (0.14): the SDK is now the crates `hobnix-pkg` (base), `hobnix-pkg-command` and `hobnix-pkg-service`. This crate
//! re-exports them under the old paths for one release and is removed after it (docs/PLAN-package-sdk.md, docs/extensions-sdk.md).
//!
//! Not every extension written against 0.13 compiles unchanged: docs/extensions-sdk.md "Moving from `hobnix-ext-sdk`" lists what needs an
//! edit. For these signatures that the new API changed, this crate keeps the old one and adapts:
//! - [`Ctx`] is the old trait: `credential` returns `Option<String>` (the new one returns a `Secret`) and `event` is still there. Every
//!   `hobnix_pkg::Ctx` (the runners' contexts, `testing::FakeCtx`) is one.
//! - [`service::Service`] is the old trait with `Result<(), String>`; [`service::run`] adapts it to the new one (`hobnix_pkg::Error`).
//! - [`command::Request`] is the old struct that a test can build with a literal (the new one is `#[non_exhaustive]`).
//! - [`service::credential_for`] returns `Option<String>`; the one-name [`service::credential`] stays deprecated here.
//!
//! The entry points (`command::run`, `service::run`, their `run_with`, `service::credential_for`) are marked deprecated, so a build says
//! what to move to. Wire output is the new crates' and stays byte for byte what 0.13 wrote.

pub mod command;
mod ctx;
pub mod service;

pub use ctx::Ctx;
pub use hobnix_pkg::{Event, EventLevel, LogLevel, MAX_LINE, VERSION, http, integrations, testing};
