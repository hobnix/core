#!/usr/bin/env bash
# `--dry-run` on `hs backup` and unknown words on `hs net ip` change nothing (#1354: `hs backup ct <name> reset --dry-run` removed the
# rules, `hs net ip <name> clear --dryrun` cleared the reservation). backup.sh takes --dry-run out for every command, so each changing
# command is run with it here: it shows a plan or refuses. Stand-ins log every call; the files are compared before and after.
# Needs jq, no root, no disk, no restic, no Incus.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
export HS_LANG=en HS_PLAIN=1 HS_CALLER=test HS_AUDIT_OFF=1 HS_LIVE_LOG=$WORK/live.log

if ! command -v jq >/dev/null 2>&1; then skip "jq is not installed: tests not run"; finish; exit $?; fi

export LOG=$WORK/calls.log DATA=$WORK/data
export HS_STATE_DIR=$DATA/state HS_BULK=$DATA/bulk HS_FAST=$DATA/fast HS_BACKUP_NO_MOUNT=1 HS_BACKUP_MOUNT=$DATA/mnt
export HS_BACKUP_REPO=$DATA/mnt/restic HS_NIXOS_DIR=$DATA/nixos HS_BACKUP_HOST_FILES=$DATA/nixos/machine.toml HS_INCUS=incus
export HS_BACKUP_NOTIFY=$WORK/bin/notify
BIN=$WORK/bin; mkdir -p "$BIN"
cp -r "$SCRIPTS" "$WORK/scripts"
cat > "$WORK/scripts/unifi.sh" <<'FAKE'
echo "unifi $*" >> "$LOG"
FAKE
# every program that could change something only logs
for p in systemctl systemd-run net mount umount wipefs mkfs.ext4 udevadm notify; do
  printf '#!/usr/bin/env bash\necho "%s $*" >> "$LOG"\n' "$p" > "$BIN/$p"
done
cat > "$BIN/lsblk" <<'FAKE'
#!/usr/bin/env bash
case "$*" in *-J*) echo '{"blockdevices":[]}' ;; esac
FAKE
cat > "$BIN/restic" <<'FAKE'
#!/usr/bin/env bash
echo "restic $*" >> "$LOG"
case " $* " in
  *" snapshots --tag ct:web "*) echo '[{"id":"abc123","time":"2026-01-01T00:00:00Z","tags":["ct:web","partial"]}]' ;;
  *" restore "*)   # config restore reads the settings into a temporary folder
    prev=""; for a in "$@"; do [ "$prev" != --target ] || target=$a; prev=$a; done
    mkdir -p "$target$HS_NIXOS_DIR"; echo 'from = "backup"' > "$target$HS_NIXOS_DIR/machine.toml" ;;
  *" stats "*) echo '{"total_size":1}' ;;
esac
FAKE
cat > "$BIN/incus" <<'FAKE'
#!/usr/bin/env bash
echo "incus $*" >> "$LOG"
case "$1" in
  query) echo '{"type":"container"}' ;;
  config) echo "00:16:3e:00:00:01" ;;
esac
FAKE
chmod +x "$BIN"/*
export PATH=$BIN:$PATH
H="bash $WORK/scripts/lib/hs.sh"
# backup.sh itself, for the rows with an argument template: what the dispatcher does with extra words there is #1345 (tests/ct-dry-run.sh)
S="bash $WORK/scripts/backup.sh"

setup() {
  rm -rf "$DATA"
  mkdir -p "$HS_STATE_DIR/backup-rules.d" "$HS_BULK/shares/docs" "$HS_BULK/shares/restored" "$HS_FAST" "$HS_BACKUP_REPO/data" "$HS_NIXOS_DIR"
  echo secret > "$HS_STATE_DIR/restic-password"
  echo web > "$HS_STATE_DIR/backup-instances"
  printf 'last_ok=1000\nstatus=ok\n' > "$HS_STATE_DIR/backup.state"
  echo 'sftp:me@nas.example:/backup' > "$HS_STATE_DIR/backup-offsite.repo"
  : > "$HS_BACKUP_REPO/config"
  : > "$HS_BACKUP_REPO/data/0a-tmp-1"
  echo 'from = "server"' > "$HS_NIXOS_DIR/machine.toml"
  # a rule file of the instance, at the place the script itself uses
  ( STATE=$HS_STATE_DIR; . "$SCRIPTS/lib/backup-rules.sh"; f=$(rules_file web); mkdir -p "$(dirname "$f")"; printf 'include /a\ninclude /b\n' > "$f" )
}
# every file and folder with its content; empty lock files are no state
files() { find "$DATA" ! -name '*.lock' -printf '%y %p %l\n' | sort; find "$DATA" -type f ! -name '*.lock' -exec cksum {} + | sort; }
# the logged calls that change something
changed() {
  grep -Ev '^incus (info|query|list|config get|config device get)( |$)|^restic .* (snapshots|stats|ls|find|cat|list)( |$)|^restic .* forget --dry-run( |$)|^restic .* restore .*--tag host --target [^ ]*\.config-restore\.|^unifi (reserved|used) |^unifi .*--dry-run' "$LOG" || true
}
RC=0; OUT=""; BEFORE=""
run() { setup; BEFORE=$(files); : > "$LOG"; RC=0; OUT=$("$@" 2>&1 </dev/null) || RC=$?; }
untouched() { [ "$(files)" = "$BEFORE" ] && [ -z "$(changed)" ]; }
why() { echo "exit $RC, calls: $(changed | tr '\n' ';') files: $(diff <(echo "$BEFORE") <(files) | head -n 4 | tr '\n' ' ') output: $(head -c 200 <<<"$OUT" | tr '\n' ' ')"; }
refused() {   # refused "what" <command...>: non-zero, a message, nothing changed
  local what=$1; shift
  run "$@"
  if [ "$RC" != 0 ] && [ -n "$OUT" ] && untouched; then pass "$what is refused and changes nothing"; else fail "$what must be refused ($(why))"; fi
}
planned() {   # planned "what" <regex of the plan> <command...>: exit 0, the plan, nothing changed
  local what=$1 re=$2; shift 2
  run "$@"
  if [ "$RC" = 0 ] && untouched && grep -Eq -- "$re" <<<"$OUT"; then pass "$what --dry-run shows the plan and changes nothing"; else fail "$what --dry-run ($(why))"; fi
}

echo "-- the two commands of the issue, as a person types them"
refused "hs backup ct web reset --dry-run"      $H backup ct web reset --dry-run
refused "reset of one rule, --dry-run"           $S ct web reset /a --dry-run
refused "hs net ip web clear --dryrun"          $H net ip web clear --dryrun

echo "-- every changing hs backup command: no dry run, so refused"
refused "share on"                  $S docs on --dry-run
refused "share off"                 $S docs off --dry-run
refused "instance on"               $S ct web on --dry-run
refused "instance off"              $S ct web off --dry-run
refused "include"                   $S ct web include /c --dry-run
refused "exclude"                   $S ct web exclude '*.log' --dry-run
refused "apply (the interface)"     bash "$WORK/scripts/backup.sh" ct web apply reset=all --dry-run
refused "restore of a path"         $H backup restore latest /x --to "$HS_BULK/shares/restored" --dry-run
refused "drill"                     $H backup drill --dry-run
refused "drill ct"                  $H backup drill ct --dry-run
refused "verify"                    $H backup verify --dry-run
refused "browse"                    $H backup browse --dry-run
refused "browse --off"              $H backup browse --off --dry-run
refused "offsite set"               $H backup offsite set sftp:me@other.example:/b --dry-run
refused "offsite now"               $H backup offsite now --dry-run
refused "offsite off"               $S offsite off --dry-run
refused "offsite migrate"           $H backup offsite migrate --dry-run
refused "offsite retention"         $H backup offsite retention --dry-run
refused "a word that is no command" $H backup frobnicate --dry-run
check_match "the refusal says why" "no dry run" "$OUT"

echo "-- the commands that honour --dry-run"
planned "now"            "Shares in the backup"  $H backup now --dry-run
export HS_BACKUP_NEW_SHARES=off   # reading which shares are in used to write the list of included shares
planned "now (new shares start off)" "Shares in the backup:   docs" $H backup now --dry-run
unset HS_BACKUP_NEW_SHARES
planned "report"         "nothing sent"          $H backup report --dry-run
planned "prune"          "nothing changed"       $H backup prune --dry-run
planned "restore ct"     "nothing was changed"   $H backup restore ct web --dry-run
planned "config restore" "nothing changed"       $H backup config restore --dry-run
if [ -b /dev/loop0 ]; then planned "init" "nothing changed" $H backup init /dev/loop0 --dry-run
else skip "no block device /dev/loop0: init --dry-run not run"; fi
run $S ct web paths --dry-run
if [ "$RC" = 0 ] && untouched; then pass "a command that only reads still takes --dry-run"; else fail "ct paths --dry-run ($(why))"; fi

echo "-- without --dry-run the rule commands still work"
run $H backup ct web reset
check_eq "reset removes the rules" "0 changed" "$RC $([ "$(files)" != "$BEFORE" ] && echo changed)"

echo "-- every changing hs backup command refuses a word or option it does not know"
refused "prune, misspelled"             $H backup prune --dryrun
refused "verify with a word"            $H backup verify everything
refused "report, misspelled"            $H backup report --dryrun
refused "now, misspelled"               $H backup now --dryrun
refused "browse, misspelled"            $H backup browse --of
refused "browse --off and more"         $H backup browse --off --dryrun
refused "drill, misspelled"             $H backup drill --dryrun
refused "drill with two numbers"        $H backup drill 3 4
refused "drill ct, misspelled"          $H backup drill ct --dryrun
refused "drill ct with two names"       $S drill ct web db
refused "init, misspelled"              $S init /dev/loop0 --dryrun
refused "init without a device"         $S init --dryrun
refused "restore of a path, misspelled" $H backup restore latest /x --to "$HS_BULK/shares/restored" --dryrun
refused "restore ct, misspelled"        $H backup restore ct web --yes --dryrun
refused "config restore, misspelled"    $H backup config restore --yes --dryrun
refused "config restore, two snapshots" $H backup config restore latest abc123 --yes
refused "config, misspelled"            $H backup config restor --yes
refused "offsite set, misspelled"       $H backup offsite set sftp:me@other.example:/b --dryrun
refused "offsite set, a second address" $H backup offsite set --kind folder --path "$DATA/off2" extra
refused "offsite now, misspelled"       $S offsite now --dryrun
refused "offsite off, misspelled"       $S offsite off --dryrun
refused "offsite migrate, a word"       $S offsite migrate all
refused "offsite retention, misspelled" $S offsite retention prun
refused "share on, misspelled"          $S docs on --dryrun
refused "share off, a word"             $S docs off now
refused "instance on, misspelled"       $S ct web on --dryrun
refused "instance off, a word"          $S ct web off now
refused "include, misspelled"           $S ct web include /c --dryrun
refused "exclude, an option as pattern" $S ct web exclude --dryrun
refused "reset, misspelled"             $S ct web reset --dryrun
refused "reset of a path, misspelled"   $S ct web reset /a --dryrun
refused "apply with a typo after a change" $S ct web apply reset=all --dryrun
for o in --yes --machine --foreground "--repo offsite"; do
  # shellcheck disable=SC2086
  refused "share off $o (it would be ignored)" $S docs off $o
done
# shellcheck disable=SC2086
for c in "prune --yes" "prune --repo offsite" "prune --machine" "now --repo offsite" "offsite off --yes" "report --foreground" "browse --repo offsite"; do
  refused "$c (it would be ignored)" $S $c
done
refused "--repo twice"                  $S verify --repo offsite --repo local

echo "-- what timers, jobs, the interface and the guides call still runs"
accepted() {   # accepted "what" <backup.sh words...>: not refused for its words (it may fail later for want of a real disk)
  local what=$1; shift
  run $S "$@"
  if grep -Eq "Unknown option or word|has no dry run|^usage:" <<<"$OUT"; then fail "$what is refused: $(head -c 200 <<<"$OUT")"; else pass "$what is taken"; fi
}
accepted "the nightly run"            now --scheduled
accepted "now --foreground"           now --foreground
accepted "verify --foreground"        verify --foreground
accepted "verify"                     verify
accepted "prune"                      prune
accepted "drill 5 (timer)"            drill 5
accepted "drill ct (timer)"           drill ct
accepted "drill ct <name>"            drill ct web
accepted "drill --repo offsite"       drill --repo offsite
accepted "the monthly report"         report --scheduled
accepted "share on (docker, web)"     docs on
accepted "share off"                  docs off
accepted "instance on"                ct web on
accepted "instance off"               ct web off
accepted "rules from the interface"   ct web apply include=/c 'exclude=*.log' reset=/a
accepted "include"                    ct web include /c
accepted "exclude"                    ct web exclude '*.log'
accepted "reset of one rule"          ct web reset /a
accepted "init job"                   init /dev/loop0 --yes
accepted "offsite set (job)"          offsite set sftp:me@other.example:/b
accepted "offsite set by kind"        offsite set --kind folder --path "$DATA/off2"
accepted "offsite set --machine"      offsite set --kind folder --path "$DATA/off2" --machine
accepted "offsite now"                offsite now
accepted "offsite off"                offsite off
accepted "offsite migrate"            offsite migrate
accepted "offsite retention"          offsite retention
accepted "offsite retention prune"    offsite retention prune
accepted "browse"                     browse
accepted "browse --off"               browse --off
accepted "share restore"              restore latest /x --to "$HS_BULK/shares/restored"
accepted "restore with tag, offsite"  restore latest /x --tag host --to "$HS_BULK/shares/restored" --keep-owner --repo offsite
accepted "restore ct job"             restore ct web --recipe web --dry-run
accepted "config restore"             config restore latest --with-state --yes --dry-run
accepted "list --repo offsite"        list --repo offsite
accepted "find --repo offsite"        find a.txt --repo offsite

echo "-- hs net ip refuses what it does not know"
refused "clear with a second word"       $H net ip web clear now
refused "clear --yes"                    $H net ip web clear --yes
refused "set with a typo"                $H net ip web set 192.0.2.5 --dryrun
refused "show with an extra word"        bash "$WORK/scripts/net-ip.sh" web show extra
refused "an unknown option for show"     bash "$WORK/scripts/net-ip.sh" web --dryrun
check_match "the refusal names the word" "'--dryrun'" "$OUT"
run $H net ip web clear --dry-run
if [ "$RC" = 0 ] && untouched; then pass "clear --dry-run changes nothing"; else fail "clear --dry-run ($(why))"; fi
run $H net ip web clear
check_eq "a plain clear still clears" "unifi clear-ip 00:16:3e:00:00:01" "$(changed)"
run bash "$WORK/scripts/net-ip.sh" web show
check_eq "show still works" "0" "$RC"

finish
