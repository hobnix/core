use super::*;
use crate::db::tests::{TempDir, make};
use std::os::unix::net::UnixDatagram;

const NOW: i64 = 1_000_000_000;

#[test]
fn a_kind_is_source_and_kind_in_lower_case() {
    for good in ["a.b", "9.9", "pkg.my-app.x", "storage.a.b-c"] {
        assert_eq!(
            EventName::parse(good).map(|n| n.to_string()).as_deref(),
            Some(good)
        );
    }
    let bad = [
        "storage",
        "Storage.new",
        "storage.New",
        "my-source.new",
        "storage.-new",
        "storage.",
        ".new",
        "storage.new ",
        "storage.new\n",
        "storage new",
        "storage_x.new",
        "storage..new",
        "",
    ];
    for name in bad {
        assert_eq!(EventName::parse(name), None, "{name:?}");
    }
}

#[test]
fn a_line_has_no_breaks_is_stripped_and_then_cut_to_500_characters() {
    assert_eq!(one_line("  a\tb\r\n\nc  "), "a b c");
    assert_eq!(one_line("\nline one\r\nline two\t"), "line one line two");
    assert_eq!(one_line("a \t b"), "a   b");
    assert_eq!(one_line("\u{1f}\u{a0}x\u{b}\u{1c}"), "x");
    assert_eq!(one_line("\u{200b}x"), "\u{200b}x");
    assert_eq!(one_line(&"ä😀".repeat(300)).chars().count(), 500);
    assert_eq!(
        one_line(&format!("{} yz", "x".repeat(499))),
        format!("{} ", "x".repeat(499))
    );
}

/// A database and the (empty) directories of the kind files.
struct Log {
    dir: TempDir,
    files: KindFiles,
}

impl Log {
    fn new(name: &str) -> Self {
        let dir = TempDir::new(name);
        make(&dir.0.join("state.db"), "WAL", "");
        let files = KindFiles {
            scripts: dir.0.join("scripts"),
            installed: dir.0.join("installed"),
        };
        Self { dir, files }
    }

    fn open(&self) -> StateDb {
        StateDb::open_rw(&self.dir.0.join("state.db")).expect("open")
    }

    fn emit(&self, now: i64, kind: &str, subject: &str, keep: i64) {
        let request = EmitRequest {
            name: EventName::parse(kind).expect("kind"),
            subject: subject.to_string(),
            text: String::new(),
            level: None,
            payload: None,
        };
        let retention = Retention {
            keep,
            ..Retention::default()
        };
        emit(&mut self.open(), now, &request, retention, &self.files).expect("emit");
    }

    fn subjects(&self) -> Vec<String> {
        let db = self.open();
        let mut statement = db
            .connection
            .prepare("SELECT subject FROM events ORDER BY id")
            .expect("prepare");
        let rows = statement.query_map([], |r| r.get(0)).expect("query");
        rows.collect::<rusqlite::Result<_>>().expect("rows")
    }
}

#[test]
fn the_row_has_every_column() {
    let log = Log::new("events-row");
    let request = EmitRequest {
        name: EventName::parse("pkg.rapp.some.thing").expect("kind"),
        subject: "a\tb".to_string(),
        text: " t ".to_string(),
        level: Some(Level::Warn),
        payload: Some("{ \"a\": 1 }".to_string()),
    };
    emit(
        &mut log.open(),
        NOW,
        &request,
        Retention::default(),
        &log.files,
    )
    .expect("emit");
    let row: String = log
        .open()
        .connection
        .query_row(
            "SELECT concat_ws('|', id, time, source, kind, subject, level, text, payload, v) FROM events",
            [],
            |r| r.get(0),
        )
        .expect("row");
    assert_eq!(
        row,
        "1|1000000000|pkg|rapp.some.thing|a b|warn|t|{\"a\":1}|1"
    );
}

#[test]
fn the_newest_rows_stay_and_a_negative_count_is_no_limit() {
    let log = Log::new("events-count");
    for subject in ["1", "2", "3", "4"] {
        log.emit(NOW, "storage.new", subject, 3);
    }
    assert_eq!(log.subjects(), ["2", "3", "4"]);
    log.emit(NOW, "storage.new", "5", -1);
    assert_eq!(log.subjects(), ["2", "3", "4", "5"]);
}

#[test]
fn old_rows_go_and_package_kinds_go_by_their_class() {
    let log = Log::new("events-age");
    std::fs::create_dir_all(&log.files.installed).expect("dir");
    let row = |kind: &str, class: &str| {
        format!("pkg.rapp.{kind}\tinfo\t-\tL\t-\tm\t-\t-\t-\t-\t{class}\n")
    };
    let declared = [
        row("loud", "audit"),
        row("flash", "ephemeral"),
        row("tick", "metric"),
    ]
    .concat();
    std::fs::write(log.files.installed.join("rapp.tsv"), declared).expect("declare");
    let days_ago = |days: i64| NOW - days * SECONDS_PER_DAY;
    for (age, kind, subject) in [
        (91, "storage.new", "too-old"),
        (90, "storage.new", "just-inside"),
        (36, "pkg.rapp.tick", "metric-old"),
        (36, "pkg.rapp.loud", "audit-old"),
        (8, "pkg.rapp.flash", "flash-old"),
        (8, "pkg.rapp.tick", "metric-young"),
        (6, "pkg.rapp.flash", "flash-young"),
        (0, "storage.new", "now"),
    ] {
        log.emit(days_ago(age), kind, subject, 5000);
    }
    log.emit(NOW, "storage.new", "last", 5000);
    assert_eq!(
        log.subjects(),
        [
            "just-inside",
            "audit-old",
            "metric-young",
            "flash-young",
            "now",
            "last"
        ]
    );
}

#[test]
fn absurd_retention_numbers_do_not_overflow() {
    assert_eq!(cutoff(NOW, i64::MAX), i64::MIN + NOW + 1);
    assert_eq!(cutoff(NOW, i64::MIN), i64::MAX);
}

#[test]
fn a_failed_trim_writes_no_row() {
    let log = Log::new("events-rollback");
    log.emit(NOW, "storage.new", "first", 5000);
    log.open()
        .connection
        .execute_batch(
            "CREATE TRIGGER no_delete BEFORE DELETE ON events BEGIN SELECT RAISE(ABORT, 'no'); END",
        )
        .expect("trigger");
    let request = EmitRequest {
        name: EventName::parse("storage.new").expect("kind"),
        subject: "second".to_string(),
        text: String::new(),
        level: None,
        payload: None,
    };
    let keep_one = Retention {
        keep: 1,
        ..Retention::default()
    };
    assert!(emit(&mut log.open(), NOW, &request, keep_one, &log.files).is_err());
    assert_eq!(log.subjects(), ["first"]);
}

#[test]
fn a_poke_is_one_datagram_and_nobody_listening_is_no_error() {
    let dir = TempDir::new("events-poke");
    let path = dir.0.join("live.sock");
    assert!(!poke(&path));
    let server = UnixDatagram::bind(&path).expect("bind");
    assert!(poke(&path));
    let mut got = [0; 16];
    let length = server.recv(&mut got).expect("datagram");
    assert_eq!(got.get(..length), Some(b"1".as_slice()));
}
