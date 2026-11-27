//! The payload of an event, written in the one form scripts/state-db.py stores: what `json.loads` reads (without `NaN` and `Infinity`),
//! written again by `json.dumps(obj, allow_nan=False, separators=(",", ":"))`. `serde_json` cannot stand in: it writes UTF-8, has its own
//! number format and refuses a lone surrogate.

use std::collections::HashMap;
use std::fmt::Write as _;
use std::str::Chars;

/// Arrays and objects inside each other. Deeper payloads are not stored. Python has a limit of its own that depends on its version
/// (a `RecursionError`); this one keeps the stack of this parser small.
const MAX_DEPTH: usize = 1000;
/// python refuses to read a longer whole number (`sys.int_info.default_max_str_digits`).
const MAX_INTEGER_DIGITS: usize = 4300;

enum Value {
    /// `null`, `true`, `false`.
    Word(&'static str),
    /// The digits as they are stored: a whole number of any size stays exact.
    Integer(String),
    Float(f64),
    /// UTF-16 units: a lone surrogate (`\ud800`) is kept, as python keeps it.
    Text(Vec<u16>),
    Array(Vec<Value>),
    /// In the order of the first place of each key, with its last value.
    Object(Vec<(Vec<u16>, Value)>),
}

/// The stored form of `raw`, or `None` when state-db.py stores NULL: not JSON, not an object, or a number too large for a float.
pub(super) fn normalise(raw: &str) -> Option<String> {
    let mut reader = Reader { rest: raw.chars() };
    let value = reader.value(0)?;
    reader.skip_space();
    if reader.peek().is_some() || !matches!(value, Value::Object(_)) {
        return None;
    }
    let mut out = String::with_capacity(raw.len());
    write_value(&value, &mut out)?;
    Some(out)
}

/// Every method gives `None` for text that is not JSON.
struct Reader<'a> {
    rest: Chars<'a>,
}

impl Reader<'_> {
    fn peek(&self) -> Option<char> {
        self.rest.clone().next()
    }

    fn skip_space(&mut self) {
        while matches!(self.peek(), Some(' ' | '\t' | '\n' | '\r')) {
            self.rest.next();
        }
    }

    fn take(&mut self, wanted: char) -> bool {
        let is_next = self.peek() == Some(wanted);
        if is_next {
            self.rest.next();
        }
        is_next
    }

    fn value(&mut self, depth: usize) -> Option<Value> {
        self.skip_space();
        match self.peek()? {
            '{' | '[' if depth >= MAX_DEPTH => None,
            '{' => self.object(depth + 1),
            '[' => self.array(depth + 1),
            '"' => self.string().map(Value::Text),
            'n' => self.word("null"),
            't' => self.word("true"),
            'f' => self.word("false"),
            _ => self.number(),
        }
    }

    fn word(&mut self, word: &'static str) -> Option<Value> {
        word.chars()
            .all(|c| self.take(c))
            .then_some(Value::Word(word))
    }

    /// The members between the opening character (next) and `close`, separated by commas.
    fn members(
        &mut self,
        close: char,
        mut member: impl FnMut(&mut Self) -> Option<()>,
    ) -> Option<()> {
        self.rest.next();
        self.skip_space();
        if self.take(close) {
            return Some(());
        }
        loop {
            member(self)?;
            self.skip_space();
            if self.take(close) {
                return Some(());
            }
            if !self.take(',') {
                return None;
            }
        }
    }

    fn array(&mut self, depth: usize) -> Option<Value> {
        let mut items = Vec::new();
        self.members(']', |reader| {
            items.push(reader.value(depth)?);
            Some(())
        })?;
        Some(Value::Array(items))
    }

    fn object(&mut self, depth: usize) -> Option<Value> {
        let mut pairs: Vec<(Vec<u16>, Value)> = Vec::new();
        let mut places: HashMap<Vec<u16>, usize> = HashMap::new();
        self.members('}', |reader| {
            reader.skip_space();
            if reader.peek() != Some('"') {
                return None;
            }
            let key = reader.string()?;
            reader.skip_space();
            if !reader.take(':') {
                return None;
            }
            let value = reader.value(depth)?;
            if let Some(pair) = places.get(&key).and_then(|at| pairs.get_mut(*at)) {
                pair.1 = value;
            } else {
                places.insert(key.clone(), pairs.len());
                pairs.push((key, value));
            }
            Some(())
        })?;
        Some(Value::Object(pairs))
    }

    /// A string; the opening quote is next.
    fn string(&mut self) -> Option<Vec<u16>> {
        self.rest.next();
        let mut units = Vec::new();
        loop {
            match self.rest.next()? {
                '"' => return Some(units),
                '\\' => units.push(self.escape()?),
                control if control < ' ' => return None,
                plain => units.extend_from_slice(plain.encode_utf16(&mut [0; 2])),
            }
        }
    }

    fn escape(&mut self) -> Option<u16> {
        let plain = match self.rest.next()? {
            c @ ('"' | '\\' | '/') => c,
            'b' => '\u{8}',
            'f' => '\u{c}',
            'n' => '\n',
            'r' => '\r',
            't' => '\t',
            'u' => {
                let mut unit = 0;
                for _ in 0..4 {
                    unit = unit * 16 + self.rest.next()?.to_digit(16)?;
                }
                return u16::try_from(unit).ok();
            }
            _ => return None,
        };
        u16::try_from(u32::from(plain)).ok()
    }

    /// Appends the digits that come next to `text`; gives how many there were.
    fn digits(&mut self, text: &mut String) -> usize {
        let mut count = 0;
        while let Some(digit) = self.peek().filter(char::is_ascii_digit) {
            text.push(digit);
            self.rest.next();
            count += 1;
        }
        count
    }

    /// `-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][-+]?[0-9]+)?`. A part that is not complete is not read: it is then text after the number,
    /// which makes the payload no JSON.
    fn number(&mut self) -> Option<Value> {
        let mut text = String::new();
        if self.take('-') {
            text.push('-');
        }
        let count = if self.take('0') {
            text.push('0');
            1
        } else {
            self.digits(&mut text)
        };
        if count == 0 {
            return None;
        }
        let mut is_float = false;
        if self.take('.') {
            text.push('.');
            if self.digits(&mut text) == 0 {
                return None;
            }
            is_float = true;
        }
        if let Some(e) = self.peek().filter(|c| matches!(c, 'e' | 'E')) {
            self.rest.next();
            text.push(e);
            if let Some(sign) = self.peek().filter(|c| matches!(c, '+' | '-')) {
                self.rest.next();
                text.push(sign);
            }
            if self.digits(&mut text) == 0 {
                return None;
            }
            is_float = true;
        }
        if is_float {
            return text.parse().ok().map(Value::Float);
        }
        if count > MAX_INTEGER_DIGITS {
            return None;
        }
        Some(Value::Integer(if text == "-0" {
            "0".to_string()
        } else {
            text
        }))
    }
}

/// `None` for a float that is not finite: only a number that stays in the object counts, a repeated key may have replaced it.
fn write_value(value: &Value, out: &mut String) -> Option<()> {
    match value {
        Value::Word(word) => out.push_str(word),
        Value::Integer(digits) => out.push_str(digits),
        Value::Float(number) => out.push_str(&float_text(*number)?),
        Value::Text(units) => write_string(units, out),
        Value::Array(items) => {
            out.push('[');
            for (at, item) in items.iter().enumerate() {
                if at > 0 {
                    out.push(',');
                }
                write_value(item, out)?;
            }
            out.push(']');
        }
        Value::Object(pairs) => {
            out.push('{');
            for (at, (key, item)) in pairs.iter().enumerate() {
                if at > 0 {
                    out.push(',');
                }
                write_string(key, out);
                out.push(':');
                write_value(item, out)?;
            }
            out.push('}');
        }
    }
    Some(())
}

/// `ensure_ascii`: everything outside printable ASCII is escaped, a character beyond the basic plane as its two UTF-16 units.
fn write_string(units: &[u16], out: &mut String) {
    out.push('"');
    for &unit in units {
        match u8::try_from(unit) {
            Ok(b'"') => out.push_str("\\\""),
            Ok(b'\\') => out.push_str("\\\\"),
            Ok(8) => out.push_str("\\b"),
            Ok(12) => out.push_str("\\f"),
            Ok(b'\n') => out.push_str("\\n"),
            Ok(b'\r') => out.push_str("\\r"),
            Ok(b'\t') => out.push_str("\\t"),
            Ok(printable @ b' '..=b'~') => out.push(char::from(printable)),
            // writing to a String cannot fail
            _ => drop(write!(out, "\\u{unit:04x}")),
        }
    }
    out.push('"');
}

/// python's `repr(float)`: the shortest digits that read back, with an exponent below 1e-4 and from 1e16 on.
fn float_text(number: f64) -> Option<String> {
    if !number.is_finite() {
        return None;
    }
    // `{:e}` gives the shortest digits as `-d.ddde-7`
    let scientific = format!("{number:e}");
    let (mantissa, exponent) = scientific.split_once('e')?;
    let exponent: i32 = exponent.parse().ok()?;
    let sign = if mantissa.starts_with('-') { "-" } else { "" };
    let digits: String = mantissa.chars().filter(char::is_ascii_digit).collect();
    if !(-4..16).contains(&exponent) {
        let (first, rest) = digits.split_at_checked(1)?;
        let point = if rest.is_empty() { "" } else { "." };
        let direction = if exponent < 0 { '-' } else { '+' };
        let size = exponent.unsigned_abs();
        return Some(format!("{sign}{first}{point}{rest}e{direction}{size:02}"));
    }
    if exponent < 0 {
        let zeros = "0".repeat(usize::try_from(-exponent - 1).ok()?);
        return Some(format!("{sign}0.{zeros}{digits}"));
    }
    let before_point = usize::try_from(exponent).ok()? + 1;
    Some(match digits.split_at_checked(before_point) {
        Some((whole, rest)) if !rest.is_empty() => format!("{sign}{whole}.{rest}"),
        _ => format!("{sign}{digits:0<before_point$}.0"),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Each pair is a payload and what `json.dumps(json.loads(payload), allow_nan=False, separators=(",", ":"))` gives for it.
    fn assert_stored(cases: &[(&str, &str)]) {
        for (raw, stored) in cases {
            assert_eq!(normalise(raw).as_deref(), Some(*stored), "{raw}");
        }
    }

    #[test]
    fn spaces_go_and_keys_keep_their_first_place_with_the_last_value() {
        assert_stored(&[
            (" { \"a\" : [1, 2] }\r\n\t", "{\"a\":[1,2]}"),
            (r#"{"b":1,"a":2}"#, r#"{"b":1,"a":2}"#),
            (r#"{"a":1,"b":2,"a":3}"#, r#"{"a":3,"b":2}"#),
            (r#"{"ä":1,"\u00e4":2}"#, r#"{"\u00e4":2}"#),
            (
                r#"{"a":{"b":[true,false,null,{}]},"c":[]}"#,
                r#"{"a":{"b":[true,false,null,{}]},"c":[]}"#,
            ),
        ]);
    }

    #[test]
    fn strings_are_escaped_as_python_escapes_them() {
        assert_stored(&[
            (r#"{"n":"ä😀"}"#, r#"{"n":"\u00e4\ud83d\ude00"}"#),
            (
                r#"{"s":"a\/b\u0001\u007F\n\b\f\r\t\"\\"}"#,
                r#"{"s":"a/b\u0001\u007f\n\b\f\r\t\"\\"}"#,
            ),
            ("{\"s\":\"\u{7f}\"}", r#"{"s":"\u007f"}"#),
            (r#"{"s":"\ud800"}"#, r#"{"s":"\ud800"}"#),
            (r#"{"s":"\udc00\ud800x"}"#, r#"{"s":"\udc00\ud800x"}"#),
        ]);
    }

    #[test]
    fn numbers_are_written_as_python_writes_them() {
        assert_stored(&[
            (
                r#"{"x":1.0,"y":1e3,"z":0.10}"#,
                r#"{"x":1.0,"y":1000.0,"z":0.1}"#,
            ),
            (r#"{"x":1e22,"y":0.0000001}"#, r#"{"x":1e+22,"y":1e-07}"#),
            (
                r#"{"x":1E+15,"y":1e16,"z":0.0001,"w":0.00001}"#,
                r#"{"x":1000000000000000.0,"y":1e+16,"z":0.0001,"w":1e-05}"#,
            ),
            (
                r#"{"x":-0.0,"y":-0,"z":-12.5,"w":-1.25e-300}"#,
                r#"{"x":-0.0,"y":0,"z":-12.5,"w":-1.25e-300}"#,
            ),
            (
                r#"{"x":5e-324,"y":1.7976931348623157e308,"z":123456.789}"#,
                r#"{"x":5e-324,"y":1.7976931348623157e+308,"z":123456.789}"#,
            ),
            (r#"{"x":1e-400}"#, r#"{"x":0.0}"#),
            (
                r#"{"big":123456789012345678901234567890}"#,
                r#"{"big":123456789012345678901234567890}"#,
            ),
            // the number too large for a float is gone: the key was repeated
            (r#"{"a":1e400,"a":1}"#, r#"{"a":1}"#),
        ]);
    }

    #[test]
    fn what_python_does_not_store_is_not_stored() {
        for none in [
            "[1,2]",
            r#""text""#,
            "7",
            "null",
            "nonsense",
            "",
            "{",
            r#"{"a":NaN}"#,
            r#"{"a":Infinity}"#,
            r#"{"a":-Infinity}"#,
            r#"{"a":NaN,"a":1}"#,
            r#"{"a":1}x"#,
            r#"{"a":1e400}"#,
            r#"{"a":[{"b":-1e400}]}"#,
            "[1e400]",
            r#"{"a":01}"#,
            r#"{"a":1.}"#,
            r#"{"a":.5}"#,
            r#"{"a":+1}"#,
            r#"{"a":1e}"#,
            r#"{"a":-}"#,
            r#"{"a":tru}"#,
            r#"{"a":1,}"#,
            r#"{"a":[1,]}"#,
            r"{a:1}",
            r#"{"a" 1}"#,
            r#"{"a":"\x"}"#,
            r#"{"a":"\u12"}"#,
            r#"{"a":"\u+123"}"#,
            "{\"a\":\"\t\"}",
            "\u{feff}{}",
            "{}\u{a0}",
        ] {
            assert_eq!(normalise(none), None, "{none}");
        }
    }

    #[test]
    fn a_whole_number_is_read_up_to_pythons_limit() {
        let longest = format!(r#"{{"a":-{}}}"#, "9".repeat(MAX_INTEGER_DIGITS));
        assert_eq!(normalise(&longest).as_deref(), Some(longest.as_str()));
        let longer = format!(r#"{{"a":{}}}"#, "9".repeat(MAX_INTEGER_DIGITS + 1));
        assert_eq!(normalise(&longer), None);
    }

    #[test]
    fn nesting_has_a_limit_and_absurd_nesting_is_only_refused() {
        let nested = |n: usize| format!(r#"{{"a":{}{}}}"#, "[".repeat(n), "]".repeat(n));
        let deepest = nested(MAX_DEPTH - 1);
        assert_eq!(normalise(&deepest).as_deref(), Some(deepest.as_str()));
        assert_eq!(normalise(&nested(MAX_DEPTH)), None);
        assert_eq!(normalise(&"[".repeat(1_000_000)), None);
        assert_eq!(normalise(&r#"{"a":"#.repeat(200_000)), None);
    }
}
