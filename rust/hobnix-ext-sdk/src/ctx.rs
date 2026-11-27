//! The `Ctx` trait of 0.13, kept for extensions that have not moved to `hobnix_pkg::Ctx`.
use std::io;
use std::sync::Arc;

use hobnix_pkg::integrations::Integration;
use serde_json::Value;

use crate::{Event, LogLevel};

/// The 0.13 form of `hobnix_pkg::Ctx`: [`Ctx::credential`] returns the key as a `String`, and [`Ctx::event`] is the old name of
/// [`Ctx::emit`]. Every `hobnix_pkg::Ctx` is a `Ctx` (a blanket implementation), so the runners and `testing::FakeCtx` work with it.
pub trait Ctx: Send + Sync {
    /// The key that the provider package `provider` holds for the integration `name`, or `None`.
    fn credential(&self, name: &str, provider: &str) -> Option<String>;

    /// The integration rows the host handed this process.
    fn integrations(&self) -> &[Integration];

    /// Ask the host to write an event. Fails with `InvalidInput` for a kind that is not `pkg.<package>.<kind>`.
    fn emit(&self, ev: &Event) -> io::Result<()>;

    /// Send a log line; `text` is cut to 1000 characters. Not for secrets.
    fn log(&self, level: LogLevel, text: &str) -> io::Result<()>;

    /// Report progress of a command; a service does nothing.
    fn progress(&self, fraction: Option<f64>, text: &str) -> io::Result<()>;

    /// Same as [`Ctx::emit`].
    fn event(&self, ev: &Event) -> io::Result<()> {
        self.emit(ev)
    }

    /// Add to the monthly rollup; a service only. A command gets `Unsupported`.
    fn rollup(&self, _kind: &str, _user: &str, _n: f64, _sum: f64) -> io::Result<()> {
        Err(io::Error::new(
            io::ErrorKind::Unsupported,
            "rollup is not available here",
        ))
    }

    /// Publish the newest state of `topic`; a service only. A command gets `Unsupported`.
    fn snapshot(&self, _topic: &str, _data: Value) -> io::Result<()> {
        Err(io::Error::new(
            io::ErrorKind::Unsupported,
            "snapshot is not available here",
        ))
    }

    /// A handle of the same context that can move to another thread.
    fn shared(&self) -> Arc<dyn Ctx>;
}

impl<C: hobnix_pkg::Ctx + ?Sized> Ctx for C {
    fn credential(&self, name: &str, provider: &str) -> Option<String> {
        hobnix_pkg::Ctx::credential(self, name, provider).map(|s| s.expose().to_owned())
    }
    fn integrations(&self) -> &[Integration] {
        hobnix_pkg::Ctx::integrations(self)
    }
    fn emit(&self, ev: &Event) -> io::Result<()> {
        hobnix_pkg::Ctx::emit(self, ev)
    }
    fn log(&self, level: LogLevel, text: &str) -> io::Result<()> {
        hobnix_pkg::Ctx::log(self, level, text)
    }
    fn progress(&self, fraction: Option<f64>, text: &str) -> io::Result<()> {
        hobnix_pkg::Ctx::progress(self, fraction, text)
    }
    fn rollup(&self, kind: &str, user: &str, n: f64, sum: f64) -> io::Result<()> {
        hobnix_pkg::Ctx::rollup(self, kind, user, n, sum)
    }
    fn snapshot(&self, topic: &str, data: Value) -> io::Result<()> {
        hobnix_pkg::Ctx::snapshot(self, topic, data)
    }
    fn shared(&self) -> Arc<dyn Ctx> {
        Arc::new(hobnix_pkg::Ctx::shared(self))
    }
}
