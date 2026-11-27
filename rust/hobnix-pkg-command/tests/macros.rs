//! The command macros end to end: the generated dispatch over the wire, the rows, the drift check, and the inputs they refuse (trybuild).
#![cfg(feature = "macros")]

#[cfg(test)]
mod tests {
    use std::io::{Cursor, Write};
    use std::sync::{Arc, Mutex};

    use hobnix_pkg_command::{
        ArgKind, Args, Commands, Ctx, Failure, Request, Success, command, commands,
    };
    use serde_json::{Value, json};

    /// How far to count.
    #[derive(Args)]
    struct CountArgs {
        /// the last number
        n: u32,
        /// a word to show
        label: Option<String>,
    }

    #[command(
        name = "count",
        reads,
        help = "count to n",
        help_de = "zählt bis n",
        topic = "system",
        sys = "the count as data"
    )]
    fn count(ctx: &dyn Ctx, args: CountArgs) -> Result<Success, Failure> {
        let CountArgs { n, label } = args;
        if n == 0 {
            return Err(Failure::bad_request("n starts at 1"));
        }
        let _ = ctx.progress(Some(1.0), "done");
        Ok(Success::data(json!({ "n": n, "label": label })))
    }

    #[command(name = "who am-i", changes, help = "say who called", timeout = 120)]
    fn who(_ctx: &dyn Ctx, _args: (), req: &Request) -> Result<Success, hobnix_pkg::Error> {
        if req.argv.is_empty() {
            Ok(Success::text(format!("{:?}", req.caller)))
        } else {
            Err(hobnix_pkg::Error::bad_request("no"))
        }
    }

    fn table() -> Commands {
        commands!(package = "demo", script = "@/bin/demo", count, who)
    }

    const ROWS: &str = "user\text demo count\t@/bin/demo\t-\tcount to n\tzählt bis n\ttopic:system,reads,proto\n\
                        sys\tsys ext demo count\t@/bin/demo\t-\tthe count as data\t-\treads,proto\n\
                        user\text demo who am-i\t@/bin/demo\t-\tsay who called\t-\tchanges,timeout:120,proto\n";

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

    fn call(command: &[&str], argv: &[&str]) -> (u8, Vec<Value>) {
        let line = json!({"v":1,"type":"request","id":"0123456789abcdef","command":command,"argv":argv,"lang":"en","caller":"web","timeout_ms":30000});
        let out = Buf::default();
        let code = table().run_with(&mut Cursor::new(format!("{line}\n")), out.clone());
        let text = String::from_utf8(out.0.lock().unwrap().clone()).unwrap();
        (
            code,
            text.lines()
                .map(|l| serde_json::from_str(l).unwrap())
                .collect(),
        )
    }

    #[test]
    fn the_rows_come_from_the_attributes_in_list_order() {
        assert_eq!(table().tsv(), ROWS);
        let names: Vec<&str> = table()
            .list()
            .iter()
            .map(hobnix_pkg_command::Command::words)
            .collect();
        assert_eq!(names, ["count", "who am-i"]);
        let spec = table().list()[0].args();
        assert_eq!(
            (spec[0].name, spec[0].kind, spec[0].type_name, spec[0].help),
            ("n", ArgKind::Required, "u32", "the last number")
        );
        assert_eq!(spec[1].kind, ArgKind::Optional);
        assert_eq!(<CountArgs as Args>::SPEC.len(), 2);
    }

    #[test]
    fn dispatches_by_the_command_words() {
        let (code, lines) = call(&["count"], &["3", "x"]);
        assert_eq!(code, 0);
        assert_eq!(lines[0]["type"], "progress");
        assert_eq!(
            lines[1],
            json!({"v":1,"type":"result","ok":true,"data":{"n":3,"label":"x"}})
        );
        let (code, lines) = call(&["who", "am-i"], &[]);
        assert_eq!((code, lines[0]["text"].as_str()), (0, Some("Web")));
    }

    #[test]
    fn refuses_unknown_commands_and_bad_arguments() {
        let (code, lines) = call(&["nothing"], &[]);
        assert_eq!(
            (code, lines[0]["error"]["code"].as_str()),
            (1, Some("not_found"))
        );
        assert_eq!(lines[0]["error"]["message"], "no such command: nothing");
        let (_, lines) = call(&["count"], &["x"]);
        assert_eq!(lines[0]["error"]["code"], "bad_request");
        assert_eq!(
            lines[0]["error"]["message"],
            "argument n: cannot read 'x' as u32; usage: count <n> [label]"
        );
        let (_, lines) = call(&["count"], &[]);
        assert_eq!(
            lines[0]["error"]["message"],
            "missing argument n; usage: count <n> [label]"
        );
        let (_, lines) = call(&["who", "am-i"], &["extra"]);
        assert_eq!(
            lines[0]["error"]["message"],
            "too many arguments; usage: who am-i"
        );
    }

    #[test]
    fn the_drift_check_sees_a_changed_row_and_a_changed_handler() {
        let file = format!(
            "# kind\tpath\tscript\targs\thelp\thelp.de\tflags\n{ROWS}user\text demo other\t@/other.sh\t-\tx\t-\treads\n"
        );
        assert_eq!(table().check(&file), Ok(()));
        // a row edited by hand
        assert!(
            table()
                .check(&file.replace("count to n", "count up to n"))
                .is_err()
        );
        // a row missing, as when a handler was added to commands! but not to the file
        assert!(
            table()
                .check(&file.replace("user\text demo who am-i", "#"))
                .is_err()
        );
        // a handler with another help than the file (the file of an older build)
        let older = Commands::check(&table(), &file.replace("changes,timeout:120", "changes"));
        assert!(
            older
                .unwrap_err()
                .to_string()
                .contains("they must be:\nuser\text demo count")
        );
    }

    #[test]
    fn the_table_is_in_the_program_file() {
        // what `hs pkg validate` reads: the marker, the rows, a NUL, in the bytes of this test program
        let exe = std::fs::read(std::env::current_exe().unwrap()).unwrap();
        let mut want = hobnix_pkg_command::TABLE_START.to_vec();
        want.extend_from_slice(ROWS.as_bytes());
        want.push(0);
        assert!(exe.windows(want.len()).any(|w| w == want.as_slice()));
    }

    #[test]
    fn refused_inputs_fail_to_compile_with_their_message() {
        trybuild::TestCases::new().compile_fail("tests/ui/*.rs");
    }
}
