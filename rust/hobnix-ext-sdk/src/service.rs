//! Service extensions (ADR 0011): one supervised process, JSON lines both ways.
//!
//! Implement [`Service`] and call [`run`]. The SDK reads `init`, calls [`Service::start`], sends `ready`, then loops: it calls
//! [`Service::tick`] and sends `health` at least every `health_interval` (half of it, so one late tick is not a missed heartbeat),
//! passes each `event` to [`Service::on_event`] and sends the `ack` when that returns `Ok`, and returns when the core sends `shutdown`
//! or closes stdin. Events are delivered at least once: `on_event` must be idempotent (use `EventRow::id` as the key).
//!
//! A slow `on_event` or `tick` delays the heartbeat; keep them short or hand work to your own threads (`Ctx::shared` gives a handle that moves to another thread).

use std::io::{self, BufRead, Write};
use std::sync::Arc;
use std::sync::mpsc::{self, RecvTimeoutError};
use std::thread;
use std::time::{Duration, Instant};

use serde::Deserialize;
use serde_json::{Value, json};

use crate::command::Lang;
use crate::integrations::Integration;
use crate::proto::{Line, Out, cut, read_line};
use crate::{Ctx, Event, LogLevel, VERSION};

/// First message from the core.
#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct Init {
    pub name: String,
    pub lang: Lang,
    /// Event kind globs from the manifest; empty for a pure collector.
    pub subscribe: Vec<String>,
    /// Seconds between `health` messages the core expects at most.
    pub health_interval: f64,
    /// The rows of the integrations the package declared (`permissions = ["integration:<name>"]`), built by the core: a confined service
    /// cannot run `hs pkg integrations`. No keys in it, read them with [`Integration::credential`]. Empty when none is declared or
    /// when the core is older than this field.
    #[serde(default)]
    pub integrations: Vec<Integration>,
}

/// One row of the event log, delivered at least once and in `id` order.
#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct EventRow {
    pub id: u64,
    pub time: i64,
    pub source: String,
    pub kind: String,
    pub subject: String,
    pub level: String,
    #[serde(default)]
    pub text: Option<String>,
    #[serde(default)]
    pub payload: Option<Value>,
}

/// The answer to a heartbeat. `ok: false` marks the service `degraded`; the text is one English line (cut to 200 characters).
#[derive(Debug, Clone, PartialEq)]
pub struct Health {
    pub ok: bool,
    pub text: Option<String>,
}

impl Health {
    pub fn ok() -> Self {
        Health {
            ok: true,
            text: None,
        }
    }
    pub fn degraded(text: impl Into<String>) -> Self {
        Health {
            ok: false,
            text: Some(text.into()),
        }
    }
}

/// The stdin/stdout side of [`Ctx`] for a service: `log`, `emit`, `rollup` and `snapshot` lines on stdout.
#[derive(Clone)]
struct StdioCtx {
    out: Out,
    integrations: Arc<[Integration]>,
}

impl Ctx for StdioCtx {
    fn credential(&self, name: &str, provider: &str) -> Option<String> {
        credential_for(name, provider)
    }
    fn integrations(&self) -> &[Integration] {
        &self.integrations
    }
    /// The core allows 50 a minute per service and only kinds of the manifest's `[[events]]`.
    fn emit(&self, ev: &Event) -> io::Result<()> {
        self.out.event("emit", ev)
    }
    fn log(&self, level: LogLevel, text: &str) -> io::Result<()> {
        self.out.log(level, text)
    }
    fn progress(&self, _fraction: Option<f64>, _text: &str) -> io::Result<()> {
        Ok(())
    }
    /// The core does it, only for a `kind` of this package declared in `[[events]]` with `retention = "metric"`; others are dropped
    /// with a warning. Counts against the emit limit. `user`: 1 to 64 of `A-Za-z0-9_.@-`, the first a letter or digit (never an option).
    fn rollup(&self, kind: &str, user: &str, n: f64, sum: f64) -> io::Result<()> {
        let user_ok = user
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '_' | '.' | '@' | '-'));
        let first_ok = user
            .chars()
            .next()
            .is_some_and(|c| c.is_ascii_alphanumeric());
        if !(1..=64).contains(&user.len()) || !user_ok || !first_ok {
            let why = "user must be 1 to 64 characters of A-Za-z0-9 and _ . @ -, starting with a letter or digit";
            return Err(io::Error::new(io::ErrorKind::InvalidInput, why));
        }
        self.out.typed(
            "rollup",
            json!({"kind": kind, "user": user, "n": n, "sum": sum}),
        )
    }
    /// `topic` is `[a-z0-9-]{1,60}`; replaces the previous state. At most 256 KiB.
    fn snapshot(&self, topic: &str, data: Value) -> io::Result<()> {
        let chars_ok = topic
            .chars()
            .all(|c| matches!(c, 'a'..='z' | '0'..='9' | '-'));
        if !(1..=60).contains(&topic.len()) || !chars_ok {
            let why = "topic must be 1 to 60 characters of a-z, 0-9 and -";
            return Err(io::Error::new(io::ErrorKind::InvalidInput, why));
        }
        let size = serde_json::to_vec(&data).map_err(io::Error::other)?.len();
        if size > 256 << 10 {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "snapshot larger than 256 KiB",
            ));
        }
        self.out
            .typed("snapshot", json!({"topic": topic, "data": data}))
    }
    fn shared(&self) -> Arc<dyn Ctx> {
        Arc::new(self.clone())
    }
}

fn valid_name(s: &str) -> bool {
    !s.is_empty() && s.chars().all(|c| matches!(c, 'a'..='z' | '0'..='9' | '-'))
}

/// `$CREDENTIALS_DIRECTORY`, read where a credential is asked for (the tests pass a folder to the `_in` functions instead).
fn credentials_dir() -> Option<std::path::PathBuf> {
    std::env::var_os("CREDENTIALS_DIRECTORY").map(std::path::PathBuf::from)
}

fn read_credential(dir: &std::path::Path, file: &str) -> Option<String> {
    let text = std::fs::read_to_string(dir.join(file)).ok()?;
    Some(text.trim_end().to_string())
}

/// [`credential_for`] from the folder `dir`.
pub(crate) fn credential_in(dir: &std::path::Path, name: &str, provider: &str) -> Option<String> {
    if !valid_name(name) || !valid_name(provider) {
        return None;
    }
    read_credential(dir, &format!("integration-{name}-{provider}"))
}

/// The deprecated [`credential`] from the folder `dir`.
fn legacy_credential_in(dir: &std::path::Path, name: &str) -> Option<String> {
    if !valid_name(name) {
        return None;
    }
    read_credential(dir, &format!("integration-{name}"))
}

/// The key that the provider package `provider` holds for the integration `name` (declared as `integration:<name>` in `permissions`). The
/// core hands a confined service one systemd credential per provider, `integration-<name>-<provider>`: read from `$CREDENTIALS_DIRECTORY`,
/// never from argv or the environment. The provider is the `package` column of `hs pkg integrations` (or [`crate::integrations::Integration::credential`]).
/// Trailing whitespace is cut. `None` when there is no such credential (not declared, the provider has no key, the key is locked or missing).
pub fn credential_for(name: &str, provider: &str) -> Option<String> {
    credential_in(&credentials_dir()?, name, provider)
}

/// Deprecated, goes away after the next release: the old one-name form `integration-<name>` (the first provider with a key, owner not told).
/// Use [`credential_for`], which names the provider. Same rules as there; `None` when there is no such credential.
#[deprecated(note = "use credential_for(name, provider): the credential is one per provider")]
pub fn credential(name: &str) -> Option<String> {
    legacy_credential_in(&credentials_dir()?, name)
}

pub trait Service {
    /// Called once after `init`, before `ready`. An `Err` ends the process with status 1 (the core marks the start failed).
    fn start(&mut self, _init: &Init, _ctx: &dyn Ctx) -> Result<(), String> {
        Ok(())
    }
    /// Handle one event. `Ok` sends the `ack`. `Err` logs the reason, sends no ack and keeps going: the event comes again after a
    /// restart, and the core stops delivering when 100 events are unacknowledged, so a service that cannot handle events should
    /// report `Health::degraded` from [`Service::tick`].
    fn on_event(&mut self, _event: &EventRow, _ctx: &dyn Ctx) -> Result<(), String> {
        Ok(())
    }
    /// Called at startup and then every half `health_interval`: do periodic work (a collector reads and sends a snapshot here) and
    /// say how the service is.
    fn tick(&mut self, _ctx: &dyn Ctx) -> Health {
        Health::ok()
    }
}

/// Run the service against stdin/stdout. Returns the exit code: 0 after `shutdown` or end of stdin, 1 after a protocol error.
pub fn run(service: impl Service) -> std::process::ExitCode {
    let code = run_with(io::BufReader::new(io::stdin()), io::stdout(), service);
    std::process::ExitCode::from(code)
}

enum Msg {
    Event(EventRow),
    Shutdown,
    Eof,
    Bad(String),
}

/// [`run`] over any reader and writer (for tests).
pub fn run_with(
    mut input: impl BufRead + Send + 'static,
    output: impl Write + Send + 'static,
    mut service: impl Service,
) -> u8 {
    let out = Out::new(output);
    // Before `ready` only `ready` may be written, so a failure here is reported on stderr only.
    let init: Init = match read_line(&mut input) {
        Ok(Line::Text(l)) => match parse(&l, "init") {
            Ok(v) => v,
            Err(e) => return die(&e),
        },
        Ok(Line::Eof) => return die("stdin closed before init"),
        Ok(Line::TooLong) => return die("init longer than 1 MiB"),
        Err(e) => return die(&format!("cannot read init: {e}")),
    };
    let ctx = StdioCtx {
        out: out.clone(),
        integrations: init.integrations.clone().into(),
    };
    if let Err(e) = service.start(&init, &ctx) {
        return die(&format!("start failed: {e}"));
    }
    if out.typed("ready", json!({})).is_err() {
        return 1;
    }

    let (tx, rx) = mpsc::channel();
    thread::spawn(move || {
        loop {
            let msg = match read_line(&mut input) {
                Ok(Line::Eof) | Err(_) => Msg::Eof,
                Ok(Line::TooLong) => Msg::Bad("line longer than 1 MiB".into()),
                Ok(Line::Text(l)) => match classify(&l) {
                    Ok(Some(m)) => m,
                    // a type this version does not know: ignored (ADR 0010 rule 3)
                    Ok(None) => continue,
                    Err(e) => Msg::Bad(e),
                },
            };
            let last = !matches!(msg, Msg::Event(_));
            if tx.send(msg).is_err() || last {
                break;
            }
        }
    });

    let period = Duration::from_secs_f64((init.health_interval / 2.0).clamp(0.05, 150.0));
    let mut next_tick = Instant::now();
    loop {
        if Instant::now() >= next_tick {
            let h = service.tick(&ctx);
            let mut f = json!({"ok": h.ok});
            if let Some(t) = h.text {
                f["text"] = json!(cut(&t, 200));
            }
            if out.typed("health", f).is_err() {
                return 1;
            }
            next_tick = Instant::now() + period;
        }
        match rx.recv_timeout(next_tick.saturating_duration_since(Instant::now())) {
            Ok(Msg::Event(ev)) => match service.on_event(&ev, &ctx) {
                Ok(()) => {
                    if out.typed("ack", json!({"id": ev.id})).is_err() {
                        return 1;
                    }
                }
                Err(e) => {
                    let _ = ctx.log(
                        LogLevel::Error,
                        &format!("event {} not handled: {e}", ev.id),
                    );
                }
            },
            Ok(Msg::Shutdown) | Ok(Msg::Eof) | Err(RecvTimeoutError::Disconnected) => return 0,
            Ok(Msg::Bad(e)) => return die(&e),
            Err(RecvTimeoutError::Timeout) => {}
        }
    }
}

#[allow(clippy::print_stderr)] // the one error line on stderr is part of the extension protocol
fn die(reason: &str) -> u8 {
    eprintln!("hobnix-ext-sdk: {reason}");
    1
}

fn parse<T: serde::de::DeserializeOwned>(line: &str, ty: &str) -> Result<T, String> {
    let v: Value = serde_json::from_str(line).map_err(|_| "a line that is not JSON".to_string())?;
    if v.get("v").and_then(Value::as_u64) != Some(VERSION as u64) {
        return Err("unsupported protocol version (this SDK speaks 1)".into());
    }
    if v.get("type").and_then(Value::as_str) != Some(ty) {
        return Err(format!("expected a {ty} message"));
    }
    serde_json::from_value(v).map_err(|e| format!("invalid {ty}: {e}"))
}

fn classify(line: &str) -> Result<Option<Msg>, String> {
    let v: Value = serde_json::from_str(line).map_err(|_| "a line that is not JSON".to_string())?;
    if v.get("v").and_then(Value::as_u64) != Some(VERSION as u64) {
        return Err("unsupported protocol version (this SDK speaks 1)".into());
    }
    match v.get("type").and_then(Value::as_str) {
        Some("event") => match serde_json::from_value(v) {
            Ok(e) => Ok(Some(Msg::Event(e))),
            Err(e) => Err(format!("invalid event: {e}")),
        },
        Some("shutdown") => Ok(Some(Msg::Shutdown)),
        // `init` twice or a type from a later minor version: not for this loop
        _ => Ok(None),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// One credential per provider (hobnix/core#1135): each row reads only its own file. The folder is passed in, the environment of the
    /// test process is not changed (tests/ext-sdk-rust.sh covers `$CREDENTIALS_DIRECTORY` end to end).
    #[test]
    fn one_credential_per_provider() {
        let dir = std::env::temp_dir().join(format!("hs-sdk-cred-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("integration-media-jellyfin"), "JELLY\n").unwrap();
        std::fs::write(dir.join("integration-media-radarr"), "RADAR \n").unwrap();
        std::fs::write(dir.join("integration-media"), "OLD\n").unwrap();

        assert_eq!(
            credential_in(&dir, "media", "jellyfin").as_deref(),
            Some("JELLY")
        );
        assert_eq!(
            credential_in(&dir, "media", "radarr").as_deref(),
            Some("RADAR")
        );
        assert!(credential_in(&dir, "media", "sonarr").is_none());
        assert!(credential_in(&dir, "media", "../jellyfin").is_none());
        assert!(credential_in(&dir, "", "jellyfin").is_none());

        let rows = crate::integrations::parse(
            "radarr\tmedia\trecipe\thttp://x\t/k\t-\tX-Api-Key\nsonarr\tmedia\trecipe\t-\t-\t-\t-\n",
        );
        assert_eq!(rows[0].credential_name(), "integration-media-radarr");
        let of = |r: &Integration| credential_in(&dir, &r.integration, &r.package);
        assert_eq!(of(&rows[0]).as_deref(), Some("RADAR"));
        assert!(of(&rows[1]).is_none());

        assert_eq!(legacy_credential_in(&dir, "media").as_deref(), Some("OLD"));
        assert!(legacy_credential_in(&dir, "../media").is_none());
        std::fs::remove_dir_all(&dir).unwrap();
    }
}
