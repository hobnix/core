//! [`Ctx`]: what a package asks of the host, as a trait, so a handler does not know which runtime or transport is behind it.
use std::io;
use std::sync::Arc;

use serde_json::Value;

use crate::integrations::Integration;
use crate::{Event, LogLevel, Secret};

/// Everything a package asks of the host, and nothing else: the protocol of ADR 0010 and 0011 carries no call to run a host command
/// (ADR 0031 decisions 7 and 8). Handlers get a `&dyn Ctx`; tests use [`crate::testing::FakeCtx`]. `&C` and `Arc<C>` of a `Ctx` are a
/// `Ctx` too.
///
/// Write failures are returned, not hidden; a call that has no use for them can ignore the result. A new method gets a default body, so
/// an implementation outside this crate keeps compiling.
pub trait Ctx: Send + Sync {
    /// The key that the provider package `provider` holds for the integration `name`, or `None` (see
    /// [`crate::credentials::credential_for`]).
    fn credential(&self, name: &str, provider: &str) -> Option<Secret>;

    /// The integration rows the host handed this process: `init.integrations` in a service, empty in a command (the core sends none).
    fn integrations(&self) -> &[Integration];

    /// Ask the host to write an event. Fails with `InvalidInput` for a kind that is not `pkg.<package>.<kind>` and for a line longer
    /// than [`crate::MAX_LINE`]; with the write error when the host is gone.
    fn emit(&self, ev: &Event) -> io::Result<()>;

    /// Send a log line; `text` is cut to 1000 characters. Not for secrets. Fails when the line cannot be written.
    fn log(&self, level: LogLevel, text: &str) -> io::Result<()>;

    /// Report progress of a command: `fraction` is clamped to 0..=1, `text` is cut to 200 characters. A service has no progress message
    /// and the call does nothing. Fails when the line cannot be written.
    fn progress(&self, fraction: Option<f64>, text: &str) -> io::Result<()>;

    /// Add to the monthly rollup of (month, `user`, `kind`); a service only (ADR 0011). A command gets `Unsupported`; a `user` outside
    /// the schema gets `InvalidInput`.
    fn rollup(&self, _kind: &str, _user: &str, _n: f64, _sum: f64) -> io::Result<()> {
        Err(unsupported("rollup"))
    }

    /// Publish the newest state of `topic`; a service only (ADR 0011). A command gets `Unsupported`; a bad topic or more than 256 KiB
    /// gets `InvalidInput`.
    fn snapshot(&self, _topic: &str, _data: Value) -> io::Result<()> {
        Err(unsupported("snapshot"))
    }

    /// A handle of the same context that can move to another thread (a service hands work to its own threads).
    fn shared(&self) -> Arc<dyn Ctx>;
}

fn unsupported(what: &str) -> io::Error {
    io::Error::new(
        io::ErrorKind::Unsupported,
        format!("{what} is not available here"),
    )
}

macro_rules! forward {
    ($($ty:ty),*) => {$(
        impl<C: Ctx + ?Sized> Ctx for $ty {
            fn credential(&self, name: &str, provider: &str) -> Option<Secret> {
                (**self).credential(name, provider)
            }
            fn integrations(&self) -> &[Integration] {
                (**self).integrations()
            }
            fn emit(&self, ev: &Event) -> io::Result<()> {
                (**self).emit(ev)
            }
            fn log(&self, level: LogLevel, text: &str) -> io::Result<()> {
                (**self).log(level, text)
            }
            fn progress(&self, fraction: Option<f64>, text: &str) -> io::Result<()> {
                (**self).progress(fraction, text)
            }
            fn rollup(&self, kind: &str, user: &str, n: f64, sum: f64) -> io::Result<()> {
                (**self).rollup(kind, user, n, sum)
            }
            fn snapshot(&self, topic: &str, data: Value) -> io::Result<()> {
                (**self).snapshot(topic, data)
            }
            fn shared(&self) -> Arc<dyn Ctx> {
                (**self).shared()
            }
        }
    )*};
}

forward!(&C, Arc<C>);
