//! SDK for Hobnix extensions written in Rust.
//!
//! The extension side of two protocols, both JSON Lines with `"v": 1`:
//! - [`command`]: one process per call, one request on stdin, progress/log/event lines and exactly one result on stdout
//!   (docs/adr/0010-extension-command-protocol.md, docs/api/ext-protocol-v1.schema.json).
//! - [`service`]: one long-running process, `init`/`event`/`shutdown` in, `ready`/`health`/`ack`/`log`/`emit`/`snapshot`/`rollup` out
//!   (docs/adr/0011-extension-service-lifecycle.md, docs/api/ext-service-v1.schema.json).
//!
//! Helpers for a service that talks to an integration: [`http`] (blocking client, plain http only, no TLS), [`integrations`] (the
//! `hs pkg integrations` listing as typed rows) and [`service::credential`] (the key from `$CREDENTIALS_DIRECTORY`).
//!
//! Rules the SDK keeps for you: stdout carries nothing but protocol lines (use `eprintln!` for diagnostics, never `println!`),
//! every line is under 1 MiB, free text is cut to the schema limits, and event kinds are checked against `pkg.<name>.<kind>`
//! before they are written.
//!
//! The core calls commands (ADR 0010) and services (ADR 0011) through this protocol; ADR 0031 describes how a Rust extension is built, shipped and run.
//! A service must not call `hs`: what it needs from the core arrives as protocol data.

pub mod command;
pub mod http;
pub mod integrations;
mod proto;
pub mod service;

pub use proto::{EventLevel, LogLevel, MAX_LINE, VERSION};

/// A message the extension asks the core to write to the event log (`event` in a command, `emit` in a service).
#[derive(Debug, Clone, PartialEq)]
pub struct Event {
    /// `pkg.<package>.<kind>`; must be declared in the package's `[[events]]`, the core drops others.
    pub kind: String,
    pub subject: String,
    pub text: Option<String>,
    pub level: Option<EventLevel>,
    pub payload: Option<serde_json::Map<String, serde_json::Value>>,
}

impl Event {
    pub fn new(kind: impl Into<String>, subject: impl Into<String>) -> Self {
        Event {
            kind: kind.into(),
            subject: subject.into(),
            text: None,
            level: None,
            payload: None,
        }
    }
    pub fn text(mut self, text: impl Into<String>) -> Self {
        self.text = Some(text.into());
        self
    }
    pub fn level(mut self, level: EventLevel) -> Self {
        self.level = Some(level);
        self
    }
    pub fn payload(mut self, payload: serde_json::Map<String, serde_json::Value>) -> Self {
        self.payload = Some(payload);
        self
    }
}
