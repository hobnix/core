//! [`Event`]: what a package asks the core to write to the event log.
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

use crate::EventLevel;

/// A message the extension asks the core to write to the event log (`event` in a command, `emit` in a service). Build it with
/// [`Event::new`] and the builder methods; the fields are public for reading and for a test.
#[non_exhaustive]
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Event {
    /// `pkg.<package>.<kind>`; must be declared in the package's `[[events]]`, the core drops others. A kind of another shape is refused
    /// before it is written ([`crate::wire::is_event_kind`]).
    pub kind: String,
    /// What the event is about (a user, a file, a job id).
    pub subject: String,
    /// One English line for a person; `None` writes no `text`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub text: Option<String>,
    /// `None` writes no `level` (the core takes `info`).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub level: Option<EventLevel>,
    /// Structured data; `None` writes no `payload`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub payload: Option<Map<String, Value>>,
}

impl Event {
    /// An event of `kind` about `subject`, without text, level or payload.
    pub fn new(kind: impl Into<String>, subject: impl Into<String>) -> Self {
        Event {
            kind: kind.into(),
            subject: subject.into(),
            text: None,
            level: None,
            payload: None,
        }
    }
    /// Set the text.
    #[must_use]
    pub fn text(mut self, text: impl Into<String>) -> Self {
        self.text = Some(text.into());
        self
    }
    /// Set the level.
    #[must_use]
    pub fn level(mut self, level: EventLevel) -> Self {
        self.level = Some(level);
        self
    }
    /// Set the payload.
    #[must_use]
    pub fn payload(mut self, payload: Map<String, Value>) -> Self {
        self.payload = Some(payload);
        self
    }
}
