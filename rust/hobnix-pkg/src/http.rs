//! A small blocking HTTP/1.1 client for the JSON APIs of media servers (Jellyfin, Plex, ...), standard library only.
//!
//! Plain `http://` works. `https://` does NOT: it is refused with [`HttpError::TlsUnsupported`]. The SDK has no TLS stack on purpose:
//! rustls pulls `ring` (C and assembly, a cross C toolchain for `x86_64-unknown-linux-musl`) and about twenty crates, and the core's
//! Nix build of `rust/` could not be checked with it (issue #1131). Integrations are on the same host or the LAN (`api_url` from
//! `hs pkg integrations`), so plain http covers them; for an https-only API put a local TLS-terminating proxy in front.
//!
//! One request per connection (`Connection: close`), `Content-Length` and `chunked` bodies, redirects are not followed, the body is
//! capped at 16 MiB, every step has a timeout.
use serde_json::Value;
use std::io::{Read, Write};
use std::net::{TcpStream, ToSocketAddrs};
use std::time::Duration;

use crate::Secret;

const MAX_BODY: usize = 16 << 20;

/// Why a request failed.
#[non_exhaustive]
#[derive(Debug)]
pub enum HttpError {
    /// The URL is not `http://host[:port]/path`.
    BadUrl(String),
    /// `https://` (see the module text).
    TlsUnsupported,
    /// Connect, read or write failed, or timed out.
    Io(std::io::Error),
    /// The answer is not HTTP/1.x, or is cut off, or too large.
    BadResponse(String),
    /// Not 2xx; the body is kept (cut to 512 characters).
    Status(u16, String),
    /// The body is not JSON.
    Json(serde_json::Error),
}

impl std::fmt::Display for HttpError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            HttpError::BadUrl(u) => write!(f, "bad url: {u}"),
            HttpError::TlsUnsupported => write!(f, "https is not supported by the SDK client"),
            HttpError::Io(e) => write!(f, "{e}"),
            HttpError::BadResponse(w) => write!(f, "bad response: {w}"),
            HttpError::Status(c, b) => write!(f, "http {c}: {b}"),
            HttpError::Json(e) => write!(f, "not json: {e}"),
        }
    }
}
impl std::error::Error for HttpError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            HttpError::Io(e) => Some(e),
            HttpError::Json(e) => Some(e),
            _ => None,
        }
    }
}
impl From<std::io::Error> for HttpError {
    fn from(e: std::io::Error) -> Self {
        HttpError::Io(e)
    }
}

/// An answer of the server.
#[non_exhaustive]
#[derive(Debug, Clone)]
pub struct Response {
    /// The status code (`200`).
    pub status: u16,
    /// Header names lower-cased.
    pub headers: Vec<(String, String)>,
    /// The body, at most 16 MiB.
    pub body: Vec<u8>,
}

impl Response {
    /// A response with `status`, `headers` (names are lower-cased here) and `body`; for a test of code that reads one.
    pub fn new(status: u16, headers: Vec<(String, String)>, body: Vec<u8>) -> Self {
        let headers = headers
            .into_iter()
            .map(|(k, v)| (k.to_ascii_lowercase(), v))
            .collect();
        Response {
            status,
            headers,
            body,
        }
    }
    /// The first header called `name` (any case).
    pub fn header(&self, name: &str) -> Option<&str> {
        let n = name.to_ascii_lowercase();
        self.headers
            .iter()
            .find(|(k, _)| *k == n)
            .map(|(_, v)| v.as_str())
    }
    /// The body as text (invalid UTF-8 is replaced).
    pub fn text(&self) -> String {
        String::from_utf8_lossy(&self.body).into_owned()
    }
    /// The body as JSON; [`HttpError::Json`] when it is not.
    pub fn json(&self) -> Result<Value, HttpError> {
        serde_json::from_slice(&self.body).map_err(HttpError::Json)
    }
    /// `self` for 2xx, else [`HttpError::Status`].
    pub fn ok(self) -> Result<Response, HttpError> {
        if (200..300).contains(&self.status) {
            Ok(self)
        } else {
            let t: String = self.text().chars().take(512).collect();
            Err(HttpError::Status(self.status, t))
        }
    }
}

/// The value of a request header. Made from a `String`, a `&str` or a [`Secret`]; never printed (it can be the integration key).
#[derive(Clone)]
pub struct HeaderValue(String);

impl std::fmt::Debug for HeaderValue {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("***")
    }
}

impl From<String> for HeaderValue {
    fn from(v: String) -> Self {
        HeaderValue(v)
    }
}
impl From<&String> for HeaderValue {
    fn from(v: &String) -> Self {
        HeaderValue(v.clone())
    }
}
impl From<&str> for HeaderValue {
    fn from(v: &str) -> Self {
        HeaderValue(v.to_owned())
    }
}
impl From<Secret> for HeaderValue {
    fn from(v: Secret) -> Self {
        HeaderValue(v.expose().to_owned())
    }
}
impl From<&Secret> for HeaderValue {
    fn from(v: &Secret) -> Self {
        HeaderValue(v.expose().to_owned())
    }
}

/// A blocking client: a timeout and headers sent with every request.
#[derive(Clone)]
pub struct Client {
    timeout: Duration,
    headers: Vec<(String, HeaderValue)>,
}

/// Header names only: a value can be the integration key.
impl std::fmt::Debug for Client {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let names: Vec<&str> = self.headers.iter().map(|(k, _)| k.as_str()).collect();
        f.debug_struct("Client")
            .field("timeout", &self.timeout)
            .field("headers", &names)
            .finish()
    }
}

impl Default for Client {
    fn default() -> Self {
        Client {
            timeout: Duration::from_secs(10),
            headers: Vec::new(),
        }
    }
}

impl Client {
    /// A client with a 10 s timeout and no headers.
    pub fn new() -> Self {
        Self::default()
    }
    /// Timeout for the connect and for each read and write (default 10 s).
    #[must_use]
    pub fn timeout(mut self, t: Duration) -> Self {
        self.timeout = t;
        self
    }
    /// A header sent with every request, e.g. the key header from the integration listing with the key as a [`Secret`]. A line break in
    /// it is refused when sending.
    #[must_use]
    pub fn header(mut self, name: impl Into<String>, value: impl Into<HeaderValue>) -> Self {
        self.headers.push((name.into(), value.into()));
        self
    }
    /// GET and parse the body as JSON; a non-2xx status is [`HttpError::Status`].
    pub fn get_json(&self, url: &str) -> Result<Value, HttpError> {
        self.request("GET", url, None)?.ok()?.json()
    }
    /// POST a JSON body and parse the answer as JSON.
    pub fn post_json(&self, url: &str, body: &Value) -> Result<Value, HttpError> {
        let b = serde_json::to_vec(body).map_err(HttpError::Json)?;
        self.request("POST", url, Some(&b))?.ok()?.json()
    }
    /// GET; any status is an `Ok` response.
    pub fn get(&self, url: &str) -> Result<Response, HttpError> {
        self.request("GET", url, None)
    }

    /// Send one request; any status is an `Ok` response (use [`Response::ok`] to turn non-2xx into an error).
    pub fn request(
        &self,
        method: &str,
        url: &str,
        json_body: Option<&[u8]>,
    ) -> Result<Response, HttpError> {
        let (host, port, path) = parse_url(url)?;
        let bad = |s: &str| s.contains(['\r', '\n']);
        if self.headers.iter().any(|(k, v)| bad(k) || bad(&v.0)) {
            return Err(HttpError::BadUrl("header with a line break".into()));
        }
        let addr = (host.as_str(), port)
            .to_socket_addrs()?
            .next()
            .ok_or_else(|| HttpError::BadUrl(format!("no address for {host}")))?;
        let mut s = TcpStream::connect_timeout(&addr, self.timeout)?;
        s.set_read_timeout(Some(self.timeout))?;
        s.set_write_timeout(Some(self.timeout))?;
        let mut head = format!(
            "{method} {path} HTTP/1.1\r\nHost: {host}:{port}\r\nUser-Agent: hobnix-pkg\r\nAccept: application/json\r\nConnection: close\r\n"
        );
        for (k, v) in &self.headers {
            head.push_str(k);
            head.push_str(": ");
            head.push_str(&v.0);
            head.push_str("\r\n");
        }
        if let Some(b) = json_body {
            head.push_str("Content-Type: application/json\r\nContent-Length: ");
            head.push_str(&b.len().to_string());
            head.push_str("\r\n");
        }
        head.push_str("\r\n");
        s.write_all(head.as_bytes())?;
        if let Some(b) = json_body {
            s.write_all(b)?;
        }
        let mut raw = Vec::new();
        s.take(MAX_BODY as u64 + 65536).read_to_end(&mut raw)?;
        parse_response(&raw)
    }
}

fn parse_url(url: &str) -> Result<(String, u16, String), HttpError> {
    if url.starts_with("https://") {
        return Err(HttpError::TlsUnsupported);
    }
    let bad = || HttpError::BadUrl(redact_url(url));
    let rest = url.strip_prefix("http://").ok_or_else(bad)?;
    let (auth, path) = rest
        .find('/')
        .and_then(|i| rest.split_at_checked(i))
        .unwrap_or((rest, "/"));
    if auth.is_empty() || auth.contains('@') || path.contains(['\r', '\n', ' ']) {
        return Err(bad());
    }
    let (host, port) = if let Some(r) = auth.strip_prefix('[') {
        let (h, tail) = r.split_once(']').ok_or_else(bad)?;
        let p = match tail.strip_prefix(':') {
            Some(p) => p.parse().map_err(|_| bad())?,
            None => 80,
        };
        (h.to_string(), p)
    } else if let Some((h, p)) = auth.rsplit_once(':') {
        (h.to_string(), p.parse().map_err(|_| bad())?)
    } else {
        (auth.to_string(), 80)
    };
    Ok((host, port, path.to_string()))
}

/// The URL for an error text: the query and fragment become `?***`, a userinfo part `***@` (either can carry a key).
///
/// A pasted password may hold `/`, `?` or `#` unencoded, so everything before the LAST `@` goes (an `@` in the path or query hides the
/// host too: too much hidden is fine in an error text, too little is not); only a well-formed scheme is kept in front of it.
fn redact_url(url: &str) -> String {
    let (head, rest) = match url.rsplit_once('@') {
        Some((before, after)) => {
            let scheme = before.split_once("://").map(|(s, _)| s).filter(|s| {
                !s.is_empty()
                    && s.chars()
                        .all(|c| c.is_ascii_alphanumeric() || matches!(c, '+' | '-' | '.'))
            });
            (
                scheme.map_or_else(|| "***@".to_string(), |s| format!("{s}://***@")),
                after,
            )
        }
        None => (String::new(), url),
    };
    match rest.split_once(['?', '#']) {
        Some((base, _)) => format!("{head}{base}?***"),
        None => format!("{head}{rest}"),
    }
}

fn parse_response(raw: &[u8]) -> Result<Response, HttpError> {
    let bad = |w: &str| HttpError::BadResponse(w.into());
    let end = raw
        .windows(4)
        .position(|w| w == b"\r\n\r\n")
        .ok_or_else(|| bad("no end of headers"))?;
    // `end` is where the four bytes were found: both parts exist
    let (Some(head), Some(rest)) = (raw.get(..end), raw.get(end + 4..)) else {
        return Err(bad("no end of headers"));
    };
    let head = std::str::from_utf8(head).map_err(|_| bad("headers are not text"))?;
    let mut lines = head.split("\r\n");
    let mut parts = lines.next().unwrap_or("").splitn(3, ' ');
    if !parts.next().is_some_and(|v| v.starts_with("HTTP/1.")) {
        return Err(bad("not HTTP/1.x"));
    }
    let status: u16 = parts
        .next()
        .and_then(|c| c.parse().ok())
        .ok_or_else(|| bad("no status code"))?;
    let headers: Vec<(String, String)> = lines
        .filter_map(|l| l.split_once(':'))
        .map(|(k, v)| (k.trim().to_ascii_lowercase(), v.trim().to_string()))
        .collect();
    let find = |n: &str| {
        headers
            .iter()
            .find(|(k, _)| k == n)
            .map(|(_, v)| v.as_str())
    };
    let chunked =
        find("transfer-encoding").is_some_and(|v| v.to_ascii_lowercase().contains("chunked"));
    let body = if chunked {
        dechunk(rest)?
    } else if let Some(len) = find("content-length") {
        let n: usize = len.parse().map_err(|_| bad("bad content-length"))?;
        if n > MAX_BODY {
            return Err(bad("body too large"));
        }
        rest.get(..n).ok_or_else(|| bad("body cut off"))?.to_vec()
    } else {
        rest.to_vec()
    };
    if body.len() > MAX_BODY {
        return Err(bad("body too large"));
    }
    Ok(Response {
        status,
        headers,
        body,
    })
}

fn dechunk(mut b: &[u8]) -> Result<Vec<u8>, HttpError> {
    let bad = |w: &str| HttpError::BadResponse(w.into());
    let mut out = Vec::new();
    loop {
        let i = b
            .windows(2)
            .position(|w| w == b"\r\n")
            .ok_or_else(|| bad("chunk size missing"))?;
        let (line, tail) = (b.get(..i), b.get(i + 2..));
        let size_text =
            std::str::from_utf8(line.unwrap_or_default()).map_err(|_| bad("chunk size"))?;
        let size_text = size_text.split(';').next().unwrap_or("").trim();
        let n = usize::from_str_radix(size_text, 16).map_err(|_| bad("chunk size"))?;
        b = tail.unwrap_or_default();
        if n == 0 {
            return Ok(out);
        }
        // the size comes from the peer: refuse it before any arithmetic with it
        if n > MAX_BODY || out.len().saturating_add(n) > MAX_BODY {
            return Err(bad("body too large"));
        }
        let end = n.checked_add(2).ok_or_else(|| bad("chunk size"))?;
        let (Some(chunk), Some(next)) = (b.get(..n), b.get(end..)) else {
            return Err(bad("chunk cut off"));
        };
        out.extend_from_slice(chunk);
        b = next;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn urls() {
        assert_eq!(
            parse_url("http://127.0.0.1:8096/System/Info?x=1").unwrap(),
            ("127.0.0.1".into(), 8096, "/System/Info?x=1".into())
        );
        assert_eq!(parse_url("http://h").unwrap(), ("h".into(), 80, "/".into()));
        assert_eq!(parse_url("http://[::1]:9/a").unwrap().0, "::1");
        assert!(matches!(
            parse_url("https://h/"),
            Err(HttpError::TlsUnsupported)
        ));
        assert!(parse_url("ftp://h").is_err());
        assert!(parse_url("http://u@h/").is_err());
    }

    #[test]
    fn chunked_and_length() {
        let r = parse_response(
            b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n3\r\n{\"a\r\n4\r\n\":1}\r\n0\r\n\r\n",
        )
        .unwrap();
        assert_eq!(r.json().unwrap()["a"], 1);
        let r = parse_response(b"HTTP/1.1 404 No\r\nContent-Length: 2\r\n\r\nxyEXTRA").unwrap();
        assert_eq!(r.body, b"xy");
        assert!(matches!(r.ok(), Err(HttpError::Status(404, _))));
        assert!(parse_response(b"HTTP/1.1 200 OK\r\nContent-Length: 9\r\n\r\nab").is_err());
        assert!(parse_response(b"garbage").is_err());
    }

    #[test]
    fn bad_url_does_not_show_query_or_userinfo() {
        for url in [
            "http://u:pw-9d2e@h/a?api_key=key-4f1c9a",
            "ftp://h/x?api_key=key-4f1c9a",
            "http://h/a b?api_key=key-4f1c9a#pw-9d2e",
            "pw-9d2e@h?api_key=key-4f1c9a",
            "http://h:notaport/?token=key-4f1c9a",
        ] {
            let e = parse_url(url).unwrap_err();
            for shown in [e.to_string(), format!("{e:?}")] {
                assert!(!shown.contains("key-4f1c9a"), "{shown}");
                assert!(!shown.contains("pw-9d2e"), "{shown}");
            }
        }
        let e = parse_url("ftp://h:1/x?y=1").unwrap_err();
        assert_eq!(e.to_string(), "bad url: ftp://h:1/x?***");
        let e = parse_url("http://u:p@h/x").unwrap_err();
        assert_eq!(e.to_string(), "bad url: http://***@h/x");
    }

    #[test]
    fn bad_url_hides_a_password_with_slash_question_mark_or_hash() {
        for url in [
            "http://u:pa?ss-9d2e@h/x",
            "http://u:pa/ss-9d2e@h/x",
            "http://u:pa#ss-9d2e@h/x",
            "ftp://u:pa?ss-9d2e@h",
            "u@x://pa?ss-9d2e@h",
        ] {
            let e = parse_url(url).unwrap_err();
            for shown in [e.to_string(), format!("{e:?}")] {
                assert!(!shown.contains("pa"), "{url}: {shown}");
                assert!(!shown.contains("9d2e"), "{url}: {shown}");
            }
        }
        let e = parse_url("http://u:pa/ss@h/x?k=1").unwrap_err();
        assert_eq!(e.to_string(), "bad url: http://***@h/x?***");
        let e = parse_url("ftp://h/x#frag").unwrap_err();
        assert_eq!(e.to_string(), "bad url: ftp://h/x?***");
    }

    #[test]
    fn debug_does_not_show_header_values() {
        let c = Client::new()
            .header("X-Emby-Token", "key-4f1c9a")
            .header("Accept-Language", "en");
        let d = format!("{c:?}");
        assert!(!d.contains("key-4f1c9a"), "{d}");
        assert!(!d.contains("\"en\""), "{d}");
        assert!(d.contains("X-Emby-Token"), "{d}");
        assert!(d.contains("timeout"), "{d}");
    }

    #[test]
    fn absurd_chunk_sizes_are_errors_not_panics() {
        for size in [
            "ffffffffffffffff",
            "fffffffffffffffe",
            "10000000000000000",
            "1000001",
        ] {
            let raw = format!(
                "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n{size}\r\nab\r\n0\r\n\r\n"
            );
            assert!(
                matches!(
                    parse_response(raw.as_bytes()),
                    Err(HttpError::BadResponse(_))
                ),
                "chunk size {size}"
            );
        }
        // a chunk that claims more than it carries, and one without its line end
        assert!(dechunk(b"5\r\nab\r\n0\r\n\r\n").is_err());
        assert!(dechunk(b"2\r\nab").is_err());
        assert_eq!(dechunk(b"2\r\nab\r\n0\r\n\r\n").unwrap(), b"ab");
    }
}
