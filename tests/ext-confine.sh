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
TemporaryFileSystem=/var/lib/hs:ro
InaccessiblePaths=-/root -/etc/shadow -/etc/gshadow -/etc/ssh -/etc/nixos
BindPaths=-/var/lib/hs/ext-svc"
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
TemporaryFileSystem=/var/lib/hs:ro
InaccessiblePaths=-/root -/etc/shadow -/etc/gshadow -/etc/ssh -/etc/nixos
ReadWritePaths=-/srv/media
BindPaths=-/var/lib/hs/ext-svc -/var/lib/hs/ext/fixsvc
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

echo "-- secrets are hidden and a grant that overlaps them is refused (#947)"
check_eq "/var/lib/hs is an empty read-only tmpfs, the bridge state is bound back" "2" "$($EC - | grep -c 'TemporaryFileSystem=/var/lib/hs:ro$\|BindPaths=-/var/lib/hs/ext-svc$')"
check_eq "root, shadow, ssh and nixos are inaccessible" "1" "$($EC - | grep -c '^InaccessiblePaths=-/root -/etc/shadow -/etc/gshadow -/etc/ssh -/etc/nixos$')"
for g in /var/lib/hs /var/lib/hs/restic-password /var/lib/hs/api-tokens/x /var/lib /root /root/.ssh /etc/shadow /etc/ssh/ssh_host_ed25519_key /etc/nixos/machine.toml /etc; do
  rc=0; $EC "fs.read:$g" >/dev/null 2>&1 || rc=$?
  check_eq "fs.read:$g is refused" "1" "$rc"
  rc=0; $EC "fs.write:$g" >/dev/null 2>&1 || rc=$?
  check_eq "fs.write:$g is refused" "1" "$rc"
done
for g in /etc/hs /etc/systemd /boot /nix/store; do
  rc=0; $EC "fs.write:$g" >/dev/null 2>&1 || rc=$?
  check_eq "fs.write:$g is refused (system files)" "1" "$rc"
done
rc=0; $EC fs.read:/etc/hs >/dev/null 2>&1 || rc=$?
check_eq "fs.read:/etc/hs stays grantable" "0" "$rc"
rc=0; $EC fs.write:/var/lib/hs/ext/x fs.read:/var/lib/hs/ext-svc/y >/dev/null 2>&1 || rc=$?
check_eq "state below /var/lib/hs/ext and ext-svc stays grantable" "0" "$rc"
rc=0; $EC fs.write:/var/lib/hs/fixsvc fs.read:/var/lib/hs/fixsvc/sub >/dev/null 2>&1 || rc=$?
check_eq "a package may use /var/lib/hs/<its own name>" "0" "$rc"
check_eq "and it is bound back into the empty /var/lib/hs" "1" "$($EC fs.write:/var/lib/hs/fixsvc | grep -c '^BindPaths=-/var/lib/hs/ext-svc -/var/lib/hs/fixsvc$')"
rc=0; $EC fs.write:/var/lib/hs/other >/dev/null 2>&1 || rc=$?
check_eq "but not the folder of another package or one with the same prefix" "1" "$rc"
rc=0; $EC fs.write:/var/lib/hs/fixsvcx >/dev/null 2>&1 || rc=$?
check_eq "fixsvcx is not fixsvc" "1" "$rc"
rc=0; python3 -I "$SCRIPTS/lib/ext_confine.py" dropin --name passthrough -- fs.write:/etc/hs/gateway-public >/dev/null 2>&1 || rc=$?
check_eq "no package has an exception: not even passthrough may write below /etc" "1" "$rc"
rc=0; python3 -I "$SCRIPTS/lib/ext_confine.py" dropin --name passthrough -- fs.read:/etc/hs fs.write:/var/lib/hs-gateway >/dev/null 2>&1 || rc=$?
check_eq "reading /etc/hs and writing its own /var/lib/hs-gateway is fine" "0" "$rc"
rc=0; python3 -I "$SCRIPTS/lib/ext_confine.py" props --name fixsvc -- fs.write:/var/lib/hs/fixsvc >/dev/null 2>&1 || rc=$?
check_eq "props takes the package name too (confined commands)" "0" "$rc"
check_eq "the refusal names the secret it overlaps" "1" "$($EC fs.read:/var/lib/hs/restic-password 2>&1 | grep -c 'overlaps /var/lib/hs')"

echo "-- the template unit is the bridge: it is not sandboxed (#1130), the service is, as a transient unit"
for l in ProtectSystem ProtectHome PrivateTmp PrivateDevices NoNewPrivileges CapabilityBoundingSet ReadWritePaths; do
  check_eq "configuration.nix: hs-ext-svc@ does not set $l (the bridge writes state.db)" "0" "$(sed -n '/systemd.services."hs-ext-svc@"/,/^  };/p' "$ROOT/configuration.nix" | grep -c "^      $l ")"
done

echo "-- hs ext start checks the permissions and writes no drop-in (the bridge is not confined, the service is: ext_service.py confined_program)"
EXT=$WORK/ext; mkdir -p "$EXT/pk/okpkg" "$EXT/pk/nopkg" "$EXT/pk/badpkg" "$EXT/state" "$EXT/dropin"
mk() {   # mk <name> <permissions line or empty>
  printf 'name = "%s"
title = "t"
kind = "feature"
requires = []
provides = []
needs = []
extension = true
%s
[service]
exec = "@/run.sh"
' "$1" "$2" > "$EXT/pk/$1/capability.toml"
  printf '#!/usr/bin/env bash
exit 0
' > "$EXT/pk/$1/run.sh"
  mkdir -p "$EXT/root/capabilities/$1"   # where pkg.py perms reads the declaration (HS_PACKAGES_ROOT)
  printf 'name = "%s"
version = "1.0.0"
kind = "feature"
requires = []
provides = []
needs = []
extension = true
%s
' "$1" "$2" > "$EXT/root/capabilities/$1/package.toml"
}
mk okpkg 'permissions = ["fs.write:/srv/ok", "fs.read:/etc/hs"]'
mk nopkg ''
mk badpkg 'permissions = ["fs.write:/srv/../etc"]'
printf '#!/usr/bin/env bash
echo "$*" >> "%s"
exit 0
' "$EXT/ctl.log" > "$EXT/systemctl"; chmod +x "$EXT/systemctl"
printf 'hostName = "t"
' > "$EXT/machine.toml"; printf 'okpkg
nopkg
badpkg
' > "$EXT/caps"
xe() { HS_LANG=en HS_PLAIN=1 HS_CALLER=test HS_STATE_DIR=$EXT/state HS_PACKAGES_ROOT=$EXT/root HS_PACKAGES_DIR=$EXT/pk HS_CAPABILITIES_FILE=$EXT/caps HS_MACHINE_FILE=$EXT/machine.toml HS_SYSTEMCTL=$EXT/systemctl HS_CONFINE_DIR=$EXT/dropin bash "$SCRIPTS/ext.sh" "$@"; }
mkdir -p "$EXT/dropin/hs-ext-svc@okpkg.service.d"; : > "$EXT/dropin/hs-ext-svc@okpkg.service.d/10-confine.conf"
xe start okpkg >/dev/null 2>&1 || true
check "start writes no drop-in and removes an old one (it would confine the bridge)" test ! -e "$EXT/dropin/hs-ext-svc@okpkg.service.d/10-confine.conf"
check_eq "and starts the unit" "1" "$(grep -c '^start hs-ext-svc@okpkg.service' "$EXT/ctl.log")"
check "removing an old drop-in reloads systemd (else the bridge keeps its sandbox until reboot)" grep -q "^daemon-reload" "$EXT/ctl.log"
check_eq "and the daemon-reload comes before the start" "daemon-reload" "$(grep -o "^daemon-reload\|^start" "$EXT/ctl.log" | head -n1)"
: > "$EXT/ctl.log"
out=$(xe start nopkg 2>&1) || true
check_out "a package without permissions is warned about" "does not declare permissions" printf '%s' "$out"
: > "$EXT/ctl.log"
rc=0; out=$(xe start badpkg 2>&1) || rc=$?
check_eq "a package with a bad path is not started" "1 0" "$rc $(grep -c '^start' "$EXT/ctl.log")"

echo "-- commands: the flag confine runs a row through systemd-run (step 11)"
CF=$WORK/cf; mkdir -p "$CF/pk/fixconf" "$CF/pk/fixplain" "$CF/root/capabilities/fixconf" "$CF/root/capabilities/fixplain" "$CF/state"
tab=$(printf '\t')
for n in fixconf fixplain; do
  cp "$ROOT/tests/fixtures/ext-proto/ext.py" "$CF/pk/$n/ext.py"
  printf 'name = "%s"\ntitle = "t"\ntitle_de = "t"\nkind = "feature"\nrequires = []\nprovides = []\nneeds = []\nextension = true\n' "$n" > "$CF/pk/$n/capability.toml"
done
pt='name = "%s"\nversion = "1.0.0"\nkind = "capability"\nrequires_core = ">=10"\nprotocol = [1]\n%s\n'
printf "$pt" fixconf 'permissions = ["fs.write:/srv/ok", "fs.read:/etc/hs", "net:lan"]' | tee "$CF/pk/fixconf/package.toml" > "$CF/root/capabilities/fixconf/package.toml"
printf "$pt" fixplain 'permissions = ["fs.write:/srv/ok"]' | tee "$CF/pk/fixplain/package.toml" > "$CF/root/capabilities/fixplain/package.toml"
row() { printf '%s\t%s\t@/ext.py\t-\tx\tx\t%s\n' sys "$1" "$2"; }
{ row "sys ext fixconf rows" confine; row "sys ext fixconf echo" -; } > "$CF/pk/fixconf/commands.tsv"
row "sys ext fixplain rows" - > "$CF/pk/fixplain/commands.tsv"
# a fake systemd-run: records its arguments, then runs what follows the --
cat > "$CF/systemd-run" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$CF_LOG"
while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do shift; done
shift
exec "$@"
SH
chmod +x "$CF/systemd-run"
printf 'fixconf\nfixplain\n' > "$CF/caps"; printf 'hostName = "t"\n' > "$CF/machine.toml"
hsc() { CF_LOG=$CF/run.log HS_SYSTEMD_RUN=${HS_SYSTEMD_RUN:-$CF/systemd-run} HS_LANG=en HS_PLAIN=1 HS_CALLER=test HS_STATE_DIR=$CF/state HS_PACKAGES_ROOT=$CF/root \
  HS_PACKAGES_DIR=$CF/pk HS_CAPABILITIES_FILE=$CF/caps HS_MACHINE_FILE=$CF/machine.toml bash "$SCRIPTS/lib/hs.sh" "$@"; }
ran() { [ -e "$CF/run.log" ] && echo yes || echo no; }   # did the fake systemd-run get called
rm -f "$CF/run.log"
check_eq "a confined row still answers like an unconfined one" "$(printf 'alpha\tb c\t-\nx\t3\t-')" "$(hsc sys ext fixconf rows 2>/dev/null)"
expect="--pipe
--wait
--collect
--quiet
--description=hs extension command of fixconf
--property=KillMode=control-group
--property=ProtectSystem=strict
--property=ProtectHome=yes
--property=PrivateTmp=yes
--property=NoNewPrivileges=yes
--property=CapabilityBoundingSet=
--property=PrivateDevices=yes
--property=TemporaryFileSystem=/var/lib/hs:ro
--property=InaccessiblePaths=-/root -/etc/shadow -/etc/gshadow -/etc/ssh -/etc/nixos
--property=ReadWritePaths=-/srv/ok
--property=BindPaths=-/var/lib/hs/ext-svc
--property=ReadOnlyPaths=-/etc/hs
--
python3
-I
$CF/pk/fixconf/ext.py"
check_eq "systemd-run gets exactly the properties of the declared permissions, then the program" "$expect" "$(cat "$CF/run.log")"
want=$(python3 -I "$SCRIPTS/lib/ext_confine.py" props -- fs.write:/srv/ok fs.read:/etc/hs net:lan)
check_eq "they are the properties of the service drop-in (one mapping)" "$want" "$(grep '^--property=[A-Z]' "$CF/run.log" | grep -v KillMode | sed 's/^--property=//')"
check_eq "and ext_confine.py dropin prints the same lines" "$want" "$(python3 -I "$SCRIPTS/lib/ext_confine.py" dropin --name fixconf -- fs.write:/srv/ok fs.read:/etc/hs net:lan | sed '1,2d;/^#/d')"
rm -f "$CF/run.log"; rc=0; hsc sys ext fixconf echo >/dev/null 2>&1 || rc=$?
check_eq "an unconfined row of the same package is unchanged: run directly" "0 no" "$rc $(ran)"
hsc sys ext fixplain rows >/dev/null 2>&1 || true
check_eq "a package without a confined row never calls systemd-run" "no" "$(ran)"
rc=0; HS_SYSTEMD_RUN=$CF/missing hsc sys ext fixconf rows >/dev/null 2>&1 || rc=$?
check_eq "without systemd-run the command is refused (69), not run unconfined" "69 no" "$rc $(ran)"
printf 'name = "fixconf"\nversion = "1.0.0"\nkind = "capability"\nrequires_core = ">=10"\nprotocol = [1]\n' > "$CF/root/capabilities/fixconf/package.toml"
rc=0; err=$(hsc sys ext fixconf rows 2>&1 >/dev/null) || rc=$?
check_eq "a package that lost its permissions is refused at run time" "69 no" "$rc $(ran)"
check_out "and the reason is said" "does not declare permissions" printf '%s' "$err"
printf 'name = "fixconf"\nversion = "1.0.0"\nkind = "capability"\nrequires_core = ">=10"\nprotocol = [1]\npermissions = ["fs.write:/srv/../etc"]\n' > "$CF/root/capabilities/fixconf/package.toml"
rc=0; hsc sys ext fixconf rows >/dev/null 2>&1 || rc=$?
check_eq "a bad path is refused at run time" "69 no" "$rc $(ran)"

echo "-- the install and update prompt says what confinement covers"
PRM=$(python3 -I - "$SCRIPTS" <<'PY'
import importlib.util, os, sys, tempfile
def load(n, f):
    s = importlib.util.spec_from_file_location(n, os.path.join(sys.argv[1], f)); m = importlib.util.module_from_spec(s); s.loader.exec_module(m); return m
proto = load("pkg_protocol", "lib/pkg_protocol.py")
repo = load("pkg_repo", "pkg_repo.py")
st = tempfile.mkdtemp()
tab = chr(9)
for n, flag in (("fixconf", "confine"), ("fixplain", "-")):
    os.makedirs(os.path.join(st, "current", n))
    open(os.path.join(st, "current", n, "commands.tsv"), "w").write(tab.join(["user", "ext %s go" % n, "@/g", "-", "h", "h", flag]) + chr(10))
class P:
    pkg_protocol = proto
    def state_dir(self): return st
R = repo.Repos(P())
print(chr(10).join(R.confine_text("fixconf", None)))
print("PLAIN=" + repr(R.confine_text("fixplain", None)))
print("NONE=" + repr(R.confine_text("nothere", None)))
PY
)
check_out "the prompt names the confined row" 'confined commands \(ext fixconf go\)' printf '%s' "$PRM"
check_out "it says what is covered" "it covers: writes outside fs.write" printf '%s' "$PRM"
check_out "it says what is not covered: reads, network, hs and incus" "it does NOT cover: reading the file system.*the network.*incus" bash -c "printf '%s' \"\$0\" | tr '\n' ' '" "$PRM"
check_out "it says the other commands run as root, unconfined" "run as root, unconfined" printf '%s' "$PRM"
check_out "a package without a confined row gets no extra text" 'PLAIN=\[\]' printf '%s' "$PRM"
check_out "an uninstalled package gets none and no error" 'NONE=\[\]' printf '%s' "$PRM"

finish
