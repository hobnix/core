#!/usr/bin/env bash
# hs backup offsite (step 13 of docs/PLAN-storage-nas.md): guided targets, secrets in files restic reads by path, an own password for a new
# repository, restore/find/list from it with --repo offsite. A real restic with a folder target; a fake restic (argv and environment logged)
# for the S3, REST and typed kinds. No root, no loop device. What this cannot tell: a real S3 service, rest-server, sshd.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
have restic || { skip "restic is not installed"; finish; exit $?; }

export HS_STATE_DIR=$WORK/state HS_BACKUP_NO_MOUNT=1 HS_BACKUP_MOUNT=$WORK/mnt HS_BACKUP_REPO=$WORK/local HS_BACKUP_CACHE=$WORK/cache HS_PLAIN=1 HS_LANG=en
export HS_BACKUP_YES=1 HS_VAULT_DIR=$WORK/vault HS_CALLER=test
mkdir -p "$HS_STATE_DIR" "$WORK/mnt" "$WORK/data"
echo "pw-local" > "$HS_STATE_DIR/restic-password"; chmod 600 "$HS_STATE_DIR/restic-password"
echo hello > "$WORK/data/a.txt"
rl() { restic -r "$WORK/local" --password-file "$HS_STATE_DIR/restic-password" "$@"; }
hsb() { bash "$SCRIPTS/backup.sh" "$@"; }
rl init >/dev/null 2>&1 && rl backup --tag shares "$WORK/data" >/dev/null 2>&1 || { skip "restic could not make a repository here"; finish; exit $?; }

echo "-- a folder target: own password, files 0600"
off=$WORK/off
check "set --kind folder" hsb offsite set --kind folder --path "$off"
check_eq "the address is in the repository file" "$off" "$(cat "$HS_STATE_DIR/backup-offsite.repo")"
check_eq "repository file is 0600" 600 "$(stat -c %a "$HS_STATE_DIR/backup-offsite.repo")"
check_eq "own password file is 0600" 600 "$(stat -c %a "$HS_STATE_DIR/restic-offsite-password")"
check "the repository opens with its own password" restic -r "$off" --password-file "$HS_STATE_DIR/restic-offsite-password" cat config
check "and not with the backup disk's password" bash -c "! restic -r '$off' --password-file '$HS_STATE_DIR/restic-password' cat config"
before=$(cat "$HS_STATE_DIR/restic-offsite-password")
check "the same target again" hsb offsite set --kind folder --path "$off"
check_eq "keeps the password it has" "$before" "$(cat "$HS_STATE_DIR/restic-offsite-password")"
check "offsite now copies" hsb offsite now
check_out "--repo offsite list shows the snapshot" "shares" hsb list --repo offsite
check_out "--repo offsite find finds the file" "a.txt" hsb find a.txt --repo offsite
mkdir -p "$WORK/back"
snap=$(restic -r "$off" --password-file "$HS_STATE_DIR/restic-offsite-password" snapshots --json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["short_id"])')
check "restic restores from the off-site repository" bash -c "restic -r '$off' --password-file '$HS_STATE_DIR/restic-offsite-password' restore '$snap' --target '$WORK/back' >/dev/null 2>&1 && find '$WORK/back' -name a.txt | grep -q ."
check_out "the machine mode says the password once for a new repository" "^secret.password." hsb offsite set --machine --kind folder --path "$WORK/off2"
check_out "state shows the address" "offsite.$WORK/off2" hsb --state
hsb offsite off >/dev/null 2>&1
check "offsite off removes the address" test ! -e "$HS_STATE_DIR/backup-offsite.repo"

echo "-- a refused target changes nothing"
check "a path with .. is refused" bash -c "! bash '$SCRIPTS/backup.sh' offsite set --kind folder --path /a/../b"
check "no repository file is left" test ! -e "$HS_STATE_DIR/backup-offsite.repo"

echo "-- S3, REST, typed with a fake restic: no secret on argv, none in this script's environment"
BIN=$WORK/bin; mkdir -p "$BIN"
cat > "$BIN/restic" <<'FAKE'
#!/usr/bin/env bash
# logs argv and the interesting environment of every call; cat config fails (no repository yet), everything else works
{ printf 'ARGV'; printf ' [%s]' "$@"; printf '\n'; env | grep -E '^(AWS_|B2_|FOO|AWS_X)' | sed 's/^/ENV /'; } >> "$FAKELOG"
for a in "$@"; do [ "$a" = cat ] && exit 1; done
exit 0
FAKE
chmod +x "$BIN/restic"
export FAKELOG=$WORK/fake.log
OLDPATH=$PATH; export PATH="$BIN:$PATH"
: > "$FAKELOG"
printf 'AKIAEXAMPLEID\nsecret/KEY+value\n' | hsb offsite set --kind s3 --endpoint s3.example.org --bucket mybucket --prefix hobnix >/dev/null 2>&1
check_eq "S3 address" "s3:https://s3.example.org/mybucket/hobnix" "$(cat "$HS_STATE_DIR/backup-offsite.repo" 2>/dev/null)"
check_out "the keys are in a credentials file" "aws_secret_access_key = secret/KEY\+value" cat "$HS_STATE_DIR/backup-offsite.credentials"
check_eq "credentials file is 0600" 600 "$(stat -c %a "$HS_STATE_DIR/backup-offsite.credentials")"
check_out "restic got --repository-file" "\[--repository-file\] \[$HS_STATE_DIR/backup-offsite.repo\]" cat "$FAKELOG"
check_out "restic got the credentials file by path" "ENV AWS_SHARED_CREDENTIALS_FILE=$HS_STATE_DIR/backup-offsite.credentials" cat "$FAKELOG"
if grep -q 'secret/KEY\|AKIAEXAMPLEID' "$FAKELOG"; then fail "a key reached restic's argv or environment"; else pass "no key on restic's argv or in its environment"; fi

: > "$FAKELOG"
printf 'p@ss/w:rd\n' | hsb offsite set --kind rest --url https://nas.example:8000/hobnix --user bob >/dev/null 2>&1
check_out "REST: the password is inside the repository file, encoded" "rest:https://bob:p%40ss%2Fw%3Ard@nas.example:8000/hobnix" cat "$HS_STATE_DIR/backup-offsite.repo"
check_eq "and the S3 keys of before are gone" "no" "$([ -e "$HS_STATE_DIR/backup-offsite.credentials" ] && echo yes || echo no)"
if grep -q 'p@ss\|p%40ss' "$FAKELOG"; then fail "the REST password reached restic's argv"; else pass "the REST password is not on restic's argv"; fi
check_out "state masks the REST password" "offsite.rest:https://bob:\*\*\*@" hsb --state

echo "-- the old env file: parsed, never sourced; only restic's own process gets the variables"
rm -f "$HS_STATE_DIR/backup-offsite.repo"
printf 'FOO=bar\nAWS_X=$(touch %s/pwned)\nB2_ACCOUNT_ID="id1"\nPATH=/evil\n' "$WORK" > "$HS_STATE_DIR/backup-offsite.env"
: > "$FAKELOG"
hsb offsite set b2:bucket:path >/dev/null 2>&1
check "nothing in the env file was executed" test ! -e "$WORK/pwned"
check_out "a B2 variable reaches restic" "ENV B2_ACCOUNT_ID=id1" cat "$FAKELOG"
check_out "a value is taken literally" 'ENV AWS_X=\$\(touch' cat "$FAKELOG"
if grep -q 'ENV FOO' "$FAKELOG"; then fail "an unknown variable was passed on"; else pass "only restic's cloud variables are passed on"; fi
printf 'AWS_ACCESS_KEY_ID=AKIAOLD\nAWS_SECRET_ACCESS_KEY=oldsecret\n' > "$HS_STATE_DIR/backup-offsite.env"
check "migrate moves S3 keys into a credentials file" hsb offsite migrate
check_out "with the keys in it" "aws_access_key_id = AKIAOLD" cat "$HS_STATE_DIR/backup-offsite.credentials"
check "and the env file is gone" test ! -e "$HS_STATE_DIR/backup-offsite.env"
PATH=$OLDPATH

finish
