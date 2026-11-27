//! Opening /var/lib/hs/state.db for writing (hobnix/core#1336). Python owns the schema while both write: this code never creates a file or a
//! table, never migrates, and changes no setting that stays in the file (`journal_mode`, `user_version`, `meta.oldest_writer`).

use crate::{Error, Result};
use rusqlite::types::ValueRef;
use rusqlite::{Connection, OpenFlags, OptionalExtension};
use std::path::Path;
use std::time::Duration;

/// The schema this writer knows: `SCHEMA_VERSION` of scripts/state-db.py.
pub const SCHEMA_VERSION: i64 = 2;

/// As long as state-db.py waits for another writer.
const BUSY_TIMEOUT: Duration = Duration::from_secs(30);

/// The longest number scripts/state-db.py reads from `meta.oldest_writer`.
const OLDEST_WRITER_DIGITS: usize = 9;

/// An open state.db that this program may write.
#[derive(Debug)]
pub struct StateDb {
    pub(crate) connection: Connection,
}

fn database(error: &rusqlite::Error) -> Error {
    Error::Failed(format!("state.db: {error}"))
}

pub(crate) fn database_error<T>(result: rusqlite::Result<T>) -> Result<T> {
    result.map_err(|e| database(&e))
}

/// The WAL-reset bug (sqlite.org/wal.html) is in 3.7.0 to 3.51.2; it is fixed in 3.51.3, in 3.50.7 and in 3.44.6. It needs two writers on
/// one file, which is what this writer beside the Python ones is. `number` is `SQLite`'s `X*1000000 + Y*1000 + Z`.
fn has_wal_reset_fix(number: i32) -> bool {
    number >= 3_051_003
        || (3_050_007..=3_050_999).contains(&number)
        || (3_044_006..=3_044_999).contains(&number)
}

fn check_sqlite(number: i32, version: &str) -> Result<()> {
    if has_wal_reset_fix(number) {
        return Ok(());
    }
    Err(Error::Refused(format!(
        "SQLite {version} has the WAL-reset bug (fixed in 3.51.3): this writer does not use it"
    )))
}

/// The oldest schema version that may still write the database, `None` when it does not say (`oldest_writer` of state-db.py).
fn oldest_writer(connection: &Connection) -> rusqlite::Result<Option<i64>> {
    let has_meta = connection
        .query_row(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'meta'",
            [],
            |_| Ok(()),
        )
        .optional()?;
    if has_meta.is_none() {
        return Ok(None);
    }
    let number = connection
        .query_row(
            "SELECT value FROM meta WHERE key = 'oldest_writer'",
            [],
            |row| {
                Ok(match row.get_ref(0)? {
                    ValueRef::Text(text) => {
                        std::str::from_utf8(text).ok().and_then(readable_number)
                    }
                    ValueRef::Integer(n) => readable_number(&n.to_string()),
                    ValueRef::Null | ValueRef::Real(_) | ValueRef::Blob(_) => None,
                })
            },
        )
        .optional()?;
    Ok(number.flatten())
}

/// `[0-9]{1,9}`, as state-db.py reads it.
fn readable_number(text: &str) -> Option<i64> {
    let is_readable = (1..=OLDEST_WRITER_DIGITS).contains(&text.len())
        && text.bytes().all(|b| b.is_ascii_digit());
    if is_readable { text.parse().ok() } else { None }
}

/// `check_may_write` of state-db.py, plus: an older database is refused, because only Python migrates. Reads only. A newer database that
/// its number allows is written as it is.
fn check_may_write(connection: &Connection) -> Result<()> {
    let oldest = database_error(oldest_writer(connection))?;
    if let Some(oldest) = oldest.filter(|oldest| SCHEMA_VERSION < *oldest) {
        return Err(Error::Refused(format!(
            "state.db may be written from schema version {oldest} on, this release knows up to {SCHEMA_VERSION}: it was written by a newer \
             release"
        )));
    }
    let have: i64 = database_error(connection.query_row("PRAGMA user_version", [], |r| r.get(0)))?;
    if oldest.is_none() && have > SCHEMA_VERSION {
        return Err(Error::Refused(format!(
            "state.db has schema version {have}, this release knows up to {SCHEMA_VERSION}: it was written by a newer release"
        )));
    }
    if have < SCHEMA_VERSION {
        return Err(Error::Refused(format!(
            "state.db has schema version {have}, older than {SCHEMA_VERSION}: hs state migrates it, this writer does not"
        )));
    }
    Ok(())
}

fn require_wal(connection: &Connection) -> Result<()> {
    let mode: String =
        database_error(connection.query_row("PRAGMA journal_mode", [], |r| r.get(0)))?;
    if mode == "wal" {
        Ok(())
    } else {
        Err(Error::Refused(format!(
            "state.db is not in WAL mode (journal mode {mode})"
        )))
    }
}

impl StateDb {
    /// Open an existing state.db. `Missing` when there is no file; `Refused` for a `SQLite` with the WAL-reset bug, for a schema this program
    /// must not write and for a file that is not in WAL mode.
    pub fn open_rw(path: &Path) -> Result<Self> {
        check_sqlite(rusqlite::version_number(), rusqlite::version())?;
        if !path.is_file() {
            return Err(Error::Missing(format!(
                "no state database at {}",
                path.display()
            )));
        }
        // no SQLITE_OPEN_CREATE (a file that vanished is not made again) and no SQLITE_OPEN_URI (the path is a path)
        let flags = OpenFlags::SQLITE_OPEN_READ_WRITE | OpenFlags::SQLITE_OPEN_NO_MUTEX;
        let connection = database_error(Connection::open_with_flags(path, flags))?;
        database_error(connection.busy_timeout(BUSY_TIMEOUT))?;
        check_may_write(&connection)?;
        require_wal(&connection)?;
        database_error(connection.pragma_update(None, "synchronous", "NORMAL"))?; // of this connection only
        Ok(Self { connection })
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use std::path::PathBuf;

    /// A copy of the tables of `SCHEMA` in scripts/state-db.py that the writer touches. The shell test tests/event-writer-rust.sh, which
    /// runs against a database that state-db.py made, is authoritative.
    const DDL: &str = "
        CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);
        CREATE TABLE events (
          id INTEGER PRIMARY KEY AUTOINCREMENT, time INTEGER NOT NULL, kind TEXT NOT NULL, subject TEXT, text TEXT,
          source TEXT NOT NULL DEFAULT 'storage', level TEXT NOT NULL DEFAULT 'info', payload TEXT, v INTEGER NOT NULL DEFAULT 1);
    ";

    /// An empty directory that goes away with the value.
    pub(crate) struct TempDir(pub(crate) PathBuf);

    impl TempDir {
        pub(crate) fn new(name: &str) -> Self {
            let path = std::env::temp_dir().join(format!("hobnix-{name}-{}", std::process::id()));
            let _ = std::fs::remove_dir_all(&path);
            std::fs::create_dir_all(&path).expect("temp dir");
            Self(path)
        }
    }

    impl Drop for TempDir {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

    /// A database as state-db.py makes it, then changed by `extra`.
    pub(crate) fn make(path: &Path, journal: &str, extra: &str) {
        let c = Connection::open(path).expect("open");
        c.query_row(&format!("PRAGMA journal_mode={journal}"), [], |_| Ok(()))
            .expect("journal mode");
        c.execute_batch(DDL).expect("ddl");
        c.execute_batch(&format!(
            "PRAGMA user_version=2; INSERT INTO meta VALUES ('oldest_writer', '2'); {extra}"
        ))
        .expect("setup");
    }

    fn open_after(name: &str, extra: &str) -> Result<()> {
        let dir = TempDir::new(name);
        let path = dir.0.join("state.db");
        make(&path, "WAL", extra);
        StateDb::open_rw(&path).map(drop)
    }

    fn refusal(name: &str, extra: &str) -> String {
        match open_after(name, extra) {
            Err(Error::Refused(reason)) => reason,
            other => panic!("expected a refusal, got {other:?}"),
        }
    }

    #[test]
    fn refuses_a_sqlite_with_the_wal_reset_bug() {
        for bad in [
            3_007_000, 3_044_005, 3_045_000, 3_046_001, 3_050_006, 3_051_000, 3_051_002,
        ] {
            assert!(
                matches!(check_sqlite(bad, "x"), Err(Error::Refused(m)) if m.contains("WAL-reset")),
                "{bad}"
            );
        }
        for fixed in [
            3_044_006, 3_044_999, 3_050_007, 3_050_999, 3_051_003, 3_053_003, 4_000_000,
        ] {
            assert_eq!(check_sqlite(fixed, "x"), Ok(()), "{fixed}");
        }
    }

    #[test]
    fn the_linked_sqlite_has_the_wal_reset_fix() {
        assert!(
            has_wal_reset_fix(rusqlite::version_number()),
            "linked SQLite {}: build with the nixpkgs pin (nix-shell scripts/dev/rust-shell.nix)",
            rusqlite::version()
        );
    }

    #[test]
    fn opens_the_database_python_made() {
        assert_eq!(open_after("db-ok", ""), Ok(()));
    }

    #[test]
    fn a_missing_file_is_missing_and_is_not_made() {
        let dir = TempDir::new("db-missing");
        let path = dir.0.join("state.db");
        assert!(matches!(StateDb::open_rw(&path), Err(Error::Missing(_))));
        assert!(!path.exists());
    }

    #[test]
    fn refuses_a_database_that_is_not_in_wal_mode_and_leaves_it() {
        let dir = TempDir::new("db-journal");
        let path = dir.0.join("state.db");
        make(&path, "DELETE", "");
        assert!(
            matches!(StateDb::open_rw(&path), Err(Error::Refused(m)) if m.contains("WAL mode"))
        );
        let mode: String = Connection::open(&path)
            .and_then(|c| c.query_row("PRAGMA journal_mode", [], |r| r.get(0)))
            .expect("mode");
        assert_eq!(mode, "delete");
    }

    #[test]
    fn refuses_a_database_python_has_to_migrate() {
        for have in [0, 1] {
            let reason = refusal("db-old", &format!("PRAGMA user_version={have}"));
            assert!(reason.contains("older than 2"), "{reason}");
        }
    }

    #[test]
    fn refuses_when_the_oldest_writer_is_above_this_one() {
        for have in [2, 3] {
            let extra = format!("UPDATE meta SET value = '3'; PRAGMA user_version={have}");
            let reason = refusal("db-oldest", &extra);
            assert!(reason.contains("newer release"), "{reason}");
        }
    }

    #[test]
    fn writes_a_newer_database_that_its_number_allows_and_changes_neither() {
        let dir = TempDir::new("db-newer");
        let path = dir.0.join("state.db");
        make(
            &path,
            "WAL",
            "UPDATE meta SET value = '1'; PRAGMA user_version=99",
        );
        let db = StateDb::open_rw(&path).expect("allowed");
        let state: (i64, String) = db
            .connection
            .query_row(
                "SELECT (SELECT * FROM pragma_user_version), value FROM meta",
                [],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )
            .expect("state");
        assert_eq!(state, (99, "1".to_string()));
    }

    #[test]
    fn without_a_readable_number_a_newer_database_is_refused() {
        let unreadable = [
            "DELETE FROM meta",
            "DROP TABLE meta",
            "UPDATE meta SET value = ''",
            "UPDATE meta SET value = '2x'",
            "UPDATE meta SET value = ' 2'",
            "UPDATE meta SET value = '-1'",
            "UPDATE meta SET value = '0000000002'",
            "UPDATE meta SET value = NULL",
            "UPDATE meta SET value = x'32'",
        ];
        for change in unreadable {
            let reason = refusal("db-number", &format!("{change}; PRAGMA user_version=3"));
            assert!(reason.contains("schema version 3"), "{change}: {reason}");
            assert_eq!(open_after("db-number-2", change), Ok(()), "{change}");
        }
    }
}
