//! The messages of the service protocol (ADR 0011, docs/api/ext-service-v1.schema.json): `init`, `event` and `shutdown` from the core;
//! `ready`, `health`, `ack`, `log`, `emit`, `snapshot` and `rollup` from the service.
use serde::{Deserialize, Serialize};
use serde_json::Value;

use super::{Log, Message, ProtocolError, fields};
use crate::integrations::Integration;
use crate::{Event, Lang};

/// Longest `text` of a `health` message, in characters.
pub const HEALTH_TEXT_MAX: usize = 200;
/// Largest `data` of a `snapshot`, in bytes of JSON.
pub const SNAPSHOT_MAX: usize = 256 << 10;

/// First message from the core.
#[non_exhaustive]
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Init {
    /// The extension name.
    pub name: String,
    /// The language of the server.
    pub lang: Lang,
    /// Event kind globs from the manifest; empty for a pure collector.
    pub subscribe: Vec<String>,
    /// Seconds between `health` messages the core expects at most.
    pub health_interval: f64,
    /// The rows of the integrations the package declared (`permissions = ["integration:<name>"]`), built by the core: a confined service
    /// cannot run `hs pkg integrations`. No keys in it, read them with [`Integration::credential`]. Empty when none is declared or
    /// when the core is older than this field; then it is not written either.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub integrations: Vec<Integration>,
}

impl Init {
    /// An `init` for the service `name` that subscribes to nothing and has no integrations (set the fields for others).
    pub fn new(name: impl Into<String>, lang: Lang, health_interval: f64) -> Self {
        Init {
            name: name.into(),
            lang,
            subscribe: Vec::new(),
            health_interval,
            integrations: Vec::new(),
        }
    }
}

/// One row of the event log, delivered at least once and in `id` order. `text` and `payload` are always written (`null` when `None`),
/// as the core writes them.
#[non_exhaustive]
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct EventRow {
    /// The id in the event log, from 1; the key for idempotent handling.
    pub id: u64,
    /// Seconds since the epoch.
    pub time: i64,
    /// Who wrote it (`core`, `pkg.<name>`).
    pub source: String,
    /// The kind (`job.done`).
    pub kind: String,
    /// What it is about.
    pub subject: String,
    /// `info`, `warn` or `error`; kept as written, so a level a newer core adds still arrives.
    pub level: String,
    /// One English line, or `None`.
    #[serde(default)]
    pub text: Option<String>,
    /// Structured data, or `None`.
    #[serde(default)]
    pub payload: Option<Value>,
}

impl EventRow {
    /// A row `id` of `kind` about `subject`, at time 0 from the `core`, level `info`, without text or payload (set the fields for others).
    pub fn new(id: u64, kind: impl Into<String>, subject: impl Into<String>) -> Self {
        EventRow {
            id,
            time: 0,
            source: "core".into(),
            kind: kind.into(),
            subject: subject.into(),
            level: "info".into(),
            text: None,
            payload: None,
        }
    }
}

/// The core asks the service to stop.
#[non_exhaustive]
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Shutdown {
    /// After this the core sends SIGTERM, then SIGKILL. 0 when the line has none.
    #[serde(default)]
    pub grace_ms: u64,
}

impl Shutdown {
    /// A shutdown with `grace_ms`.
    pub fn new(grace_ms: u64) -> Self {
        Shutdown { grace_ms }
    }
}

/// The answer to a heartbeat. `ok: false` marks the service `degraded`; the text is one English line (the runner cuts it to
/// [`HEALTH_TEXT_MAX`] characters).
///
/// Not `#[non_exhaustive]` yet: services of 0.13 build it with a struct literal. The attribute comes when the deprecated
/// `hobnix-ext-sdk` is removed.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Health {
    /// `false` marks the service `degraded`.
    pub ok: bool,
    /// Why; `None` writes no `text`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub text: Option<String>,
}

impl Health {
    /// Healthy, without text.
    pub fn ok() -> Self {
        Health {
            ok: true,
            text: None,
        }
    }
    /// Degraded, with the reason.
    pub fn degraded(text: impl Into<String>) -> Self {
        Health {
            ok: false,
            text: Some(text.into()),
        }
    }
}

/// The service has handled the event `id`.
#[non_exhaustive]
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Ack {
    /// The id of the event.
    pub id: u64,
}

impl Ack {
    /// The ack of event `id`.
    pub fn new(id: u64) -> Self {
        Ack { id }
    }
}

/// The newest state of a collector, kept by the core as the live topic `ext-<name>-<topic>`.
#[non_exhaustive]
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Snapshot {
    /// `[a-z0-9-]{1,60}` ([`is_snapshot_topic`]).
    pub topic: String,
    /// Any JSON, at most [`SNAPSHOT_MAX`] bytes.
    pub data: Value,
}

impl Snapshot {
    /// The state `data` of `topic`.
    pub fn new(topic: impl Into<String>, data: Value) -> Self {
        Snapshot {
            topic: topic.into(),
            data,
        }
    }
}

/// Add to the monthly rollup of (month, `user`, `kind`).
#[non_exhaustive]
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Rollup {
    /// A `retention = "metric"` kind of the package.
    pub kind: String,
    /// [`is_rollup_user`].
    pub user: String,
    /// How many; 1 when the line has none.
    #[serde(default = "one")]
    pub n: f64,
    /// The sum to add; 0 when the line has none.
    #[serde(default)]
    pub sum: f64,
}

fn one() -> f64 {
    1.0
}

impl Rollup {
    /// Add `n` and `sum` for `user` to `kind`.
    pub fn new(kind: impl Into<String>, user: impl Into<String>, n: f64, sum: f64) -> Self {
        Rollup {
            kind: kind.into(),
            user: user.into(),
            n,
            sum,
        }
    }
}

/// `user` fits a rollup: 1 to 64 of `A-Za-z0-9_.@-`, the first a letter or digit (never an option).
pub fn is_rollup_user(user: &str) -> bool {
    let chars_ok = user
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || matches!(c, '_' | '.' | '@' | '-'));
    let first_ok = user
        .chars()
        .next()
        .is_some_and(|c| c.is_ascii_alphanumeric());
    (1..=64).contains(&user.len()) && chars_ok && first_ok
}

/// `topic` fits a snapshot: 1 to 60 of `a-z0-9-`.
pub fn is_snapshot_topic(topic: &str) -> bool {
    (1..=60).contains(&topic.len())
        && topic
            .chars()
            .all(|c| matches!(c, 'a'..='z' | '0'..='9' | '-'))
}

/// What the core writes to a service.
#[non_exhaustive]
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(tag = "type", rename_all = "lowercase")]
pub enum FromCore {
    /// `init`: the first line.
    Init(Init),
    /// `event`: one row of the event log.
    Event(EventRow),
    /// `shutdown`
    Shutdown(Shutdown),
}

/// What a service writes to the core.
#[non_exhaustive]
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(tag = "type", rename_all = "lowercase")]
pub enum FromService {
    /// `ready`: the first line, after `init`.
    Ready,
    /// `health`
    Health(Health),
    /// `ack`
    Ack(Ack),
    /// `log`
    Log(Log),
    /// `emit`: asks the core to write one entry to the event log.
    Emit(Event),
    /// `snapshot`
    Snapshot(Snapshot),
    /// `rollup`
    Rollup(Rollup),
}

impl Message for FromCore {
    fn from_typed(message_type: &str, value: Value) -> Result<Option<Self>, ProtocolError> {
        Ok(match message_type {
            "init" => Some(FromCore::Init(fields(message_type, value)?)),
            "event" => Some(FromCore::Event(fields(message_type, value)?)),
            "shutdown" => Some(FromCore::Shutdown(fields(message_type, value)?)),
            _ => None,
        })
    }
}

impl Message for FromService {
    fn from_typed(message_type: &str, value: Value) -> Result<Option<Self>, ProtocolError> {
        Ok(match message_type {
            "ready" => Some(FromService::Ready),
            "health" => Some(FromService::Health(fields(message_type, value)?)),
            "ack" => Some(FromService::Ack(fields(message_type, value)?)),
            "log" => Some(FromService::Log(fields(message_type, value)?)),
            "emit" => Some(FromService::Emit(fields(message_type, value)?)),
            "snapshot" => Some(FromService::Snapshot(fields(message_type, value)?)),
            "rollup" => Some(FromService::Rollup(fields(message_type, value)?)),
            _ => None,
        })
    }
}
