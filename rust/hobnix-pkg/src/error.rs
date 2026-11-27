//! [`Error`]: the error a package handler returns.
use std::error::Error as StdError;
use std::fmt;

type Cause = Box<dyn StdError + Send + Sync + 'static>;

/// What kind of failure an [`Error`] is; a runner maps it to the protocol (a command answers `failed`, `bad_request`, `not_found` or
/// `cancelled`). Match the kind, never the text.
#[non_exhaustive]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ErrorKind {
    /// Anything else: the work could not be done.
    Failed,
    /// The input is refused (bad arguments, a value out of range).
    BadRequest,
    /// The thing asked for does not exist.
    NotFound,
    /// The work was stopped before it ended.
    Cancelled,
}

/// An error of a package: a kind, one English line and the cause.
///
/// `Display` writes the line; the cause is [`std::error::Error::source`]. An error converted from another one with `From` or
/// [`Error::other`] is transparent: it shows that error's text and returns that error's own source.
#[derive(Debug)]
pub struct Error {
    kind: ErrorKind,
    repr: Repr,
}

#[derive(Debug)]
enum Repr {
    Message(String),
    Context { message: String, cause: Cause },
    Wrapped(Cause),
}

impl Error {
    /// An error of `kind` with `message` and no cause.
    pub fn new(kind: ErrorKind, message: impl Into<String>) -> Self {
        Error {
            kind,
            repr: Repr::Message(message.into()),
        }
    }
    /// [`ErrorKind::Failed`] with `message`.
    pub fn failed(message: impl Into<String>) -> Self {
        Self::new(ErrorKind::Failed, message)
    }
    /// [`ErrorKind::BadRequest`] with `message`.
    pub fn bad_request(message: impl Into<String>) -> Self {
        Self::new(ErrorKind::BadRequest, message)
    }
    /// [`ErrorKind::NotFound`] with `message`.
    pub fn not_found(message: impl Into<String>) -> Self {
        Self::new(ErrorKind::NotFound, message)
    }
    /// `cause` as an [`ErrorKind::Failed`] error that shows its text.
    pub fn other(cause: impl StdError + Send + Sync + 'static) -> Self {
        Error {
            kind: ErrorKind::Failed,
            repr: Repr::Wrapped(Box::new(cause)),
        }
    }
    /// An error of `kind` that says `message` and keeps `cause` as its source.
    pub fn with_cause(
        kind: ErrorKind,
        message: impl Into<String>,
        cause: impl StdError + Send + Sync + 'static,
    ) -> Self {
        Error {
            kind,
            repr: Repr::Context {
                message: message.into(),
                cause: Box::new(cause),
            },
        }
    }
    /// The kind.
    pub fn kind(&self) -> ErrorKind {
        self.kind
    }
    /// The line and every cause after it, joined by `: ` (what a log line shows).
    pub fn chain(&self) -> String {
        let mut text = self.to_string();
        let mut next = StdError::source(self);
        while let Some(e) = next {
            text.push_str(": ");
            text.push_str(&e.to_string());
            next = e.source();
        }
        text
    }
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match &self.repr {
            Repr::Message(m) | Repr::Context { message: m, .. } => f.write_str(m),
            Repr::Wrapped(e) => e.fmt(f),
        }
    }
}

impl StdError for Error {
    fn source(&self) -> Option<&(dyn StdError + 'static)> {
        match &self.repr {
            Repr::Message(_) => None,
            Repr::Context { cause, .. } => Some(cause.as_ref()),
            Repr::Wrapped(e) => e.source(),
        }
    }
}

impl From<String> for Error {
    /// [`ErrorKind::Failed`] with the text, so `?` works on a `Result<_, String>`.
    fn from(message: String) -> Self {
        Error::failed(message)
    }
}

impl From<&str> for Error {
    fn from(message: &str) -> Self {
        Error::failed(message)
    }
}

impl From<std::io::Error> for Error {
    fn from(e: std::io::Error) -> Self {
        Error::other(e)
    }
}

impl From<serde_json::Error> for Error {
    fn from(e: serde_json::Error) -> Self {
        Error::other(e)
    }
}

impl From<crate::http::HttpError> for Error {
    fn from(e: crate::http::HttpError) -> Self {
        Error::other(e)
    }
}

impl From<crate::wire::ProtocolError> for Error {
    fn from(e: crate::wire::ProtocolError) -> Self {
        Error::other(e)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn display_is_the_line_and_chain_adds_the_causes() {
        let io = std::io::Error::other("disk gone");
        let e = Error::with_cause(ErrorKind::NotFound, "no state folder", io);
        assert_eq!(e.to_string(), "no state folder");
        assert_eq!(e.chain(), "no state folder: disk gone");
        assert_eq!(e.kind(), ErrorKind::NotFound);
        let w: Error = std::io::Error::other("closed").into();
        assert_eq!(
            (w.to_string(), w.chain()),
            ("closed".into(), "closed".into())
        );
        let s: Error = String::from("cannot").into();
        assert_eq!((s.kind(), s.chain()), (ErrorKind::Failed, "cannot".into()));
    }

    #[test]
    fn the_error_can_cross_threads() {
        fn is_send_sync<T: Send + Sync + StdError + 'static>() {}
        is_send_sync::<Error>();
    }
}
