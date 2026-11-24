#!/usr/bin/env bash
# The vps profile: a server with only tailscale and the edge roles (preset edge) switched on. "vps works" means exactly this:
#   1. `hs` loads: hs help runs, lists the edge commands (rows of capabilities/edge-status/commands.tsv) and no command of a capability that is off
#      that is flagged capability:<name>;
#   2. `hs smoke` passes: its programs and probes are those of the capabilities that are on (the edge probe runs and is ok; no program of storage,
#      incus, samba or backup is looked for; a core probe of a capability that is off is skipped);
#   3. the edge health read works: `hs edge health --dry-run` (and --keys) answers without a shell error and sends nothing.
# Not claimed: that no core command of storage is loaded at all (most of them carry no capability flag until #1074).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
export HS_LANG=en HS_PLAIN=1
export HS_CAPABILITIES_FILE=$WORK/capabilities HS_STATE_DIR=$WORK/state HS_HEALTH_STATE=$WORK/health.state HS_NOTIFY_URL=
mkdir -p "$HS_STATE_DIR"
printf '%s\n' tailscale edge-mail edge-ports edge-watcher edge-status > "$HS_CAPABILITIES_FILE"
HS="bash $SCRIPTS/lib/hs.sh"

echo "-- hs loads"
help=$($HS help --all 2>&1); rc=$?
check_eq "hs help runs" "0" "$rc"
check_out "the edge health command is there" "edge health" echo "$help"
rows=$(bash -c ". $SCRIPTS/lib/registry-load.sh; registry_rows")
check_out "the rows of the package are loaded" "edge health" echo "$rows"
check_out "and the sys row" "sys edge status" echo "$rows"
shown=$($HS help 2>&1)
off=$(printf '%s\n' "$rows" | awk -F'\t' '$1 == "user" { n = split($7, f, ","); for (i = 1; i <= n; i++) if (f[i] ~ /^capability:/) print $2 "\t" substr(f[i], 12) }' | grep -v 'edge-status$' | grep -vP '\t(tailscale|edge-mail|edge-ports|edge-watcher|vps)$' | cut -f1 | head -n 40)
bad=""
while IFS= read -r w; do
  [ -n "$w" ] || continue
  grep -qE "^ *hs $w( |$)" <<<"$shown" && bad="$bad $w"
done <<<"$off"
check_eq "hs help shows no command of a capability that is off" "" "$bad"

echo "-- hs smoke"
list=$(HS_SMOKE_PROBES= bash $SCRIPTS/smoke.sh --no-run --list 2>&1 || true)
for t in zpool incus samba-tool wbinfo restic snapraid cryptsetup; do
  if grep -q "^tool	$t	" <<<"$list"; then fail "smoke does not look for $t"; else pass "smoke does not look for $t"; fi
done
printf 'hs backup status	backup status	0
' > "$WORK/probes-off"
full=$(HS_SMOKE_TOOLS="" HS_SMOKE_PROBES=$WORK/probes-off bash $SCRIPTS/smoke.sh --list 2>&1 || true)
check_out "a probe of a capability that is off is skipped" "probe	hs backup status	skip	capability backup is off" echo "$full"
dirs=$(for c in tailscale edge-mail edge-ports edge-watcher edge-status; do echo "$ROOT/capabilities/$c"; done)
# shellcheck disable=SC2086
python3 "$SCRIPTS/lib/pkg_probes.py" probes $dirs > "$WORK/probes"
check_out "the packages that are on bring the edge probe" "hs edge health --dry-run" cat "$WORK/probes"
out=$(HS_SMOKE_TOOLS="" HS_SMOKE_PROBES=$WORK/probes bash $SCRIPTS/smoke.sh --list 2>&1); rc=$?
check_eq "smoke with the probes of the packages that are on passes" "0" "$rc"
check_out "and the edge probe is ok" "probe	hs edge health --dry-run	ok" echo "$out"

echo "-- the edge health read"
out=$($HS edge health --keys 2>&1); rc=$?
case "$rc" in 0|1) pass "hs edge health --keys answers (exit $rc)" ;; *) fail "hs edge health --keys answers (exit $rc): $out" ;; esac
out=$($HS edge health --dry-run 2>&1); rc=$?
case "$rc" in 0|1) pass "hs edge health --dry-run answers (exit $rc)" ;; *) fail "hs edge health --dry-run answers (exit $rc): $out" ;; esac
if grep -qiE 'command not found|syntax error|Traceback' <<<"$out"; then fail "no shell error in the health read"; else pass "no shell error in the health read"; fi
check "it wrote no state" test ! -e "$HS_HEALTH_STATE"

finish
