#!/usr/bin/env bash
# hs backup offsite (step 13 of docs/PLAN-storage-nas.md): guided targets, secrets in files restic reads by path, an own password for a new
# repository, list/find/restore from it with --repo offsite, the 7/4/6 retention. A FAKE restic (chmod +x, first on PATH) that keeps a folder
# repository as a `config` file holding its password and logs every call's argv and the interesting environment. No root, no real restic,
# no loop device. What this cannot tell: a real S3 service, rest-server, sshd, restic's own handling of the files.
set -uo pipefail
. "$(dirname "$0")/lib.sh"

export HS_STATE_DIR=$WORK/state HS_BACKUP_NO_MOUNT=1 HS_BACKUP_MOUNT=$WORK/mnt HS_BACKUP_REPO=$WORK/local HS_BACKUP_CACHE=$WORK/cache HS_PLAIN=1 HS_LANG=en
export HS_BACKUP_YES=1 HS_VAULT_DIR=$WORK/vault HS_CALLER=test
mkdir -p "$HS_STATE_DIR" "$WORK/mnt" "$WORK/local"
echo "pw-local" > "$HS_STATE_DIR/restic-password"; chmod 600 "$HS_STATE_DIR/restic-password"
echo "pw-local" > "$WORK/local/config"

BIN=$WORK/bin; mkdir -p "$BIN"
cat > "$BIN/restic" <<'FAKE'
#!/usr/bin/env bash
# Folder repositories (an address starting with /) are real enough: `config` holds the password. Every other address: cat config fails (no
# repository yet unless the test made $FAKE_REMOTE), everything else works.
{ printf 'ARGV'; printf ' [%s]' "$@"; printf '\n'; env | grep -E '^(AWS_|B2_|FOO)' | sed 's/^/ENV /'; } >> "$FAKELOG"
repo="" pw="" cmd="" from="" fpw="" rest=()
while [ $# -gt 0 ]; do
  case "$1" in
    -r) repo=$2; shift 2 ;;
    --repository-file) repo=$(cat "$2"); shift 2 ;;
    --password-file) pw=$(cat "$2"); shift 2 ;;
    --from-repo) from=$2; shift 2 ;;
    --from-password-file) fpw=$(cat "$2"); shift 2 ;;
    -*) [ -n "$cmd" ] && rest+=("$1"); shift ;;
    *) if [ -z "$cmd" ]; then cmd=$1; else rest+=("$1"); fi; shift ;;
  esac
done
case "$repo" in
  /*) folder=1 ;;
  *) folder=0 ;;
esac
case "$cmd" in
  cat) if [ "$folder" = 1 ]; then [ "$(cat "$repo/config" 2>/dev/null)" = "$pw" ]; else [ -e "$FAKE_REMOTE" ]; fi ;;   # a remote exists once the test says so
  init) if [ "$folder" = 1 ]; then
          [ ! -f "$repo/config" ] || exit 1
          mkdir -p "$repo"; printf '%s\n' "$pw" > "$repo/config"
        fi ;;
  copy) [ "$folder" = 1 ] && [ "$(cat "$repo/config")" = "$pw" ] && [ "$(cat "$from/config")" = "$fpw" ] && : > "$repo/copied" ;;
  snapshots|list) echo "abc123  shares" ;;
  find) echo "abc123 /data/a.txt" ;;
  restore) [ "$folder" = 1 ] && [ "$(cat "$repo/config")" = "$pw" ] && [ -f "$repo/copied" ] || exit 1
           for ((i = 0; i < ${#rest[@]}; i++)); do [ "${rest[$i]}" = "--target" ] && mkdir -p "${rest[$((i + 1))]}" && : > "${rest[$((i + 1))]}/a.txt"; done ;;
  *) : ;;
esac
FAKE
chmod +x "$BIN/restic"
export FAKELOG=$WORK/fake.log FAKE_REMOTE=$WORK/remote-exists; : > "$FAKELOG"
export PATH="$BIN:$PATH"
hsb() { bash "$SCRIPTS/backup.sh" "$@"; }
repofile=$HS_STATE_DIR/backup-offsite.repo pwfile=$HS_STATE_DIR/restic-offsite-password

echo "-- a folder target: own password, files 0600"
off=$WORK/off
check "set --kind folder" hsb offsite set --kind folder --path "$off"
check_eq "the address is in the repository file" "$off" "$(cat "$repofile")"
check_eq "repository file is 0600" 600 "$(stat -c %a "$repofile")"
check_eq "own password file is 0600" 600 "$(stat -c %a "$pwfile")"
check_eq "the repository was made with the own password" "$(cat "$pwfile")" "$(cat "$off/config")"
if [ "$(cat "$off/config")" = pw-local ]; then fail "the new repository got the backup disk's password"; else pass "not the backup disk's password"; fi
check_out "init copied the chunker parameters from the local repository" "\[init\].*\[--copy-chunker-params\]" cat "$FAKELOG"
before=$(cat "$pwfile")
check "the same target again" hsb offsite set --kind folder --path "$off"
check_eq "keeps the password it has" "$before" "$(cat "$pwfile")"
check "offsite now copies (own password in, local password as the source)" hsb offsite now
check "the copy reached the repository" test -f "$off/copied"
check_out "--repo offsite list uses the repository file and the own password" "shares" hsb list --repo offsite
check_out "restic got --repository-file" "\[--repository-file\] \[$repofile\]" cat "$FAKELOG"
check_out "--repo offsite find" "a.txt" hsb find a.txt --repo offsite
mkdir -p "$WORK/shares/restored"
hsb restore latest /data --to "$WORK/shares/restored" --repo offsite >/dev/null 2>&1
check_out "--repo offsite restore reads the off-site repository, not the backup disk" "\[--repository-file\] \[$repofile\].*\[ls\]|\[restore\]" cat "$FAKELOG"
check_out "the machine mode says the password once for a new repository" "^secret.password." hsb offsite set --machine --kind folder --path "$WORK/off2"
check_out "state shows the address" "offsite.$WORK/off2" hsb --state
hsb offsite off >/dev/null 2>&1
check "offsite off removes the address" test ! -e "$repofile"

echo "-- a refused target changes nothing"
check "a path with .. is refused" bash -c "! bash '$SCRIPTS/backup.sh' offsite set --kind folder --path /a/../b"
check "no repository file is left" test ! -e "$repofile"

echo "-- retention: the 7/4/6 rule, a Sunday prune, nothing for a REST target"
hsb offsite set --kind folder --path "$WORK/off2" >/dev/null 2>&1   # off2 owns the password file now
: > "$FAKELOG"
check "retention" hsb offsite retention
check_out "forget with the same rule" "\[forget\].*\[--keep-daily\] \[7\] \[--keep-weekly\] \[4\] \[--keep-monthly\] \[6\]" cat "$FAKELOG"
if grep -q '\[--prune\]' "$FAKELOG"; then fail "no prune on a weekday"; else pass "no prune on a weekday"; fi
: > "$FAKELOG"
check "retention prune" hsb offsite retention prune
check_out "prune on Sundays" "\[forget\].*\[--prune\]" cat "$FAKELOG"

echo "-- S3, REST, typed: no secret on argv, none in restic's environment"
: > "$FAKELOG"
printf 'AKIAEXAMPLEID\nsecret/KEY+value\n' | hsb offsite set --kind s3 --endpoint s3.example.org --bucket mybucket --prefix hobnix >/dev/null 2>&1
check_eq "S3 address" "s3:https://s3.example.org/mybucket/hobnix" "$(cat "$repofile" 2>/dev/null)"
check_out "the keys are in a credentials file" "aws_secret_access_key = secret/KEY\+value" cat "$HS_STATE_DIR/backup-offsite.credentials"
check_eq "credentials file is 0600" 600 "$(stat -c %a "$HS_STATE_DIR/backup-offsite.credentials")"
check_out "restic got --repository-file" "\[--repository-file\] \[$repofile\]" cat "$FAKELOG"
check_out "restic got the credentials file by path" "ENV AWS_SHARED_CREDENTIALS_FILE=$HS_STATE_DIR/backup-offsite.credentials" cat "$FAKELOG"
if grep -q 'secret/KEY\|AKIAEXAMPLEID' "$FAKELOG"; then fail "a key reached restic's argv or environment"; else pass "no key on restic's argv or in its environment"; fi
: > "$WORK/remote-exists"   # from here on the remote repositories "exist"
check "S3 gets a retention" bash -c ": > '$FAKELOG'; bash '$SCRIPTS/backup.sh' offsite retention >/dev/null 2>&1; grep -q 'keep-daily' '$FAKELOG'"

: > "$FAKELOG"
printf 'p@ss/w:rd\n' | hsb offsite set --kind rest --url https://nas.example:8000/hobnix --user bob >/dev/null 2>&1
check_out "REST: the password is inside the repository file, encoded" "rest:https://bob:p%40ss%2Fw%3Ard@nas.example:8000/hobnix" cat "$repofile"
check_eq "and the S3 keys of before are gone" "no" "$([ -e "$HS_STATE_DIR/backup-offsite.credentials" ] && echo yes || echo no)"
if grep -q 'p@ss\|p%40ss' "$FAKELOG"; then fail "the REST password reached restic's argv"; else pass "the REST password is not on restic's argv"; fi
check_out "state masks the REST password" "offsite.rest:https://bob:\*\*\*@" hsb --state
: > "$FAKELOG"
check "a REST target is not forgotten from here (append-only)" hsb offsite retention prune
if grep -q 'forget' "$FAKELOG"; then fail "forget was called on a REST target"; else pass "no forget on a REST target"; fi

echo "-- the old env file: parsed, never sourced; only restic's own process gets the variables"
rm -f "$repofile"
printf 'FOO=bar\nAWS_X=$(touch %s/pwned)\nB2_ACCOUNT_ID="id1"\nPATH=/evil\n' "$WORK" > "$HS_STATE_DIR/backup-offsite.env"
: > "$FAKELOG"
hsb offsite set b2:bucket:path >/dev/null 2>&1
check "nothing in the env file was executed" test ! -e "$WORK/pwned"
check_out "a B2 variable reaches restic" "ENV B2_ACCOUNT_ID=id1" cat "$FAKELOG"
if grep -q 'ENV FOO' "$FAKELOG"; then fail "an unknown variable was passed on"; else pass "only restic's cloud variables are passed on"; fi
if env | grep -q '^B2_ACCOUNT_ID='; then fail "the variable leaked into this shell"; else pass "this shell's environment stays clean"; fi
printf 'AWS_ACCESS_KEY_ID=AKIAOLD\nAWS_SECRET_ACCESS_KEY=oldsecret\n' > "$HS_STATE_DIR/backup-offsite.env"
check "migrate moves S3 keys into a credentials file" hsb offsite migrate
check_out "with the keys in it" "aws_access_key_id = AKIAOLD" cat "$HS_STATE_DIR/backup-offsite.credentials"
check "and the env file is gone" test ! -e "$HS_STATE_DIR/backup-offsite.env"

finish
