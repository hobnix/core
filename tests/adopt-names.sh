#!/usr/bin/env bash
# The share names adopting a disk makes (scripts/lib/adopt-names.sh, used by scripts/manage-pool.sh): never longer than a new share may be
# (41 characters), always the same for the same folder, and two folders never become one share (issue 1245). No root, no disks.
# The whole adoption runs in tests/adopt.sh (root).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
export HS_DISKS_ROOT=$WORK/disks HS_BULK=$WORK/bulk HS_FAST=$WORK/fast HS_MACHINE_FILE=$WORK/machine.toml HS_BULK_TYPE_FILE=$WORK/bulk-type HS_NET=$WORK/net
echo snapraid > "$HS_BULK_TYPE_FILE"
printf '#!/usr/bin/env bash\n[ "$*" = "conf listshares" ] && printf "data-03-in-samba\\n"\nexit 0\n' > "$HS_NET"; chmod +x "$HS_NET"
mkdir -p "$WORK/disks/data-01/shares" "$WORK/bulk/shares"
. "$SCRIPTS/lib/bulkpath.sh"
. "$SCRIPTS/lib/sharepath.sh"
. "$SCRIPTS/lib/adopt-names.sh"

LONG=CommunityApplicationsAppdataBackup      # data-02-<it> is 42 characters (the report of issue 1245)
merge_folders=false
adopt_reset "$WORK/bulk"

echo "-- one share per disk and folder"
check_eq "a short name stays" "data-02-my-media" "$(adopt_target bulk-data-02 'My Media')"
t=$(adopt_target bulk-data-02 "$LONG")
check_eq "a long name is cut to 41 characters" 41 "${#t}"
check_match "and keeps its start, then 6 hex digits" '^data-02-communityapplicationsappda-[0-9a-f]{6}$' "$t"
check_eq "the same folder always gets the same name" "$t" "$(adopt_target bulk-data-02 "$LONG")"
a=$(adopt_target bulk-data-02 "${LONG}One"); b=$(adopt_target bulk-data-02 "${LONG}Two")
[ "$a" != "$b" ] && pass "two long folders with the same start stay apart ($a, $b)" || fail "same short name: $a"
check_eq "41 characters are not cut" "data-02-$(printf 'a%.0s' $(seq 1 33))" "$(adopt_target bulk-data-02 "$(printf 'a%.0s' $(seq 1 33))")"
t=$(adopt_target bulk-data-02 "$(printf 'a%.0s' $(seq 1 25))-$(printf 'b%.0s' $(seq 1 30))")
check_match "no double dash where the cut falls on one" '^data-02-a{25}-[0-9a-f]{6}$|^data-02-a{25}-b+-[0-9a-f]{6}$' "$t"
case "$t" in *--*) fail "double dash: $t" ;; *) pass "no double dash: $t" ;; esac
u=$(LC_ALL=C adopt_target bulk-data-02 "$(printf 'ü%.0s' $(seq 1 50))")
if printf '%s' "$u" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1; then pass "a name with umlauts is not cut inside a character ($u)"; else fail "broken UTF-8: $u"; fi

echo "-- two folders never become one share"
claim() { adopt_claim "$1" "$2" "$(adopt_target "$1" "$2")"; }
adopt_reset "$WORK/bulk"
claim bulk-data-02 'My Media' && pass "the first folder" || fail "first: $adopt_why"
claim bulk-data-02 'my-media' && fail "'my-media' took the name of 'My Media'" || pass "a second folder with the same share name is refused"
check_match "the reason names both folders" "'my-media'.*data-02-my-media.*'My Media'" "$adopt_why"
adopt_reset "$WORK/bulk"
short=$(adopt_target bulk-data-02 "$LONG")
claim bulk-data-02 "$LONG" && claim bulk-data-02 "${short#data-02-}" && fail "a folder named like the short name was taken too" || pass "a folder named like a shortened name is refused"
mkdir -p "$WORK/disks/data-01/shares/data-02-media" "$WORK/disks/data-01/sensitive/data-02-keys"
adopt_reset "$WORK/bulk"
claim bulk-data-02 Media && fail "an existing share was merged into" || pass "a share that exists on a disk is refused"
check_match "the reason says it exists" "exists already" "$adopt_why"
claim bulk-data-02 Keys && fail "an existing sensitive share was reused" || pass "a sensitive share of that name is refused"
claim bulk-data-03 'In Samba' && fail "a Samba share name was reused" || pass "a Samba share of that name is refused"
adopt_reset "$WORK/bulk"; adopt_own=(data-02-photos)
claim bulk-data-02 Photos && fail "a folder already in shares/ of the disk was reused" || pass "a name the disk has in shares/ already is refused"
adopt_own=()

echo "-- --merge: the folders of one name become one share, other names never"
merge_folders=true
adopt_reset "$WORK/bulk"
check_eq "a short name stays as it is" "My Media" "$(adopt_target bulk-data-02 'My Media')"
check_eq "a reserved name gets its suffix" "Global-adopted" "$(adopt_target bulk-data-02 Global)"
M=CommunityApplicationsAppdataBackupOfUnraid
m=$(adopt_target bulk-data-02 "$M")
check_eq "a long folder name is cut to 41" 41 "${#m}"
check_eq "the same on every disk, so it still merges" "$m" "$(adopt_target bulk-data-03 "$M")"
claim bulk-data-02 "$M" && claim bulk-data-03 "$M" && pass "the same folder on two disks is merged" || fail "merge refused: $adopt_why"
claim bulk-data-03 "$m" && fail "another folder took the shortened name" || pass "another folder with the shortened name is refused"
adopt_reset "$WORK/bulk"
claim bulk-data-02 Global && claim bulk-data-03 Global-adopted && fail "Global and Global-adopted were merged" || pass "a suffixed reserved name never takes another folder"
adopt_reset "$WORK/bulk"
claim bulk-data-02 Media && claim bulk-data-03 media && pass "folders that differ in case keep their names, as before" || fail "case: $adopt_why"
mkdir -p "$WORK/disks/data-01/shares/Backups"
claim bulk-data-02 Backups && pass "an existing share of the same name is what --merge merges into" || fail "merge into existing refused: $adopt_why"
mkdir -p "$WORK/disks/data-01/shares/$M"
adopt_reset "$WORK/bulk"
check_eq "a long share that exists already keeps its name (no second, shortened share beside it)" "$M" "$(adopt_target bulk-data-02 "$M")"

echo "-- the plan says it in words"
check_match "shortened" "shortened: '$LONG'.*at most 41.*data-02-" "$(merge_folders=false; adopt_reset "$WORK/none"; adopt_name_note bulk-data-02 "$LONG")"
check_match "kept" "'$M' is longer than 41 characters" "$(adopt_name_note bulk-data-02 "$M")"
check_eq "nothing to say for a short name" "" "$(adopt_name_note bulk-data-02 Media)"
finish
