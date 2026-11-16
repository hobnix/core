#!/usr/bin/env bash
# Start at boot (#614, decision D14): on = boot.autostart=true, off = the key is UNSET (Incus restores the last state), never "false".
# A fake incus keeps the config and the state of three instances in files; boot() models what Incus does at start:
# autostart true -> started, key unset -> the state before the shutdown comes back (a stopped one stays stopped).
# Needs jq (for manage-ct.sh), no root, no Incus.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
export HS_LANG=en HS_PLAIN=1
BIN=$WORK/bin; mkdir -p "$BIN" "$WORK/inc"
export INC=$WORK/inc

if ! command -v jq >/dev/null 2>&1; then skip "jq is not installed: container tests not run"; finish; exit $?; fi

cat > "$BIN/incus" <<'FAKE'
#!/usr/bin/env bash
case "$1" in
  info) [ -e "$INC/$2.state" ] ;;
  query) echo '{"type":"container","expanded_devices":{}}' ;;
  start) echo Running > "$INC/$2.state" ;;
  stop) echo Stopped > "$INC/$2.state" ;;
  config)
    case "$2" in
      set) case "$4" in boot.autostart=*) echo "${4#boot.autostart=}" > "$INC/$3.auto" ;; esac ;;
      unset) [ "$4" != boot.autostart ] || rm -f "$INC/$3.auto" ;;
    esac ;;
esac
exit 0
FAKE
chmod +x "$BIN/incus"
export PATH="$BIN:$PATH"
C="bash $SCRIPTS/manage-ct.sh"

mk() { echo "$2" > "$INC/$1.state"; rm -f "$INC/$1.auto"; }
# what Incus does at start: autostart=true starts; no key restores the state the instance had
boot() {
  local n st
  for f in "$INC"/*.state; do
    n=$(basename "$f" .state); st=$(cat "$f")
    if [ "$(cat "$INC/$n.auto" 2>/dev/null || true)" = true ]; then echo Running > "$f"
    else echo "$st" > "$f"; fi
  done
}
state() { cat "$INC/$1.state"; }

echo "-- on sets the key, off unsets it"
mk web Running; mk db Stopped; mk cache Stopped
$C db --set autostart=on >/dev/null
check_eq "on writes true" "true" "$(cat "$INC/db.auto")"
$C web --set autostart=off >/dev/null
[ ! -e "$INC/web.auto" ] && pass "off removes the key" || fail "off left a key behind"
$C db --set autostart=no >/dev/null
[ ! -e "$INC/db.auto" ] && pass "no is off" || fail "no left a key behind"
$C db --set autostart=yes >/dev/null
check_eq "yes is on" "true" "$(cat "$INC/db.auto")"
check_out "another value is refused and changes nothing" "autostart must be on or off" $C db --set autostart=maybe
check_eq "the key stays after a refusal" "true" "$(cat "$INC/db.auto")"

echo "-- a reboot"
# web: running, flag off; db: stopped, flag on; cache: stopped, flag off
check_eq "before: web runs" Running "$(state web)"
mk web Stopped   # web was stopped by hand before the reboot
boot
check_eq "flag on: a stopped instance starts at boot" Running "$(state db)"
check_eq "flag off and stopped: it stays stopped" Stopped "$(state web)"
check_eq "never set and stopped: it stays stopped" Stopped "$(state cache)"

echo "-- stop with --keep-off"
$C db --set autostart=on >/dev/null
$C db --stop --keep-off >/dev/null
check_eq "stop --keep-off stops" Stopped "$(state db)"
[ ! -e "$INC/db.auto" ] && pass "stop --keep-off unsets the key" || fail "key still set after --keep-off"
boot
check_eq "it stays off after the reboot" Stopped "$(state db)"
$C db --start >/dev/null; $C db --set autostart=on >/dev/null; $C db --stop >/dev/null
boot
check_eq "a plain stop keeps the flag: it starts again at boot" Running "$(state db)"

finish
