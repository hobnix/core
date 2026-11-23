#!/usr/bin/env bash
# What a confined extension service can and cannot reach (#1130, ADR 0014 and 0011): the sandbox properties, the transient unit the bridge builds
# (ext_service.py confined_program), the keys as LoadCredential, and the `rollup` message that replaces a shell-out to `hs sys state rollup-add`.
# Not run here: the real systemd sandbox (stage `confine`/hardware): this checks the generated properties and arguments only. No root, python3 only.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
command -v python3 >/dev/null || { echo "python3 missing: skipped"; exit 0; }
EC="python3 -I $SCRIPTS/lib/ext_confine.py dropin --name media --"

echo "-- what the sandbox of a service hides (the finding: it hides what the old shell-outs needed)"
P=$($EC integration:media fs.write:/var/lib/hs/media)
check_eq "/var/lib/hs is an empty tmpfs: no state.db for rollup-add, no key files" "1" "$(printf '%s\n' "$P" | grep -c '^TemporaryFileSystem=/var/lib/hs:ro$')"
check_eq "only ext-svc and the granted path are bound back" "1" "$(printf '%s\n' "$P" | grep -c '^BindPaths=-/var/lib/hs/ext-svc -/var/lib/hs/media$')"
check_eq "the package folders (/etc/nixos, /var/lib/hs/packages) are not granted by integration:media" "0" "$(printf '%s\n' "$P" | grep -c 'packages\|key')"
check_eq "/etc/nixos is inaccessible" "1" "$(printf '%s\n' "$P" | grep -c '^InaccessiblePaths=.*-/etc/nixos')"
rc=0; $EC fs.read:/var/lib/hs/radarr/api-key >/dev/null 2>&1 || rc=$?
check_eq "a key file cannot be granted with fs.read (the way to it is LoadCredential)" "1" "$rc"
check_eq "the bridge unit sets no sandbox (it writes state.db)" "0" "$(sed -n '/systemd.services."hs-ext-svc@"/,/^  };/p' "$ROOT/configuration.nix" | grep -c 'TemporaryFileSystem\|ProtectSystem')"

echo "-- the transient unit of the service"
python3 -I - "$SCRIPTS" "$WORK" <<'PY' > "$WORK/unit.txt" 2>&1 || true
import importlib.util, os, sys
s = importlib.util.spec_from_file_location("es", os.path.join(sys.argv[1], "lib", "ext_service.py")); es = importlib.util.module_from_spec(s); s.loader.exec_module(es)
pk = os.path.join(sys.argv[2], "pk", "media"); os.makedirs(pk)
root = os.path.join(sys.argv[2], "lib"); os.makedirs(os.path.join(root, "radarr")); es.LIB_DIR = root   # the state root of the test
os.environ["HS_CRED_DIR"] = os.path.join(sys.argv[2], "cred")
key = os.path.join(root, "radarr", "api-key"); open(key, "w").write("SECRET-KEY\n")
open(os.path.join(pk, "package.toml"), "w").write('name = "media"\npermissions = ["integration:media", "fs.write:/var/lib/hs/media"]\n')
cmd, bad = es.confined_program("media", pk, ["python3", "svc.py"], [("integration-media", "radarr", key)])
print("CMD=" + " ".join(cmd)); print("BAD=%r" % bad)
cp = os.path.join(sys.argv[2], "cred", "media", "integration-media")
print("COPY=%r MODE=%o DIR=%o" % (open(cp).read(), os.stat(cp).st_mode & 0o777, os.stat(os.path.dirname(cp)).st_mode & 0o777))
print("NOKEYINARGV=%r" % ("SECRET-KEY" not in " ".join(cmd)))
es.drop_creds("media"); print("DROPPED=%r" % (not os.path.exists(cp)))
cmd, bad = es.confined_program("media", root + "/packages/current/media", ["x"], [("integration-media", "radarr", key)])
print("INS=" + " ".join(cmd))
cmd, bad = es.confined_program("media", pk, ["x"], [("Bad Name", "radarr", "/k")]); print("BADCRED=%r" % bad)
open(os.path.join(pk, "package.toml"), "w").write('name = "media"\npermissions = ["fs.write:/etc/hs"]\n')
cmd, bad = es.confined_program("media", pk, ["x"]); print("BADPERM=%r" % (bad is not None))
PY
check_out "it runs under systemd-run with a name of its own" "CMD=systemd-run --pipe --wait --collect --quiet --unit=hs-ext-run-media " cat "$WORK/unit.txt"
check_out "the key goes as LoadCredential (a file name, never the key)" "property=LoadCredential=integration-media:.*/cred/media/integration-media" cat "$WORK/unit.txt"
check_out "systemd gets a private 0600 copy in a 0700 folder, not the original path" "COPY='SECRET-KEY\\\\n' MODE=600 DIR=700" cat "$WORK/unit.txt"
check_out "the key text is never in the arguments" "NOKEYINARGV=True" cat "$WORK/unit.txt"
check_out "the copy is removed when the service ends" "DROPPED=True" cat "$WORK/unit.txt"
check_out "the sandbox properties come from the declared permissions" "property=TemporaryFileSystem=/var/lib/hs:ro .*property=BindPaths=-/var/lib/hs/ext-svc -/var/lib/hs/media" cat "$WORK/unit.txt"
check_out "a package folder below /var/lib/hs is bound back read only" "INS=.*property=BindReadOnlyPaths=-.*/lib/packages/current/media" cat "$WORK/unit.txt"
check_out "a bad credential name is refused" "BADCRED=.bad credential" cat "$WORK/unit.txt"
check_out "a bad permission path means no run (fail closed)" "BADPERM=True" cat "$WORK/unit.txt"

echo "-- keys: only declared integration:<name> permissions are granted (integration.sh)"
H=$WORK/here; mkdir -p "$H" "$WORK/keys"; : > "$WORK/keys/api-key"
python3 -I - "$H/pkg.py" "$WORK/keys/api-key" <<'PY'
import sys
open(sys.argv[1], "w", newline="\n").write('''import sys
a = sys.argv[1:]
if a[0] == "perms":
    print("integration:media"); print("integration:gone"); print("fs.read:/etc/hs")
elif a[0] == "integration-grant":
    if a[1] == "media": print(%r + "\\tradarr")
    else: print("no such integration"); sys.exit(1)
''' % sys.argv[2])
PY
: > "$H/recipes-list.sh"; : > "$H/parts.sh"
out=$(bash -c ". '$SCRIPTS/lib/ui.sh'; here='$H'; . '$SCRIPTS/lib/integration.sh'; integration_credentials media" 2>/dev/null) || true
check_eq "a declared integration with a key file is listed (name, path, providing package)" "media	$WORK/keys/api-key	radarr" "$out"
check_eq "a declared one that is refused is skipped, an fs permission is ignored" "1" "$(printf '%s\n' "$out" | grep -c .)"
check_out "the bridge gets them as --credential, not as the key" "credential \"integration-" grep -n 'credential "integration-' "$SCRIPTS/ext.sh"

echo "-- rollup: a message of the service channel, only for a declared metric kind"
python3 -I - "$SCRIPTS" "$WORK" <<'PY' > "$WORK/roll.txt" 2>&1 || true
import importlib.util, os, sys
s = importlib.util.spec_from_file_location("es", os.path.join(sys.argv[1], "lib", "ext_service.py")); es = importlib.util.module_from_spec(s); s.loader.exec_module(es)
pk = os.path.join(sys.argv[2], "pk", "rl"); os.makedirs(pk)
open(os.path.join(pk, "package.toml"), "w").write('name = "rl"\n[[events]]\nkind = "pkg.rl.watch"\nretention = "metric"\n[[events]]\nkind = "pkg.rl.other"\n')
log = os.path.join(sys.argv[2], "roll.log"); sh = os.path.join(sys.argv[2], "roll.sh")
open(sh, "w", newline="\n").write('#!/bin/sh\necho "$@" >> %s\n' % log); os.chmod(sh, 0o755)
os.environ["HS_EXT_ROLLUP"] = sh
warns = []
h = es.make_handler("rl", warn=warns.append, pkgdir=pk)
ok = {"v": 1, "type": "rollup", "kind": "pkg.rl.watch", "user": "anna", "n": 2, "sum": 90.5}
print("VALID=%r" % es.check_message(ok))
h(ok); h(dict(ok, kind="pkg.rl.other")); h(dict(ok, kind="pkg.zz.watch")); h(dict(ok, kind="pkg.rl.other"))
print("LOG=" + open(log).read().strip().replace("\n", "|")); print("WARNS=%d" % len(warns))
for bad in (dict(ok, user="a b"), dict(ok, kind="x"), dict(ok, n="2"), dict(ok, sum=True), dict(ok, user="--time"), dict(ok, user="anna" + chr(10)), dict(ok, kind="pkg.x.-y")):
    print("BAD=%r" % (es.check_message(bad) is not None))
PY
check_out "a valid rollup message passes the check" "VALID=None" cat "$WORK/roll.txt"
check_out "a declared metric kind reaches rollup-add with kind user n sum" "LOG=pkg.rl.watch anna --n 2 --sum 90.500000$" cat "$WORK/roll.txt"
check_out "a kind without retention = metric, or of another package, is dropped and warned once each" "WARNS=2" cat "$WORK/roll.txt"
check_eq "bad messages are refused (user, kind, n as text, sum as boolean, a user that is an option, a user with a newline, kind pkg.x.-y)" "7" "$(grep -c 'BAD=True' "$WORK/roll.txt")"


echo "-- a hostile manifest cannot get a root-read of another file (review of #1133)"
python3 -I - "$SCRIPTS" "$WORK" <<'PY' > "$WORK/host.txt" 2>&1 || true
import importlib.util, os, sys
def load(n):
    s = importlib.util.spec_from_file_location(n, os.path.join(sys.argv[1], "lib", n + ".py")); m = importlib.util.module_from_spec(s); s.loader.exec_module(m); return m
pi = load("pkg_integrations"); es = load("ext_service")
os.environ["HS_CRED_DIR"] = os.path.join(sys.argv[2], "cred2")
root = os.path.join(sys.argv[2], "hs"); os.makedirs(os.path.join(root, "radarr")); os.makedirs(os.path.join(root, "evil"))
open(os.path.join(root, "radarr", "key"), "w").write("k")
os.symlink("/etc/passwd", os.path.join(root, "radarr", "leak"))
os.symlink("/etc", os.path.join(root, "evil", "dir"))
f = lambda p, prov="radarr", caller="media": pi.key_file_problem(p, prov, caller, root=root, resolve=True)
print("OK=%r" % f(root + "/radarr/key"))
print("SHADOW=%r" % (f("/etc/shadow") is not None))
print("OTHER=%r" % (f(root + "/restic-password") is not None))
print("DOTS=%r" % (f(root + "/radarr/../restic-password") is not None))
print("SELF=%r" % (f(root + "/radarr/key", "radarr", "radarr") is not None))
print("LINKFILE=%r" % (f(root + "/radarr/leak") is not None))
print("LINKDIR=%r" % (f(root + "/evil/dir/shadow", "evil") is not None))
print("NL=%r" % (f(root + "/radarr/key\n") is not None))
print("VALIDATOR=%r" % pi.manifest_problems({"name": "evil", "integrations": {"x": {"key_file": "/etc/shadow"}}}))
ms = [("", {"name": "evil", "kind": "recipe", "integrations": {"x": {"key_file": "/etc/shadow"}}}), ("", {"name": "e", "kind": "extension", "permissions": ["integration:x"]})]
print("GRANT=%r" % (pi.grant(ms, {"evil"}, "x", "e")[0],))
es.LIB_DIR = root
cmd, bad = es.confined_program("media", "/tmp/nopkg", ["x"], [("integration-x", "radarr", "/etc/shadow")]); print("BRIDGE=%r" % (bad is not None))
cmd, bad = es.confined_program("media", "/tmp/nopkg", ["x"], [("integration-x", "radarr", root + "/evil/k")]); print("BRIDGEPROV=%r" % (bad is not None))
os.makedirs(os.path.join(root, "disks")); open(os.path.join(root, "disks", "k"), "w").write("x")
print("RESERVED=%r" % (f(root + "/disks/k", "disks") is not None))
print("RESERVED2=%r" % (pi.read_key(root + "/disks/k", "disks", "media", root=root)[1] is not None))
print("LEAK=%r" % (pi.read_key(root + "/radarr/leak", "radarr", "media", root=root)[1] is not None))
# a link swap after the check: the check is made to pass as if the file had been fine a moment ago, then the file is a link to /etc/passwd
os.symlink("/etc/passwd", os.path.join(root, "radarr", "swapped"))
real_check = pi.key_file_problem; pi.key_file_problem = lambda *a, **k: None
print("SWAP=%r" % (pi.read_key(root + "/radarr/swapped", "radarr", "media", root=root)[1] is not None))
pi.key_file_problem = real_check
# the vault: a link that ends at a regular file in the vault is fine, one that ends at a directory or outside is not
vault = os.path.join(sys.argv[2], "vault"); os.makedirs(vault); os.environ["HS_VAULT_DIR"] = vault
dz = pi.designated(root + "/radarr/vk", root); os.makedirs(os.path.dirname(dz)); open(dz, "w").write("vk"); os.symlink(dz, os.path.join(root, "radarr", "vk"))
open(os.path.join(vault, "k"), "w").write("other"); os.symlink(os.path.join(vault, "k"), os.path.join(root, "radarr", "vother"))
print("VAULTOTHER=%r" % (pi.read_key(root + "/radarr/vother", "radarr", "media", root=root)[1] is not None))
os.symlink(vault, os.path.join(root, "radarr", "vdir"))
print("VAULTOK=%r" % (pi.read_key(root + "/radarr/vk", "radarr", "media", root=root),))
print("VAULTDIR=%r" % (pi.read_key(root + "/radarr/vdir", "radarr", "media", root=root)[1] is not None))
print("DIRKEY=%r" % (pi.read_key(root + "/radarr", "radarr", "media", root=root)[1] is not None))
print("GRANTFULL=%r" % (pi.grant_full([("", {"name": "radarr", "kind": "recipe", "integrations": {"m": {"key_file": "/var/lib/hs/radarr/key"}}}), ("", {"name": "e", "kind": "capability"})], {"radarr"}, "m", "e"),))
PY
check_out "a good key file in the provider's folder passes" "OK=None" cat "$WORK/host.txt"
for k in VAULTOTHER SHADOW OTHER DOTS SELF LINKFILE LINKDIR NL BRIDGE BRIDGEPROV RESERVED RESERVED2 LEAK SWAP VAULTDIR DIRKEY; do check_out "key file check refuses: $k" "^$k=True" cat "$WORK/host.txt"; done
check_out "a link to exactly the vault file designated for it is read; a link to another vault file is refused (VAULTOTHER above)" "VAULTOK=\\(b'vk', None\\)" cat "$WORK/host.txt"
check_out "grant_full names the registered providing package" "GRANTFULL=.*radarr" cat "$WORK/host.txt"
check_out "the validator refuses key_file=/etc/shadow" "VALIDATOR=.*key_file" cat "$WORK/host.txt"
check_out "grant hands out no key for it (integration_key and LoadCredential are built on grant)" "GRANT=None" cat "$WORK/host.txt"

echo "-- a newline or control character in a permission is refused"
rc=0; python3 -I "$SCRIPTS/lib/ext_confine.py" dropin --name media -- $'fs.write:/etc\n' >/dev/null 2>&1 || rc=$?
check_eq "ext_confine refuses fs.write:/etc<newline>" "1" "$rc"
rc=0; python3 -I "$SCRIPTS/lib/ext_confine.py" dropin --name media -- $'fs.write:/srv/ok\n' >/dev/null 2>&1 || rc=$?
check_eq "and a harmless path with a trailing newline" "1" "$rc"
check_eq "pkg_perms refuses it too" "1" "$(python3 -I -c "
import importlib.util
s = importlib.util.spec_from_file_location('p', '$SCRIPTS/lib/pkg_perms.py'); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
print(int(m.check_one('x', 'fs.write:/srv/ok' + chr(10)) is not None))")"
check_eq "the bridge refuses it before it builds the unit (cmd_boot never ran svc_confine)" "1" "$(python3 -I - "$SCRIPTS" "$WORK" <<'PY'
import importlib.util, os, sys
s = importlib.util.spec_from_file_location("es", os.path.join(sys.argv[1], "lib", "ext_service.py")); es = importlib.util.module_from_spec(s); s.loader.exec_module(es)
pk = os.path.join(sys.argv[2], "pk", "nl"); os.makedirs(pk)
open(os.path.join(pk, "package.toml"), "w").write('name = "nl"\npermissions = ["fs.write:/etc\\n"]\n')
print(int(es.confined_program("nl", pk, ["x"])[1] is not None))
PY
)"

echo "-- rollup-add itself takes a float sum (the real path, not a fake)"
SD=$WORK/sdb; mkdir -p "$SD"
rs() { HS_PLAIN=1 HS_LANG=en HS_CALLER=test HS_STATE_DIR=$SD bash "$SCRIPTS/state.sh" "$@"; }
rc=0; rs rollup-add pkg.rl.watch --time --n 1 >/dev/null 2>&1 || rc=$?
check_eq "rollup-add refuses a user that starts with a dash (it would be an option)" "1" "$rc"
rc=0; rs rollup-add pkg.rl.watch anna --n 2.0 --sum 90.5 >/dev/null 2>&1 || rc=$?
check_eq "n 2.0 and sum 90.5 are stored (exit 0)" "0" "$rc"
check_eq "the fraction is rounded to the whole-number column" "pkg.rl.watch	2	91" "$(rs rollups pkg.rl.watch anna | cut -f3-5)"
rc=0; err=$(rs rollup-add pkg.rl.watch anna --sum -3 2>&1 >/dev/null) || rc=$?
check_eq "a negative number is refused with a message" "1" "$rc"
check_out "the message names the option" "rollup-add: --sum needs a number" printf '%s' "$err"
python3 -I - "$SCRIPTS" "$WORK" "$SD" <<'PY' > "$WORK/real.txt" 2>&1 || true
import importlib.util, os, sys
s = importlib.util.spec_from_file_location("es", os.path.join(sys.argv[1], "lib", "ext_service.py")); es = importlib.util.module_from_spec(s); s.loader.exec_module(es)
os.environ.update({"HS_STATE_DIR": sys.argv[3], "HS_PLAIN": "1", "HS_LANG": "en", "HS_CALLER": "test"})
os.environ.pop("HS_EXT_ROLLUP", None)
m = {"v": 1, "type": "rollup", "kind": "pkg.rl.watch", "user": "anna", "n": 2.0, "sum": 90.5}
print("CHECK=%r" % es.check_message(m)); print("STORED=%r" % es.rollup_add(m))
print("NEG=%r" % (es.check_message(dict(m, sum=-1)) is not None)); print("INF=%r" % (es.check_message(dict(m, sum=float("inf"))) is not None))
os.environ["HS_EXT_ROLLUP"] = "/bin/false"
print("WARN=%r" % (es.rollup_add(m) is not None))
PY
check_out "the bridge stores a Rust-style float rollup through the real rollup-add" "STORED=None" cat "$WORK/real.txt"
check_out "a refused rollup gives the bridge a reason to warn about" "WARN=True" cat "$WORK/real.txt"
check_out "a negative or infinite number is refused by the message check" "NEG=True.*INF=True" bash -c "tr '\n' ' ' < '$WORK/real.txt'"
check_eq "the second add of the month sums up: n 4, sum 182" "pkg.rl.watch	4	182" "$(rs rollups pkg.rl.watch anna | cut -f3-5)"

echo "-- the transient unit: no orphan, PATH set"
check_out "it is bound to the bridge unit and has a stop timeout" "property=BindsTo=hs-ext-svc@media.service .*property=TimeoutStopSec=15|property=TimeoutStopSec=15 .*property=BindsTo=hs-ext-svc@media.service" cat "$WORK/unit.txt"
check_out "it gets an explicit PATH" "setenv=PATH=" cat "$WORK/unit.txt"
check_eq "the bridge stops the unit before it starts and in a finally" "2" "$(grep -c "^ *stop_unit(name)" "$SCRIPTS/lib/ext_service.py")"

echo "-- other services cannot reach the key copies or the vault (review 3)"
check_eq "the transient unit hides the vault and the key copies" "2" "$(grep -c 'property=InaccessiblePaths=.*-/var/lib/hs-vault -/run/hs-ext-cred' "$WORK/unit.txt")"
check_eq "fs.read of the vault or the copies cannot be granted" "1 1" "$($EC fs.read:/var/lib/hs-vault >/dev/null 2>&1; echo -n $?) $($EC fs.read:/run/hs-ext-cred/x >/dev/null 2>&1; echo $?)"
python3 -I - "$SCRIPTS" "$WORK" <<'PY' > "$WORK/sweep.txt" 2>&1 || true
import importlib.util, os, sys
s = importlib.util.spec_from_file_location("es", os.path.join(sys.argv[1], "lib", "ext_service.py")); es = importlib.util.module_from_spec(s); s.loader.exec_module(es)
cr = os.path.join(sys.argv[2], "credroot"); os.environ["HS_CRED_DIR"] = cr
for n in ("mine", "running", "crashed"):
    os.makedirs(os.path.join(cr, n)); open(os.path.join(cr, n, "integration-x"), "w").write("k")
es.sweep_creds("mine", active=lambda n: n == "running")
print("LEFT=%s" % ",".join(sorted(os.listdir(cr))))
es.make_private_dir(cr); es.make_private_dir(os.path.join(cr, "new"))
print("MODE=%o %o" % (os.stat(cr).st_mode & 0o777, os.stat(os.path.join(cr, "new")).st_mode & 0o777))
PY
check_out "a bridge start removes the copies of a crash and of units that are not running" "LEFT=running" cat "$WORK/sweep.txt"
check_out "the folders are 0700" "MODE=700 700" cat "$WORK/sweep.txt"
check_eq "a service that reaches running has no copy left (drop_creds in on_state)" "1" "$(grep -c 'if s == "running":' "$SCRIPTS/lib/ext_service.py")"

echo "-- the key copy folder exists before the first unit is built (review 4)"
python3 -I - "$SCRIPTS" "$WORK" <<'PY' > "$WORK/first.txt" 2>&1 || true
import importlib.util, os, sys
s = importlib.util.spec_from_file_location("es", os.path.join(sys.argv[1], "lib", "ext_service.py")); es = importlib.util.module_from_spec(s); s.loader.exec_module(es)
cr = os.path.join(sys.argv[2], "first-cred"); os.environ["HS_CRED_DIR"] = cr
pk = os.path.join(sys.argv[2], "pk", "plain"); os.makedirs(pk); open(os.path.join(pk, "package.toml"), "w").write('name = "plain"\npermissions = []\n')
print("BEFORE=%r" % os.path.isdir(cr))
cmd, bad = es.confined_program("plain", pk, ["x"])
print("AFTER=%r MODE=%o" % (os.path.isdir(cr), os.stat(cr).st_mode & 0o777)); print("PRIVATE=%r" % ("--property=MountFlags=private" in cmd))
os.rmdir(cr); es.sweep_creds("plain"); print("SWEEP=%r" % os.path.isdir(cr))
PY
check_out "a service without credentials creates the folder (0700) when its unit is built" "BEFORE=False AFTER=True MODE=700" bash -c "tr '\n' ' ' < '$WORK/first.txt'"
check_out "the bridge start creates it before the sweep" "SWEEP=True" cat "$WORK/first.txt"
check_out "the transient unit does not take mounts from the host (an unlocked vault cannot appear over the hidden path)" "PRIVATE=True" cat "$WORK/first.txt"

echo "-- core folder names are reserved, scanned from the code (review 3)"
python3 -I - "$SCRIPTS" "$ROOT" <<'PY' > "$WORK/resv.txt" 2>&1 || true
import importlib.util, os, re, sys
s = importlib.util.spec_from_file_location("pi", os.path.join(sys.argv[1], "lib", "pkg_integrations.py")); pi = importlib.util.module_from_spec(s); s.loader.exec_module(pi)
for n in ("unifi", "backup-dc", "backup-instances", "remote-x", "node-key-abc", "docker-registry-x", "recipe-x", "disks", "ext", "vault"):
    print("R_%s=%r" % (n, pi.is_reserved(n)))
print("R_radarr=%r" % pi.is_reserved("radarr"))
# every /var/lib/hs/<dir> or $state/<dir> the core code names must be reserved or a documented example (an app or example folder of a package)
DOC = {"hs", "radarr", "lock", "media", "fixsvc"}
root = sys.argv[2]; pats = [re.compile(r"/var/lib/hs/([a-z][a-z0-9-]*)"), re.compile(r"join\((?:state_root\(\)|LIB_DIR|STATE|\"/var/lib/hs\")\s*,\s*\"([a-z][a-z0-9-]*)\""), re.compile(r"\$\{?(?:state|STATE|HS_STATE_DIR(?::-[^}]*)?|state_dir)\}?/([a-z][a-z0-9-]*)")]
files = [os.path.join(root, "configuration.nix")]
for dp, dn, fn in os.walk(os.path.join(root, "capabilities")):
    files += [os.path.join(dp, f) for f in fn if f.endswith(".nix")]
for dp, dn, fn in os.walk(os.path.join(root, "scripts")):
    dn[:] = [x for x in dn if x not in ("__pycache__", "dev")]
    files += [os.path.join(dp, f) for f in fn if f.endswith((".sh", ".py"))]
miss = set()
for f in files:
    t = open(f, encoding="utf-8", errors="ignore").read()
    for p in pats:
        for m in p.finditer(t):
            if not pi.is_reserved(m.group(1)) and m.group(1) not in DOC:
                miss.add(m.group(1))
print("UNRESERVED=%s" % ",".join(sorted(miss)))
PY
for n in unifi backup-dc backup-instances remote-x node-key-abc docker-registry-x recipe-x disks ext vault; do check_out "$n is reserved" "R_$n=True" cat "$WORK/resv.txt"; done
check_out "radarr (an app) is not reserved" "R_radarr=False" cat "$WORK/resv.txt"
check_out "the code uses no /var/lib/hs folder that is neither reserved nor a documented example (add it to RESERVED in pkg_integrations.py)" "UNRESERVED=$" cat "$WORK/resv.txt"

echo "-- a manifest whose name is not its folder, or a duplicate name, is ignored (review 3)"
PR=$WORK/pkgroot; mkdir -p "$PR/packages/aaa" "$PR/capabilities/bbb" "$PR/capabilities/aaa"
printf 'name = "aaa"\nkind = "recipe"\n' > "$PR/packages/aaa/package.toml"
printf 'name = "aaa"\nkind = "extension"\n' > "$PR/capabilities/aaa/package.toml"
printf 'name = "radarr"\nkind = "extension"\n' > "$PR/capabilities/bbb/package.toml"
out=$(HS_PACKAGES_ROOT=$PR HS_STATE_DIR=$WORK/nostate python3 -I - "$SCRIPTS" 2>"$WORK/mf.err" <<'PY'
import importlib.util, os, sys
s = importlib.util.spec_from_file_location("pkgmod", os.path.join(sys.argv[1], "pkg.py")); m = importlib.util.module_from_spec(s); sys.modules["pkgmod"] = m; s.loader.exec_module(m)
print(",".join("%s:%s" % (os.path.basename(os.path.dirname(p)), d["kind"]) for p, d in m.manifests(True)))
PY
) || true
check_eq "the first package of a name wins, a name that is not the folder is dropped" "aaa:recipe" "$out"
check_out "and both are said on stderr" "name is not its folder name" cat "$WORK/mf.err"
check_out "the duplicate too" "another package has the name aaa" cat "$WORK/mf.err"

finish
