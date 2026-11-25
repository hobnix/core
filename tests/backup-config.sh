#!/usr/bin/env bash
# hs backup config [restore]: list the host snapshots, put machine.toml / machine.nix back (no root, no disk, a fake restic).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
if ! have jq; then skip "jq missing"; finish; exit 0; fi
export HS_PLAIN=1 HS_LANG=en HS_BACKUP_NO_MOUNT=1
unset HS_CALLER HS_BACKUP_YES
ST=$WORK/state NX=$WORK/nixos FIX=$WORK/fixture
export HS_STATE_DIR=$ST HS_NIXOS_DIR=$NX HS_BACKUP_REPO=$WORK/repo FIX
mkdir -p "$ST" "$NX" "$WORK/repo" "$WORK/bin" "$FIX$NX" "$FIX$ST/disks" "$FIX$ST/sub"
: > "$WORK/repo/config"
echo live-pass > "$ST/restic-password"
echo 'old = 1' > "$NX/machine.toml"
echo 'hw-live' > "$NX/hardware-configuration.nix"
echo 'old = 1' > "$NX/machine.nix"
echo 'old = 1' > "$FIX$NX/machine.nix"          # same as live
echo 'new = 2' > "$FIX$NX/machine.toml"         # differs
echo 'hw-snapshot' > "$FIX$NX/hardware-configuration.nix"
echo snap-pass > "$FIX$ST/restic-password"
echo 'disk-a' > "$FIX$ST/disks/a"
echo 'uuid' > "$FIX$ST/vault-uuid"
echo 'luks' > "$FIX$ST/luks-uuids"
echo 'setting' > "$FIX$ST/sub/keep"
cat > "$WORK/bin/restic" <<'FAKE'
#!/usr/bin/env bash
# restore <snap> --tag host --target T --include P ...: copy P from $FIX below T; ls <snap> P: print P if it is in $FIX
cmd="" target="" inc=() ; args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[$i]}" in
    --password-file) [ -z "${FIXPASS:-}" ] || [ "$(cat "${args[$((i + 1))]}")" = "$FIXPASS" ] || { echo "wrong password" >&2; exit 1; }
                     echo "${args[*]}" >> "$FIX.calls" ;;
    --target) target=${args[$((i + 1))]} ;;
    --include) inc+=("${args[$((i + 1))]}") ;;
    snapshots|restore|ls) cmd=${cmd:-${args[$i]}} ;;
  esac
done
case "$cmd" in
  snapshots) echo '[{"id":"abcdef0123456789","time":"2026-11-05T04:00:01Z"}]' ;;
  ls) p=${args[$((${#args[@]} - 1))]}; [ -e "$FIX$p" ] && echo "$p" ;;
  restore) shopt -s nullglob
    for p in "${inc[@]}"; do for q in $FIX$p; do q=${q#"$FIX"}; mkdir -p "$target$(dirname "$q")"; cp -a "$FIX$q" "$target$q"; done; done ;;
esac
exit 0
FAKE
chmod +x "$WORK/bin/restic"
export PATH="$WORK/bin:$PATH"
b() { bash "$SCRIPTS/backup.sh" "$@" </dev/null 2>&1; }
has() { grep -qF -- "$1" <<<"$out"; }

echo "-- list"
out=$(b config)
has "abcdef01" && has "machine.toml, machine.nix" && pass "the snapshot with the files it holds" || fail "list: $out"

echo "-- dry run"
out=$(b config restore --dry-run)
has "changed" && has "$NX/machine.toml" && has "dry run" && pass "the plan names the changed file" || fail "dry: $out"
case "$out" in *new\ =*) fail "contents printed" ;; *) pass "no contents in the plan" ;; esac
check_eq "dry run changes nothing" "old = 1" "$(cat "$NX/machine.toml")"
check_eq "no safety copy yet" 0 "$(ls "$NX" | grep -c before-restore || true)"

echo "-- refuses without a terminal and without --yes"
if out=$(b config restore); then fail "no refusal: $out"; else has "terminal" && pass "refused" || fail "refusal text: $out"; fi
check_eq "still unchanged" "old = 1" "$(cat "$NX/machine.toml")"

echo "-- restore with --yes"
out=$(b config restore --yes) || fail "restore failed: $out"
check_eq "machine.toml is back" "new = 2" "$(cat "$NX/machine.toml")"
check_eq "one safety copy" 1 "$(ls "$NX" | grep -c '^machine.toml.before-restore-')"
check_eq "the safety copy is the old file" "old = 1" "$(cat "$NX"/machine.toml.before-restore-*)"
check_eq "the identical file got no copy" 0 "$(ls "$NX" | grep -c '^machine.nix.before-restore-' || true)"
check_eq "hardware-configuration.nix untouched" "hw-live" "$(cat "$NX/hardware-configuration.nix")"
has "hs rebuild" && pass "points to hs rebuild" || fail "no rebuild hint: $out"
check_eq "no temp folder left" 0 "$(ls -A "$ST" | grep -c config-restore || true)"

echo "-- second run"
out=$(b config restore --yes)
has "identical" && pass "says identical" || fail "second: $out"
check_eq "still one safety copy" 1 "$(ls "$NX" | grep -c '^machine.toml.before-restore-')"

echo "-- with state"
echo 'new = 3' > "$FIX$NX/machine.toml"
out=$(b config restore --yes --with-state)
check_eq "restic-password not restored" "live-pass" "$(cat "$ST/restic-password")"
[ ! -e "$ST/disks" ] && pass "disks not restored" || fail "disks restored"
[ ! -e "$ST/vault-uuid" ] && [ ! -e "$ST/luks-uuids" ] && pass "vault-uuid and luks-uuids not restored" || fail "uuids restored"
check_eq "other state files are restored" "setting" "$(cat "$ST/sub/keep" 2>/dev/null)"
check_eq "machine.toml updated again" "new = 3" "$(cat "$NX/machine.toml")"
check_eq "hardware-configuration.nix still untouched" "hw-live" "$(cat "$NX/hardware-configuration.nix")"

echo "-- with state: the state folder of a service is the service's (links it planted are never followed)"
mkdir -p "$FIX$ST/svc/sub" "$FIX$ST/svc/new/deeper" "$WORK/pub/svc" "$WORK/victimdir"
echo restored > "$FIX$ST/svc/watched.tsv"; echo restored-sub > "$FIX$ST/svc/sub/f"; echo restored-deep > "$FIX$ST/svc/new/deeper/g"
echo victim > "$WORK/victim"
ln -s "$WORK/pub/svc" "$ST/svc"
ln -s "$WORK/victim" "$WORK/pub/svc/watched.tsv"
ln -s "$WORK/victimdir" "$WORK/pub/svc/sub"
ln -s "$WORK/victimdir" "$WORK/pub/svc/new"
out=$(b config restore --yes --with-state 2>&1)
check_eq "the file a link pointed to is untouched" "victim" "$(cat "$WORK/victim")"
check_eq "the folder a link pointed to got nothing" "" "$(ls "$WORK/victimdir")"
check "the planted link at the file is replaced by the restored file" sh -c "[ ! -L '$WORK/pub/svc/watched.tsv' ] && [ \"\$(cat '$WORK/pub/svc/watched.tsv')\" = restored ]"
check "the link replaced is kept as a link" sh -c "ls '$WORK/pub/svc' | grep -q '^watched.tsv.before-restore-' && [ -L \"\$(ls -d '$WORK/pub/svc/watched.tsv.before-restore-'*)\" ]"
check "a link in the way of a folder is refused (still a link, nothing below it)" sh -c "[ -L '$WORK/pub/svc/sub' ] && [ -L '$WORK/pub/svc/new' ]"
rm -f "$WORK/pub/svc/sub" "$WORK/pub/svc/new"; b config restore --yes --with-state >/dev/null 2>&1
check_eq "without a link in the way folders are made and files restored" "restored-sub restored-deep" "$(cat "$WORK/pub/svc/sub/f") $(cat "$WORK/pub/svc/new/deeper/g")"
check_eq "and the folders made are closed (0700)" "700" "$(stat -c %a "$WORK/pub/svc/new")"
rm -f "$ST/svc"; rm -rf "$WORK/pub"

echo "-- with state: a snapshot taken after the move keeps the data below the private root (/var/lib/hs/<name> is only a link there)"
export HS_EXT_STATE_DIR=$WORK/ext HS_PRIVATE_DIR=$WORK/priv
EP=$HS_PRIVATE_DIR/hs-ext
mkdir -p "$FIX$EP/Bad_Name" "$FIX$EP/svc2/sub" "$HS_EXT_STATE_DIR"; echo bad > "$FIX$EP/Bad_Name/x"; echo after-move > "$FIX$EP/svc2/data"; echo deep > "$FIX$EP/svc2/sub/f"
ln -s "$EP/svc2" "$FIX$HS_EXT_STATE_DIR/svc2" 2>/dev/null || true       # restic keeps the link itself; find -type f never lists it
out=$(b config restore --yes --with-state 2>&1)
check "a name below the private root that is no package name is refused, not copied with cp" test ! -e "$EP/Bad_Name" -a ! -e "$HS_EXT_STATE_DIR/Bad_Name"
check_eq "a fresh install gets the service state from the private root of the snapshot" "after-move deep" "$(cat "$HS_EXT_STATE_DIR/svc2/data" 2>/dev/null) $(cat "$HS_EXT_STATE_DIR/svc2/sub/f" 2>/dev/null)"
check_eq "and the folder is closed (0700), made the way a moved one is" "700 700" "$(stat -c %a "$HS_EXT_STATE_DIR/svc2") $(stat -c %a "$HS_EXT_STATE_DIR/svc2/sub")"
rm -rf "$HS_EXT_STATE_DIR/svc2"; mkdir -p "$EP/svc2/sub"; ln -s "$HS_EXT_STATE_DIR/svc2" "$HS_EXT_STATE_DIR/x" 2>/dev/null; rm -f "$HS_EXT_STATE_DIR/x"
ln -s "$EP/svc2" "$HS_EXT_STATE_DIR/svc2"
rm -rf "$EP/svc2/sub"; ln -s "$WORK/victimdir" "$EP/svc2/sub"; ln -s "$WORK/victim" "$EP/svc2/data"
out=$(b config restore --yes --with-state 2>&1)
check_eq "a link planted in the live service state: the file it points to is untouched" "victim" "$(cat "$WORK/victim")"
check_eq "and the folder it points to got nothing" "" "$(ls "$WORK/victimdir")"
check "the planted link at the file is replaced" sh -c "[ ! -L '$EP/svc2/data' ] && [ \"\$(cat '$EP/svc2/data')\" = after-move ]"
rm -rf "$HS_EXT_STATE_DIR" "$EP"

echo "-- an in-place restore never writes into the state of a service (the target and the path are canonicalised first)"
: > "$FIX.calls"
EXTP=$HS_EXT_STATE_DIR; mkdir -p "$EXTP"
rm -rf "$ST/svc"; mkdir -p "$EP/svc2"; ln -s "$EP/svc2" "$ST/svc"
for case_ in "// $ST/svc" "/. $ST/svc" "/./ $ST" "/ $WORK" "/ $(dirname "$WORK")" "/ $EP/svc2" "/ $EXTP" "/ $(dirname "$ST")/state/../state"; do
  set -- $case_
  out=$(b restore latest "$2" --tag host --to "$1" 2>&1 || true)
  case $out in *"Not restored in place"*) pass "refused: --to $1 $2" ;; *) fail "not refused: --to $1 $2: $(echo "$out" | head -2)" ;; esac
done
check "restic was never started for them" test ! -s "$FIX.calls"
out=$(b restore latest /srv/other --tag host --to / 2>&1 || true)
case $out in *"Not restored in place"*) fail "an unrelated path was refused" ;; *) pass "a path outside the state roots is not refused by the guard" ;; esac
rm -rf "$EXTP" "$EP"; rm -f "$ST/svc"

echo "-- from-disk: a fresh install (no password file, no state)"
export FIXPASS=typed-pass HS_RUN_DIR=$WORK
rm -rf "$ST" "$NX"; mkdir -p "$NX" "$ST"
echo 'old = 1' > "$NX/machine.toml"
echo 'new = 5' > "$FIX$NX/machine.toml"
export HS_SSH_DIR=$WORK/ssh HS_SAMBA_DIR=$WORK/samba
mkdir -p "$HS_SSH_DIR" "$FIX$HS_SSH_DIR" "$FIX$HS_SAMBA_DIR"
echo hostkey > "$FIX$HS_SSH_DIR/ssh_host_ed25519_key"
echo livekey > "$HS_SSH_DIR/ssh_host_ed25519_key"
echo sambasecret > "$FIX$HS_SAMBA_DIR/secrets.tdb"
fd() { bash "$SCRIPTS/backup.sh" config restore --from-disk /dev/fake "$@" 2>&1; }

out=$(printf 'typed-pass\n' | fd --dry-run)
has "ssh_host_ed25519_key" && has "machine.toml" && has "dry run" && pass "the plan names machine.toml and the SSH host key" || fail "from-disk dry: $out"
check_eq "dry run changes nothing" "old = 1" "$(cat "$NX/machine.toml")"
has "--with-samba" && pass "says Samba is left out" || fail "samba note: $out"
case "$out" in *secrets.tdb*) fail "samba listed without the flag" ;; *) pass "Samba not in the plan" ;; esac

if out=$(printf 'wrong\n' | fd --dry-run); then fail "wrong passphrase accepted"; else has "passphrase" && pass "wrong passphrase refused" || fail "wrong pass text: $out"; fi
if out=$(printf '\n' | fd --dry-run); then fail "empty passphrase accepted"; else pass "empty passphrase refused"; fi
if grep -qF typed-pass "$FIX.calls" 2>/dev/null; then fail "passphrase on argv"; else pass "passphrase never on argv"; fi

out=$(printf 'typed-pass\nmachine.toml\nnope\n' | fd)
check_eq "machine.toml restored" "new = 5" "$(cat "$NX/machine.toml")"
check_eq "SSH key kept without the typed line" "livekey" "$(cat "$HS_SSH_DIR/ssh_host_ed25519_key")"
has "SSH host keys not restored" && pass "says the keys were skipped" || fail "skip text: $out"
check_eq "no restic-password written" 0 "$(ls "$ST" | grep -c '^restic-password$' || true)"
check_eq "no passphrase file left" 0 "$(ls "$WORK" | grep -c 'hs-config-restore-pw' || true)"

out=$(printf 'typed-pass\nmachine.toml\nssh host keys\n' | fd)
check_eq "SSH key restored after typing its name" "hostkey" "$(cat "$HS_SSH_DIR/ssh_host_ed25519_key")"
check_eq "SSH key safety copy" "livekey" "$(cat "$HS_SSH_DIR"/ssh_host_ed25519_key.before-restore-*)"
[ ! -e "$HS_SAMBA_DIR/secrets.tdb" ] && pass "Samba secrets not restored by default" || fail "samba restored"

echo 'new = 6' > "$FIX$NX/machine.toml"
out=$(printf 'typed-pass\nmachine.toml\n' | fd --with-samba)
check_eq "Samba secrets restored with the flag" "sambasecret" "$(cat "$HS_SAMBA_DIR/secrets.tdb" 2>/dev/null)"

echo 'new = 7' > "$FIX$NX/machine.toml"
echo livekey2 > "$HS_SSH_DIR/ssh_host_ed25519_key"
out=$(printf 'typed-pass\n' | fd --yes)
check_eq "--yes leaves the SSH key alone" "livekey2" "$(cat "$HS_SSH_DIR/ssh_host_ed25519_key")"
check_eq "--yes restores machine.toml" "new = 7" "$(cat "$NX/machine.toml")"
if out=$(bash "$SCRIPTS/backup.sh" config restore --with-samba </dev/null 2>&1); then fail "--with-samba without --from-disk accepted"; else pass "--with-samba needs --from-disk"; fi

echo "-- vendor/ comes back with the settings (ADR 0017 decision 10)"
echo live-pass > "$ST/restic-password"; unset FIXPASS
mkdir -p "$FIX$NX/vendor/capabilities/fixmod"
printf '[fixmod]
version = "1.0.0"
' > "$FIX$NX/vendor/capabilities.lock"
echo '{ ... }: { }' > "$FIX$NX/vendor/capabilities/fixmod/module.nix"
out=$(b config)
has "vendor/" && pass "the list says the snapshot holds vendor/" || fail "list: $out"
out=$(b config restore --dry-run)
has "$NX/vendor/capabilities.lock" && has "$NX/vendor/capabilities/fixmod/module.nix" && pass "the plan names the lock and the module" || fail "plan: $out"
rm -rf "$NX/vendor"
out=$(b config restore --yes) || fail "restore failed: $out"
check_eq "the lock is back" '[fixmod]' "$(head -n 1 "$NX/vendor/capabilities.lock" 2>/dev/null)"
check "and the vendored module" test -f "$NX/vendor/capabilities/fixmod/module.nix"
check "the host snapshot takes /etc/nixos/vendor" grep -q '/etc/nixos/vendor' "$SCRIPTS/backup.sh"

finish
