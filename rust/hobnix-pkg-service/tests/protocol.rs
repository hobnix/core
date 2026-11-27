//! The service runner against the wire format of ADR 0011, with in-memory pipes (no processes).

#[cfg(test)]
mod tests {
    use std::io::{Cursor, Write};
    use std::sync::{Arc, Mutex};

    use hobnix_pkg::credentials::credential_for;
    use hobnix_pkg::{Ctx, Error, Event};
    use hobnix_pkg_service::{self as service, EventRow, Health, Init, Service};
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

    #[derive(Default)]
    struct Probe {
        events: Vec<u64>,
        started: Option<String>,
    }
    impl Service for Probe {
        fn start(&mut self, init: &Init, _: &dyn Ctx) -> Result<(), Error> {
            self.started = Some(format!("{} {:?}", init.name, init.subscribe));
            Ok(())
        }
        fn on_event(&mut self, ev: &EventRow, ctx: &dyn Ctx) -> Result<(), Error> {
            self.events.push(ev.id);
            if ev.subject == "bad" {
                return Err(Error::failed("cannot"));
            }
            ctx.emit(&Event::new("pkg.demo.seen", &ev.subject))
                .map_err(Error::from)
        }
        fn tick(&mut self, ctx: &dyn Ctx) -> Health {
            ctx.snapshot("t", json!({"n": self.events.len()})).unwrap();
            Health::ok()
        }
    }

    fn svc_input(lines: &[Value]) -> Cursor<Vec<u8>> {
        let mut s = String::new();
        for l in lines {
            s.push_str(&l.to_string());
            s.push('\n');
        }
        Cursor::new(s.into_bytes())
    }

    fn init() -> Value {
        json!({"v":1,"type":"init","name":"demo","lang":"en","subscribe":["job.*"],"health_interval":30})
    }
    fn ev(id: u64, subject: &str) -> Value {
        json!({"v":1,"type":"event","id":id,"time":1,"source":"s","kind":"job.done","subject":subject,"level":"info","text":null,"payload":null})
    }

    #[test]
    fn service_ready_first_acks_handled_events_and_stops_on_shutdown() {
        let buf = Buf::default();
        let input = svc_input(&[
            init(),
            ev(1, "a"),
            json!({"v":1,"type":"future-thing"}), // unknown type: ignored
            ev(2, "bad"),                         // handler fails: no ack
            ev(3, "c"),
            json!({"v":1,"type":"shutdown","grace_ms":1000}),
        ]);
        let code = service::run_with(input, buf.clone(), Probe::default());
        assert_eq!(code, 0);
        let out = buf.lines();
        assert_eq!(out[0], json!({"v":1,"type":"ready"}));
        assert!(out.iter().all(|m| m["v"] == 1));
        let acks: Vec<u64> = out
            .iter()
            .filter(|m| m["type"] == "ack")
            .map(|m| m["id"].as_u64().unwrap())
            .collect();
        assert_eq!(acks, [1, 3]);
        assert!(
            out.iter()
                .any(|m| m["type"] == "log" && m["level"] == "error")
        );
        assert!(
            out.iter()
                .any(|m| m["type"] == "emit" && m["kind"] == "pkg.demo.seen")
        );
        assert!(out.iter().any(|m| m["type"] == "health" && m["ok"] == true));
        assert!(
            out.iter()
                .any(|m| m["type"] == "snapshot" && m["topic"] == "t")
        );
    }

    #[test]
    fn service_exits_0_when_stdin_closes_and_1_on_protocol_error() {
        let buf = Buf::default();
        assert_eq!(
            service::run_with(svc_input(&[init()]), buf.clone(), Probe::default()),
            0
        );
        let buf = Buf::default();
        let mut bad = svc_input(&[init()]).into_inner();
        bad.extend_from_slice(b"garbage\n");
        assert_eq!(
            service::run_with(Cursor::new(bad), buf.clone(), Probe::default()),
            1
        );
    }

    #[test]
    fn service_writes_nothing_when_init_is_wrong() {
        let wrong_version = json!({"v": 2, "type": "init"});
        for input in [
            svc_input(&[]),
            svc_input(&[ev(1, "a")]),
            svc_input(&[wrong_version]),
        ] {
            let buf = Buf::default();
            assert_eq!(service::run_with(input, buf.clone(), Probe::default()), 1);
            assert!(buf.lines().is_empty(), "only `ready` may come first");
        }
    }

    #[test]
    fn service_degraded_health_and_topic_checks() {
        struct Sick;
        impl Service for Sick {
            fn tick(&mut self, ctx: &dyn Ctx) -> Health {
                assert!(ctx.snapshot("Bad Topic", json!(1)).is_err());
                assert!(ctx.snapshot("big", json!("x".repeat(300 << 10))).is_err());
                Health::degraded("device gone")
            }
        }
        let buf = Buf::default();
        service::run_with(svc_input(&[init()]), buf.clone(), Sick);
        let h = buf
            .lines()
            .into_iter()
            .find(|m| m["type"] == "health")
            .unwrap();
        assert_eq!(
            h,
            json!({"v":1,"type":"health","ok":false,"text":"device gone"})
        );
    }

    #[test]
    fn service_rollup_message_and_credential() {
        struct Roll;
        impl Service for Roll {
            fn tick(&mut self, ctx: &dyn Ctx) -> Health {
                ctx.rollup("pkg.t.watch", "anna", 2.0, 90.5).unwrap();
                assert!(ctx.rollup("pkg.t.watch", "a b", 1.0, 0.0).is_err());
                assert!(ctx.rollup("pkg.t.watch", "-time", 1.0, 0.0).is_err());
                Health::ok()
            }
        }
        let buf = Buf::default();
        service::run_with(svc_input(&[init()]), buf.clone(), Roll);
        let lines = buf.lines();
        let m = lines
            .iter()
            .find(|m| m["type"] == "rollup")
            .expect("a rollup line");
        assert_eq!(m["kind"], "pkg.t.watch");
        assert_eq!(m["user"], "anna");
        assert_eq!(m["n"], 2.0);
        assert_eq!(m["sum"], 90.5);
        assert_eq!(m["v"], 1);
        assert!(credential_for("Bad Name", "jellyfin").is_none());
        assert!(credential_for("media", "../x").is_none());
        assert!(credential_for("media", "").is_none());
    }
}
