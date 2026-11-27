//! The one way to stdout of a service. Nothing but `ready` may come before `ready` (ADR 0011 rule 6, a `protocol_error`), but `start`
//! and the threads it starts can already write through their [`Ctx`](hobnix_pkg::Ctx), so those messages are held back and follow
//! `ready` in the order they were written (#1353).
//!
//! A held write returns at once: `start` may wait for a thread that writes. The protocol has no message that the core answers, so
//! nothing a service writes can wait for `ready` to be out.

use std::io::{self, Write};
use std::sync::{Arc, Mutex, MutexGuard, PoisonError};

use hobnix_pkg::LogLevel;
use hobnix_pkg::wire::service::FromService;
use hobnix_pkg::wire::{self, Log, ProtocolError};

/// Most messages held before `ready`.
const HELD_MAX_MESSAGES: usize = 1000;
/// Most bytes of lines held before `ready`.
const HELD_MAX_BYTES: usize = 4 << 20;

/// The messages written before `ready`, as encoded lines.
#[derive(Default)]
struct Held {
    lines: Vec<HeldLine>,
    bytes: usize,
    /// Messages that did not fit; the newest are refused, so what is held has no older gap than the first refusal.
    refused: u64,
}

struct HeldLine {
    is_log: bool,
    /// With its newline.
    text: String,
}

impl Held {
    /// Keep the line, or refuse it with `QuotaExceeded` when a limit is reached.
    fn push(&mut self, line: HeldLine) -> io::Result<()> {
        let bytes = self.bytes.saturating_add(line.text.len());
        if self.lines.len() >= HELD_MAX_MESSAGES || bytes > HELD_MAX_BYTES {
            self.refused = self.refused.saturating_add(1);
            let why = "too much was written before ready; the message is dropped";
            return Err(io::Error::new(io::ErrorKind::QuotaExceeded, why));
        }
        self.bytes = bytes;
        self.lines.push(line);
        Ok(())
    }

    /// What became of the refused messages, if there are any.
    fn refused_text(&self) -> Option<String> {
        (self.refused > 0).then(|| {
            format!(
                "{} messages written before ready were dropped (at most {HELD_MAX_MESSAGES} messages or {} MiB are held)",
                self.refused,
                HELD_MAX_BYTES >> 20
            )
        })
    }
}

enum State {
    /// Before `ready`.
    Holding(Held),
    /// `ready` is out: every message is written at once.
    Open,
    /// The service never became ready: nothing may be written any more.
    Closed,
}

struct Inner {
    sink: Box<dyn Write + Send>,
    state: State,
}

/// A clonable handle on the output, so a service can write from several threads.
#[derive(Clone)]
pub(crate) struct Output(Arc<Mutex<Inner>>);

impl Output {
    pub(crate) fn new(sink: impl Write + Send + 'static) -> Self {
        Output(Arc::new(Mutex::new(Inner {
            sink: Box::new(sink),
            state: State::Holding(Held::default()),
        })))
    }

    fn lock(&self) -> MutexGuard<'_, Inner> {
        self.0.lock().unwrap_or_else(PoisonError::into_inner)
    }

    /// Write `msg`, or hold it while `ready` is not out. Fails as [`wire::encode`] does (before `ready` too), with the write error,
    /// with `QuotaExceeded` when no more can be held and with `NotConnected` after [`Output::abandon`].
    pub(crate) fn send(&self, msg: &FromService) -> Result<(), ProtocolError> {
        let line = HeldLine {
            is_log: matches!(msg, FromService::Log(_)),
            text: encode_line(msg)?,
        };
        let mut inner = self.lock();
        let Inner { sink, state } = &mut *inner;
        match state {
            State::Holding(held) => held.push(line),
            State::Open => write_line(sink, &line.text),
            State::Closed => Err(io::Error::new(
                io::ErrorKind::NotConnected,
                "the service did not become ready",
            )),
        }
        .map_err(ProtocolError::Io)
    }

    /// Write `ready`, then what was held, then a warning when messages were dropped. The lock is kept over all of it, so a thread
    /// that writes at the same time comes after. When a write fails nothing is forgotten: [`Output::abandon`] still has it.
    pub(crate) fn ready(&self) -> Result<(), ProtocolError> {
        let ready = encode_line(&FromService::Ready)?;
        let mut inner = self.lock();
        let Inner { sink, state } = &mut *inner;
        write_line(sink, &ready).map_err(ProtocolError::Io)?;
        if let State::Holding(held) = state {
            for line in &held.lines {
                write_line(sink, &line.text).map_err(ProtocolError::Io)?;
            }
            if let Some(text) = held.refused_text() {
                let warning = FromService::Log(Log::new(LogLevel::Warn, &text));
                write_line(sink, &encode_line(&warning)?).map_err(ProtocolError::Io)?;
            }
        }
        *state = State::Open;
        Ok(())
    }

    /// The service does not become ready: what was held may not go to the core, so the log lines go to `diagnostics` (stderr) and
    /// the rest is counted there. Later writes fail. Does nothing after [`Output::ready`].
    pub(crate) fn abandon(&self, diagnostics: &mut dyn Write) {
        let held = {
            let mut inner = self.lock();
            match std::mem::replace(&mut inner.state, State::Closed) {
                State::Holding(held) => held,
                other => {
                    inner.state = other;
                    return;
                }
            }
        };
        // a failing stderr leaves no other place to say it
        let _ = report_unsent(&held, diagnostics);
    }
}

fn report_unsent(held: &Held, to: &mut dyn Write) -> io::Result<()> {
    for line in held.lines.iter().filter(|line| line.is_log) {
        write!(to, "hobnix-pkg-service: not sent: {}", line.text)?;
    }
    let others = held.lines.iter().filter(|line| !line.is_log).count();
    if others > 0 {
        writeln!(
            to,
            "hobnix-pkg-service: not sent: {others} other messages (emit, snapshot, rollup)"
        )?;
    }
    if let Some(text) = held.refused_text() {
        writeln!(to, "hobnix-pkg-service: {text}")?;
    }
    Ok(())
}

/// Calls [`Output::abandon`] with stderr when it is dropped, so a panicking `start` loses no log line either.
pub(crate) struct AbandonOnDrop<'a>(pub(crate) &'a Output);

impl Drop for AbandonOnDrop<'_> {
    fn drop(&mut self) {
        self.0.abandon(&mut io::stderr());
    }
}

fn encode_line(msg: &FromService) -> Result<String, ProtocolError> {
    let mut line = wire::encode(msg)?;
    line.push('\n');
    Ok(line)
}

fn write_line(sink: &mut Box<dyn Write + Send>, line: &str) -> io::Result<()> {
    sink.write_all(line.as_bytes())?;
    sink.flush()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn log(text: &str) -> FromService {
        FromService::Log(Log::new(LogLevel::Error, text))
    }

    #[test]
    fn abandoned_log_lines_go_to_the_diagnostics_in_order() {
        let output = Output::new(io::sink());
        output.send(&log("first\nline")).unwrap();
        output.send(&FromService::Ready).unwrap();
        output.send(&log("second")).unwrap();
        let mut diagnostics = Vec::new();
        output.abandon(&mut diagnostics);
        assert_eq!(
            String::from_utf8(diagnostics).unwrap(),
            concat!(
                r#"hobnix-pkg-service: not sent: {"level":"error","text":"first\nline","type":"log","v":1}"#,
                "\n",
                r#"hobnix-pkg-service: not sent: {"level":"error","text":"second","type":"log","v":1}"#,
                "\n",
                "hobnix-pkg-service: not sent: 1 other messages (emit, snapshot, rollup)\n",
            )
        );
    }

    #[test]
    fn abandoned_output_says_how_many_were_dropped() {
        let output = Output::new(io::sink());
        for _ in 0..HELD_MAX_MESSAGES {
            output.send(&log("x")).unwrap();
        }
        assert!(output.send(&log("x")).is_err());
        let mut diagnostics = Vec::new();
        output.abandon(&mut diagnostics);
        let text = String::from_utf8(diagnostics).unwrap();
        assert!(text.ends_with(
            "1 messages written before ready were dropped (at most 1000 messages or 4 MiB are held)\n"
        ));
    }

    #[test]
    fn abandon_after_ready_does_nothing() {
        let output = Output::new(io::sink());
        output.ready().unwrap();
        let mut diagnostics = Vec::new();
        output.abandon(&mut diagnostics);
        assert!(diagnostics.is_empty());
        output.send(&log("still open")).unwrap();
    }

    #[test]
    fn a_message_that_cannot_be_written_is_refused_before_ready_too() {
        let output = Output::new(io::sink());
        let huge = FromService::Snapshot(wire::service::Snapshot::new(
            "t",
            "x".repeat(wire::MAX_LINE).into(),
        ));
        assert!(matches!(output.send(&huge), Err(ProtocolError::TooLong)));
    }
}
