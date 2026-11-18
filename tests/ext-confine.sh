#!/usr/bin/env bash
# systemd confinement of extension services (ADR 0014 step 2, docs/PLAN-extensions-access.md step 10): scripts/lib/ext_confine.py turns the declared
# permissions into a drop-in of hs-ext-svc@<name>.service, `hs ext start` writes it, and a bad path is refused. The text is checked line for line.
# The systemd side (a service cannot write outside fs.write) is the nested stage `confine`, not run here. No root, python3 only.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
command -v python3 >/dev/null || { echo "python3 missing: skipped"; exit 0; }
EC="python3 -I $SCRIPTS/lib/ext_confine.py dropin --name fixsvc --"
HEAD1='# Written by hs ext (scripts/lib/ext_confine.py) from the permissions of fixsvc. Do not edit; it is rewritten at every start.'

echo "-- the mapping"
nodecl="$HEAD1
[Service]
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
NoNewPrivileges=yes
CapabilityBoundingSet=
PrivateDevices=yes
ReadWritePaths=-/var/lib/hs/ext-svc"
check_eq "a package without permissions gets the strict defaults" "$nodecl" "$($EC -)"
check_eq "declared but empty is the same text" "$nodecl" "$($EC)"
check_eq "permissions that are not systemd's business change nothing" "$nodecl" "$($EC web.read events.emit:pkg.fixsvc.x host:incus secrets:key)"
full="$HEAD1
[Service]
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
NoNewPrivileges=yes
CapabilityBoundingSet=
PrivateDevices=no
DevicePolicy=closed
DeviceAllow=char-drm rw
ReadWritePaths=-/var/lib/hs/ext-svc -/var/lib/hs/ext/fixsvc -/srv/media
ReadOnlyPaths=-/etc/hs -/srv/in
# net=lan is declared only: nothing here limits the network"
check_eq "fs.write, fs.read, devices and net map to the lines" "$full" "$($EC fs.write:/var/lib/hs/ext/fixsvc fs.read:/etc/hs fs.write:/srv/media/ fs.read:/srv/in devices:gpu net:lan)"
check_eq "a path listed twice is written once" "1" "$($EC fs.write:/srv/a fs.write:/srv/a | grep -c -- '-/srv/a')"
check_eq "fs.read alone never makes a path writable" "0" "$($EC fs.read:/srv/a | grep -c 'ReadWritePaths=.*/srv/a')"
check_eq "no devices: PrivateDevices=yes and no DeviceAllow" "0" "$($EC fs.write:/srv/a | grep -c 'DeviceAllow\|PrivateDevices=no')"
check_eq "no capabilities by default" "1" "$($EC fs.write:/srv/a | grep -c '^CapabilityBoundingSet=$')"

echo "-- bad input is refused"
for bad in relative/path ../etc /srv/../etc /srv/./a /srv//a / // '/srv/a b' '/srv/$HOME' '/srv/*'; do
  rc=0; out=$($EC "fs.write:$bad" 2>&1) || rc=$?
  check_eq "fs.write:$bad is refused (exit 1, no text on stdout)" "1" "$rc"
  rc=0; out=$($EC "fs.read:$bad" 2>/dev/null) || rc=$?
  check_eq "fs.read:$bad is refused" "1 " "$rc $out"
done
rc=0; $EC devices:tape >/dev/null 2>&1 || rc=$?
check_eq "an unknown device is refused" 1 "$rc"
rc=0; python3 -I "$SCRIPTS/lib/ext_confine.py" dropin --name 'Bad Name' -- - >/dev/null 2>&1 || rc=$?
check_eq "a bad package name is refused" 2 "$rc"

echo "-- the template unit is the floor"
for l in 'ProtectSystem = "strict"' 'ProtectHome = true' 'PrivateTmp = true' 'PrivateDevices = true' 'NoNewPrivileges = true' 'CapabilityBoundingSet = ""'; do
  check "configuration.nix: hs-ext-svc@ has $l" grep -q "^      $l;" "$ROOT/configuration.nix"
done

echo "-- hs ext start writes the drop-in, and refuses a bad path"
EXT=$WORK/ext; mkdir -p "$EXT/pk/okpkg" "$EXT/pk/nopkg" "$EXT/pk/badpkg" "$EXT/state" "$EXT/dropin"
mk() {   # mk <name> <permissions line or empty>
  printf 'name = "%s"\ntitle = "t"\nkind = "feature"\nrequires = []\nprovides = []\nneeds = []\nextension = true\n%s\n[service]\nexec = "@/run.sh"\n' "$1" "$2" > "$EXT/pk/$1/capability.toml"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$EXT/pk/$1/run.sh"
  mkdir -p "$EXT/root/capabilities/$1"   # where pkg.py perms reads the declaration (HS_PACKAGES_ROOT)
  printf 'name = "%s"\nversion = "1.0.0"\nkind = "feature"\nrequires = []\nprovides = []\nneeds = []\nextension = true\n%s\n' "$1" "$2" > "$EXT/root/capabilities/$1/package.toml"
}
mk okpkg 'permissions = ["fs.write:/srv/ok", "fs.read:/etc/hs"]'
mk nopkg ''
mk badpkg 'permissions = ["fs.write:/srv/../etc"]'
printf '#!/usr/bin/env bash\necho "$*" >> "%s"\nexit 0\n' "$EXT/ctl.log" > "$EXT/systemctl"; chmod +x "$EXT/systemctl"
printf 'hostName = "t"\n' > "$EXT/machine.toml"; printf 'okpkg\nnopkg\nbadpkg\n' > "$EXT/caps"
xe() { HS_LANG=en HS_PLAIN=1 HS_CALLER=test HS_STATE_DIR=$EXT/state HS_PACKAGES_ROOT=$EXT/root HS_PACKAGES_DIR=$EXT/pk HS_CAPABILITIES_FILE=$EXT/caps HS_MACHINE_FILE=$EXT/machine.toml HS_SYSTEMCTL=$EXT/systemctl HS_CONFINE_DIR=$EXT/dropin bash "$SCRIPTS/ext.sh" "$@"; }
xe start okpkg >/dev/null 2>&1 || true
f=$EXT/dropin/hs-ext-svc@okpkg.service.d/10-confine.conf
check "start writes the drop-in under the unit's .d folder" test -f "$f"
check "the drop-in of a package with permissions" grep -qx 'ReadWritePaths=-/var/lib/hs/ext-svc -/srv/ok' "$f"
check "it lists fs.read" grep -qx 'ReadOnlyPaths=-/etc/hs' "$f"
check "systemd is told to reload before the unit starts" grep -q '^daemon-reload' "$EXT/ctl.log"
check_eq "daemon-reload comes before start" "daemon-reload start" "$(grep -o '^daemon-reload\|^start' "$EXT/ctl.log" | tr '\n' ' ' | sed 's/ $//')"
: > "$EXT/ctl.log"
out=$(xe start nopkg 2>&1) || true
check_out "a package without permissions is warned about" "does not declare permissions" printf '%s' "$out"
check "and gets the strict defaults" grep -qx 'PrivateDevices=yes' "$EXT/dropin/hs-ext-svc@nopkg.service.d/10-confine.conf"
: > "$EXT/ctl.log"
rc=0; out=$(xe start badpkg 2>&1) || rc=$?
check_eq "a package with a bad path is not started" "1 0" "$rc $(grep -c '^start' "$EXT/ctl.log")"
check "no drop-in is left for it" test ! -e "$EXT/dropin/hs-ext-svc@badpkg.service.d/10-confine.conf"
finish
