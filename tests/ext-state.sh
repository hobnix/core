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
setup; mkdir -p "$R/hs/posters/sub"; echo data > "$R/hs/posters/a.png"; echo deep > "$R/hs/posters/sub/b"; chmod 0600 "$R/hs/posters/a.png"; chmod 0750 "$R/hs/posters/sub"
out=$($ES prepare posters 2>&1); check_eq "a real folder is moved" "moved	-" "$out"
check_eq "the content is intact" "data deep" "$(cat "$R/ext/posters/a.png" "$R/ext/posters/sub/b" | tr '\n' ' ' | sed 's/ $//')"
check_eq "the old path is a link to the new folder" "$R/ext/posters" "$(readlink "$R/hs/posters")"
check_eq "modes are kept" "600 750" "$(stat -c %a "$R/ext/posters/a.png") $(stat -c %a "$R/ext/posters/sub")"
check_eq "the owner is kept" "$(id -u)" "$(stat -c %u "$R/ext/posters/a.png")"
check_eq "a second run changes nothing" "ok	-" "$($ES prepare posters 2>&1)"
check_eq "a third run too" "ok	-" "$($ES prepare posters 2>&1)"

echo "-- a crash between the rename and the link"
setup; mkdir -p "$R/ext/posters"; echo x > "$R/ext/posters/f"
check_eq "old missing, new present: the link is made" "linked	-" "$($ES prepare posters 2>&1)"
check_eq "the link points to the new folder" "$R/ext/posters" "$(readlink "$R/hs/posters")"
check_eq "and the next run is ok" "ok	-" "$($ES prepare posters 2>&1)"
setup; mkdir -p "$R/private/hs-ext/posters"
check_eq "only the private folder exists (systemd made it): linked" "linked	-" "$($ES prepare posters 2>&1)"

echo "-- both folders exist: refuse, change nothing"
setup; mkdir -p "$R/hs/posters" "$R/ext/posters"; echo a > "$R/hs/posters/a"; echo b > "$R/ext/posters/b"
before=$(tree "$R")
if out=$($ES prepare posters 2>&1); then fail "both exist was accepted: $out"; else
  case $out in "state_conflict: both $R/hs/posters and $R/ext/posters exist; nothing was moved") pass "refused and names both folders";; *) fail "text: $out";; esac; fi
check_eq "nothing changed on disk" "$before" "$(tree "$R")"
setup; mkdir -p "$R/hs/posters" "$R/private/hs-ext/posters"; echo a > "$R/hs/posters/a"; before=$(tree "$R")
if $ES prepare posters >/dev/null 2>&1; then fail "old and private folder accepted"; else pass "old and private folder: refused"; fi
check_eq "nothing changed on disk (private)" "$before" "$(tree "$R")"

echo "-- other states of the old path"
setup; echo x > "$R/hs/posters"
if out=$($ES prepare posters 2>&1); then fail "a file was accepted"; else case $out in "state_conflict: $R/hs/posters is not a folder") pass "a file is refused";; *) fail "text: $out";; esac; fi
setup; ln -s /elsewhere "$R/hs/posters"
if out=$($ES prepare posters 2>&1); then fail "a wrong link was accepted"; else case $out in "state_conflict: $R/hs/posters is a link to /elsewhere, not $R/ext/posters") pass "a link to somewhere else is refused";; *) fail "text: $out";; esac; fi
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
case $out in "(None, '"*"state_move_failed: "*"is on another file system than "*"; nothing was moved')") pass "EXDEV is refused, no copy";; *) fail "EXDEV: $out";; esac
check_eq "EXDEV changed nothing" "$before" "$(tree "$R")"

echo "-- repair"
setup; mkdir -p "$R/private/hs-ext/posters"; ln -s "$R/private/hs-ext/posters" "$R/ext/posters"; echo a > "$R/private/hs-ext/posters/f"
check_eq "an own-owned top: nothing to change" "ok	0" "$($ES repair posters 2>&1)"
setup; mkdir -p "$R/elsewhere"; ln -s "$R/elsewhere" "$R/ext/posters"
if out=$($ES repair posters 2>&1); then fail "a folder outside the private root was repaired"; else case $out in *"not $R/private/hs-ext/posters"*) pass "repair refuses a folder outside the private root";; *) fail "text: $out";; esac; fi
setup; check_eq "repair of a service without state is ok" "ok	0" "$($ES repair posters 2>&1)"

echo "-- the host backup lists the new paths"
check "backup.sh host_files has /var/lib/hs-ext and /var/lib/private/hs-ext" grep -Eq '"\$STATE" /var/lib/hs-ext /var/lib/private/hs-ext' "$ROOT/scripts/backup.sh"

finish
