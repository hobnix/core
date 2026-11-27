//! Base of the Hobnix package SDK (docs/PLAN-package-sdk.md): what every package kind shares.
//!
//! - [`wire`]: the messages of the command protocol (ADR 0010, docs/api/ext-protocol-v1.schema.json) and the service protocol (ADR 0011,
//!   docs/api/ext-service-v1.schema.json) as types that can be read and written, so the extension side and a host share one definition.
//! - [`Ctx`]: what a handler asks of the host (credential, integrations, emit, log, progress, rollup, snapshot), as a trait.
//!   [`testing::FakeCtx`] stands in for it in a test.
//! - [`Event`], [`LogLevel`], [`EventLevel`], [`Secret`], [`Error`].
//! - Helpers for a package that talks to an integration: [`http`] (blocking client, plain http only), [`integrations`] (the
//!   `hs pkg integrations` listing as typed rows) and [`credentials`] (the key from `$CREDENTIALS_DIRECTORY`).
//!
//! The runners are in their own crates: `hobnix-pkg-command` (one process per call) and `hobnix-pkg-service` (one supervised process).
//! Rules they keep for you: stdout carries nothing but protocol lines, every line is under 1 MiB ([`MAX_LINE`]), free text is cut to the
//! schema limits, and event kinds are checked against `pkg.<name>.<kind>` before they are written. A service must not call `hs`: what it
//! needs from the core arrives as protocol data (ADR 0031).

pub mod credentials;
mod ctx;
mod error;
mod event;
pub mod http;
pub mod integrations;
mod secret;
pub mod testing;
pub mod wire;

pub use ctx::Ctx;
pub use error::{Error, ErrorKind};
pub use event::Event;
pub use secret::Secret;
pub use wire::{EventLevel, Lang, LogLevel, MAX_LINE, VERSION};
