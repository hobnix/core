#!/usr/bin/env bash
# hs docker migrate (scripts/docker.sh): the setting docker replaces dockerManager as the on switch, a running manager is never touched. Fake incus, no root.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
export HS_LANG=en HS_PLAIN=1
BIN=$WORK/bin; mkdir -p "$BIN"
export LOG=$WORK/incus.log STATE=$WORK/ct-state OWNERF=$WORK/ct-owner
export HS_SETTINGS_DIR=$WORK/settings HS_STATE_DIR=$WORK/state HS_CAPABILITIES_FILE=$WORK/caps
mkdir -p "$HS_SETTINGS_DIR" "$HS_STATE_DIR"; : > "$HS_CAPABILITIES_FILE"; : > "$LOG"

if ! command -v jq >/dev/null 2>&1; then skip "jq is not installed: docker migrate tests not run"; finish; exit $?; fi

cat > "$BIN/incus" <<'FAKE'
#!/usr/bin/env bash
echo "incus $*" >> "$LOG"
case "$1" in
  info) [ -e "$STATE" ]; exit $? ;;
  query) o=$(cat "$OWNERF" 2>/dev/null || true)
    jq -n --arg o "$o" '{type:"container",config:(if $o=="" then {} else {"user.hs.managed_by":$o} end),expanded_devices:{}}' ;;
  exec) shift 3; [ "$1" = -- ] && shift
    if [ "$1" = test ] && [ "$2" = -f ]; then [ -e "$STATE.old-$(basename "$(dirname "$3")")" ]; exit $?; fi ;;
esac
exit 0
FAKE
chmod +x "$BIN/incus"
export PATH="$BIN:$PATH"
D="bash $SCRIPTS/docker.sh"
reset() { rm -f "$STATE" "$OWNERF" "$HS_SETTINGS_DIR"/* "$HS_STATE_DIR/docker-manager-legacy" "$STATE".old-*; rm -rf "$HS_STATE_DIR/packages"; : > "$LOG"; }
sget() { cat "$HS_SETTINGS_DIR/$1" 2>/dev/null || true; }
cap_on() { bash -c ". $SCRIPTS/lib/capability.sh; capability_on docker"; }
owned_ct() { : > "$STATE"; echo docker > "$OWNERF"; }

echo "-- dockerManager=arcane: migrate sets docker, keeps the manager, touches nothing"
reset; owned_ct; echo arcane > "$HS_SETTINGS_DIR/dockerManager"
rc=0; $D migrate </dev/null >/dev/null 2>&1 || rc=$?
check_eq "exit 0" 0 "$rc"
check_eq "docker=on" on "$(sget docker)"
[ ! -e "$HS_SETTINGS_DIR/dockerManager" ] && pass "dockerManager unset" || fail "dockerManager still set"
check_eq "legacy file" arcane "$(cat "$HS_STATE_DIR/docker-manager-legacy" 2>/dev/null || true)"
! grep -qE "compose|--delete|stop|restart|config set" "$LOG" && pass "no container touched" || fail "container touched: $(cat "$LOG")"
echo docker > "$HS_CAPABILITIES_FILE"; cap_on && pass "capability stays on" || fail "capability off after migrate"; : > "$HS_CAPABILITIES_FILE"
out=$($D --status)
check_eq "status: manager row" $'manager\tarcane' "$(echo "$out" | grep '^manager')"
check_eq "status: 11 rows in order" "state instance owned running manager size memory cpus children address mapped" "$(echo "$out" | cut -f1 | tr '\n' ' ' | sed 's/ $//')"

echo "-- a second run changes nothing"
sum1=$(cat "$HS_SETTINGS_DIR"/* "$HS_STATE_DIR/docker-manager-legacy" | cksum)
rc=0; out=$($D migrate </dev/null 2>&1) || rc=$?
check_eq "exit 0" 0 "$rc"; check_eq "no output" "" "$out"
check_eq "same files" "$sum1" "$(cat "$HS_SETTINGS_DIR"/* "$HS_STATE_DIR/docker-manager-legacy" | cksum)"

echo "-- webui: docker=on, no legacy file"
reset; owned_ct; echo webui > "$HS_SETTINGS_DIR/dockerManager"
$D migrate </dev/null >/dev/null 2>&1
check_eq "docker=on" on "$(sget docker)"
[ ! -e "$HS_STATE_DIR/docker-manager-legacy" ] && pass "no legacy file" || fail "legacy file written"

echo "-- empty dockerManager and /opt/arcane counts as arcane, once"
reset; owned_ct; : > "$STATE.old-arcane"
$D migrate </dev/null >/dev/null 2>&1
check_eq "docker=on" on "$(sget docker)"
check_eq "legacy file" arcane "$(cat "$HS_STATE_DIR/docker-manager-legacy" 2>/dev/null || true)"
rm -f "$HS_STATE_DIR/docker-manager-legacy"   # a recipe adopted it
$D migrate </dev/null >/dev/null 2>&1
[ ! -e "$HS_STATE_DIR/docker-manager-legacy" ] && pass "not found again after the recipe took over" || fail "legacy file came back"

echo "-- nothing to do"
reset
rc=0; out=$($D migrate </dev/null 2>&1) || rc=$?
check_eq "exit 0" 0 "$rc"; check_eq "no output" "" "$out"
[ ! -e "$HS_SETTINGS_DIR/docker" ] && pass "docker not set from nothing" || fail "docker set"

echo "-- --undo"
reset; owned_ct; echo portainer > "$HS_SETTINGS_DIR/dockerManager"
$D migrate </dev/null >/dev/null 2>&1; $D migrate --undo </dev/null >/dev/null 2>&1
check_eq "dockerManager back" portainer "$(sget dockerManager)"
[ ! -e "$HS_SETTINGS_DIR/docker" ] && [ ! -e "$HS_STATE_DIR/docker-manager-legacy" ] && pass "docker and the legacy file gone" || fail "undo left files"

echo "-- the manager row follows an installed recipe"
reset; owned_ct; echo on > "$HS_SETTINGS_DIR/docker"
mkdir -p "$HS_STATE_DIR/packages/current/portainer"; echo 'provides = ["docker-manager"]' > "$HS_STATE_DIR/packages/current/portainer/package.toml"
check_eq "manager row" $'manager\tportainer' "$($D --status | grep '^manager')"

echo "-- disable removes docker and the legacy file"
reset; owned_ct; echo on > "$HS_SETTINGS_DIR/docker"; echo arcane > "$HS_STATE_DIR/docker-manager-legacy"
rm -f "$STATE" "$OWNERF"
$D disable --yes --confirm docker --no-backup </dev/null >/dev/null 2>&1 || true
[ ! -e "$HS_SETTINGS_DIR/docker" ] && [ ! -e "$HS_STATE_DIR/docker-manager-legacy" ] && pass "both gone" || fail "left over"

finish
