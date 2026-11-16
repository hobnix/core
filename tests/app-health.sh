#!/usr/bin/env bash
# The declared health of apps (docs/PLAN-app-lifecycle.md step 10): app_health.py runs the [app.health] check of a recipe against fake http and tcp
# targets on 127.0.0.1 (HS_APP_HEALTH_HOST); the states merge turns a failing check into stage on + flag unhealthy. No root, no incus.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
export HS_LANG=en HS_PLAIN=1 HS_STATE_DIR=$WORK/state
tab=$'\t'
T=$WORK/tree; mkdir -p "$HS_STATE_DIR" "$T/packages"
export HS_PACKAGES_ROOT=$T
mk() { mkdir -p "$T/packages/$1"; printf 'name = "%s"\nkind = "recipe"\nversion = "1.0.0"\n%s\n' "$1" "$2" > "$T/packages/$1/package.toml"; }

# fake targets: an http server answering 200 on /ok and 500 on /bad, and a tcp port that only accepts
cat > "$WORK/fake.py" <<'PY'
import http.server, socket, sys, threading
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200 if self.path == "/ok" else 500); self.end_headers()
    def log_message(self, *a): pass
web = http.server.HTTPServer(("127.0.0.1", 0), H)
tcp = socket.socket(); tcp.bind(("127.0.0.1", 0)); tcp.listen(5)
dead = socket.socket(); dead.bind(("127.0.0.1", 0)); dp = dead.getsockname()[1]; dead.close()
print(web.server_port, tcp.getsockname()[1], dp, flush=True)
threading.Thread(target=lambda: [tcp.accept()[0].close() for _ in iter(int, 1)], daemon=True).start()
web.serve_forever()
PY
python3 "$WORK/fake.py" > "$WORK/ports" &
FAKE=$!
trap 'kill $FAKE 2>/dev/null' EXIT
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$WORK/ports" ] && break; sleep 0.3; done
read -r WEB TCP DEAD < "$WORK/ports"

mk httpok "[app.health]
check = \"http\"
port = $WEB
path = \"/ok\""
mk httpbad "[app.health]
check = \"http\"
port = $WEB
path = \"/bad\""
mk tcpok "[app.health]
check = \"tcp\"
port = $TCP"
mk tcpdown "[app.health]
check = \"tcp\"
port = $DEAD
timeout = 1"
mk ctonly "[app.health]
check = \"container\""
mk stopped "[app.health]
check = \"tcp\"
port = $TCP"
mk plain ""
mk nocheck "[app]
instances = \"one\""

R=$WORK/recipes; : > "$R"
for n in httpok httpbad tcpok tcpdown ctonly stopped plain nocheck; do printf '%s\t%s\t%s\tinstalled\n' "$n" "x" "$n" >> "$R"; done
printf '%s\n' "httpok,RUNNING" "httpbad,RUNNING" "tcpok,RUNNING" "tcpdown,RUNNING" "ctonly,RUNNING" "stopped,STOPPED" "plain,RUNNING" "nocheck,RUNNING" > "$WORK/running"
: > "$WORK/addr"
export HS_APP_HEALTH_HOST=127.0.0.1
H() { python3 -I "$SCRIPTS/app_health.py" --recipes "$R" --running "$WORK/running" --addr "$WORK/addr" | tr -d '\r'; }
H > "$WORK/health"

echo "-- the declared check"
check_out "http 200 is healthy" "^httpok${tab}healthy\$" cat "$WORK/health"
check_out "http 500 is unhealthy" "^httpbad${tab}unhealthy\$" cat "$WORK/health"
check_out "a tcp port that accepts is healthy" "^tcpok${tab}healthy\$" cat "$WORK/health"
check_out "a tcp port nobody listens on is unhealthy" "^tcpdown${tab}unhealthy\$" cat "$WORK/health"
check_out "the container check is healthy while it runs" "^ctonly${tab}healthy\$" cat "$WORK/health"
check_out "a stopped instance is stopped, not probed" "^stopped${tab}stopped\$" cat "$WORK/health"
check_eq "an app without [app.health] has no row" "0" "$(grep -c '^plain\|^nocheck' "$WORK/health")"
check_eq "one row per declaring app" "6" "$(wc -l < "$WORK/health" | tr -d ' ')"
unset HS_APP_HEALTH_HOST
check_out "without the knob and without an address a tcp check is unhealthy" "^tcpok${tab}unhealthy\$" H

echo "-- the states merge"
M=$WORK/m; mkdir -p "$M"
printf '%s\n' "httpok${tab}recipe${tab}repo${tab}1.0.0${tab}1.0.0${tab}current${tab}no${tab}generic${tab}x" > "$M/market"
: > "$M/parts"; : > "$M/pending"
printf '%s\n' "httpok${tab}x${tab}httpok${tab}installed" > "$M/recipes"
printf '%s\n' "httpok,RUNNING" > "$M/running"
st() { python3 -I "$SCRIPTS/pkg.py" states --market "$M/market" --parts "$M/parts" --pending "$M/pending" --recipes "$M/recipes" --running "$M/running" "$@" | tr -d '\r'; }
printf 'httpok\tunhealthy\n' > "$M/h1"; printf 'httpok\thealthy\n' > "$M/h2"
check_out "a failing check on a running instance is on + unhealthy" "^httpok${tab}recipe${tab}on${tab}unhealthy${tab}" st --health "$M/h1"
check_out "a passing check is running" "^httpok${tab}recipe${tab}running${tab}-${tab}" st --health "$M/h2"
check_out "no health input is running as before" "^httpok${tab}recipe${tab}running${tab}-${tab}" st
check_eq "the row keeps nine fields" "0" "$(st --health "$M/h1" | awk -F'\t' 'NF != 9' | wc -l | tr -d ' ')"
finish
