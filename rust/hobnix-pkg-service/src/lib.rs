//! Service extensions (ADR 0011): one supervised process, JSON lines both ways (docs/api/ext-service-v1.schema.json). The base types
//! (`Ctx`, `Event`, `LogLevel`, `Error`) are in `hobnix-pkg`.
//!
//! Implement [`Service`] and call [`run`]. The runner reads `init`, calls [`Service::start`], sends `ready`, then loops: it calls
//! [`Service::tick`] and sends `health` at least every `health_interval` (half of it, so one late tick is not a missed heartbeat),
//! passes each `event` to [`Service::on_event`] and sends the `ack` when that returns `Ok`, and returns when the core sends `shutdown`
//! or closes stdin. Events are delivered at least once: `on_event` must be idempotent (use `EventRow::id` as the key).
//!
//! A slow `on_event` or `tick` delays the heartbeat; keep them short or hand work to your own threads (`Ctx::shared` gives a handle that
//! moves to another thread).

use std::io::{self, BufRead, Write};
use std::sync::Arc;
use std::sync::mpsc::{self, RecvTimeoutError};
use std::thread;
use std::time::{Duration, Instant};

use hobnix_pkg::integrations::Integration;
use hobnix_pkg::wire::service::{
    Ack, FromCore, FromService, HEALTH_TEXT_MAX, Rollup, SNAPSHOT_MAX, Snapshot, is_rollup_user,
    is_snapshot_topic,
};
use hobnix_pkg::wire::{self, Decoded, Log, ProtocolError, Writer};
use hobnix_pkg::{Ctx, Error, Event, LogLevel, Secret};
use serde_json::Value;

pub use hobnix_pkg::Lang;
pub use hobnix_pkg::wire::service::{EventRow, Health, Init};

/// What a service does; every method has a default, so implement only what you need.
pub trait Service {
    /// Called once after `init`, before `ready`. An `Err` ends the process with status 1 (the core marks the start failed); the error
    /// and its causes go to stderr.
    fn start(&mut self, _init: &Init, _ctx: &dyn Ctx) -> Result<(), Error> {
        Ok(())
    }
    /// Handle one event. `Ok` sends the `ack`. `Err` logs the error with its causes, sends no ack and keeps going: the event comes again
    /// after a restart, and the core stops delivering when 100 events are unacknowledged, so a service that cannot handle events should
    /// report `Health::degraded` from [`Service::tick`].
    fn on_event(&mut self, _event: &EventRow, _ctx: &dyn Ctx) -> Result<(), Error> {
        Ok(())
    }
    /// Called at startup and then every half `health_interval`: do periodic work (a collector reads and sends a snapshot here) and
    /// say how the service is.
    fn tick(&mut self, _ctx: &dyn Ctx) -> Health {
        Health::ok()
    }
}

/// The stdin/stdout side of [`Ctx`] for a service: `log`, `emit`, `rollup` and `snapshot` lines on stdout.
#[derive(Clone)]
struct StdioCtx {
    out: Writer,
    integrations: Arc<[Integration]>,
}

/// A write error as the `io::Error` the [`Ctx`] methods return: a refused message is `InvalidInput`.
fn to_io(e: ProtocolError) -> io::Error {
    match e {
        ProtocolError::Io(e) => e,
        ProtocolError::Encode(e) => io::Error::other(e),
        e => io::Error::new(io::ErrorKind::InvalidInput, e.to_string()),
    }
}

fn invalid(why: &str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidInput, why)
}

impl StdioCtx {
    fn send(&self, msg: &FromService) -> io::Result<()> {
        self.out.send(msg).map_err(to_io)
    }
}

impl Ctx for StdioCtx {
    fn credential(&self, name: &str, provider: &str) -> Option<Secret> {
        hobnix_pkg::credentials::credential_for(name, provider)
    }
    fn integrations(&self) -> &[Integration] {
        &self.integrations
    }
    /// The core allows 50 a minute per service and only kinds of the manifest's `[[events]]`.
    fn emit(&self, ev: &Event) -> io::Result<()> {
        if !wire::is_event_kind(&ev.kind) {
            return Err(invalid("event kind must look like pkg.<package>.<kind>"));
        }
        self.send(&FromService::Emit(ev.clone()))
    }
    fn log(&self, level: LogLevel, text: &str) -> io::Result<()> {
        self.send(&FromService::Log(Log::new(level, text)))
    }
    fn progress(&self, _fraction: Option<f64>, _text: &str) -> io::Result<()> {
        Ok(())
    }
    /// The core does it, only for a `kind` of this package declared in `[[events]]` with `retention = "metric"`; others are dropped
    /// with a warning. Counts against the emit limit.
    fn rollup(&self, kind: &str, user: &str, n: f64, sum: f64) -> io::Result<()> {
        if !is_rollup_user(user) {
            return Err(invalid(
                "user must be 1 to 64 characters of A-Za-z0-9 and _ . @ -, starting with a letter or digit",
            ));
        }
        self.send(&FromService::Rollup(Rollup::new(kind, user, n, sum)))
    }
    /// Replaces the previous state of `topic`.
    fn snapshot(&self, topic: &str, data: Value) -> io::Result<()> {
        if !is_snapshot_topic(topic) {
            return Err(invalid(
                "topic must be 1 to 60 characters of a-z, 0-9 and -",
            ));
        }
        let size = serde_json::to_vec(&data).map_err(io::Error::other)?.len();
        if size > SNAPSHOT_MAX {
            return Err(invalid("snapshot larger than 256 KiB"));
        }
        self.send(&FromService::Snapshot(Snapshot::new(topic, data)))
    }
    fn shared(&self) -> Arc<dyn Ctx> {
        Arc::new(self.clone())
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
    let out = Writer::new(output);
    // Before `ready` only `ready` may be written, so a failure here is reported on stderr only.
    let init = match read_init(&mut input) {
        Ok(init) => init,
        Err(e) => return die(&e),
    };
    let ctx = StdioCtx {
        out: out.clone(),
        integrations: init.integrations.clone().into(),
    };
    if let Err(e) = service.start(&init, &ctx) {
        return die(&format!("start failed: {}", e.chain()));
    }
    if out.send(&FromService::Ready).is_err() {
        return 1;
    }
    let rx = spawn_reader(input);
    let period = Duration::from_secs_f64((init.health_interval / 2.0).clamp(0.05, 150.0));
    let mut next_tick = Instant::now();
    loop {
        if Instant::now() >= next_tick {
            if send_health(&out, service.tick(&ctx)).is_err() {
                return 1;
            }
            next_tick = Instant::now() + period;
        }
        match rx.recv_timeout(next_tick.saturating_duration_since(Instant::now())) {
            Ok(Msg::Event(ev)) => {
                if handle(&mut service, &ev, &ctx).is_err() {
                    return 1;
                }
            }
            Ok(Msg::Shutdown | Msg::Eof) | Err(RecvTimeoutError::Disconnected) => return 0,
            Ok(Msg::Bad(e)) => return die(&e),
            Err(RecvTimeoutError::Timeout) => {}
        }
    }
}

/// One event: the `ack` when the service handled it, else a log line. Fails only when the ack cannot be written.
fn handle(service: &mut impl Service, ev: &EventRow, ctx: &StdioCtx) -> io::Result<()> {
    match service.on_event(ev, ctx) {
        Ok(()) => ctx.send(&FromService::Ack(Ack::new(ev.id))),
        Err(e) => {
            let text = format!("event {} not handled: {}", ev.id, e.chain());
            let _ = ctx.log(LogLevel::Error, &text);
            Ok(())
        }
    }
}

/// The first line, which must be `init`; the error is the stderr text.
fn read_init(input: &mut impl BufRead) -> Result<Init, String> {
    let line = match wire::read_line(input) {
        Ok(Some(l)) => l,
        Ok(None) => return Err("stdin closed before init".into()),
        Err(ProtocolError::TooLong) => return Err("init longer than 1 MiB".into()),
        Err(e) => return Err(format!("cannot read init: {}", to_io(e))),
    };
    match wire::decode::<FromCore>(&line) {
        Ok(Decoded::Message(FromCore::Init(init))) => Ok(init),
        Err(ProtocolError::Invalid {
            message_type,
            source,
        }) if message_type == "init" => Err(format!("invalid init: {source}")),
        Err(e @ (ProtocolError::NotJson(_) | ProtocolError::UnsupportedVersion(_))) => {
            Err(bad_line(&e))
        }
        _ => Err("expected a init message".into()),
    }
}

/// The stderr text of a line that is not JSON or not version 1.
fn bad_line(e: &ProtocolError) -> String {
    match e {
        ProtocolError::UnsupportedVersion(_) => "unsupported protocol version (this SDK speaks 1)",
        _ => "a line that is not JSON",
    }
    .into()
}

/// Reads stdin on its own thread so `tick` keeps its period while no line comes. It ends after the first message that is not an
/// event, or when the receiver is gone.
fn spawn_reader(mut input: impl BufRead + Send + 'static) -> mpsc::Receiver<Msg> {
    let (tx, rx) = mpsc::channel();
    thread::spawn(move || {
        loop {
            let msg = match wire::read_line(&mut input) {
                Ok(None) | Err(ProtocolError::Io(_)) => Msg::Eof,
                Err(_) => Msg::Bad("line longer than 1 MiB".into()),
                Ok(Some(l)) => match classify(&l) {
                    Some(m) => m,
                    // a type this version does not know: ignored (ADR 0010 rule 3)
                    None => continue,
                },
            };
            let last = !matches!(msg, Msg::Event(_));
            if tx.send(msg).is_err() || last {
                break;
            }
        }
    });
    rx
}

/// One line after `init`: `None` for a line that is not for this loop (`init` twice, a type of a later minor version, no type).
fn classify(line: &str) -> Option<Msg> {
    match wire::decode::<FromCore>(line) {
        Ok(Decoded::Message(FromCore::Event(e))) => Some(Msg::Event(e)),
        // the core wants the service gone: a shutdown line with odd fields still is one
        Ok(Decoded::Message(FromCore::Shutdown(_))) => Some(Msg::Shutdown),
        Err(ProtocolError::Invalid { message_type, .. }) if message_type == "shutdown" => {
            Some(Msg::Shutdown)
        }
        Err(ProtocolError::Invalid {
            message_type,
            source,
        }) if message_type == "event" => Some(Msg::Bad(format!("invalid event: {source}"))),
        Err(e @ (ProtocolError::NotJson(_) | ProtocolError::UnsupportedVersion(_))) => {
            Some(Msg::Bad(bad_line(&e)))
        }
        _ => None,
    }
}

fn send_health(out: &Writer, h: Health) -> Result<(), ProtocolError> {
    let text = h.text.map(|t| wire::truncate(&t, HEALTH_TEXT_MAX));
    out.send(&FromService::Health(Health { ok: h.ok, text }))
}

/// The one error line on stderr (part of the protocol: the core keeps it) and exit status 1.
fn die(reason: &str) -> u8 {
    let _ = writeln!(io::stderr(), "hobnix-pkg-service: {reason}");
    1
}
