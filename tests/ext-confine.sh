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
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
ProtectClock=yes
ProtectHostname=yes
RestrictNamespaces=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes
LockPersonality=yes
SystemCallArchitectures=native
SystemCallFilter=~@mount @swap @reboot @module @raw-io @cpu-emulation @debug @obsolete
SystemCallErrorNumber=EPERM
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK
PrivateDevices=yes
TemporaryFileSystem=/var/lib/hs:ro
InaccessiblePaths=-/root -/etc/shadow -/etc/gshadow -/etc/ssh -/etc/nixos -/var/lib/hs-vault -/run/hs-ext-cred
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
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
ProtectClock=yes
ProtectHostname=yes
RestrictNamespaces=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes
LockPersonality=yes
SystemCallArchitectures=native
SystemCallFilter=~@mount @swap @reboot @module @raw-io @cpu-emulation @debug @obsolete
SystemCallErrorNumber=EPERM
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK
PrivateDevices=no
DevicePolicy=closed
DeviceAllow=char-drm rw
TemporaryFileSystem=/var/lib/hs:ro
InaccessiblePaths=-/root -/etc/shadow -/etc/gshadow -/etc/ssh -/etc/nixos -/var/lib/hs-vault -/run/hs-ext-cred
ReadWritePaths=-/srv/media
BindPaths=-/var/lib/hs/ext-svc -/var/lib/hs/ext/fixsvc
ReadOnlyPaths=-/etc/hs -/srv/in
# net=lan is declared only: nothing here limits the network"
check_eq "fs.write, fs.read, devices and net map to the lines" "$full" "$($EC fs.write:/var/lib/hs/ext/fixsvc fs.read:/etc/hs fs.write:/srv/media/ fs.read:/srv/in devices:gpu net:lan)"
check_eq "a path listed twice is written once" "1" "$($EC fs.write:/srv/a fs.write:/srv/a | grep -c -- '-/srv/a')"
check_eq "fs.read alone never makes a path writable" "0" "$($EC fs.read:/srv/a | grep -c 'ReadWritePaths=.*/srv/a')"
check_eq "no devices: PrivateDevices=yes and no DeviceAllow" "0" "$($EC fs.write:/srv/a | grep -c 'DeviceAllow\|PrivateDevices=no')"
check_eq "no capabilities by default" "1" "$($EC fs.write:/srv/a | grep -c '^CapabilityBoundingSet=$')"

echo "-- hardening: every flag is in the unit, and no declared permission loses its access"
ALL="$($EC fs.write:/srv/a fs.read:/etc/hs devices:gpu net:lan)"
for l in ProtectKernelTunables=yes ProtectKernelModules=yes ProtectKernelLogs=yes ProtectControlGroups=yes ProtectClock=yes ProtectHostname=yes \
  RestrictNamespaces=yes RestrictRealtime=yes RestrictSUIDSGID=yes LockPersonality=yes   SystemCallArchitectures=native "SystemCallFilter=~@mount @swap @reboot @module @raw-io @cpu-emulation @debug @obsolete" SystemCallErrorNumber=EPERM "RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK"; do
  check_eq "a package without permissions gets $l" "1" "$($EC - | grep -c -x -- "$l")"
  check_eq "and so does one with fs, devices and net: $l" "1" "$(printf '%s\n' "$ALL" | grep -c -x -- "$l")"
done
check_eq "unix sockets stay (the bridge pipe, incus, journal): AF_UNIX is allowed" "1" "$($EC host:incus | grep -c '^RestrictAddressFamilies=AF_UNIX ')"
check_eq "net:lan keeps AF_INET and AF_INET6 (net is declared only)" "1" "$($EC net:lan | grep -c '^RestrictAddressFamilies=.*AF_INET AF_INET6 ')"
check_eq "no IP filter: network filtering is a firewall decision" "0" "$($EC net:lan net:wan | grep -c 'IPAddress\|PrivateNetwork')"
check_eq "devices:gpu keeps its device (DeviceAllow, not PrivateDevices)" "2" "$(printf '%s\n' "$ALL" | grep -c '^DeviceAllow=char-drm rw$\|^PrivateDevices=no$')"
check_eq "fs.write stays writable (no ProtectSystem=full, no ReadOnly of it)" "1" "$(printf '%s\n' "$ALL" | grep -c '^ReadWritePaths=-/srv/a$')"
check_eq "an allow list would kill a service with SIGSYS: the filter is a deny list and refused calls are errors" "0" "$(printf '%s\n' "$ALL" | grep -c '^SystemCallFilter=@\|ProtectProc\|ProcSubset')"
check_eq "no DynamicUser yet (step 7) and no MemoryDenyWriteExecute" "0" "$(printf '%s\n' "$ALL" | grep -c 'DynamicUser\|MemoryDenyWriteExecute\|^User=')"
check_eq "props (confined commands) carry the same flags" "14" "$(python3 -I $SCRIPTS/lib/ext_confine.py props --name fixsvc -- - | grep -c '^Protect\(Kernel\|Control\|Clock\|Hostname\)\|^Restrict\|^LockPers\|^SystemCall')"

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
check_eq "root, shadow, ssh and nixos are inaccessible" "1" "$($EC - | grep -c '^InaccessiblePaths=-/root -/etc/shadow -/etc/gshadow -/etc/ssh -/etc/nixos -/var/lib/hs-vault -/run/hs-ext-cred$')"
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
printf "$pt" fixconf 'permissions = ["fs.write:/var/lib/hs/fixconf", "fs.read:/etc/hs", "net:lan"]' | tee "$CF/pk/fixconf/package.toml" > "$CF/root/capabilities/fixconf/package.toml"
printf "$pt" fixplain 'permissions = ["fs.write:/srv/ok"]' | tee "$CF/pk/fixplain/package.toml" > "$CF/root/capabilities/fixplain/package.toml"
row() { printf '%s\t%s\t@/ext.py\t-\tx\tx\t%s\n' sys "$1" "$2"; }
{ row "sys ext fixconf rows" confine; row "sys ext fixconf echo" -; } > "$CF/pk/fixconf/commands.tsv"
row "sys ext fixplain rows" - > "$CF/pk/fixplain/commands.tsv"
# a fake systemd-run: records its arguments (and what the old state path was then), does what StateDirectory= does, then runs what follows the --
cat > "$CF/systemd-run" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$CF_LOG"
if [ -L "$HS_STATE_DIR/fixconf" ]; then echo link; elif [ -d "$HS_STATE_DIR/fixconf" ]; then echo folder; else echo missing; fi > "$CF_LOG.old"
if [ ! -e "$HS_EXT_STATE_DIR/fixconf" ]; then mkdir -p "$HS_PRIVATE_DIR/hs-ext/fixconf" "$HS_EXT_STATE_DIR"; ln -s "$HS_PRIVATE_DIR/hs-ext/fixconf" "$HS_EXT_STATE_DIR/fixconf"; fi
while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do shift; done
shift
exec "$@"
SH
chmod +x "$CF/systemd-run"
printf 'fixconf\nfixplain\n' > "$CF/caps"; printf 'hostName = "t"\n' > "$CF/machine.toml"
hsc() { CF_LOG=$CF/run.log HS_SYSTEMD_RUN=${HS_SYSTEMD_RUN:-$CF/systemd-run} HS_LANG=en HS_PLAIN=1 HS_CALLER=test HS_STATE_DIR=$CF/state HS_PACKAGES_ROOT=$CF/root \
  HS_EXT_STATE_DIR=$CF/ext HS_PRIVATE_DIR=$CF/private HS_PACKAGES_DIR=$CF/pk HS_CAPABILITIES_FILE=$CF/caps HS_MACHINE_FILE=$CF/machine.toml bash "$SCRIPTS/lib/hs.sh" "$@"; }
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
--property=ProtectKernelTunables=yes
--property=ProtectKernelModules=yes
--property=ProtectKernelLogs=yes
--property=ProtectControlGroups=yes
--property=ProtectClock=yes
--property=ProtectHostname=yes
--property=RestrictNamespaces=yes
--property=RestrictRealtime=yes
--property=RestrictSUIDSGID=yes
--property=LockPersonality=yes
--property=SystemCallArchitectures=native
--property=SystemCallFilter=~@mount @swap @reboot @module @raw-io @cpu-emulation @debug @obsolete
--property=SystemCallErrorNumber=EPERM
--property=RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK
--property=PrivateDevices=yes
--property=DynamicUser=yes
--property=User=hsx-fixconf
--property=StateDirectory=hs-ext/fixconf
--property=StateDirectoryMode=0700
--property=UMask=0077
--property=ProtectProc=invisible
--property=TemporaryFileSystem=/var/lib/hs:ro
--property=InaccessiblePaths=-/root -/etc/shadow -/etc/gshadow -/etc/ssh -/etc/nixos -/var/lib/hs-vault -/run/hs-ext-cred
--property=ReadOnlyPaths=-/etc/hs
--
python3
-I
$CF/pk/fixconf/ext.py"
check_eq "systemd-run gets exactly the properties of the declared permissions, then the program" "$expect" "$(cat "$CF/run.log")"
want=$(python3 -I "$SCRIPTS/lib/ext_confine.py" props --dynamic --name fixconf -- fs.write:/var/lib/hs/fixconf fs.read:/etc/hs net:lan)
check_eq "they are the properties of the service drop-in (one mapping)" "$want" "$(grep '^--property=[A-Z]' "$CF/run.log" | grep -v KillMode | sed 's/^--property=//')"
check_eq "and ext_confine.py dropin prints the same lines" "$want" "$(python3 -I "$SCRIPTS/lib/ext_confine.py" dropin --dynamic --name fixconf -- fs.write:/var/lib/hs/fixconf fs.read:/etc/hs net:lan | sed '1,2d;/^#/d')"
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

echo "-- a confined row runs as the dynamic user and shares the state folder of the package (#1134 S4): prepared first, fail closed"
confperms() { printf "$pt" fixconf "permissions = [$1]" > "$CF/root/capabilities/fixconf/package.toml"; cp "$CF/root/capabilities/fixconf/package.toml" "$CF/pk/fixconf/package.toml"; }
fresh_state() { rm -rf "$CF/state/fixconf" "$CF/ext" "$CF/private" "$CF/victim" "$CF/run.log" "$CF/run.log.old"; mkdir -p "$CF/state"; }
confrun() { rc=0; err=$(hsc sys ext fixconf rows 2>&1 >/dev/null) || rc=$?; }
tree() { (cd "$1" && find . -printf '%p %y %m %l\n' | sort; find . -type f -exec cksum {} + | sort); }
confperms '"fs.write:/var/lib/hs/fixconf"'
fresh_state; confrun
check_eq "a first run: no link before systemd-run, the link afterwards" "0 missing $CF/ext/fixconf" "$rc $(cat "$CF/run.log.old") $(readlink "$CF/state/fixconf")"
fresh_state; mkdir -p "$CF/state/fixconf"; echo data > "$CF/state/fixconf/f"; confrun
check_eq "an old state folder is moved before systemd-run" "0 link data" "$rc $(cat "$CF/run.log.old") $(cat "$CF/state/fixconf/f")"
check_out "and said" "moved the state of fixconf from $CF/state/fixconf to $CF/ext/fixconf" printf '%s' "$err"
confrun; check_eq "the next run moves nothing" "0 0" "$rc $(printf '%s' "$err" | grep -c 'moved the state')"
fresh_state; mkdir -p "$CF/state/fixconf" "$CF/ext/fixconf"; echo a > "$CF/state/fixconf/a"; echo b > "$CF/ext/fixconf/b"
before=$(tree "$CF/state/fixconf"; tree "$CF/ext"); confrun
check_eq "both folders: refused (69), not run" "69 no" "$rc $(ran)"
check_eq "and nothing changed on disk" "$before" "$(tree "$CF/state/fixconf"; tree "$CF/ext")"
check_out "the reason is said" "ext.state-conflict" printf '%s' "$err"
fresh_state; mkdir -p "$CF/victim"; ln -s "$CF/victim" "$CF/state/fixconf"; confrun
check_eq "a state path that links somewhere else: refused, link kept" "69 no $CF/victim" "$rc $(ran) $(readlink "$CF/state/fixconf")"
fresh_state; mkdir -p "$CF/state/fixconf"
for p in /srv/ok /var/lib/hs/ext-svc /var/lib/hs/other /var/lib/hs-ext/other /var/lib/private /var/lib/hs /etc; do
  confperms "\"fs.write:$p\""; confrun
  check_eq "fs.write:$p is refused (69), not run" "69 no" "$rc $(ran)"
done
confperms '"fs.read:/var/lib/hs/ext-svc"'; confrun
check_eq "fs.read of the bridge state is refused" "69 no" "$rc $(ran)"
check "no refusal moved the state" sh -c "[ -d '$CF/state/fixconf' ] && [ ! -L '$CF/state/fixconf' ] && [ ! -e '$CF/ext/fixconf' ]"
confperms '"fs.write:/var/lib/hs/fixconf"'; rc=0; HS_SYSTEMD_RUN=$CF/missing hsc sys ext fixconf rows >/dev/null 2>&1 || rc=$?
check "without systemd-run nothing is moved either" sh -c "[ $rc = 69 ] && [ ! -L '$CF/state/fixconf' ] && [ ! -e '$CF/ext/fixconf' ]"

confperms '"fs.write:/var/lib/hs/fixconf"'; fresh_state; confrun
check_eq "a package that is not installed gets no BindReadOnlyPaths of its folder" "0" "$(grep -c '^--property=BindReadOnlyPaths' "$CF/run.log")"
mkdir -p "$CF/state/current/fixconf"; confrun
check_eq "an installed package gets its own folder back, read-only (the dynamic /var/lib/hs is empty)" "--property=BindReadOnlyPaths=-$CF/state/current/fixconf" "$(grep '^--property=BindReadOnlyPaths' "$CF/run.log")"
rm -rf "$CF/state/current"

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
check_out "it says what is covered" "it covers: writes outside the package.s own state folder" printf '%s' "$PRM"
check_out "it says the confined command is not root" "unprivileged user, not as root" printf '%s' "$PRM"
check_out "it says what is not covered: reads, network, hs and incus" "it does NOT cover: reading the file system.*the network.*incus" bash -c "printf '%s' \"\$0\" | tr '\n' ' '" "$PRM"
check_out "it says the other commands run as root, unconfined" "run as root, unconfined" printf '%s' "$PRM"
check_out "a package without a confined row gets no extra text" 'PLAIN=\[\]' printf '%s' "$PRM"
check_out "an uninstalled package gets none and no error" 'NONE=\[\]' printf '%s' "$PRM"

# --- the dynamic mapping (#1134): what services and confined rows get; the checks of the `dropin` text further above are the mapping without --dynamic ---
ECD="python3 -I $SCRIPTS/lib/ext_confine.py dropin --dynamic --name fixsvc --"
dyn=$($ECD fs.write:/var/lib/hs/fixsvc | sed '1,2d')
check_eq "dynamic: no line binds the bridge state" "0" "$(printf '%s\n' "$dyn" | grep -c 'ext-svc')"
check_eq "dynamic: the user and the state folder" "4" "$(printf '%s\n' "$dyn" | grep -c '^DynamicUser=yes$\|^User=hsx-fixsvc$\|^StateDirectory=hs-ext/fixsvc$\|^StateDirectoryMode=0700$')"
check_eq "dynamic: UMask=0077" "1" "$(printf '%s\n' "$dyn" | grep -c '^UMask=0077$')"
check_eq "dynamic: the own state is not bound (systemd shows it at /var/lib/hs-ext/fixsvc), no BindPaths at all" "0" "$(printf '%s\n' "$dyn" | grep -c '^BindPaths=')"
check_eq "dynamic: the hardening of the old mapping is kept" "$($EC fs.write:/var/lib/hs/fixsvc | grep -c '^Protect\|^Restrict\|^SystemCall\|^Lock\|^NoNew\|^Capab')" "$(printf '%s\n' "$dyn" | grep -v "^ProtectProc" | grep -c '^Protect\|^Restrict\|^SystemCall\|^Lock\|^NoNew\|^Capab')"
check_eq "dynamic: without devices no extra groups" "0" "$($ECD - | grep -c SupplementaryGroups)"
check_eq "dynamic: devices:gpu adds the groups" "1" "$($ECD devices:gpu | grep -c '^SupplementaryGroups=render video$')"
rc=0; err=$($ECD fs.write:/srv/a 2>&1 >/dev/null) || rc=$?
check_eq "dynamic: fs.write outside /var/lib/hs/<name> is refused" "1" "$rc"
check_eq "dynamic: and the refusal has the code" "1" "$(printf '%s\n' "$err" | grep -c 'ext.dynamic-write')"
rc=0; $ECD fs.write:/var/lib/hs/other >/dev/null 2>&1 || rc=$?
check_eq "dynamic: another package's state folder is refused too" "1" "$rc"
check_eq "dynamic: fs.read below the own folder adds no line" "$($ECD - )" "$($ECD fs.read:/var/lib/hs/fixsvc/x)"
check_eq "dynamic: other fs.read is a ReadOnlyPaths line" "1" "$($ECD fs.read:/etc/hs | grep -c '^ReadOnlyPaths=-/etc/hs$')"
rc=0; python3 -I "$SCRIPTS/lib/ext_confine.py" dropin --dynamic --name disks -- - >/dev/null 2>&1 || rc=$?
check_eq "dynamic: a name of the core's own /var/lib/hs folders is refused (ext_state.RESERVED)" "1" "$rc"
rc=0; python3 -I "$SCRIPTS/lib/ext_confine.py" props --dynamic -- - >/dev/null 2>&1 || rc=$?
check_eq "dynamic: props needs the package name" "1" "$rc"
long=$(printf 'a%.0s' $(seq 1 40))
u1=$(python3 -I "$SCRIPTS/lib/ext_confine.py" props --dynamic --name "$long" -- - | sed -n 's/^User=//p')
u2=$(python3 -I "$SCRIPTS/lib/ext_confine.py" props --dynamic --name "$long" -- - | sed -n 's/^User=//p')
check_eq "dynamic: a 40-character name gives a 31-character user" "31" "${#u1}"
check_eq "dynamic: ending in _ and twelve hex digits" "1" "$(printf '%s\n' "$u1" | grep -c -- '_[0-9a-f]\{12\}$')"
check_eq "dynamic: and it is stable" "$u1" "$u2"
rc=0; $EC fs.read:/var/lib/hs-ext/other >/dev/null 2>&1 || rc=$?
check_eq "a grant may never reach another package's dynamic state folder" "1" "$rc"
rc=0; $EC fs.write:/var/lib/private/hs-ext/other >/dev/null 2>&1 || rc=$?
check_eq "nor the private folder behind it" "1" "$rc"

check_eq "dynamic: the old 6-digit cut no longer collides (two names of the review get two users)" "2" "$(for n in media-hub-long-exten-7c910f media-hub-long-extension-name-x; do python3 -I "$SCRIPTS/lib/ext_confine.py" props --dynamic --name "$n" -- - | sed -n 's/^User=//p'; done | sort -u | wc -l | tr -d ' ')"
check_eq "dynamic: injective over many generated names, all within 31 characters" "ok" "$(python3 -I - "$SCRIPTS/lib" <<'PY'
import importlib.util, random, sys
sp = importlib.util.spec_from_file_location("c", sys.argv[1] + "/ext_confine.py"); m = importlib.util.module_from_spec(sp); sp.loader.exec_module(m)
r = random.Random(1); a = "abcdefghijklmnopqrstuvwxyz0123456789-"; seen = {}
names = ["media-hub-long-exten-7c910f", "media-hub-long-extension-name-x"]
for _ in range(20000):
    base = "".join(r.choice(a[:26]) + "".join(r.choice(a) for _ in range(r.randint(0, 39))) for _ in [0])
    names += [base, base[:27], base[:14] + "-x"]
for n in names:
    u = m.unit_user(n)
    assert len(u) <= 31, u
    assert seen.setdefault(u, n) == n, (u, n, seen[u])
print("ok")
PY
)"
rc=0; err=$($ECD fs.read:/var/lib/hs/ext-svc 2>&1 >/dev/null) || rc=$?
check_eq "dynamic: fs.read of the bridge state is refused" "1" "$rc"
check_eq "dynamic: with the code ext.dynamic-read" "1" "$(printf '%s
' "$err" | grep -c 'ext.dynamic-read')"
rc=0; $ECD fs.read:/var/lib/hs/ext/x >/dev/null 2>&1 || rc=$?
check_eq "dynamic: and of /var/lib/hs/ext" "1" "$rc"
rc=0; $ECD fs.read:/var/lib/hs-ext/other >/dev/null 2>&1 || rc=$?
check_eq "dynamic: and of another extension's state" "1" "$rc"
check_eq "dynamic: ProtectProc=invisible" "1" "$($ECD - | grep -c '^ProtectProc=invisible$')"
check_eq "a literal --dynamic after -- is a permission, not the mode" "0" "$(python3 -I "$SCRIPTS/lib/ext_confine.py" props --name fixsvc -- --dynamic | grep -c '^DynamicUser=')"

finish
