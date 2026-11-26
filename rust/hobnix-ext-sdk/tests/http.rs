//! The HTTP client against a one-shot server on localhost.
#![expect(
    clippy::unwrap_used,
    reason = "test code: a failed unwrap is the failure"
)]
use hobnix_ext_sdk::http::{Client, HttpError};
use serde_json::json;
use std::io::{Read, Write};
use std::net::TcpListener;
use std::time::Duration;

/// Serve one connection with `reply`; the thread returns the request text it saw.
fn serve(reply: &'static [u8]) -> (u16, std::thread::JoinHandle<String>) {
    let l = TcpListener::bind("127.0.0.1:0").unwrap();
    let port = l.local_addr().unwrap().port();
    let h = std::thread::spawn(move || {
        let (mut s, _) = l.accept().unwrap();
        let mut got = Vec::new();
        let mut buf = [0u8; 4096];
        loop {
            let n = s.read(&mut buf).unwrap();
            got.extend_from_slice(buf.get(..n).unwrap());
            let t = String::from_utf8_lossy(&got).into_owned();
            if let Some(i) = t.find("\r\n\r\n") {
                let len = t
                    .get(..i)
                    .unwrap()
                    .to_ascii_lowercase()
                    .split("content-length: ")
                    .nth(1)
                    .and_then(|r| r.split("\r\n").next()?.parse::<usize>().ok())
                    .unwrap_or(0);
                if got.len() >= i + 4 + len {
                    break;
                }
            }
            if n == 0 {
                break;
            }
        }
        s.write_all(reply).unwrap();
        String::from_utf8_lossy(&got).into_owned()
    });
    (port, h)
}

#[test]
fn get_json_sends_the_key_header() {
    let (port, h) = serve(b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 14\r\n\r\n{\"name\":\"jf1\"}");
    let v = Client::new()
        .header("X-Emby-Token", "s3cret")
        .get_json(&format!("http://127.0.0.1:{port}/System/Info"))
        .unwrap();
    assert_eq!(v["name"], "jf1");
    let req = h.join().unwrap();
    assert!(req.starts_with("GET /System/Info HTTP/1.1\r\n"));
    assert!(req.contains("X-Emby-Token: s3cret\r\n"));
}

#[test]
fn post_json_and_error_status() {
    let (port, h) = serve(b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}");
    Client::new()
        .post_json(&format!("http://127.0.0.1:{port}/x"), &json!({"a": 1}))
        .unwrap();
    let req = h.join().unwrap();
    assert!(req.contains("Content-Type: application/json"));
    assert!(req.ends_with("{\"a\":1}"));
    let (port, _h) = serve(b"HTTP/1.1 401 Unauthorized\r\nContent-Length: 3\r\n\r\nbad");
    let e = Client::new()
        .get_json(&format!("http://127.0.0.1:{port}/"))
        .unwrap_err();
    assert!(matches!(e, HttpError::Status(401, ref b) if b == "bad"));
}

#[test]
fn https_is_refused_and_a_dead_port_times_out_or_fails() {
    let e = Client::new().get("https://127.0.0.1/").unwrap_err();
    assert!(matches!(e, HttpError::TlsUnsupported));
    // a silent server: the read timeout ends it
    let l = TcpListener::bind("127.0.0.1:0").unwrap();
    let port = l.local_addr().unwrap().port();
    let e = Client::new()
        .timeout(Duration::from_millis(200))
        .get(&format!("http://127.0.0.1:{port}/"))
        .unwrap_err();
    assert!(matches!(e, HttpError::Io(_)));
    let bad = Client::new()
        .header("X", "a\r\nInjected: 1")
        .get(&format!("http://127.0.0.1:{port}/"));
    assert!(bad.is_err());
}
