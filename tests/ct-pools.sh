#!/usr/bin/env bash
# scripts/ct-pools.sh (hs sys ct pools) and the disk placement of manage-ct.sh --create (--pool, --iso): stand-in incus, no root, no Incus.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
export HS_LANG=en HS_PLAIN=1 HS_CALLER=test HS_MNT_BULK=/bulk HS_DISKS_ROOT=/mnt/bulk
if ! command -v jq >/dev/null 2>&1; then skip "jq is not installed: ct-pools tests not run"; finish; exit $?; fi
cat > "$WORK/incus" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >> "$HS_FAKE_LOG"
case "$1 $2" in
  "query /1.0/storage-pools?recursion=1") echo '[{"name":"default","driver":"zfs","config":{"source":"tank/incus"}},{"name":"bulk1","driver":"dir","config":{"source":"/bulk/data-01/incus"}},{"name":"gone","driver":"dir","config":{}}]' ;;
  "query /1.0/storage-pools/default/resources") echo '{"space":{"used":40,"total":100}}' ;;
  "query /1.0/storage-pools/bulk1/resources") echo '{"space":{"used":1000,"total":4000}}' ;;
  "query /1.0/storage-pools/gone/resources") exit 1 ;;
  "info vm1") exit 1 ;;
  "storage show") [ "$3" = bulk1 ] || exit 1 ;;
  "storage list") echo default ;;
  "query /1.0/instances/web") echo '{"type":"container"}' ;;
  "config device"|"storage volume") exit 1 ;;
esac
exit 0
FAKE
chmod +x "$WORK/incus"
export HS_INCUS=$WORK/incus HS_FAKE_LOG=$WORK/calls

echo "-- the pools read"
out=$(bash "$SCRIPTS/ct-pools.sh")
check_eq "default is fast, the free space is total minus used" $'default\tzfs\tfast\t60\t100\ttank/incus' "$(sed -n 1p <<<"$out")"
check_eq "a pool under /bulk is bulk" $'bulk1\tdir\tbulk\t3000\t4000\t/bulk/data-01/incus' "$(sed -n 2p <<<"$out")"
check_eq "a pool Incus cannot size has - and no empty field" $'gone\tdir\tother\t-\t-\t-' "$(sed -n 3p <<<"$out")"

echo "-- create with a pool and an image (dry run)"
: > "$WORK/calls"
touch "$WORK/x.iso"
out=$(bash "$SCRIPTS/manage-ct.sh" --create vm1 --vm --pool bulk1 --disk 50 --iso "$WORK/x.iso" --dry-run 2>&1)
has() { grep -q -- "$1" <<<"$out"; }
has "incus init --empty vm1 -c boot.autostart=true --vm -c limits.memory=2048MiB -c limits.cpu=2 -s bulk1" && pass "an empty VM on the pool" || fail "init: $out"
has "incus config device set vm1 root size=50GiB" && pass "with a pool the root device is set, not overridden" || fail "size: $out"
has "incus config device add vm1 install disk source=$WORK/x.iso boot.priority=10 readonly=true" && pass "the image is a read only disk that boots first" || fail "iso: $out"
out=$(bash "$SCRIPTS/manage-ct.sh" --create vm1 --vm --disk 50 --dry-run 2>&1)
has "incus init images:debian/13 vm1" && has "device override vm1 root size=50GiB" && pass "without pool and image it is the old command" || fail "old: $out"
out=$(bash "$SCRIPTS/manage-ct.sh" --create vm1 --iso "$WORK/x.iso" --dry-run 2>&1) && rc=0 || rc=$?
check_eq "an image without --vm is refused" 1 "$rc"
out=$(bash "$SCRIPTS/manage-ct.sh" --create vm1 --vm --pool nope 2>&1) && rc=0 || rc=$?
check_eq "an unknown pool is refused before anything is created" 1 "$rc"
check_eq "...and no init ran" 0 "$(grep -c '^init' "$WORK/calls")"
echo "-- fast volumes follow the apps pools (D5: default stays the first, others beside it)"
export HS_MACHINE_FILE=$WORK/machine.toml
mkdir -p "$WORK/bin"; cp "$WORK/incus" "$WORK/bin/incus"; export PATH="$WORK/bin:$PATH"
printf 'pools = { tank = { role = "data", kind = "zfs" }, ssd = { role = "apps", kind = "zfs" }, ssd2 = { role = "apps", kind = "zfs" } }
' > "$HS_MACHINE_FILE"
: > "$WORK/calls"
out=$(bash "$SCRIPTS/manage-ct.sh" web --add-storage fast data /data --dry-run 2>&1) || true
grep -q "incus storage volume create default data" <<<"$out" && pass "the first apps pool is the Incus default" || fail "default volume: $out"
out=$(bash "$SCRIPTS/manage-ct.sh" web --add-storage fast data /data -s ssd2 --dry-run 2>&1) || true
grep -q "incus storage volume create ssd2 data" <<<"$out" && pass "-s puts the volume on another apps pool" || fail "ssd2 volume: $out"
out=$(bash "$SCRIPTS/manage-ct.sh" web --add-storage fast data /data -s tank --dry-run 2>&1) && rc=0 || rc=$?
check_eq "a data pool is refused for a volume" 1 "$rc"
printf 'pools = {}
' > "$HS_MACHINE_FILE"
out=$(bash "$SCRIPTS/manage-ct.sh" web --add-storage fast data /data --dry-run 2>&1) && rc=0 || rc=$?
check_eq "no apps pool: refused" 1 "$rc"
rm -f "$HS_MACHINE_FILE"
finish
