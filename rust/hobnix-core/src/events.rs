//! Writing one row of the event log (docs/events.md, ADR 0005) with the rows and effects of `state-db.py emit` (hobnix/core#1336): the
//! insert and the retention in one transaction, then the datagram to the web server. scripts/state-db.py is the writer in use.

mod kinds;
mod payload;

pub use kinds::KindFiles;

use crate::Result;
use crate::db::{StateDb, database_error};
use kinds::ShortLived;
use rusqlite::{Connection, TransactionBehavior, params};
use std::fmt;
use std::path::Path;

/// The longest subject and text, in characters.
const LINE_MAX: usize = 500;
const SECONDS_PER_DAY: i64 = 86_400;

/// The name of a kind, `<source>.<kind>`: what stands before the first dot, and the rest.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EventName {
    source: String,
    kind: String,
}

impl EventName {
    /// `[a-z0-9]+(\.[a-z0-9][a-z0-9-]*)+`, else `None`.
    #[must_use]
    pub fn parse(text: &str) -> Option<Self> {
        let is_plain = |b: u8| b.is_ascii_lowercase() || b.is_ascii_digit();
        let (source, kind) = text.split_once('.')?;
        let is_source = !source.is_empty() && source.bytes().all(is_plain);
        let is_kind = kind.split('.').all(|part| {
            part.bytes().next().is_some_and(is_plain)
                && part.bytes().all(|b| is_plain(b) || b == b'-')
        });
        (is_source && is_kind).then(|| Self {
            source: source.to_string(),
            kind: kind.to_string(),
        })
    }
}

impl fmt::Display for EventName {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}.{}", self.source, self.kind)
    }
}

/// How serious an event is.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Level {
    Info,
    Warn,
    Error,
}

impl Level {
    #[must_use]
    pub fn parse(text: &str) -> Option<Self> {
        match text {
            "info" => Some(Self::Info),
            "warn" => Some(Self::Warn),
            "error" => Some(Self::Error),
            _ => None,
        }
    }

    fn as_str(self) -> &'static str {
        match self {
            Self::Info => "info",
            Self::Warn => "warn",
            Self::Error => "error",
        }
    }
}

/// One event as the caller gives it. Subject, text and payload are brought into their stored form by [`emit`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EmitRequest {
    pub name: EventName,
    pub subject: String,
    pub text: String,
    /// `None`: the level the kind has in its list.
    pub level: Option<Level>,
    /// Kept only when it is a JSON object, else stored as NULL.
    pub payload: Option<String>,
}

/// What the log keeps: the newest `keep` rows (a negative number: no limit), nothing older than `days`, and the package kinds with
/// their own retention not older than their days.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Retention {
    pub keep: i64,
    pub days: i64,
    pub ephemeral_days: i64,
    pub metric_days: i64,
}

impl Default for Retention {
    fn default() -> Self {
        Self {
            keep: 5000,
            days: 90,
            ephemeral_days: 7,
            metric_days: 35,
        }
    }
}

/// White space as python's `str.strip` sees it: it counts the separators U+001C to U+001F, Rust does not.
fn is_space(c: char) -> bool {
    c.is_whitespace() || ('\u{1c}'..='\u{1f}').contains(&c)
}

/// `one_line` of state-db.py: every run of tabs and line breaks is one space, the ends are stripped, then the first 500 characters.
fn one_line(text: &str) -> String {
    // a break at an end leaves no space behind: the strip would remove it
    let words: Vec<&str> = text
        .split(['\t', '\r', '\n'])
        .filter(|word| !word.is_empty())
        .collect();
    let joined = words.join(" ");
    joined
        .trim_matches(is_space)
        .chars()
        .take(LINE_MAX)
        .collect()
}

/// The oldest time a row may have after `days`.
fn cutoff(now: i64, days: i64) -> i64 {
    now.saturating_sub(days.saturating_mul(SECONDS_PER_DAY))
}

/// `trim_events` of state-db.py: by count, by age, then the package kinds with their own retention.
fn trim(
    connection: &Connection,
    now: i64,
    retention: Retention,
    short_lived: &ShortLived,
) -> rusqlite::Result<()> {
    connection.execute(
        "DELETE FROM events WHERE id NOT IN (SELECT id FROM events ORDER BY id DESC LIMIT ?1)",
        [retention.keep],
    )?;
    connection.execute(
        "DELETE FROM events WHERE time < ?1",
        [cutoff(now, retention.days)],
    )?;
    let classes = [
        (&short_lived.ephemeral, retention.ephemeral_days),
        (&short_lived.metric, retention.metric_days),
    ];
    for (kinds, days) in classes {
        // the log stores source and kind apart: "pkg.x.y" is source "pkg", kind "x.y"
        for kind in kinds.iter().filter_map(|k| k.strip_prefix("pkg.")) {
            connection.execute(
                "DELETE FROM events WHERE source='pkg' AND kind=?1 AND time < ?2",
                params![kind, cutoff(now, days)],
            )?;
        }
    }
    Ok(())
}

/// Write the event with the time `now` and trim the log, in one transaction. The files are read before it begins. A busy database is
/// waited for (30 s); there is no second try. The caller pokes the web server ([`poke`]) after a success.
pub fn emit(
    db: &mut StateDb,
    now: i64,
    request: &EmitRequest,
    retention: Retention,
    files: &KindFiles,
) -> Result<()> {
    let level = request.level.unwrap_or_else(|| files.level(&request.name));
    let short_lived = files.short_lived();
    let payload = request.payload.as_deref().and_then(payload::normalise);
    let subject = one_line(&request.subject);
    let text = one_line(&request.text);
    // dropped without a commit (an error), the transaction rolls back
    let transaction = database_error(
        db.connection
            .transaction_with_behavior(TransactionBehavior::Immediate),
    )?;
    database_error(transaction.execute(
        "INSERT INTO events (time, kind, subject, text, source, level, payload) VALUES (?1,?2,?3,?4,?5,?6,?7)",
        params![
            now,
            request.name.kind,
            subject,
            text,
            request.name.source,
            level.as_str(),
            payload
        ],
    ))?;
    database_error(trim(&transaction, now, retention, &short_lived))?;
    database_error(transaction.commit())
}

/// ADR 0026 decision 9: one datagram `1` to the web server, "look at the counters now". It never blocks and never fails the write: every
/// error is ignored (no socket, nobody listening, a full queue). Gives whether the datagram was handed over.
pub fn poke(socket_path: &Path) -> bool {
    use std::os::unix::net::UnixDatagram;
    let send = || -> std::io::Result<usize> {
        let socket = UnixDatagram::unbound()?;
        socket.set_nonblocking(true)?;
        socket.send_to(b"1", socket_path)
    };
    send().is_ok()
}

#[cfg(test)]
mod tests;
