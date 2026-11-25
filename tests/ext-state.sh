#!/usr/bin/env bash
# The one-time move of a service's state folder (#1134 slice S1, scripts/lib/ext_state.py): /var/lib/hs/<name> -> /var/lib/hs-ext/<name> by ONE
# atomic rename, a link left behind; both folders, another file system, a wrong link, a crash between the steps. No root; the three roots are
# folders under $WORK (HS_STATE_DIR, HS_EXT_STATE_DIR, HS_PRIVATE_DIR). Also pins the two new paths of the host backup.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
command -v python3 >/dev/null || { echo "python3 missing: skipped"; exit 0; }
ES="python3 -I $SCRIPTS/lib/ext_state.py"
N=0
setup() {   # fresh roots; the private folder is where the public path points to (systemd does that on a real server)
  R=$WORK/r$((++N)); rm -rf "$R"; mkdir -p "$R/hs" "$R/ext" "$R/private/hs-ext"
  export HS_STATE_DIR=$R/hs HS_EXT_STATE_DIR=$R/ext HS_PRIVATE_DIR=$R/private
}
tree() { (cd "$1" && find . -printf '%p %y %m %s\n' 2>/dev/null | sort; find . -type f -exec cksum {} + 2>/dev/null | sort); }

echo "-- the move"
setup; mkdir -p "$R/hs/posters/sub"; chmod 0755 "$R/hs/posters"; echo data > "$R/hs/posters/a.png"; echo deep > "$R/hs/posters/sub/b"; chmod 0600 "$R/hs/posters/a.png"; chmod 0750 "$R/hs/posters/sub"
out=$($ES prepare posters 2>&1); check_eq "a real folder is moved" "moved	-" "$out"
check_eq "the content is intact" "data deep" "$(cat "$R/ext/posters/a.png" "$R/ext/posters/sub/b" | tr '\n' ' ' | sed 's/ $//')"
check_eq "the old path is a link to the new folder" "$R/ext/posters" "$(readlink "$R/hs/posters")"
check_eq "modes are kept" "600 750" "$(stat -c %a "$R/ext/posters/a.png") $(stat -c %a "$R/ext/posters/sub")"
check_eq "the owner is kept" "$(id -u)" "$(stat -c %u "$R/ext/posters/a.png")"
check_eq "the moved folder is closed (0700) before systemd takes it over: no group or other access" "700" "$(stat -c %a "$R/ext/posters")"
check_eq "a second run changes nothing" "ok	-" "$($ES prepare posters 2>&1)"
check_eq "a third run too" "ok	-" "$($ES prepare posters 2>&1)"

echo "-- a crash between the rename and the link"
setup; mkdir -p "$R/ext/posters"; chmod 0755 "$R/ext/posters"; echo x > "$R/ext/posters/f"
check_eq "old missing, new present: the link is made" "linked	-" "$($ES prepare posters 2>&1)"
check_eq "the link points to the new folder" "$R/ext/posters" "$(readlink "$R/hs/posters")"
check_eq "an open public folder is closed too (no group or other access)" "700" "$(stat -c %a "$R/ext/posters")"
check_eq "and the next run is ok" "ok	-" "$($ES prepare posters 2>&1)"
setup; mkdir -p "$R/private/hs-ext/posters"
check_eq "only the private folder exists (systemd made it): linked" "linked	-" "$($ES prepare posters 2>&1)"

echo "-- the bridge and a command prepare the same package at once"
fails=0
for _ in 1 2 3 4 5 6 7 8; do
  setup; mkdir -p "$R/hs/posters"; echo data > "$R/hs/posters/f"
  pids=""; for _ in 1 2 3 4; do $ES prepare posters >/dev/null 2>&1 & pids="$pids $!"; done
  for p in $pids; do wait "$p" || fails=$((fails + 1)); done
  [ "$(readlink "$R/hs/posters")" = "$R/ext/posters" ] && [ "$(cat "$R/ext/posters/f" 2>/dev/null)" = data ] || fails=$((fails + 100))
done
check_eq "all of them succeed and the data is behind the one link" 0 "$fails"

echo "-- both folders exist: refuse, change nothing"
setup; mkdir -p "$R/hs/posters" "$R/ext/posters"; echo a > "$R/hs/posters/a"; echo b > "$R/ext/posters/b"
before=$(tree "$R")
if out=$($ES prepare posters 2>&1); then fail "both exist was accepted: $out"; else
  case $out in "ext.state-conflict: both $R/hs/posters and $R/ext/posters exist; nothing was moved") pass "refused and names both folders";; *) fail "text: $out";; esac; fi
check_eq "nothing changed on disk" "$before" "$(tree "$R")"
setup; mkdir -p "$R/hs/posters" "$R/private/hs-ext/posters"; echo a > "$R/hs/posters/a"; before=$(tree "$R")
if $ES prepare posters >/dev/null 2>&1; then fail "old and private folder accepted"; else pass "old and private folder: refused"; fi
check_eq "nothing changed on disk (private)" "$before" "$(tree "$R")"

echo "-- other states of the old path"
setup; echo x > "$R/hs/posters"
if out=$($ES prepare posters 2>&1); then fail "a file was accepted"; else case $out in "ext.state-conflict: $R/hs/posters is not a folder") pass "a file is refused";; *) fail "text: $out";; esac; fi
setup; ln -s /elsewhere "$R/hs/posters"
if out=$($ES prepare posters 2>&1); then fail "a wrong link was accepted"; else case $out in "ext.state-conflict: $R/hs/posters is a link to /elsewhere, not $R/ext/posters") pass "a link to somewhere else is refused";; *) fail "text: $out";; esac; fi
check_eq "and left alone" "/elsewhere" "$(readlink "$R/hs/posters")"
setup; mkdir -p "$R/ext/posters"; ln -s "$R/ext/posters" "$R/hs/posters"
check_eq "the right link already there: ok" "ok	-" "$($ES prepare posters 2>&1)"
setup
check_eq "nothing anywhere: fresh" "fresh	-" "$($ES prepare posters 2>&1)"
check "fresh makes no link (it would dangle)" test ! -L "$R/hs/posters"
mkdir -p "$R/ext/posters"
check_eq "link after start makes it" "ok	-" "$($ES link posters 2>&1)"
check_eq "the link points to the new folder" "$R/ext/posters" "$(readlink "$R/hs/posters")"
check_eq "link again changes nothing" "ok	-" "$($ES link posters 2>&1)"
setup; check_eq "link without a public folder does nothing" "ok	-" "$($ES link posters 2>&1)"; check "no dangling link" test ! -L "$R/hs/posters"
for bad in "../x" "Posters" "a/b" "-x"; do
  if $ES prepare "$bad" >/dev/null 2>&1; then fail "name '$bad' accepted"; else pass "name '$bad' refused"; fi
done

echo "-- another file system"
setup; mkdir -p "$R/hs/posters"; echo a > "$R/hs/posters/a"; before=$(tree "$R")
out=$(python3 -I - "$SCRIPTS/lib" <<'PY' 2>&1
import errno, os, sys
sys.path.insert(0, sys.argv[1])
import ext_state
def boom(a, b):
    raise OSError(errno.EXDEV, "Invalid cross-device link")
os.rename = boom
print(ext_state.prepare("posters"))
PY
)
case $out in "(None, '"*"ext.state-move-failed: "*"is on another file system than "*"; nothing was moved')") pass "EXDEV is refused, no copy";; *) fail "EXDEV: $out";; esac
check_eq "EXDEV changed nothing" "$before" "$(tree "$R")"

echo "-- repair"
setup; mkdir -p "$R/private/hs-ext/posters"; ln -s "$R/private/hs-ext/posters" "$R/ext/posters"; echo a > "$R/private/hs-ext/posters/f"
check_eq "an own-owned top: nothing to change" "ok	0" "$($ES repair posters 2>&1)"
setup; mkdir -p "$R/elsewhere"; ln -s "$R/elsewhere" "$R/ext/posters"
if out=$($ES repair posters 2>&1); then fail "a folder outside the private root was repaired"; else case $out in *"not $R/private/hs-ext/posters"*) pass "repair refuses a folder outside the private root";; *) fail "text: $out";; esac; fi
setup; check_eq "repair of a service without state is ok" "ok	0" "$($ES repair posters 2>&1)"
setup; mkdir -p "$R/ext/posters"
check_eq "just moved (a real public folder, systemd has not taken it yet): nothing to say" "ok	0" "$($ES repair posters 2>&1)"
setup; ln -s "$R/private/hs-ext/posters" "$R/ext/posters"
check_eq "a public link whose folder is gone is not an error" "ok	0" "$($ES repair posters 2>&1)"
setup; mkdir -p "$R/hs/posters"; rm -rf "$R/ext"; echo x > "$R/ext"
if out=$($ES prepare posters 2>&1); then fail "a broken public root was accepted"; else
  case $out in "ext.state-move-failed: "*) pass "another file system error is a problem, not a traceback";; *) fail "text: $out";; esac; fi

echo "-- names of the core's own folders"
setup
for core in jobs packages disks vault vault-binds backup-rules state settings apps ext ext-svc nodes iso hs-ext private; do
  mkdir -p "$R/hs/$core"; echo keep > "$R/hs/$core/f"; before=$(tree "$R")
  if out=$($ES prepare "$core" 2>&1); then fail "core name $core accepted"; else
    case $out in "ext.state-reserved: "*) pass "$core refused before any change";; *) fail "$core text: $out";; esac; fi
  check_eq "$core: nothing changed" "$before" "$(tree "$R")"
done
check_eq "posters stays allowed" "fresh	-" "$($ES prepare posters 2>&1)"
check_eq "media-hub stays allowed" "fresh	-" "$($ES prepare media-hub 2>&1)"
check_eq "the same for link and repair (refused)" "1 1" "$($ES link jobs >/dev/null 2>&1; echo -n "$? "; $ES repair jobs >/dev/null 2>&1; echo $?)"
nl=$(printf 'posters\n')
if python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); import ext_state; sys.exit(0 if ext_state.prepare("posters\n")[1] is None else 1)' "$SCRIPTS/lib"; then fail "a name with a newline passed"; else pass "a name with a trailing newline is refused"; fi

echo "-- only the private folder exists and the old folder too: the message names the folder that exists"
setup; mkdir -p "$R/hs/posters" "$R/private/hs-ext/posters"
out=$($ES prepare posters 2>&1)
case $out in *"$R/private/hs-ext/posters exist"*) pass "names the private folder";; *) fail "text: $out";; esac

echo "-- every code the module prints is in the catalogue"
emitted=$(grep -oE 'ext\.state-[a-z-]+' "$SCRIPTS/lib/ext_state.py" | sort -u)
for c in $emitted; do check "$c is in error-codes.tsv" grep -q "^$c	" "$SCRIPTS/lib/error-codes.tsv"; done
check "at least four codes were found" test "$(echo "$emitted" | wc -l)" -ge 4

echo "-- the host backup lists the new paths"
check "backup.sh host_files has /var/lib/hs-ext and /var/lib/private/hs-ext" grep -Eq '"\$STATE" /var/lib/hs-ext /var/lib/private/hs-ext' "$ROOT/scripts/backup.sh"

echo "-- every folder the core keeps directly in /var/lib/hs is a reserved package name (read from the sources, so it cannot go stale)"
out=$(python3 -I - "$ROOT" <<'PY'
import os, re, sys
root = sys.argv[1]
sys.path.insert(0, os.path.join(root, "scripts", "lib"))
import ext_state
# names that look like a folder but are not a core one: a field name, an example, or the folder of an official package
OK = {"code", "region", "yes", "posters", "radarr"}
pats = [re.compile(r"/var/lib/hs/([A-Za-z0-9][A-Za-z0-9._-]*)"),
        re.compile(r"(?:\$\{?STATE(?:_DIR)?\}?|\$\{?HS_STATE_DIR(?::-[^}]*)?\}?|\$state|\$LIB|\$HS_LIB)/([A-Za-z0-9][A-Za-z0-9._-]*)"),
        re.compile(r"(?:state|STATE|state_dir\(\)|self\.state|STATE_DIR|LIB_DIR|lib_dir\(\)|STATE_ROOT)\s*,\s*[\"']([A-Za-z0-9][A-Za-z0-9._-]*)[\"']"),
        re.compile(r"(?:state|STATE|state_dir\(\)|STATE_DIR|LIB_DIR)\s*\+\s*[\"']/([A-Za-z0-9][A-Za-z0-9._-]*)"),
        re.compile(r"\{(?:state|STATE|state_dir\(\)|self\.state|STATE_DIR)\}/([A-Za-z0-9][A-Za-z0-9._-]*)")]
found, seen = {}, 0
for top in ("scripts", "capabilities", "configuration.nix"):
    base = os.path.join(root, top)
    walk = [(os.path.dirname(base), [], [top])] if os.path.isfile(base) else os.walk(base)
    for d, dirs, files in walk:
        dirs[:] = [x for x in dirs if x not in ("dev", "__pycache__", "node_modules")]
        for f in files:
            if not f.endswith((".py", ".sh", ".nix", ".rs")):
                continue
            seen += 1
            for line in open(os.path.join(d, f), encoding="utf-8", errors="replace"):
                for p in pats:
                    for m in p.finditer(line):
                        found.setdefault(m.group(1), os.path.join(d, f))
missing = sorted(n for n in found if n not in OK and ext_state._bad_name(n) is None)
print("scanned %d" % seen, "found %d" % len(found))
for n in missing:
    print("MISSING %s (%s)" % (n, found[n]))
PY
)
check "the scan read the sources" grep -q '^scanned [0-9][0-9][0-9]' <<<"$out"
check "no core folder of /var/lib/hs is missing in RESERVED: $(grep MISSING <<<"$out" | head -3 | tr '
' ' ')" test -z "$(grep MISSING <<<"$out")"
for n in current repos keys previous lock golden docs-site ext-cursors; do
  if python3 -I -c "import sys; sys.path.insert(0, '$SCRIPTS/lib'); import ext_state; sys.exit(0 if ext_state._bad_name('$n') else 1)"; then pass "$n is refused"; else fail "$n is accepted as a package name"; fi
done
check "the manifest check refuses a service package with a core name" python3 -I -c "
import sys; sys.path.insert(0, '$SCRIPTS/lib'); import pkg_protocol
p = pkg_protocol.manifest_problems({'name': 'current', 'protocol': [1], 'requires_core': '>=99'})
sys.exit(0 if any('current' in x and 'reserved' in x for x in p) else 1)"

finish
