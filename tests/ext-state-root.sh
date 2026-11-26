#!/usr/bin/env bash
# repair_owner of scripts/lib/ext_state.py (#1134 slice S1) really changes owners: it needs root. A root-owned file below a folder owned by
# another user gets that user; a link inside the state folder is not followed (the file it points to keeps its owner).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
need_root
command -v python3 >/dev/null || { echo "python3 missing: skipped"; exit 0; }
ES="python3 -I $SCRIPTS/lib/ext_state.py"
export HS_STATE_DIR=$WORK/hs HS_EXT_STATE_DIR=$WORK/ext HS_PRIVATE_DIR=$WORK/private
P=$WORK/private/hs-ext/posters; mkdir -p "$P/sub" "$WORK/ext" "$WORK/hs" "$WORK/outside"
ln -s "$P" "$WORK/ext/posters"
U=64321; G=64322
echo a > "$P/a"; echo b > "$P/sub/b"; echo victim > "$WORK/outside/f"
ln -s "$WORK/outside/f" "$P/link"; ln -s "$WORK/outside" "$P/dirlink"
# a folder the service swapped for a link to a folder of root (the swap is simulated by planting the link before the run)
mkdir -p "$WORK/rootdir"; echo secret > "$WORK/rootdir/shadow"; mv "$P/sub" "$P/sub.old"; ln -s "$WORK/rootdir" "$P/sub"
chown -h $U:$G "$P"
out=$($ES repair posters 2>&1)
check_eq "repair counts the entries it changed" "ok	6" "$out"
check_eq "a root-owned file gets the owner of the top folder" "$U:$G" "$(stat -c %u:%g "$P/a")"
check_eq "also below a sub folder" "$U:$G" "$(stat -c %u:%g "$P/sub.old/b")"
check_eq "a link itself is changed" "$U:$G" "$(stat -c %u:%g "$P/link")"
check_eq "the file a link points to keeps its owner" "0:0" "$(stat -c %u:%g "$WORK/outside/f")"
check_eq "a link to a folder is not followed" "0:0" "$(stat -c %u:%g "$WORK/outside")"
check_eq "a folder swapped for a link is not entered: what is below keeps its owner" "0:0" "$(stat -c %u:%g "$WORK/rootdir/shadow")"
check_eq "a second run has nothing to do" "ok	0" "$($ES repair posters 2>&1)"
chmod 0640 "$P/a"; $ES repair posters >/dev/null 2>&1
check_eq "the mode is never changed" "640" "$(stat -c %a "$P/a")"
# a second name of a file outside (a hard link): changing its owner would give the service that file
echo shadow > "$WORK/outside/shadow"; chmod 0600 "$WORK/outside/shadow"; ln "$WORK/outside/shadow" "$P/hard"; echo c > "$P/c"
if out=$($ES repair posters 2>&1); then fail "a hard link was not reported: $out"; else
  case $out in *"second hard link"*"$P/hard") pass "a hard link is reported";; *) fail "text: $out";; esac; fi
check_eq "the file behind the hard link keeps its owner" "0:0" "$(stat -c %u:%g "$WORK/outside/shadow")"
check_eq "and the other files are still repaired" "$U:$G" "$(stat -c %u:%g "$P/c")"
rm -f "$P/hard"
chown 0:0 "$P"
check_eq "a root-owned top is left to systemd" "ok	0" "$($ES repair posters 2>&1)"
check_eq "and nothing below it changed" "$U:$G" "$(stat -c %u:%g "$P/a")"

finish
