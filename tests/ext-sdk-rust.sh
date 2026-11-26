#!/usr/bin/env bash
# The Rust package SDK (rust/hobnix-pkg, hobnix-pkg-command, hobnix-pkg-service; issues #240, #1262): its example extensions built with cargo and driven by the reference
# runners of the protocols (scripts/lib/ext_proto.py for commands, ADR 0010; scripts/lib/ext_service.py for services, ADR 0011).
# The API example (http client, integration listing, credential) runs against a local python server; the musl build only when the target is installed.
# The SDK's own unit tests are `cargo test -p hobnix-pkg -p hobnix-pkg-command -p hobnix-pkg-service -p hobnix-ext-sdk` (CI runs them).
# Skipped (77) without cargo or python3, or off Linux.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
command -v cargo >/dev/null || { echo "  skip  cargo missing"; exit 77; }
command -v python3 >/dev/null || { echo "  skip  python3 missing"; exit 77; }
[ "$(uname -s)" = Linux ] || { echo "  skip  needs Linux"; exit 77; }
export CARGO_TARGET_DIR=${CARGO_TARGET_DIR:-$ROOT/rust/target}
if ! (cd "$ROOT/rust" && cargo build --locked -q -p hobnix-pkg-command -p hobnix-pkg-service --examples) > "$WORK/build.log" 2>&1; then
  # most likely no network for the crates, or a toolchain older than rust-toolchain.toml wants: not this test's business
  if grep -q -E "failed to (get|download)|Could not resolve|unable to update registry|network" "$WORK/build.log"; then echo "  skip  crates not available (offline)"; exit 77; fi
  fail "cargo build of the examples: $(tail -n 5 "$WORK/build.log" | tr '\n' ' ')"; finish; exit
fi
EX=$CARGO_TARGET_DIR/debug/examples
RUN="python3 -I $SCRIPTS/lib/ext_proto.py"

echo "-- command example"
rc=0; out=$($RUN call --command greet --arg Ada -- "$EX/hello" 2>&1) || rc=$?
check_eq "greet exits 0" 0 "$rc"
check_out "greet answers with data" '"greeting":"hello Ada"' printf '%s' "$out"
check_out "greet passes the event on" 'pkg.hello.greeted' printf '%s' "$out"
rc=0; out=$($RUN call --command count --arg 99 -- "$EX/hello" 2>&1) || rc=$?
check_eq "a bad argument is a failure with exit 1" 1 "$rc"
check_out "with the code bad_request" '"code":"bad_request"' printf '%s' "$out"
rc=0; out=$($RUN call --command nosuch -- "$EX/hello" 2>&1) || rc=$?
check_out "an unknown command is not_found, not a protocol error" '"code":"not_found"' printf '%s' "$out"

echo "-- command example written with the macros (feature macros, #1263)"
if (cd "$ROOT/rust" && cargo build --locked -q -p hobnix-pkg-command --features macros --example hello_macro) > "$WORK/macro.log" 2>&1; then
  rc=0; out=$($RUN call --command greet --arg Ada -- "$EX/hello_macro" 2>&1) || rc=$?
  check_eq "greet exits 0" 0 "$rc"
  check_out "greet answers with data" '"greeting":"hello Ada"' printf '%s' "$out"
  rc=0; out=$($RUN call --command count --arg x -- "$EX/hello_macro" 2>&1) || rc=$?
  check_out "an argument that is no number is bad_request with the usage" 'cannot read .x. as u32; usage: count <n>' printf '%s' "$out"
  rc=0; out=$($RUN call --command nosuch -- "$EX/hello_macro" 2>&1) || rc=$?
  check_out "an unknown command is not_found" '"code":"not_found"' printf '%s' "$out"
  # the drift check of validate reads the rows from the program file (never runs it)
  P=$WORK/hello; mkdir -p "$P/bin"; cp "$EX/hello_macro" "$P/bin/hello"
  "$EX/hello_macro" --commands-tsv > "$P/commands.tsv"
  drift() { python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); import pkg_binary as b; print(b.drift(sys.argv[2], "bin/hello", "w"))' "$SCRIPTS/lib" "$P"; }
  check_out "the rows the program prints are the rows validate reads from its file" '^\[\]$' drift
  check_eq "three rows: greet, count and the sys row of count" 3 "$(wc -l < "$P/commands.tsv")"
  sed -i 's/greet someone/greet anyone/' "$P/commands.tsv"
  check_out "a changed row is drift" 'binary.drift' drift
else fail "cargo build of hello_macro: $(tail -n 5 "$WORK/macro.log" | tr '\n' ' ')"; fi

echo "-- service example"
rc=0; out=$(python3 -I "$SCRIPTS/lib/ext_service.py" run --name ticker --health-interval 1 --run-for 2.5 -- "$EX/ticker" 2>&1) || rc=$?
check_eq "the service runs and stops cleanly" 0 "$rc"
check_out "it publishes snapshots" '"topic":"ticks"' printf '%s' "$out"
check_out "it ends in the state stopped" '"final","state":"stopped"' printf '%s' "$out"

echo "-- API example (http client, integration listing, credential)"
mkdir -p "$WORK/cred"; printf 's3cret\n' > "$WORK/cred/integration-jf-media-hub"
cat > "$WORK/srv.py" <<'PY'
import http.server, json, sys
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        b = json.dumps({"path": self.path, "key": self.headers.get("X-Emby-Token")}).encode()
        self.send_response(200); self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def log_message(self, *a): pass
s = http.server.HTTPServer(("127.0.0.1", 0), H)
print(s.server_address[1], flush=True)
s.handle_request(); s.handle_request()
PY
python3 -I "$WORK/srv.py" > "$WORK/port" &
SRV=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$WORK/port" ] && break; sleep 0.3; done
PORT=$(cat "$WORK/port")
printf 'media-hub\tjf\trecipe\thttp://127.0.0.1:%s\t-\t-\tX-Emby-Token\nmedia-hub\tnokey\trecipe\thttp://127.0.0.1:%s\t-\t-\t-\n' "$PORT" "$PORT" > "$WORK/listing.tsv"
rc=0; out=$(CREDENTIALS_DIRECTORY=$WORK/cred $RUN call --command get --arg "$WORK/listing.tsv" --arg jf --arg /System/Info -- "$EX/apiprobe" 2>&1) || rc=$?
check_eq "apiprobe exits 0" 0 "$rc"
check_out "it sent the key from the credential in the key header" '"key":"s3cret"' printf '%s' "$out"
check_out "it asked for the path" '"path":"/System/Info"' printf '%s' "$out"
rc=0; out=$(CREDENTIALS_DIRECTORY=$WORK/cred $RUN call --command get --arg "$WORK/listing.tsv" --arg nokey --arg /x -- "$EX/apiprobe" 2>&1) || rc=$?
check_out "a row without a key header sends no key" '"key":null' printf '%s' "$out"
kill "$SRV" 2>/dev/null; wait "$SRV" 2>/dev/null
rc=0; out=$($RUN call --command get --arg "$WORK/listing.tsv" --arg nosuch --arg /x -- "$EX/apiprobe" 2>&1) || rc=$?
check_out "an unknown integration is bad_request" '"code":"bad_request"' printf '%s' "$out"

echo "-- static musl build"
# asked in rust/: the target belongs to the toolchain that rust-toolchain.toml names, not to rustup's default
if (cd "$ROOT/rust" && rustup target list --installed 2>/dev/null) | grep -q x86_64-unknown-linux-musl; then
  if (cd "$ROOT/rust" && cargo build --locked -q --release --target x86_64-unknown-linux-musl -p hobnix-pkg-command --example apiprobe) > "$WORK/musl.log" 2>&1; then
    ok_file=$CARGO_TARGET_DIR/x86_64-unknown-linux-musl/release/examples/apiprobe
    check_out "the musl build is statically linked" 'statically linked|static-pie linked' sh -c "file '$ok_file'"
  else fail "musl build: $(tail -n 5 "$WORK/musl.log" | tr '\n' ' ')"; fi
  if (cd "$ROOT/rust" && cargo build --locked -q --release --target x86_64-unknown-linux-musl -p hobnix-pkg-command --features macros --example hello_macro) > "$WORK/musl.log" 2>&1; then
    m=$CARGO_TARGET_DIR/x86_64-unknown-linux-musl/release/examples/hello_macro
    check_out "the musl release build with the macros keeps the rows in the file" 'ext hello greet' python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); import pkg_binary as b; print(b.built_rows(sys.argv[2]))' "$SCRIPTS/lib" "$m"
  else fail "musl build of hello_macro: $(tail -n 5 "$WORK/musl.log" | tr '\n' ' ')"; fi
else echo "  skip  target x86_64-unknown-linux-musl not installed (rustup target add)"; fi
finish
