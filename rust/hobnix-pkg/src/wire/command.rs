//! The messages of the command protocol (ADR 0010, docs/api/ext-protocol-v1.schema.json): one `request` from the core, then `progress`,
//! `log` and `event` lines and exactly one `result` from the extension.
use serde::{Deserialize, Deserializer, Serialize};
use serde_json::Value;

use super::{Log, Message, ProtocolError, fields, one_line, truncate};
use crate::{Event, Lang};

/// Longest `text` of a `progress` message, in characters.
pub const PROGRESS_TEXT_MAX: usize = 200;

/// Who started the call.
#[non_exhaustive]
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Caller {
    /// `hs ext ...` at a terminal.
    Cli,
    /// The web interface.
    Web,
    /// The core at boot.
    Boot,
    /// A caller this version does not know (a newer core). It cannot be written.
    #[serde(other, skip_serializing)]
    Other,
}

/// The one request line the core writes to stdin.
#[non_exhaustive]
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Request {
    /// One id per call (16 hex digits), for logs.
    pub id: String,
    /// The words after `hs ext <name>`.
    pub command: Vec<String>,
    /// The arguments after the command words. Never a secret (ADR 0010 rule 9).
    pub argv: Vec<String>,
    /// The language of the person.
    pub lang: Lang,
    /// Who started the call.
    pub caller: Caller,
    /// The limit the core enforces; a hint only.
    pub timeout_ms: u64,
}

impl Request {
    /// A request `id` for `command` with `argv`, in English from the terminal, with a 60 s limit (set the fields for others).
    pub fn new(id: impl Into<String>, command: Vec<String>, argv: Vec<String>) -> Self {
        Request {
            id: id.into(),
            command,
            argv,
            lang: Lang::En,
            caller: Caller::Cli,
            timeout_ms: 60_000,
        }
    }

    /// The command words as `&str`, for `match req.words().as_slice() { ["status"] => ..., }`.
    pub fn words(&self) -> Vec<&str> {
        self.command.iter().map(String::as_str).collect()
    }
}

/// How far a command is.
#[non_exhaustive]
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Progress {
    /// 0 to 1; `None` writes no `fraction` (progress without a measure).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub fraction: Option<f64>,
    /// One line, at most [`PROGRESS_TEXT_MAX`] characters.
    #[serde(default)]
    pub text: String,
}

impl Progress {
    /// A progress line: a `fraction` that is not finite is left out, others are clamped to 0..=1; `text` is cut to
    /// [`PROGRESS_TEXT_MAX`] characters.
    pub fn new(fraction: Option<f64>, text: &str) -> Self {
        Progress {
            fraction: fraction
                .filter(|x| x.is_finite())
                .map(|x| x.clamp(0.0, 1.0)),
            text: truncate(text, PROGRESS_TEXT_MAX),
        }
    }
}

/// The code of a failed result. `timeout` and `protocol_error` are only ever decided by the core; a code this version does not know is
/// kept as [`ResultCode::Other`].
#[non_exhaustive]
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(from = "String", into = "String")]
pub enum ResultCode {
    /// `failed`
    Failed,
    /// `not_found`
    NotFound,
    /// `bad_request`
    BadRequest,
    /// `unsupported_version`
    UnsupportedVersion,
    /// `cancelled`
    Cancelled,
    /// `timeout`
    Timeout,
    /// `protocol_error`
    ProtocolError,
    /// Another code, as written.
    Other(String),
}

impl ResultCode {
    /// The code as written on the wire.
    pub fn as_str(&self) -> &str {
        match self {
            ResultCode::Failed => "failed",
            ResultCode::NotFound => "not_found",
            ResultCode::BadRequest => "bad_request",
            ResultCode::UnsupportedVersion => "unsupported_version",
            ResultCode::Cancelled => "cancelled",
            ResultCode::Timeout => "timeout",
            ResultCode::ProtocolError => "protocol_error",
            ResultCode::Other(s) => s,
        }
    }
}

impl From<String> for ResultCode {
    fn from(s: String) -> Self {
        match s.as_str() {
            "failed" => ResultCode::Failed,
            "not_found" => ResultCode::NotFound,
            "bad_request" => ResultCode::BadRequest,
            "unsupported_version" => ResultCode::UnsupportedVersion,
            "cancelled" => ResultCode::Cancelled,
            "timeout" => ResultCode::Timeout,
            "protocol_error" => ResultCode::ProtocolError,
            _ => ResultCode::Other(s),
        }
    }
}

impl From<ResultCode> for String {
    fn from(c: ResultCode) -> Self {
        c.as_str().to_owned()
    }
}

/// The `error` of a failed result.
#[non_exhaustive]
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ResultError {
    /// The code the interface translates.
    pub code: ResultCode,
    /// One English line.
    pub message: String,
    /// With `unsupported_version`: the versions the extension speaks.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub supported: Option<Vec<u32>>,
}

impl ResultError {
    /// An error with `code` and `message`, made one line.
    pub fn new(code: ResultCode, message: &str) -> Self {
        ResultError {
            code,
            message: one_line(message),
            supported: None,
        }
    }
    /// Set the versions the extension speaks (with `unsupported_version`).
    #[must_use]
    pub fn supported(mut self, versions: Vec<u32>) -> Self {
        self.supported = Some(versions);
        self
    }
}

/// The one `result` line: `ok: true` with optional `data` and `text`, or `ok: false` with an `error`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(into = "RawResult", try_from = "RawResult")]
pub enum Outcome {
    /// `ok: true`. `data: Some(Value::Null)` writes `"data":null`, `None` writes no `data`.
    Ok {
        /// Any JSON value; its shape belongs to the command.
        data: Option<Value>,
        /// What a person at a terminal is shown.
        text: Option<String>,
    },
    /// `ok: false`.
    Err(ResultError),
}

/// `result` as the schema writes it; [`Outcome`] goes through it.
#[derive(Serialize, Deserialize)]
struct RawResult {
    ok: bool,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        deserialize_with = "present"
    )]
    data: Option<Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    text: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    error: Option<ResultError>,
}

/// A field that is there is `Some`, also when it is `null`.
fn present<'de, D: Deserializer<'de>>(d: D) -> Result<Option<Value>, D::Error> {
    Value::deserialize(d).map(Some)
}

impl From<Outcome> for RawResult {
    fn from(o: Outcome) -> Self {
        match o {
            Outcome::Ok { data, text } => RawResult {
                ok: true,
                data,
                text,
                error: None,
            },
            Outcome::Err(e) => RawResult {
                ok: false,
                data: None,
                text: None,
                error: Some(e),
            },
        }
    }
}

impl TryFrom<RawResult> for Outcome {
    type Error = &'static str;
    fn try_from(r: RawResult) -> Result<Self, Self::Error> {
        match (r.ok, r.error) {
            (true, None) => Ok(Outcome::Ok {
                data: r.data,
                text: r.text,
            }),
            (false, Some(e)) => Ok(Outcome::Err(e)),
            (true, Some(_)) => Err("a result with ok true has no error"),
            (false, None) => Err("a result with ok false needs an error"),
        }
    }
}

/// What the core writes to a command.
#[non_exhaustive]
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(tag = "type", rename_all = "lowercase")]
pub enum FromCore {
    /// The one `request`.
    Request(Request),
}

/// What a command writes to the core.
#[non_exhaustive]
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(tag = "type", rename_all = "lowercase")]
pub enum FromExtension {
    /// `progress`
    Progress(Progress),
    /// `log`
    Log(Log),
    /// `event`: asks the core to write one entry to the event log.
    Event(Event),
    /// `result`: the last line.
    Result(Outcome),
}

impl Message for FromCore {
    fn from_typed(message_type: &str, value: Value) -> Result<Option<Self>, ProtocolError> {
        Ok(match message_type {
            "request" => Some(FromCore::Request(fields(message_type, value)?)),
            _ => None,
        })
    }
}

impl Message for FromExtension {
    fn from_typed(message_type: &str, value: Value) -> Result<Option<Self>, ProtocolError> {
        Ok(match message_type {
            "progress" => Some(FromExtension::Progress(fields(message_type, value)?)),
            "log" => Some(FromExtension::Log(fields(message_type, value)?)),
            "event" => Some(FromExtension::Event(fields(message_type, value)?)),
            "result" => Some(FromExtension::Result(fields(message_type, value)?)),
            _ => None,
        })
    }
}
