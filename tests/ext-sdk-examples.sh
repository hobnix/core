#!/usr/bin/env bash
# The shell and Python helpers and the three examples of the extension SDK (sdk/examples, scripts/lib/ext_sdk.sh and ext_sdk.py,
# docs/extensions-sdk.md, issue #197): each example is driven by the reference runner (scripts/lib/ext_proto.py, ADR 0010) and must answer
# the same way. Needs python3 and jq; the Go example runs only where `go` exists (it prints a skip line otherwise). Rust: ext-sdk-rust.sh.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
command -v python3 >/dev/null || { echo "  skip  python3 missing"; exit 77; }
command -v jq >/dev/null || { echo "  skip  jq missing"; exit 77; }
export HS_SCRIPTS=$SCRIPTS
RUN="python3 -I $SCRIPTS/lib/ext_proto.py"
EX=$ROOT/sdk/examples
GOEXE=
if command -v go >/dev/null; then
  if (cd "$EX/go" && go build -o "$WORK/hello-go" .) > "$WORK/go.log" 2>&1; then GOEXE=$WORK/hello-go
  else fail "go build of the example: $(tail -n 5 "$WORK/go.log" | tr '\n' ' ')"; fi
else
  echo "  skip  go missing: the Go example is not tested here"
fi

BADV='{"v":2,"type":"request"}'
for lang in shell python go; do
  case $lang in
    shell) prog=$EX/shell/hello.sh; direct="bash $prog" ;;
    python) prog=$EX/python/hello.py; direct="python3 -I $prog" ;;
    go) [ -n "$GOEXE" ] || continue; prog=$GOEXE; direct=$GOEXE ;;
  esac
  echo "-- $lang example"
  rc=0; out=$($RUN call --command greet --arg Ada -- "$prog" 2>&1) || rc=$?
  check_eq "$lang: greet exits 0" 0 "$rc"
  check_out "$lang: greet answers with data" '"greeting":"hello Ada"' printf '%s' "$out"
  check_out "$lang: greet passes the event on" 'pkg.hello.greeted' printf '%s' "$out"
  rc=0; out=$($RUN call --command greet --arg 'Ada Lovelace' -- "$prog" 2>&1) || rc=$?
  check_out "$lang: an argument with a space stays one argument" 'hello Ada Lovelace' printf '%s' "$out"
  rc=0; out=$($RUN call --command count --arg 3 -- "$prog" 2>&1) || rc=$?
  check_eq "$lang: count exits 0" 0 "$rc"
  check_out "$lang: count reports progress" 'step 2 of 3' printf '%s' "$out"
  check_out "$lang: count answers with data" '"counted":3' printf '%s' "$out"
  rc=0; out=$($RUN call --command count --arg 99 -- "$prog" 2>&1) || rc=$?
  check_eq "$lang: a bad argument is a failure with exit 1" 1 "$rc"
  check_out "$lang: with the code bad_request" '"code":"bad_request"' printf '%s' "$out"
  rc=0; out=$($RUN call --command nosuch -- "$prog" 2>&1) || rc=$?
  check_out "$lang: an unknown command is not_found" '"code":"not_found"' printf '%s' "$out"
  rc=0; out=$(printf '%s\n' "$BADV" | $direct 2>&1) || rc=$?
  check_eq "$lang: an unknown version exits 1" 1 "$rc"
  check_out "$lang: and says unsupported_version" '"code":"unsupported_version"' printf '%s' "$out"
done
finish
