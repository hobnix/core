//! A fake [`Ctx`] for tests of a handler: it records what the handler asked and answers from what the test set up.
use std::io;
use std::sync::{Arc, Mutex, MutexGuard};

use serde_json::Value;

use crate::integrations::Integration;
use crate::{Ctx, Event, LogLevel, Secret};

/// One call a handler made on a [`FakeCtx`].
#[non_exhaustive]
#[derive(Debug, Clone, PartialEq)]
pub enum Call {
    /// `emit`.
    Emit(Event),
    /// `log` with the level and the text as given.
    Log(LogLevel, String),
    /// `progress` with the fraction and text as given.
    Progress(Option<f64>, String),
    /// `rollup` with kind, user, n and sum.
    Rollup(String, String, f64, f64),
    /// `snapshot` with topic and data.
    Snapshot(String, Value),
}

#[derive(Default)]
struct State {
    calls: Vec<Call>,
    credentials: Vec<(String, String, String)>,
}

/// A [`Ctx`] that writes nothing and records every call; clones share the record.
#[derive(Clone, Default)]
pub struct FakeCtx {
    state: Arc<Mutex<State>>,
    integrations: Arc<[Integration]>,
}

/// Calls, integrations and the names of the credentials; never a credential's key.
impl std::fmt::Debug for FakeCtx {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let state = self.lock();
        let credentials: Vec<(&str, &str)> = state
            .credentials
            .iter()
            .map(|(n, p, _)| (n.as_str(), p.as_str()))
            .collect();
        f.debug_struct("FakeCtx")
            .field("calls", &state.calls)
            .field("integrations", &self.integrations)
            .field("credentials", &credentials)
            .finish_non_exhaustive()
    }
}

impl FakeCtx {
    /// A fake with no integrations and no credentials.
    pub fn new() -> Self {
        Self::default()
    }

    /// Set the rows [`Ctx::integrations`] returns.
    #[must_use]
    pub fn with_integrations(mut self, rows: Vec<Integration>) -> Self {
        self.integrations = rows.into();
        self
    }

    /// Make `credential(name, provider)` answer `key`.
    #[must_use]
    pub fn with_credential(self, name: &str, provider: &str, key: &str) -> Self {
        self.lock()
            .credentials
            .push((name.into(), provider.into(), key.into()));
        self
    }

    /// The calls made so far, in order.
    pub fn calls(&self) -> Vec<Call> {
        self.lock().calls.clone()
    }

    fn lock(&self) -> MutexGuard<'_, State> {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
    }

    fn record(&self, call: Call) {
        self.lock().calls.push(call);
    }
}

impl Ctx for FakeCtx {
    fn credential(&self, name: &str, provider: &str) -> Option<Secret> {
        let state = self.lock();
        let hit = state
            .credentials
            .iter()
            .find(|(n, p, _)| n == name && p == provider);
        hit.map(|(_, _, key)| Secret::new(key.as_str()))
    }
    fn integrations(&self) -> &[Integration] {
        &self.integrations
    }
    fn emit(&self, ev: &Event) -> io::Result<()> {
        self.record(Call::Emit(ev.clone()));
        Ok(())
    }
    fn log(&self, level: LogLevel, text: &str) -> io::Result<()> {
        self.record(Call::Log(level, text.into()));
        Ok(())
    }
    fn progress(&self, fraction: Option<f64>, text: &str) -> io::Result<()> {
        self.record(Call::Progress(fraction, text.into()));
        Ok(())
    }
    fn rollup(&self, kind: &str, user: &str, n: f64, sum: f64) -> io::Result<()> {
        self.record(Call::Rollup(kind.into(), user.into(), n, sum));
        Ok(())
    }
    fn snapshot(&self, topic: &str, data: Value) -> io::Result<()> {
        self.record(Call::Snapshot(topic.into(), data));
        Ok(())
    }
    fn shared(&self) -> Arc<dyn Ctx> {
        Arc::new(self.clone())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn records_calls_and_answers_credentials() {
        let ctx = FakeCtx::new().with_credential("media", "jf", "k");
        ctx.log(LogLevel::Info, "a").unwrap();
        ctx.shared().emit(&Event::new("pkg.t.x", "s")).unwrap();
        let key = ctx.credential("media", "jf");
        assert_eq!(key.as_ref().map(Secret::expose), Some("k"));
        assert!(ctx.credential("media", "other").is_none());
        assert_eq!(
            ctx.calls(),
            [
                Call::Log(LogLevel::Info, "a".into()),
                Call::Emit(Event::new("pkg.t.x", "s"))
            ]
        );
    }

    #[test]
    fn debug_does_not_show_a_credential() {
        let ctx = FakeCtx::new().with_credential("media", "jf", "key-4f1c9a");
        let d = format!("{ctx:?}");
        assert!(!d.contains("key-4f1c9a"), "{d}");
        assert!(d.contains("media") && d.contains("jf"), "{d}");
    }
}
