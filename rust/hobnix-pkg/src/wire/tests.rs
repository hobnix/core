use serde_json::{Map, Value, json};

use super::command::{self, Outcome, Progress, Request, ResultCode, ResultError};
use super::service::{self, EventRow, Health, Init};
use super::*;
use crate::{Event, EventLevel};

#[derive(Clone, Default)]
struct Buf(Arc<Mutex<Vec<u8>>>);
impl Write for Buf {
    fn write(&mut self, b: &[u8]) -> io::Result<usize> {
        self.0.lock().unwrap().extend_from_slice(b);
        Ok(b.len())
    }
    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

/// `line` read as `M` and written again gives the same bytes.
fn round_trip<M: Message + fmt::Debug>(line: &str) -> M {
    let Decoded::Message(m) = decode::<M>(line).unwrap() else {
        panic!("not a known message: {line}");
    };
    assert_eq!(encode(&m).unwrap(), line);
    m
}

/// The bytes on the wire do not depend on `serde_json`'s `preserve_order` (on in the workspace build through hobnix-core, off in an
/// extension's own build): CI runs this test both ways (`cargo test` and `cargo test -p hobnix-pkg`).
#[test]
fn wire_lines_have_sorted_keys_however_serde_json_is_built() {
    let buf = Buf::default();
    let out = Writer::new(buf.clone());
    let mut payload = Map::new();
    payload.insert("zeta".into(), json!([{"y": 1, "b": 2}]));
    payload.insert("alpha".into(), json!({"d": null, "c": "x"}));
    let ev = Event::new("pkg.demo.done", "s1")
        .text("t")
        .level(EventLevel::Warn)
        .payload(payload);
    out.send(&service::FromService::Emit(ev)).unwrap();
    out.send(&service::FromService::Log(Log::new(LogLevel::Info, "hi")))
        .unwrap();
    let text = String::from_utf8(buf.0.lock().unwrap().clone()).unwrap();
    assert_eq!(
        text,
        concat!(
            r#"{"kind":"pkg.demo.done","level":"warn","payload":{"alpha":{"c":"x","d":null},"zeta":[{"b":2,"y":1}]},"#,
            r#""subject":"s1","text":"t","type":"emit","v":1}"#,
            "\n",
            r#"{"level":"info","text":"hi","type":"log","v":1}"#,
            "\n"
        )
    );
}

/// Every message the SDK writes today, byte for byte, read and written again.
#[test]
fn extension_lines_round_trip_byte_for_byte() {
    for line in [
        r#"{"fraction":0.5,"text":"halfway","type":"progress","v":1}"#,
        r#"{"text":"","type":"progress","v":1}"#,
        r#"{"level":"warn","text":"hi","type":"log","v":1}"#,
        r#"{"kind":"pkg.hello.greeted","subject":"Ada","type":"event","v":1}"#,
        r#"{"data":{"n":1},"ok":true,"text":"done","type":"result","v":1}"#,
        r#"{"data":null,"ok":true,"type":"result","v":1}"#,
        r#"{"ok":true,"type":"result","v":1}"#,
        r#"{"error":{"code":"not_found","message":"no such thing"},"ok":false,"type":"result","v":1}"#,
        r#"{"error":{"code":"unsupported_version","message":"this extension speaks protocol version 1 only","supported":[1]},"ok":false,"type":"result","v":1}"#,
    ] {
        round_trip::<command::FromExtension>(line);
    }
    for line in [
        r#"{"type":"ready","v":1}"#,
        r#"{"ok":true,"type":"health","v":1}"#,
        r#"{"ok":false,"text":"cannot publish","type":"health","v":1}"#,
        r#"{"id":7,"type":"ack","v":1}"#,
        r#"{"level":"error","text":"event 3 not handled: x","type":"log","v":1}"#,
        r#"{"kind":"pkg.demo.seen","subject":"s","type":"emit","v":1}"#,
        r#"{"data":{"events_seen":0,"ticks":1},"topic":"ticks","type":"snapshot","v":1}"#,
        r#"{"kind":"pkg.media-hub.session-completed","n":1.0,"sum":42.0,"type":"rollup","user":"ada","v":1}"#,
    ] {
        round_trip::<service::FromService>(line);
    }
}

/// The lines the core writes (`scripts/lib/ext_proto.py` and `ext_service.py`, keys in their order there) read and written again: the same
/// JSON, with the keys sorted.
#[test]
fn core_lines_round_trip_with_sorted_keys() {
    let sorted = |line: &str| {
        let v: Value = serde_json::from_str(line).unwrap();
        serde_json::to_string(&Sorted(&v)).unwrap()
    };
    let request = r#"{"v":1,"type":"request","id":"0123456789abcdef","command":["greet"],"argv":["Ada"],"lang":"de","caller":"web","timeout_ms":30000}"#;
    let init = concat!(
        r#"{"v":1,"type":"init","name":"media-hub","lang":"en","subscribe":["job.*"],"health_interval":30.0,"#,
        r#""integrations":[{"package":"jellyfin","integration":"media","source":"recipe","api_url":"http://127.0.0.1:8096","extras":{"a":"1"},"key_header":"X-Emby-Token"},"#,
        r#"{"package":"plex","integration":"media","source":"recipe","api_url":null,"extras":{},"key_header":null}]}"#
    );
    let event = r#"{"v":1,"type":"event","id":5,"time":1700000000,"source":"core","kind":"job.done","subject":"j1","level":"info","text":null,"payload":null}"#;
    let event2 = r#"{"v":1,"type":"event","id":6,"time":1,"source":"demo","kind":"pkg.x.y","subject":"s","level":"warn","text":"t","payload":{"b":1,"a":[2]}}"#;
    let shutdown = r#"{"v":1,"type":"shutdown","grace_ms":5000}"#;
    let init_plain =
        r#"{"v":1,"type":"init","name":"ticker","lang":"de","subscribe":[],"health_interval":1.0}"#;
    round_trip::<command::FromCore>(&sorted(request));
    for line in [init, event, event2, shutdown, init_plain] {
        round_trip::<service::FromCore>(&sorted(line));
    }
}

#[test]
fn unknown_types_and_values_are_kept_or_ignored() {
    let d = decode::<service::FromCore>(r#"{"v":1,"type":"pause","x":1}"#).unwrap();
    assert_eq!(d, Decoded::Unknown("pause".into()));
    let line = r#"{"v":1,"type":"request","id":"x","command":["a"],"argv":[],"lang":"fr","caller":"job","timeout_ms":1000}"#;
    let Decoded::Message(command::FromCore::Request(r)) = decode(line).unwrap() else {
        panic!("not a request");
    };
    assert_eq!((r.lang, r.caller), (Lang::Other, command::Caller::Other));
    assert!(matches!(
        encode(&command::FromCore::Request(r)),
        Err(ProtocolError::Encode(_))
    ));
    let code = r#"{"error":{"code":"quota","message":"m"},"ok":false,"type":"result","v":1}"#;
    let m = round_trip::<command::FromExtension>(code);
    let command::FromExtension::Result(Outcome::Err(e)) = m else {
        panic!("not an error result");
    };
    assert_eq!(e.code, ResultCode::Other("quota".into()));
}

#[test]
fn bad_lines_are_typed_errors() {
    type E = ProtocolError;
    let read = decode::<command::FromCore>;
    assert!(matches!(read("not json"), Err(E::NotJson(_))));
    assert!(matches!(
        read(r#"{"v":2}"#),
        Err(E::UnsupportedVersion(Some(2)))
    ));
    assert!(matches!(
        read(r#"{"type":"request"}"#),
        Err(E::UnsupportedVersion(None))
    ));
    assert!(matches!(read(r#"{"v":1}"#), Err(E::MissingType)));
    let Err(E::Invalid {
        message_type,
        source,
    }) = read(r#"{"v":1,"type":"request","id":"x"}"#)
    else {
        panic!("not invalid");
    };
    assert_eq!(message_type, "request");
    assert_eq!(source.to_string(), "missing field `command`");
    let both = r#"{"error":{"code":"failed","message":"m"},"ok":true,"type":"result","v":1}"#;
    assert!(matches!(
        decode::<command::FromExtension>(both),
        Err(E::Invalid { .. })
    ));
    let huge = command::FromExtension::Result(Outcome::Ok {
        data: None,
        text: Some("x".repeat(MAX_LINE)),
    });
    assert!(matches!(encode(&huge), Err(E::TooLong)));
}

#[test]
fn constructors_apply_the_schema_limits() {
    let p = Progress::new(Some(7.0), &"p".repeat(500));
    assert_eq!((p.fraction, p.text.chars().count()), (Some(1.0), 200));
    assert_eq!(Progress::new(Some(f64::NAN), "x").fraction, None);
    assert_eq!(
        Log::new(LogLevel::Info, &"é".repeat(2000))
            .text
            .chars()
            .count(),
        1000
    );
    let e = ResultError::new(ResultCode::Failed, "no\nsuch\r\n thing").supported(vec![1]);
    assert_eq!(
        (e.message.as_str(), e.supported),
        ("no such thing", Some(vec![1]))
    );
    let r = Request::new("0123456789abcdef", vec!["status".into()], vec![]);
    assert_eq!(r.words(), ["status"]);
    let i = Init::new("t", Lang::De, 1.0);
    assert!(i.integrations.is_empty() && i.subscribe.is_empty());
    assert_eq!(EventRow::new(3, "job.done", "j").level, "info");
    assert!(Health::degraded("x").text.is_some());
}

#[test]
fn read_line_limits_the_length() {
    let mut ok = io::Cursor::new(b"ab\r\ncd".to_vec());
    assert_eq!(read_line(&mut ok).unwrap().as_deref(), Some("ab"));
    assert_eq!(read_line(&mut ok).unwrap().as_deref(), Some("cd"));
    assert_eq!(read_line(&mut ok).unwrap(), None);
    let mut long = io::Cursor::new(vec![b'x'; MAX_LINE + 1]);
    assert!(matches!(read_line(&mut long), Err(ProtocolError::TooLong)));
    let mut exact = io::Cursor::new([vec![b'x'; MAX_LINE], b"\n".to_vec()].concat());
    assert_eq!(
        read_line(&mut exact).unwrap().map(|l| l.len()),
        Some(MAX_LINE)
    );
}

#[test]
fn event_kinds_users_and_topics() {
    assert!(is_event_kind("pkg.demo.said") && is_event_kind("pkg.media-hub.session-completed"));
    assert!(
        !is_event_kind("core.disk")
            && !is_event_kind("pkg.demo.Said")
            && !is_event_kind("pkg.a.b.c")
    );
    assert!(service::is_rollup_user("ada@x.y") && !service::is_rollup_user("-rf"));
    assert!(!service::is_rollup_user(&"a".repeat(65)) && !service::is_rollup_user(""));
    assert!(service::is_snapshot_topic("now-playing") && !service::is_snapshot_topic("Now"));
}
