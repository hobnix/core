# shellcheck shell=bash
# Stand-ins and helpers for the tests that record how starting and stopping an app behaves (tests/app-start-stop*.sh, sourced after
# tests/lib.sh). No root, no Incus, no systemd, no network.
#
# The program under test is HS_UNDER_TEST: the words that stand for `hs` (default: the dispatcher of this checkout). A command that moved to
# Rust behind its registry row runs through the same dispatcher with HOBNIX_BIN (docs/adr/0001-rust-strangler.md), which also picks the job
# record writer. Everything that is observed is outside the program: stdout, stderr, the exit code, what the fake incus was told to do, the
# job record (hs sys jobs record), the event log (hs sys event list) and the change counters (table `topics` of the state database).
#
# The stand-ins sit where the system starts: incus, systemd-run, systemctl, journalctl, curl, logger. An implementation that talks to Incus
# or systemd without these programs (their sockets) needs other stand-ins; the assertions stay.
#
# The fake systemd-run starts nothing. The test runs the unit later (run_unit, or run_unit_bg for a cancel), with a clean environment plus
# the -E words, as a transient unit gets one. A unit that ended well or was stopped is gone afterwards (LoadState not-found, Result success,
# exit status 0), a failed one stays loaded: what systemd 25x showed for transient user units on a developer machine (2026-11-26). Not
# compared with system units on a real server.

T=$'\t'
BIN=$WORK/bin; mkdir -p "$BIN"
export FAKE=$WORK/fake
mkdir -p "$FAKE"
read -ra HS_CMD <<<"${HS_UNDER_TEST:-bash $SCRIPTS/lib/hs.sh}"

unset HS_CALLER HS_ACTOR HS_OWNER HS_JOB_ID HS_JOB_UNIT HS_JOB_KEY HS_JOB_INITIATOR HS_JOB_ENV HS_JOB_PARENT HS_JOB_KIND HS_JOB_NOBUMP \
  HS_LIVE_LOG HS_LIVE_WAKE_LOG HS_AUDIT_OFF HS_AUDIT_FORCE HS_PLAIN HS_GUIDED_TTY HS_INCUS HS_SYSTEMCTL HS_DOCKER_NO_JOB HS_DOCKER_SH \
  HS_MANAGE_CT HS_CT_CHANGE HS_CT_BINDINGS HS_JOBS HS_NOTIFY_URL HS_NOTIFY_URL_SECOND HS_NOTIFY_CHANNELS_DIR HS_NOTIFY_STRICT \
  HS_REGISTRY HS_EVENT_TOPICS HS_LIVE_TOPICS HS_VAULT_OPEN HS_VAULT_DIR HS_ASK_DIR HS_RUN_DIR HS_ASK_TIMEOUT HS_FORCE_TTY SUDO_USER \
  HS_UPDATE_YES HS_SCRIPTS HS_PYTHON
export HS_LANG=en HS_EVENT_NOROOT=1 PYTHONDONTWRITEBYTECODE=1
export HS_STATE_DIR=$WORK/state HS_STATE_DB=$WORK/state/state.db HS_JOBS_DIR=$WORK/jobs HS_SETTINGS_DIR=$WORK/settings \
  HS_CAPABILITIES_FILE=$WORK/capabilities HS_PACKAGES_DIR=$WORK/packages HS_ETC_DIR=$WORK/etc
mkdir -p "$HS_STATE_DIR" "$HS_SETTINGS_DIR" "$HS_PACKAGES_DIR" "$HS_ETC_DIR"
printf 'incus\ndocker\n' > "$HS_CAPABILITIES_FILE"

# ── the fake system ──
cat > "$BIN/systemd-run" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" | tr '\n' ' ' >> "$FAKE/systemd-run.log"; echo >> "$FAKE/systemd-run.log"
if [ -e "$FAKE/run-fail" ]; then echo "Failed to start transient service unit: stand-in" >&2; exit 1; fi
unit="" desc="" envs=() props=()
while [ $# -gt 0 ]; do
  case "$1" in
    --unit=*) unit=${1#--unit=} ;;
    --description=*) desc=${1#--description=} ;;
    --property=*) props+=("${1#--property=}") ;;
    -E) envs+=("$2"); shift ;;
    --*) ;;
    *) break ;;
  esac
  shift
done
d=$FAKE/units/$unit.service
if [ -e "$d/loadstate" ] && [ "$(cat "$d/loadstate")" = loaded ]; then echo "Unit $unit.service already exists." >&2; exit 1; fi
mkdir -p "$d"
printf '%s\0' "${envs[@]}" > "$d/env"
printf '%s\n' "${envs[@]}" > "$d/env.txt"
printf '%s\n' "${props[@]}" > "$d/props"
printf '%s\0' "$@" > "$d/argv"
printf '%s\n' "$desc" > "$d/description"
echo loaded > "$d/loadstate"; echo active > "$d/active"; echo success > "$d/result"; echo 0 > "$d/status"
echo "Started $desc." > "$d/journal"
FAKE

cat > "$BIN/systemctl" <<'FAKE'
#!/usr/bin/env bash
svc() { case "$1" in *.service|*.timer|*.scope) printf '%s' "$1" ;; *) printf '%s.service' "$1" ;; esac; }
get() { cat "$FAKE/units/$1/$2" 2>/dev/null || printf '%s' "$3"; }
case "$1" in
  show)
    u=$(svc "$2"); load=$(get "$u" loadstate not-found)
    case "$4" in
      LoadState) echo "$load" ;;
      ActiveState) get "$u" active inactive; echo ;;
      Result) if [ "$load" = loaded ]; then get "$u" result success; else echo success; fi ;;
      ExecMainStatus) if [ "$load" = loaded ]; then get "$u" status 0; else echo 0; fi ;;
      Description) if [ "$load" = loaded ]; then get "$u" description "$u"; else echo "$u"; fi ;;
      ActiveEnterTimestamp|ExecMainExitTimestamp) [ "$load" != loaded ] || get "$u" "$4" ""; echo ;;
      *) echo ;;
    esac ;;
  is-active)
    a=$(get "$(svc "${!#}")" active inactive); echo "$a"; [ "$a" = active ] ;;
  list-units)
    for d in "$FAKE"/units/hs-job-*.service; do
      [ -d "$d" ] || continue
      [ "$(cat "$d/active")" != active ] || printf '%s loaded active running %s\n' "${d##*/}" "$(cat "$d/description")"
    done ;;
  list-timers) ;;
  stop)
    shift
    printf 'stop %s\n' "$*" >> "$FAKE/systemctl.log"
    [ ! -e "$FAKE/stop-fail" ] || { echo "Failed to stop $1: stand-in" >&2; exit 1; }
    u=$(svc "$1"); d=$FAKE/units/$u
    [ -d "$d" ] || exit 0
    if [ -s "$d/pgid" ]; then   # KillMode=control-group: SIGTERM to everything in the unit
      p=$(cat "$d/pgid")
      kill -TERM -- "-$p" 2>/dev/null
      for _ in $(seq 1 50); do kill -0 -- "-$p" 2>/dev/null || break; sleep 0.1; done
      kill -KILL -- "-$p" 2>/dev/null
    fi
    echo not-found > "$d/loadstate"; echo inactive > "$d/active"
    echo "Stopped $(cat "$d/description")." >> "$d/journal" ;;
  *) printf 'unexpected systemctl %s\n' "$*" >> "$FAKE/unexpected" ;;
esac
exit 0
FAKE

cat > "$BIN/journalctl" <<'FAKE'
#!/usr/bin/env bash
u=""
while [ $# -gt 0 ]; do case "$1" in -u|-fu) u=$2; shift 2 ;; *) shift ;; esac; done
case "$u" in *.service) ;; *) u=$u.service ;; esac
cat "$FAKE/units/$u/journal" 2>/dev/null
exit 0
FAKE

# incus: instances are folders $FAKE/ct/<name> (state, autostart, owner, type). What changes the system goes to $FAKE/changes.
# Knobs (files in $FAKE): fail-<verb> (holds the exit status), hang-<verb> (waits until the file release is there, at most 30 s; writes
# `hanging` first), down (the daemon does not answer). <verb> is start, stop, restart or compose.
cat > "$BIN/incus" <<'FAKE'
#!/usr/bin/env bash
if [ -e "$FAKE/down" ]; then echo "Error: Get \"http://unix.socket/1.0\": dial unix: connect: connection refused" >&2; exit 1; fi
state() { cat "$FAKE/ct/$1/state"; }
knobs() {   # knobs <verb>
  if [ -e "$FAKE/hang-$1" ]; then
    : > "$FAKE/hanging"
    for _ in $(seq 1 300); do [ ! -e "$FAKE/release" ] || break; sleep 0.1; done
  fi
  if [ -e "$FAKE/fail-$1" ]; then echo "Error: stand-in failure of $1" >&2; exit "$(cat "$FAKE/fail-$1")"; fi
}
case "$1" in
  info) [ -d "$FAKE/ct/$2" ] || { echo "Error: Instance not found" >&2; exit 1; } ;;
  query)
    n=${2#/1.0/instances/}; [ -d "$FAKE/ct/$n" ] || exit 1
    jq -n --arg o "$(cat "$FAKE/ct/$n/owner" 2>/dev/null)" --arg s "$(state "$n")" \
      '{type:"container",status:$s,config:(if $o=="" then {} else {"user.hs.managed_by":$o} end),expanded_devices:{eth0:{hwaddr:"10:66:6a:00:00:01"}}}' ;;
  list)
    case "$*" in
      *"-c s") state "$2" 2>/dev/null ;;
      *"-c 4") printf '"192.0.2.5 (eth0)"\n' ;;
    esac ;;
  start|stop|restart)
    [ -d "$FAKE/ct/$2" ] || { echo "Error: Instance not found" >&2; exit 1; }
    printf 'incus %s\n' "$*" >> "$FAKE/changes"
    knobs "$1"
    case "$1:$(state "$2")" in
      start:RUNNING) echo "Error: The instance is already running" >&2; exit 1 ;;
      stop:STOPPED|restart:STOPPED) echo "Error: The instance is already stopped" >&2; exit 1 ;;
      stop:*) echo STOPPED > "$FAKE/ct/$2/state" ;;
      *) echo RUNNING > "$FAKE/ct/$2/state" ;;
    esac ;;
  config)
    case "$2" in
      unset|set) printf 'incus %s\n' "$*" >> "$FAKE/changes"; [ "$2:$4" != unset:boot.autostart ] || rm -f "$FAKE/ct/$3/autostart" ;;
      get) ;;
      device) exit 1 ;;
    esac ;;
  exec)
    n=$2; shift 3   # exec <name> -- <command...>
    if [ "$n" != docker ]; then
      [ "$1" != ps ] || printf 'immich 1000 1000 node\npostgres 999 999 postgres\n'
      exit 0
    fi
    if [ "$1" = docker ] && [ "$2" = ps ]; then
      [ -e "$FAKE/no-arr" ] || printf 'arr\trunning\t0.0.0.0:8989->8989/tcp\n'
      printf 'arcane\trunning\t-\n'
      exit 0
    fi
    script=$3; shift 4   # sh -c <script> sh <words...>
    case "$script" in
      *'ls -d /opt/apps/'*) printf '/shares/apps/stacks/kept/docker-compose.yml\n' ;;   # an app with a folder and no container
      *'recipes/$a'*) printf 'web\t/shares/apps/stacks/%s\n' "$1" ;;
      *'config --images'*) printf 'ghcr.io/example/app:1\n' ;;
      *'docker compose -p "$1" "$2"'*) printf 'compose %s %s\n' "$2" "$1" >> "$FAKE/changes"; knobs compose ;;
      *'docker compose -p "$app" "$@"'*)
        cat >/dev/null; app=$1; dir=$2; shift 2
        printf 'compose %s %s (in %s)\n' "$*" "$app" "$dir" >> "$FAKE/changes"; knobs compose ;;
      *) printf 'unexpected script in docker: %s\n' "${script:0:80}" >> "$FAKE/unexpected" ;;
    esac ;;
  *) printf 'unexpected incus %s\n' "$*" >> "$FAKE/unexpected" ;;
esac
exit 0
FAKE

printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" | tr "\\n" " " >> "$FAKE/pushes"; echo >> "$FAKE/pushes"\n' > "$BIN/curl"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/logger"
chmod +x "$BIN"/*
export PATH="$BIN:$PATH"
echo "https://push.example.invalid/topic" > "$HS_STATE_DIR/notify-url"

# ── state of the fake system ──
reset_fakes() {   # no instances, no units, no jobs; the event log and the counters stay (see mark)
  rm -rf "$FAKE" "$HS_JOBS_DIR"
  mkdir -p "$FAKE/ct" "$FAKE/units"
  : > "$FAKE/changes"; : > "$FAKE/pushes"; : > "$FAKE/systemctl.log"; : > "$FAKE/systemd-run.log"
}
instance() {   # instance <name> <RUNNING|STOPPED> [owner]
  mkdir -p "$FAKE/ct/$1"; echo "$2" > "$FAKE/ct/$1/state"; : > "$FAKE/ct/$1/autostart"; printf '%s' "${3:-}" > "$FAKE/ct/$1/owner"
}
changes() { cat "$FAKE/changes"; }
pushes() { grep -c . "$FAKE/pushes" || true; }
job_files() { find "$HS_JOBS_DIR" -name '*.json' 2>/dev/null | wc -l | tr -d ' '; }

# ── the program under test ──
# as_web: the way scripts/web-serve.py calls a row (HS_CALLER=web from the unit of hs-web, HS_ACTOR = the signed-in person). USER=root is
# a stand-in: the unit of hs-web names no User=, what USER holds there was not looked at.
# as_person: a person at the command line of the server (as root through sudo is not simulated). Both set RC, OUT, ERR.
_hs() {
  RC=0
  env "$@" > "$WORK/out" 2> "$WORK/err" < /dev/null || RC=$?
  OUT=$(cat "$WORK/out")
  # shellcheck disable=SC2034  # read by the tests
  ERR=$(cat "$WORK/err")
}
as_web() { _hs HS_CALLER=web HS_ACTOR=anna USER=root timeout 60 "${HS_CMD[@]}" "$@"; }
as_person() { _hs USER=tester timeout 60 "${HS_CMD[@]}" "$@"; }

# lines <line>...: the arguments as lines, every | a tab (the shape of the machine-readable output)
lines() { local l out=""; for l in "$@"; do out+="${l//|/$T}"$'\n'; done; printf '%s' "${out%$'\n'}"; }
check_run() {   # check_run "what" <exit> <stdout>: the last as_web / as_person call
  check_eq "$1: exit $2" "$2" "$RC"
  check_eq "$1: stdout" "$3" "$OUT"
}

# norm: clock times and the random part of job ids out of a text
norm() { sed -E 's/[0-9]{8}-[0-9]{6}-([A-Za-z0-9-]+)-[a-z]{4}/ID-\1/g; s/(hs-job-[A-Za-z0-9-]+)-[0-9]{6}/\1-HHMMSS/g'; }

# ── job units ──
unit_of_output() { awk -F'\t' '$1 == "unit" { print $2 }' <<<"$OUT"; }
_unit_command() {   # _unit_command <unit>: sets UNIT_DIR, UNIT_ENV and UNIT_ARGV
  UNIT_DIR=$FAKE/units/$1.service
  local -a given=()
  mapfile -d '' -t given < "$UNIT_DIR/env"
  mapfile -d '' -t UNIT_ARGV < "$UNIT_DIR/argv"
  # what the test itself needs to stay inside its sandbox, then what the program handed to the unit
  UNIT_ENV=("HOME=$HOME" "FAKE=$FAKE" "HS_EVENT_NOROOT=1" "PYTHONDONTWRITEBYTECODE=1" "HS_STATE_DIR=$HS_STATE_DIR" "HS_STATE_DB=$HS_STATE_DB"
    "HS_SETTINGS_DIR=$HS_SETTINGS_DIR" "HS_CAPABILITIES_FILE=$HS_CAPABILITIES_FILE" "HS_PACKAGES_DIR=$HS_PACKAGES_DIR" "HS_ETC_DIR=$HS_ETC_DIR"
    ${given[@]+"${given[@]}"})
}
_unit_ended() {   # _unit_ended <dir> <exit>: a unit that ended well is gone, a failed one stays loaded
  if [ "$2" -eq 0 ]; then echo not-found > "$1/loadstate"; echo inactive > "$1/active"
  else
    echo failed > "$1/active"; echo exit-code > "$1/result"; echo "$2" > "$1/status"
    echo "Thu 2026-01-01 10:00:00 UTC" > "$1/ActiveEnterTimestamp"; echo "Thu 2026-01-01 10:00:01 UTC" > "$1/ExecMainExitTimestamp"
  fi
}
run_unit() {   # run_unit <unit>: run the job to its end; sets JOB_RC
  _unit_command "$1"
  JOB_RC=0
  env -i "${UNIT_ENV[@]}" timeout 60 "${UNIT_ARGV[@]}" >> "$UNIT_DIR/journal" 2>&1 < /dev/null || JOB_RC=$?
  _unit_ended "$UNIT_DIR" "$JOB_RC"
}
run_unit_bg() {   # run_unit_bg <unit>: start it in a process group of its own and wait until a stand-in hangs; sets JOB_PID
  _unit_command "$1"
  rm -f "$FAKE/hanging" "$FAKE/release"
  setsid env -i "${UNIT_ENV[@]}" "${UNIT_ARGV[@]}" >> "$UNIT_DIR/journal" 2>&1 < /dev/null &
  JOB_PID=$!
  echo "$JOB_PID" > "$UNIT_DIR/pgid"
  local _
  for _ in $(seq 1 300); do [ ! -e "$FAKE/hanging" ] || return 0; sleep 0.1; done
  fail "the job of $1 never reached the hanging call: $(tail -n 3 "$UNIT_DIR/journal" | tr '\n' ' ')"
}
wait_unit() {   # wait_unit: the job of run_unit_bg ends (at most 40 s); sets JOB_RC
  local _
  for _ in $(seq 1 400); do kill -0 "$JOB_PID" 2>/dev/null || break; sleep 0.1; done
  if kill -0 "$JOB_PID" 2>/dev/null; then kill -KILL -- "-$JOB_PID" 2>/dev/null; fail "the job did not end in 40 s"; fi
  JOB_RC=0; wait "$JOB_PID" 2>/dev/null || JOB_RC=$?
}
_end_units() {   # nothing of a job outlives the test
  local f
  for f in "$FAKE"/units/*/pgid; do
    [ ! -s "$f" ] || kill -KILL -- "-$(cat "$f")" 2>/dev/null
  done
  cleanup
}
trap _end_units EXIT

# ── the job record ──
job_id_of() {   # job_id_of <unit>: the id of the record of a unit
  local f
  f=$(grep -lE "\"unit\": *\"$1\"" "$HS_JOBS_DIR"/*.json 2>/dev/null | head -n 1)
  f=${f##*/}; printf '%s' "${f%.json}"
}
record() {   # record <id>: the record through `hs sys jobs record`, one field=value line each in the order of the file, times as T
  as_web sys jobs record "$1"
  python3 -c '
import json, sys
r = json.loads(sys.argv[1])
for k in ("queued", "started", "ended"):
    if r.get(k): r[k] = "T"
if r.get("cancel") and r["cancel"].get("at"): r["cancel"]["at"] = "T"
for k, v in r.items(): print("%s=%s" % (k, json.dumps(v, separators=(",", ":"))))
' "$OUT" | norm
}
field() { awk -F= -v k="$2" '$1 == k { sub(/^[^=]*=/, ""); print }' <<<"$1"; }   # field "<record>" <name>

# ── the event log and the change counters ──
_last_event() { env HS_CALLER=test timeout 60 "${HS_CMD[@]}" sys event list 1 </dev/null 2>/dev/null | cut -f1; }
_snapshot() {   # the change counters as topic<TAB>count
  python3 - <<'PY'
import os, sqlite3
try:
    c = sqlite3.connect("file:%s?mode=ro" % os.environ["HS_STATE_DB"], uri=True)
    for t, g in c.execute("SELECT topic, gen FROM topics ORDER BY topic"):
        print("%s\t%d" % (t, g))
except sqlite3.Error:
    pass
PY
}
mark() {   # mark: what happens from here on is "new"
  MARK_EVENT=$(_last_event); MARK_EVENT=${MARK_EVENT:-0}
  _snapshot > "$WORK/topics.before"
}
new_events() {   # the events since mark, oldest first, as kind|subject|level|text|payload
  env HS_CALLER=test timeout 60 "${HS_CMD[@]}" sys event list 500 --after "$MARK_EVENT" </dev/null 2>/dev/null |
    awk -F'\t' '{ print $3 "." $4 "|" $5 "|" $6 "|" $7 "|" $8 }' | norm
}
check_events() {   # check_events "what" [line...]: exactly these events since mark, in this order
  local what=$1; shift
  local want="" l
  for l in "$@"; do want+="$l"$'\n'; done
  check_eq "$what: events" "${want%$'\n'}" "$(new_events)"
}

# The refresh signals. A signal is a word of scripts/lib/live.sh: @<area> (every topic of that area and of `any`), event:<kind> (the topics of
# scripts/lib/event-topics.tsv), --all or one counter. Each signal counts each of its topics up by one, so the counters say which signals
# were said and how often.
topics_of() {   # topics_of <signal>: one topic per line
  local w
  case "$1" in
    --all) awk -F'\t' '$1 != "" && $1 !~ /^#/ { print $1 }' "$SCRIPTS/lib/live-topics.tsv" ;;
    @*) awk -F'\t' -v g="${1#@}" '$1 != "" && $1 !~ /^#/ { n = split($6, a, ","); for (i = 1; i <= n; i++) if (a[i] == g || a[i] == "any") { print $1; next } }' "$SCRIPTS/lib/live-topics.tsv" ;;
    event:*) for w in $(awk -F'\t' -v k="${1#event:}" '$1 == k { gsub(",", " ", $2); print $2 }' "$SCRIPTS/lib/event-topics.tsv"); do topics_of "$w"; done ;;
    *) printf '%s\n' "$1" ;;
  esac
}
check_signals() {   # check_signals "what" [signal...]: the counters moved since mark by exactly these signals (none = nothing moved)
  local what=$1 s want got
  shift
  want=$(for s in "$@"; do topics_of "$s" | sort -u; done | sort | uniq -c | awk '{ print $2 " " $1 }' | sort)
  _snapshot > "$WORK/topics.after"
  got=$(awk -F'\t' 'NR == FNR { b[$1] = $2; next } $2 != b[$1] + 0 { print $1 " " ($2 - b[$1]) }' "$WORK/topics.before" "$WORK/topics.after" | sort)
  # an empty first file makes NR == FNR true for the second one: handle it apart
  [ -s "$WORK/topics.before" ] || got=$(awk -F'\t' '{ print $1 " " $2 }' "$WORK/topics.after" | sort)
  if [ "$want" = "$got" ]; then pass "$what: refresh signals ${*:-none}"
  else fail "$what: refresh signals ${*:-none} (counters that differ, < expected > seen: $(diff <(printf '%s\n' "$want") <(printf '%s\n' "$got") | grep '^[<>]' | head -n 8 | tr '\n' ' '))"; fi
}

check_no_surprise() {   # nothing asked the fake system for something it does not know
  if [ -s "$FAKE/unexpected" ]; then fail "$1: a call the stand-ins do not know: $(head -n 3 "$FAKE/unexpected" | tr '\n' ' ')"; fi
}
