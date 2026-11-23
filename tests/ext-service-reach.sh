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
open(os.path.join(pk, "package.toml"), "w").write('name = "media"\npermissions = ["integration:media", "fs.write:/var/lib/hs/media"]\n')
cmd, bad = es.confined_program("media", pk, ["python3", "svc.py"], [("integration-media", "/var/lib/hs/radarr/api-key")])
print("CMD=" + " ".join(cmd)); print("BAD=%r" % bad)
cmd, bad = es.confined_program("media", "/var/lib/hs/packages/current/media", ["x"], [("integration-media", "/k")])
print("INS=" + " ".join(cmd))
cmd, bad = es.confined_program("media", pk, ["x"], [("Bad Name", "/k")]); print("BADCRED=%r" % bad)
open(os.path.join(pk, "package.toml"), "w").write('name = "media"\npermissions = ["fs.write:/etc/hs"]\n')
cmd, bad = es.confined_program("media", pk, ["x"]); print("BADPERM=%r" % (bad is not None))
PY
check_out "it runs under systemd-run with a name of its own" "CMD=systemd-run --pipe --wait --collect --quiet --unit=hs-ext-run-media " cat "$WORK/unit.txt"
check_out "the key goes as LoadCredential (a file name, never the key)" "property=LoadCredential=integration-media:/var/lib/hs/radarr/api-key" cat "$WORK/unit.txt"
check_out "the sandbox properties come from the declared permissions" "property=TemporaryFileSystem=/var/lib/hs:ro .*property=BindPaths=-/var/lib/hs/ext-svc -/var/lib/hs/media" cat "$WORK/unit.txt"
check_out "a package folder below /var/lib/hs is bound back read only" "INS=.*property=BindReadOnlyPaths=-/var/lib/hs/packages/current/media" cat "$WORK/unit.txt"
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
elif a[0] == "integration-key":
    if a[1] == "media": print(%r)
    else: print("no such integration"); sys.exit(1)
''' % sys.argv[2])
PY
: > "$H/recipes-list.sh"; : > "$H/parts.sh"
out=$(bash -c ". '$SCRIPTS/lib/ui.sh'; here='$H'; . '$SCRIPTS/lib/integration.sh'; integration_credentials media" 2>/dev/null) || true
check_eq "a declared integration with a key file is listed (name, path)" "media	$WORK/keys/api-key" "$out"
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
for bad in (dict(ok, user="a b"), dict(ok, kind="x"), dict(ok, n="2"), dict(ok, sum=True)):
    print("BAD=%r" % (es.check_message(bad) is not None))
PY
check_out "a valid rollup message passes the check" "VALID=None" cat "$WORK/roll.txt"
check_out "a declared metric kind reaches rollup-add with kind user n sum" "LOG=pkg.rl.watch anna --n 2 --sum 90.5$" cat "$WORK/roll.txt"
check_out "a kind without retention = metric, or of another package, is dropped and warned once each" "WARNS=2" cat "$WORK/roll.txt"
check_eq "bad messages are refused (user, kind, n as text, sum as boolean)" "4" "$(grep -c 'BAD=True' "$WORK/roll.txt")"

finish
