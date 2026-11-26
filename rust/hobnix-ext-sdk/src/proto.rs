//! Framing shared by both protocols: one JSON object per line, `v: 1`, at most 1 MiB per line.

use std::io::{self, BufRead, Read, Write};
use std::sync::{Arc, Mutex};

use serde::Serialize;
use serde_json::{Map, Value, json};

use crate::Event;

pub const VERSION: u32 = 1;
/// Longest line either side may write (ADR 0010 rule 5, ADR 0011 rule 4).
pub const MAX_LINE: usize = 1 << 20;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum LogLevel {
    Debug,
    Info,
    Warn,
    Error,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum EventLevel {
    Info,
    Warn,
    Error,
}

/// The writing half: a clonable handle so a service can write from several threads. Every message is one line, flushed at once.
#[derive(Clone)]
pub(crate) struct Out(Arc<Mutex<Box<dyn Write + Send>>>);

impl Out {
    pub(crate) fn new(w: impl Write + Send + 'static) -> Self {
        Out(Arc::new(Mutex::new(Box::new(w))))
    }

    pub(crate) fn send(&self, mut msg: Map<String, Value>) -> io::Result<()> {
        msg.insert("v".into(), json!(VERSION));
        let mut line =
            serde_json::to_string(&Sorted(&Value::Object(msg))).map_err(io::Error::other)?;
        if line.len() + 1 > MAX_LINE {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "message longer than 1 MiB",
            ));
        }
        line.push('\n');
        let mut w = self.0.lock().unwrap_or_else(|p| p.into_inner());
        w.write_all(line.as_bytes())?;
        w.flush()
    }

    pub(crate) fn typed(&self, ty: &str, fields: Value) -> io::Result<()> {
        let mut m = match fields {
            Value::Object(m) => m,
            _ => Map::new(),
        };
        m.insert("type".into(), json!(ty));
        self.send(m)
    }

    pub(crate) fn log(&self, level: LogLevel, text: &str) -> io::Result<()> {
        self.typed("log", json!({"level": level, "text": cut(text, 1000)}))
    }

    /// `ty` is `event` (command) or `emit` (service).
    pub(crate) fn event(&self, ty: &str, ev: &Event) -> io::Result<()> {
        if !valid_kind(&ev.kind) {
            let why = "event kind must look like pkg.<package>.<kind>";
            return Err(io::Error::new(io::ErrorKind::InvalidInput, why));
        }
        let mut f = json!({"kind": ev.kind, "subject": ev.subject});
        if let Some(t) = &ev.text {
            f["text"] = json!(t);
        }
        if let Some(l) = ev.level {
            f["level"] = json!(l);
        }
        if let Some(p) = &ev.payload {
            f["payload"] = Value::Object(p.clone());
        }
        self.typed(ty, f)
    }
}

/// A JSON value written with the keys of every object in sorted order. The order of a `serde_json::Map` depends on how serde_json was
/// built: cargo turns its `preserve_order` feature on for every crate of a build when one crate asks (hobnix-core does, in this workspace),
/// so without this the wire lines of an extension would depend on what else is in its build. Sorted is what the SDK writes in an
/// extension's own build anyway.
struct Sorted<'a>(&'a Value);

impl Serialize for Sorted<'_> {
    fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        use serde::ser::SerializeMap;
        match self.0 {
            Value::Object(m) => {
                let mut entries: Vec<(&String, &Value)> = m.iter().collect();
                entries.sort_unstable_by(|a, b| a.0.cmp(b.0));
                let mut map = s.serialize_map(Some(entries.len()))?;
                for (k, v) in entries {
                    map.serialize_entry(k, &Sorted(v))?;
                }
                map.end()
            }
            Value::Array(a) => s.collect_seq(a.iter().map(Sorted)),
            v => v.serialize(s),
        }
    }
}

/// Cut to at most `max` characters (the schema's maxLength counts characters).
pub(crate) fn cut(s: &str, max: usize) -> String {
    s.chars().take(max).collect()
}

/// One line of English text: line breaks become spaces.
pub(crate) fn one_line(s: &str) -> String {
    s.split(['\n', '\r'])
        .map(str::trim)
        .filter(|p| !p.is_empty())
        .collect::<Vec<_>>()
        .join(" ")
}

/// `^pkg\.[a-z][a-z0-9-]*\.[a-z][a-z0-9-]*$`
pub(crate) fn valid_kind(kind: &str) -> bool {
    let mut parts = kind.split('.');
    let ok = |p: &str| {
        let mut c = p.chars();
        matches!(c.next(), Some('a'..='z')) && c.all(|c| matches!(c, 'a'..='z' | '0'..='9' | '-'))
    };
    matches!((parts.next(), parts.next(), parts.next(), parts.next()),
        (Some("pkg"), Some(a), Some(b), None) if ok(a) && ok(b))
}

/// What reading one line gave.
pub(crate) enum Line {
    Eof,
    TooLong,
    Text(String),
}

/// Read one line of at most [`MAX_LINE`] bytes (without the newline).
pub(crate) fn read_line(r: &mut impl BufRead) -> io::Result<Line> {
    let mut buf = Vec::new();
    let n = r
        .by_ref()
        .take(MAX_LINE as u64 + 1)
        .read_until(b'\n', &mut buf)?;
    if n == 0 {
        return Ok(Line::Eof);
    }
    if buf.last() == Some(&b'\n') {
        buf.pop();
        if buf.last() == Some(&b'\r') {
            buf.pop();
        }
    } else if buf.len() > MAX_LINE {
        return Ok(Line::TooLong);
    }
    if buf.len() > MAX_LINE {
        return Ok(Line::TooLong);
    }
    Ok(Line::Text(String::from_utf8_lossy(&buf).into_owned()))
}

#[cfg(test)]
mod tests {
    use super::*;

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

    /// The bytes on the wire do not depend on serde_json's `preserve_order` (on in the workspace build through hobnix-core, off in an
    /// extension's own build): CI runs this test both ways (`cargo test` and `cargo test -p hobnix-ext-sdk`).
    #[test]
    fn wire_lines_have_sorted_keys_however_serde_json_is_built() {
        let buf = Buf::default();
        let out = Out::new(buf.clone());
        let mut payload = Map::new();
        payload.insert("zeta".into(), json!([{"y": 1, "b": 2}]));
        payload.insert("alpha".into(), json!({"d": null, "c": "x"}));
        let ev = Event::new("pkg.demo.done", "s1")
            .text("t")
            .level(EventLevel::Warn)
            .payload(payload);
        out.event("emit", &ev).unwrap();
        out.log(LogLevel::Info, "hi").unwrap();
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
}
