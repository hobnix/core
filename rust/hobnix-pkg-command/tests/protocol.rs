//! The command runner against the wire format of ADR 0010, with in-memory pipes (no processes).

#[cfg(test)]
mod tests {
    use std::io::{Cursor, Write};
    use std::sync::{Arc, Mutex};

    use hobnix_pkg::testing::{Call, FakeCtx};
    use hobnix_pkg::{Ctx, Event, LogLevel};
    use hobnix_pkg_command::{self as command, ErrorCode, Failure, Success};
    use serde_json::{Value, json};

    #[derive(Clone, Default)]
    struct Buf(Arc<Mutex<Vec<u8>>>);
    impl Write for Buf {
        fn write(&mut self, b: &[u8]) -> std::io::Result<usize> {
            self.0.lock().unwrap().extend_from_slice(b);
            Ok(b.len())
        }
        fn flush(&mut self) -> std::io::Result<()> {
            Ok(())
        }
    }
    impl Buf {
        fn lines(&self) -> Vec<Value> {
            let s = String::from_utf8(self.0.lock().unwrap().clone()).unwrap();
            s.lines()
                .map(|l| serde_json::from_str(l).unwrap())
                .collect()
        }
    }

    fn request(command: &[&str], argv: &[&str]) -> String {
        format!(
            "{}\n",
            json!({"v":1,"type":"request","id":"0123456789abcdef","command":command,"argv":argv,"lang":"de","caller":"web","timeout_ms":30000})
        )
    }

    fn call<F>(input: &str, h: F) -> (u8, Vec<Value>)
    where
        F: FnOnce(&command::Request, &dyn Ctx) -> Result<Success, Failure>,
    {
        let buf = Buf::default();
        let code = command::run_with(&mut Cursor::new(input.as_bytes().to_vec()), buf.clone(), h);
        (code, buf.lines())
    }

    #[test]
    fn command_ok_with_messages_then_one_result() {
        let (code, out) = call(&request(&["echo"], &["a", "b c"]), |req, ctx| {
            assert_eq!(req.argv, ["a", "b c"]);
            assert_eq!(req.words(), ["echo"]);
            ctx.progress(Some(7.0), "x").unwrap(); // clamped
            ctx.log(LogLevel::Warn, "hi").unwrap();
            ctx.emit(&Event::new("pkg.demo.said", "s").text("t"))
                .unwrap();
            Ok(Success::data(json!({"n": 1})).with_text("done"))
        });
        assert_eq!(code, 0);
        let types: Vec<_> = out.iter().map(|m| m["type"].as_str().unwrap()).collect();
        assert_eq!(types, ["progress", "log", "event", "result"]);
        assert!(out.iter().all(|m| m["v"] == 1));
        assert_eq!(out[0]["fraction"], 1.0);
        assert_eq!(
            out[3],
            json!({"v":1,"type":"result","ok":true,"data":{"n":1},"text":"done"})
        );
    }

    #[test]
    fn command_failure_has_error_and_exit_1_and_no_data() {
        let (code, out) = call(&request(&["x"], &[]), |_, _| {
            Err(Failure::not_found("no\nsuch thing"))
        });
        assert_eq!(code, 1);
        assert_eq!(out.len(), 1);
        assert_eq!(out[0]["ok"], false);
        assert_eq!(
            out[0]["error"],
            json!({"code":"not_found","message":"no such thing"})
        );
        assert!(out[0].get("data").is_none());
        let req = request(&["x"], &[]);
        let (_, out) = call(&req, |_, _| Err(Failure::new(ErrorCode::Cancelled, "stop")));
        assert_eq!(out[0]["error"]["code"], "cancelled");
    }

    #[test]
    fn command_unknown_version_answers_unsupported_version() {
        let line = format!("{}\n", json!({"v":2,"type":"request"}));
        let (code, out) = call(&line, |_, _| panic!("must not run"));
        assert_eq!(code, 1);
        let want = json!({
            "code": "unsupported_version",
            "message": "this extension speaks protocol version 1 only",
            "supported": [1]
        });
        assert_eq!(out[0]["error"], want);
    }

    #[test]
    fn command_bad_input_is_bad_request() {
        let wrong_type = "{\"v\":1,\"type\":\"progress\"}\n";
        let missing_fields = "{\"v\":1,\"type\":\"request\",\"id\":\"x\"}\n";
        for input in ["", "not json\n", wrong_type, missing_fields] {
            let (code, out) = call(input, |_, _| panic!("must not run"));
            assert_eq!(code, 1, "{input:?}");
            assert_eq!(out.len(), 1);
            assert_eq!(out[0]["error"]["code"], "bad_request", "{input:?}");
        }
    }

    #[test]
    fn command_panic_is_failed() {
        let (code, out) = call(&request(&["x"], &[]), |_, _| panic!("boom"));
        assert_eq!(code, 1);
        assert_eq!(out[0]["error"]["code"], "failed");
    }

    #[test]
    fn command_rejects_bad_kind_and_oversize_result() {
        let (_, out) = call(&request(&["x"], &[]), |_, ctx| {
            assert!(ctx.emit(&Event::new("core.disk", "x")).is_err());
            assert!(ctx.emit(&Event::new("pkg.demo.Said", "x")).is_err());
            Ok(Success::text("x".repeat(2 << 20)))
        });
        // the too-long result is replaced by a failure the core can read
        assert_eq!(out.len(), 1);
        assert_eq!(out[0]["ok"], false);
    }

    #[test]
    fn log_and_progress_text_are_cut_to_schema_limits() {
        let (_, out) = call(&request(&["x"], &[]), |_, ctx| {
            ctx.log(LogLevel::Info, &"é".repeat(2000)).unwrap();
            ctx.progress(None, &"p".repeat(500)).unwrap();
            Ok(Success::default())
        });
        assert_eq!(out[0]["text"].as_str().unwrap().chars().count(), 1000);
        assert_eq!(out[1]["text"].as_str().unwrap().chars().count(), 200);
        assert!(out[1].get("fraction").is_none());
        assert_eq!(out[2], json!({"v":1,"type":"result","ok":true}));
    }

    // ---- Ctx as a trait ----

    fn greet(req: &command::Request, ctx: &dyn Ctx) -> Result<Success, Failure> {
        let failed = |e: std::io::Error| Failure::failed(e.to_string());
        ctx.progress(Some(0.5), "half").map_err(failed)?;
        ctx.emit(&Event::new("pkg.demo.greeted", req.argv.first().unwrap()))
            .map_err(failed)?;
        Ok(Success::text("done"))
    }

    #[test]
    fn a_handler_runs_against_the_fake_and_the_wire_alike() {
        let req =
            command::Request::new("0123456789abcdef", vec!["greet".into()], vec!["Ada".into()]);
        let fake = FakeCtx::new();
        assert_eq!(greet(&req, &fake).unwrap(), Success::text("done"));
        assert_eq!(
            fake.calls(),
            [
                Call::Progress(Some(0.5), "half".into()),
                Call::Emit(Event::new("pkg.demo.greeted", "Ada"))
            ]
        );
        let (code, out) = call(&request(&["greet"], &["Ada"]), greet);
        assert_eq!(code, 0);
        let types: Vec<_> = out.iter().map(|m| m["type"].as_str().unwrap()).collect();
        assert_eq!(types, ["progress", "event", "result"]);
    }
}
