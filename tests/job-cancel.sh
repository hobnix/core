#!/usr/bin/env bash
# Cancelling a web job (ADR 0010 rule 7): `hs sys jobs start stop` on an hs_job unit sends SIGTERM to everything in the unit (systemd's
# default KillMode=control-group), so a job that traps SIGTERM runs its trap and writes `cancelled`, and its children are gone. Needs root
# and a running systemd (WSL with systemd, a VM); it skips otherwise.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
export HS_PLAIN=1 HS_LANG=en
unset HS_CALLER HS_GUIDED_TTY
sd=$(systemctl is-system-running 2>/dev/null || true)
if [ "$(id -u)" -ne 0 ] || { [ "$sd" != running ] && [ "$sd" != degraded ]; }; then
  skip "needs root and a running systemd"; finish; exit 0
fi

echo "-- the unit keeps the default kill mode"
if grep -nE 'KillMode|KillSignal|SendSIGKILL|SendSIGHUP' "$SCRIPTS/lib/job.sh" | grep -qv '^[0-9]*:#'; then
  fail "hs_job sets a kill property: SIGTERM no longer reaches the whole unit"
else pass "hs_job sets no kill property"; fi

echo "-- a job that traps SIGTERM"
export HS_JOBS_DIR=$WORK/jobs HS_STATE_DIR=$WORK/state HS_EVENT_NOROOT=1
mkdir -p "$HS_JOBS_DIR" "$WORK/state"
cat > "$WORK/job.sh" <<FIXTURE
#!/usr/bin/env bash
trap 'echo cancelled > "$WORK/result"; kill "\$child"; exit 143' TERM
sleep 300 & child=\$!
echo "\$child" > "$WORK/child"
wait
FIXTURE
cat > "$WORK/outer.sh" <<FIXTURE
#!/usr/bin/env bash
sleep 301 & echo \$! > "$WORK/grandchild"   # a child the job does not trap for
bash "$WORK/job.sh"
FIXTURE
chmod +x "$WORK/job.sh" "$WORK/outer.sh"
# shellcheck source=scripts/lib/job.sh
. "$SCRIPTS/lib/job.sh"
unit=$(hs_job cancel-fixture "Cancel fixture" -- bash "$WORK/outer.sh") || { fail "hs_job did not start"; finish; exit 0; }
for _ in $(seq 1 50); do [ -s "$WORK/child" ] && [ -s "$WORK/grandchild" ] && break; sleep 0.1; done
run_rc=0; out=$(timeout 60 bash "$SCRIPTS/jobs-change.sh" start stop "$unit" </dev/null 2>/dev/null) || run_rc=$?
check_eq "stop: exit 0" 0 "$run_rc"
for _ in $(seq 1 50); do systemctl is-active --quiet "$unit.service" || break; sleep 0.2; done
check_eq "the trap ran: result is cancelled" cancelled "$(cat "$WORK/result" 2>/dev/null)"
for f in child grandchild; do
  if kill -0 "$(cat "$WORK/$f")" 2>/dev/null; then fail "the $f of the job is still running"; else pass "the $f of the job is gone"; fi
done
systemctl stop "$unit.service" 2>/dev/null || true
finish
