#!/usr/bin/env bash
# hs docker gpu [on|off] (scripts/docker.sh): the Incus device gpu of the locked container docker, with a fake incus. Needs jq, no root.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
export HS_LANG=en HS_PLAIN=1
BIN=$WORK/bin; mkdir -p "$BIN"
export LOG=$WORK/incus.log CARDS=$WORK/cards GPUDEV=$WORK/gpu-dev NORENDER=$WORK/no-render STOPPED=$WORK/stopped
export HS_SETTINGS_DIR=$WORK/settings HS_STATE_DIR=$WORK/state HS_CAPABILITIES_FILE=$WORK/caps HS_DOCKER_NO_JOB=1
mkdir -p "$HS_SETTINGS_DIR" "$HS_STATE_DIR"; echo docker > "$HS_CAPABILITIES_FILE"

if ! command -v jq >/dev/null 2>&1; then skip "jq is not installed: docker gpu tests not run"; finish; exit $?; fi

# CARDS: the JSON array .gpu.cards of /1.0/resources; GPUDEV: exists when docker has the device gpu (holds its pci)
cat > "$BIN/incus" <<'FAKE'
#!/usr/bin/env bash
echo "incus $*" >> "$LOG"
case "$1" in
  info) exit 0 ;;
  query) case "$2" in
      /1.0/resources) jq -n --argjson c "$(cat "$CARDS" 2>/dev/null || echo '[]')" '{gpu:{cards:$c}}' ;;
      *) echo '{"type":"container","config":{"user.hs.managed_by":"docker"},"expanded_devices":{}}' ;;
    esac ;;
  list) case "$*" in *" s"*) [ -e "$STOPPED" ] && echo STOPPED || echo RUNNING ;; *) echo '"10.10.95.50 (eth0)"' ;; esac ;;
  config)
    if [ "$2" = device ] && [ "$3" = get ] && [ "$5" = gpu ]; then
      [ -e "$GPUDEV" ] || exit 1
      case "$6" in pci) cat "$GPUDEV" ;; *) echo gpu ;; esac; exit 0
    fi
    if [ "$2" = device ] && [ "$3" = add ]; then for a in "$@"; do case "$a" in pci=*) echo "${a#pci=}" > "$GPUDEV" ;; esac; done; exit 0; fi
    if [ "$2" = device ] && [ "$3" = remove ]; then rm -f "$GPUDEV"; exit 0; fi ;;
  exec) case "$*" in
      *"getent group render"*) [ -e "$NORENDER" ] && exit 2; echo "render:x:993:" ;;
      *"getent group video"*) echo "video:x:44:" ;;
    esac ;;
esac
exit 0
FAKE
chmod +x "$BIN/incus"
export PATH="$BIN:$PATH"
D="bash $SCRIPTS/docker.sh"
intel='[{"driver":"i915","pci_address":"0000:00:02.0","product":"UHD Graphics 630"},{"driver":"nvidia","pci_address":"0000:01:00.0","product":"RTX"}]'
two='[{"driver":"i915","pci_address":"0000:00:02.0","product":"UHD"},{"driver":"amdgpu","pci_address":"0000:03:00.0","product":""}]'
reset() { rm -f "$GPUDEV" "$NORENDER" "$STOPPED" "$CARDS"; : > "$LOG"; }
adds() { grep -c 'config device add docker gpu' "$LOG" || true; }

echo "-- state without the device"
reset; echo "$intel" > "$CARDS"
out=$($D gpu 2>&1); rc=$?
check_eq "exit 0" 0 "$rc"
echo "$out" | grep -q "not passed in" && pass "says not passed in" || fail "state: $out"
echo "$out" | grep -q "hs docker gpu on" && pass "names hs docker gpu on" || fail "next: $out"

echo "-- on --dry-run: a plan, no change"
out=$($D gpu on --dry-run 2>&1); rc=$?
check_eq "exit 0" 0 "$rc"
echo "$out" | grep -q "0000:00:02.0" && pass "plan names the Intel chip" || fail "plan: $out"
echo "$out" | grep -q "gid 993" && pass "plan names the render gid" || fail "plan gid: $out"
echo "$out" | grep -q "0000:01:00.0" && fail "the NVIDIA card is offered: $out" || pass "NVIDIA is not picked"
check_eq "no device added" 0 "$(adds)"

echo "-- on without a terminal and without --yes refuses"
out=$($D gpu on </dev/null 2>&1); rc=$?
[ "$rc" -ne 0 ] && pass "refused (rc $rc)" || fail "not refused: $out"
check_eq "no device added" 0 "$(adds)"

echo "-- on --yes adds the device with the render gid"
out=$($D gpu on --yes 2>&1); rc=$?
check_eq "exit 0" 0 "$rc"
grep -q 'config device add docker gpu gpu gputype=physical pci=0000:00:02.0 gid=993 mode=0660' "$LOG" && pass "device added" || fail "log: $(cat "$LOG")"
echo "$out" | grep -q 'group_add: \["993"\]' && pass "prints group_add" || fail "out: $out"

echo "-- on again: nothing to do"
: > "$LOG"; out=$($D gpu on --yes 2>&1); rc=$?
check_eq "exit 0" 0 "$rc"
check_eq "no second add" 0 "$(adds)"
echo "$out" | grep -q "already" && pass "says already" || fail "out: $out"

echo "-- state with the device; status shows it"
out=$($D gpu 2>&1)
echo "$out" | grep -q "passed in (0000:00:02.0)" && pass "state passed in" || fail "state: $out"
echo "$out" | grep -q '/dev/dri:/dev/dri' && pass "prints the devices line" || fail "state: $out"
out=$($D status 2>&1)
echo "$out" | grep -q "Graphics chip" && pass "hs docker status has the chip" || fail "status: $out"
n=$($D --status | wc -l | tr -d ' ')
check_eq "--status keeps 11 keys" 11 "$n"

echo "-- off --dry-run, then off --yes"
: > "$LOG"; out=$($D gpu off --dry-run 2>&1)
echo "$out" | grep -q "lose it" && pass "off plan warns" || fail "off plan: $out"
grep -q 'device remove' "$LOG" && fail "dry-run removed" || pass "dry-run removes nothing"
$D gpu off --yes >/dev/null 2>&1
grep -q 'config device remove docker gpu' "$LOG" && pass "device removed" || fail "log: $(cat "$LOG")"
out=$($D gpu off --yes 2>&1); rc=$?
check_eq "off again exit 0" 0 "$rc"

echo "-- several chips: --pci picks, a wrong --pci refuses"
reset; echo "$two" > "$CARDS"
out=$($D gpu on --dry-run 2>&1)
echo "$out" | grep -q -- "--pci" && pass "names --pci with several chips" || fail "out: $out"
out=$($D gpu on --pci 0000:03:00.0 --yes 2>&1); rc=$?
check_eq "exit 0" 0 "$rc"
grep -q 'pci=0000:03:00.0' "$LOG" && pass "the AMD chip is passed in" || fail "log: $(cat "$LOG")"
reset; echo "$two" > "$CARDS"
out=$($D gpu on --pci 0000:09:00.0 --yes 2>&1); rc=$?
[ "$rc" -ne 0 ] && pass "unknown --pci refused" || fail "not refused: $out"

echo "-- no render group: video; NVIDIA only and stopped refuse"
reset; echo "$intel" > "$CARDS"; : > "$NORENDER"
$D gpu on --yes >/dev/null 2>&1
grep -q 'gid=44' "$LOG" && pass "falls back to video" || fail "log: $(cat "$LOG")"
reset; echo '[{"driver":"nvidia","pci_address":"0000:01:00.0"}]' > "$CARDS"
out=$($D gpu on --yes 2>&1); rc=$?
[ "$rc" -ne 0 ] && echo "$out" | grep -q NVIDIA && pass "NVIDIA only refused" || fail "rc $rc: $out"
reset; echo "$intel" > "$CARDS"; : > "$STOPPED"
out=$($D gpu on --yes 2>&1); rc=$?
[ "$rc" -ne 0 ] && echo "$out" | grep -q "stopped" && pass "stopped container refused" || fail "rc $rc: $out"
check_eq "no device added" 0 "$(adds)"

echo "-- an unknown word refuses"
out=$($D gpu maybe 2>&1); rc=$?
[ "$rc" -ne 0 ] && pass "refused" || fail "not refused: $out"

finish
