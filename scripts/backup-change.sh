#!/usr/bin/env bash
# help: change the backup without asking anything: what would happen (plan), then do it as a background job (start)
# help.de: das Backup ändern, ohne etwas zu fragen: was passieren würde (plan), dann als Hintergrundjob ausführen (start)
# args: plan|start <toggle|now|verify|prune|drill|browse|rules|offsite-set|offsite-config|offsite-now|offsite-off|init> [--name <share|instance>] [--set include=<path>|exclude=<glob>|reset=<path>|reset=all]... [--kind shares|sensitive|ct] [--to on|off] [--count <N>] [--repo <restic repository>] [--endpoint E --bucket B --prefix P --url U --user U --host H --port N --path P] [--disk <id>] [--confirm <disk name>]
# System command (hs sys backup plan|start): for the interface, timers and tests. It never asks and prints plain key<TAB>value lines like
# pool-change.sh and share-change.sh.
#   toggle --name <n> --kind shares|sensitive|ct --to on|off   put a share or an instance into the nightly backup or leave it out
#   now                                                        back up right now (the nightly run does the same)
#   verify                                                     read a part of the stored data and check it
#   prune                                                      give space back now: delete leftovers of a run that ran out of space, apply the retention, prune
#   drill [--count N]                                         restore N random files (default 5) and compare them with the originals
#   browse --to on|off                                         publish the whole backup read-only as the share backup-browse, or stop that
#   rules --name <instance> --set <change>...                  back up only chosen parts of an instance: --set include=<absolute path in it>, exclude=<restic glob>,
#                                                              reset=<path> (forget one rule) or reset=all (the whole instance again); applied in the order given
#   offsite-set --repo <restic repository>                     also copy every backup to a second repository (sftp:user@host:/path, b2:bucket:path, a folder ...); the
#                                                              credentials stay in /var/lib/hs/backup-offsite.env, written by hand, never passed through here
#   offsite-config --kind s3|rest|sftp|folder|typed [fields]   guided off-site target (hs backup offsite set --kind ...): s3 --endpoint --bucket [--prefix]; rest --url [--user];
#                                                              sftp --host --user [--port] --path; folder --path; typed --repo. The secrets (s3: access key id, secret key; rest: the
#                                                              password) are lines on STDIN, never arguments. `start` does it at once (no job: creating the repository is quick) and
#                                                              answers status done, address, created yes|no and, once, `secret<TAB>password<TAB>...` (the new repository's own password: "write it down")
#   offsite-now                                                copy the new backups to the off-site repository now
#   offsite-off                                                stop copying (what is there stays there)
#   init --disk <id>                                           RED: make a free disk (its name under /dev/disk/by-id, see `hs sys pool disks`) the backup disk: it is ERASED,
#                                                              formatted ext4 with the label `backup`, the backup password is created (or reused) and the repository initialised;
#                                                              the plan's confirm_name is the kernel name of the disk (sdc), `start` needs it in --confirm
#
# plan: exit 0 = allowed, 1 = refused, 2 = something is missing. Output: status ok|refused|needs, then needs<TAB><input>
#   | reason<TAB><text> | heading|step|note|warn|danger|command<TAB><line>, confirm_name<TAB><disk> (only init), long<TAB>yes|no. Only init is red.
# start: the same checks, then the work runs as a background job (status started, unit).
# Test knobs: HS_BACKUP (stand-in for backup.sh), HS_BACKUP_NEXT (epoch of the next timer run), HS_INCUS, HS_STATE_DIR, HS_DISK_BYID (the directory of the by-id links).
set -euo pipefail
here=$(dirname "$0")
backup=${HS_BACKUP:-$here/backup.sh}

refuse() { printf 'status\trefused\nreason\t%s\n' "$1"; exit 1; }
. "$here/lib/refuse-code.sh"   # refuse_code (ADR 0028)

verb=${1:-}; action=${2:-}
case "$verb" in plan|start) ;; *) echo "usage: backup-change.sh plan|start <toggle|now|verify|drill|browse> [options]" >&2; exit 1 ;; esac
case "$action" in toggle|now|verify|prune|drill|browse|rules|offsite-set|offsite-config|offsite-now|offsite-off|init) ;; *) refuse_code action.unknown "unknown action (toggle, now, verify, drill, browse, offsite-set|config|now|off or init)" ;; esac
shift 2
sets=()
name="" kind="" to="" count=5 repo="" disk="" confirm="" endpoint="" bucket="" prefix="" url="" user="" host="" port="" path=""
while [ $# -gt 0 ]; do
  case "$1" in
    --name)    name=${2:-}; shift 2 ;;
    --kind)    kind=${2:-}; shift 2 ;;
    --to)      to=${2:-}; shift 2 ;;
    --set)     sets+=("${2:-}"); shift 2 ;;
    --count)   count=${2:-}; shift 2 ;;
    --repo)    repo=${2:-}; shift 2 ;;
    --disk)    disk=${2:-}; shift 2 ;;
    --endpoint) endpoint=${2:-}; shift 2 ;;
    --bucket)  bucket=${2:-}; shift 2 ;;
    --prefix)  prefix=${2:-}; shift 2 ;;
    --url)     url=${2:-}; shift 2 ;;
    --user)    user=${2:-}; shift 2 ;;
    --host)    host=${2:-}; shift 2 ;;
    --port)    port=${2:-}; shift 2 ;;
    --path)    path=${2:-}; shift 2 ;;
    --confirm) confirm=${2:-}; shift 2 ;;
    *) refuse_code option.unknown "unknown option $1" ;;
  esac
done

needs=()
case "$action" in
  toggle) [ -n "$name" ] || needs+=(name); [ -n "$kind" ] || needs+=(kind); [ -n "$to" ] || needs+=(to) ;;
  browse) [ -n "$to" ] || needs+=(to) ;;
  rules) [ -n "$name" ] || needs+=(name); [ ${#sets[@]} -gt 0 ] || needs+=(set) ;;
  offsite-set) [ -n "$repo" ] || needs+=(repo) ;;
  offsite-config)
    [ -n "$kind" ] || needs+=(kind)
    case "$kind" in
      s3) [ -n "$endpoint" ] || needs+=(endpoint); [ -n "$bucket" ] || needs+=(bucket) ;;
      rest) [ -n "$url" ] || needs+=(url) ;;
      sftp) [ -n "$host" ] || needs+=(host); [ -n "$user" ] || needs+=(user); [ -n "$path" ] || needs+=(path) ;;
      folder) [ -n "$path" ] || needs+=(path) ;;
      typed) [ -n "$repo" ] || needs+=(repo) ;;
    esac ;;
  init) [ -n "$disk" ] || needs+=(disk) ;;
esac
if [ ${#needs[@]} -gt 0 ]; then
  printf 'status\tneeds\n'
  printf 'needs\t%s\n' "${needs[@]}"
  exit 2
fi
case "$action" in
  toggle)
    [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || refuse_code name.invalid "invalid name"
    case "$kind" in shares|sensitive|ct) ;; *) refuse_code backup.kind-invalid "--kind is shares, sensitive or ct" ;; esac
    [ "$to" = on ] || [ "$to" = off ] || refuse_code backup.to-invalid "--to is on or off" ;;
  browse) [ "$to" = on ] || [ "$to" = off ] || refuse_code backup.to-invalid "--to is on or off" ;;
  rules)
    [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || refuse_code name.invalid "invalid name"
    . "$here/lib/backup-rules.sh"
    for s in "${sets[@]}"; do
      case "$s" in
        include=*) rules_path_ok "${s#include=}" || refuse_code backup.rule-invalid "an include is an absolute path inside the instance, without .. in it" ;;
        exclude=*) rules_glob_ok "${s#exclude=}" || refuse_code backup.rule-invalid "an exclude is a restic pattern: not empty, no ! in front" ;;
        reset=*) [ "${s#reset=}" = all ] || [ -n "${s#reset=}" ] || refuse_code backup.rule-invalid "reset needs a path or all" ;;
        *) refuse_code backup.rule-invalid "--set is include=<path>, exclude=<glob>, reset=<path> or reset=all" ;;
      esac
    done ;;
  offsite-set) { [[ "$repo" =~ ^[A-Za-z0-9/@:._+=,~%-]+$ ]] && [[ "$repo" != -* ]] && [[ "$repo" != *..* ]]; } || refuse_code backup.repo-invalid "that is not a restic repository address (for example sftp:user@host:/path, b2:bucket:path or a folder)" ;;
  offsite-config)
    case "$kind" in s3|rest|sftp|folder|typed) ;; *) refuse_code backup.kind-invalid "--kind is s3, rest, sftp, folder or typed" ;; esac
    # every field is a plain word: no option look-alike, no .. (backup.sh checks the shape of each kind again)
    for f in "$endpoint" "$bucket" "$prefix" "$url" "$user" "$host" "$port" "$path" "$repo"; do
      { [[ "$f" =~ ^[A-Za-z0-9/@:._+=,~%-]*$ ]] && [[ "$f" != -* ]] && [[ "$f" != *..* ]]; } || refuse_code backup.repo-invalid "a field of the target has characters that do not belong in an address"
    done ;;
  init)   [[ "$disk" =~ ^[A-Za-z0-9][A-Za-z0-9._:-]*$ ]] || refuse_code disk.unknown "that is not a disk id (see hs sys pool disks)" ;;
  drill)  [[ "$count" =~ ^[0-9]+$ ]] && [ "$count" -ge 1 ] && [ "$count" -le 100 ] || refuse_code backup.count-invalid "--count is a number from 1 to 100" ;;
esac

export HS_PLAIN=1 HS_LANG=en HS_CALLER=${HS_CALLER:-ui}
unset HS_GUIDED_TTY

state=$(bash "$backup" --state 2>/dev/null || true)
st() { awk -F'\t' -v k="$1" '$1 == k { print $2 }' <<<"$state"; }
overview=$(bash "$backup" --overview 2>/dev/null || true)
state_dir=${HS_STATE_DIR:-/var/lib/hs}

# the actions that read the backup disk need it set up, the vault open and the disk there
needs_disk() {
  [ "$(st configured)" = yes ] || refuse_code backup.not-set-up "The backup is not set up yet (hs backup init <device>)."
  [ "$(st vault)" != closed ] || refuse_code vault.locked "The vault is closed: unlock it first (hs unlock)."
  [ "$(st disk)" = present ] || refuse_code backup.disk-missing "The backup disk is not plugged in."
}

case "$action" in
  toggle)
    if [ "$kind" = ct ]; then
      ${HS_INCUS:-incus} info "$name" >/dev/null 2>&1 || refuse_code backup.instance-unknown "There is no instance called '$name'."
      cmd=(bash "$backup" ct "$name" "$to")
    else
      awk -F'\t' -v n="$name" '$1 != "ct" && $1 != "always" && $2 == n { f = 1 } END { exit !f }' <<<"$overview" || refuse_code share.unknown "There is no share called '$name'."
      cmd=(bash "$backup" "$name" "$to")
    fi ;;
  rules)
    ${HS_INCUS:-incus} info "$name" >/dev/null 2>&1 || refuse_code backup.instance-unknown "There is no instance called '$name'."
    cmd=(bash "$backup" ct "$name" apply "${sets[@]}") ;;
  now)    needs_disk; cmd=(bash "$backup" now) ;;
  verify) needs_disk; cmd=(bash "$backup" verify) ;;
  prune)  needs_disk; cmd=(bash "$backup" prune) ;;
  drill)  needs_disk; cmd=(bash "$backup" drill "$count") ;;
  init)
    [ "$(st vault)" != closed ] || refuse_code vault.locked "The vault is closed: unlock it first (hs unlock)."
    # a disk labelled backup is plugged in: formatting another one would leave two, and init would not touch the first
    [ "$(st disk)" != present ] || refuse_code backup.disk-present "A backup disk is plugged in already (label 'backup'). Unplug it first if you really want to replace it."
    dev=${HS_DISK_BYID:-/dev/disk/by-id}/$disk
    [ -e "$dev" ] || refuse_code disk.unknown "There is no disk '$disk' (see hs sys pool disks)."
    diskname=$(basename "$(readlink -f "$dev")")
    rc=0
    dry=$(bash "$backup" init "$dev" --dry-run </dev/null 2>&1) || rc=$?
    if [ "$rc" -ne 0 ]; then
      echo "status	refused"
      printf '%s\n' "$dry" | sed -e 's/^[[:space:]]*//' -e 's/^✗ *//' -e 's/^! *//' | awk 'NF { print "reason\t" $0 }'
      exit 1
    fi
    cmd=(bash "$backup" init "$dev" --yes) ;;
  offsite-set) needs_disk; cmd=(bash "$backup" offsite set "$repo") ;;
  offsite-config)
    needs_disk
    if [ "$kind" = typed ]; then cmd=(bash "$backup" offsite set "$repo"); else cmd=(bash "$backup" offsite set --kind "$kind"); fi
    if [ "$kind" != typed ]; then
      for pair in endpoint:"$endpoint" bucket:"$bucket" prefix:"$prefix" url:"$url" user:"$user" host:"$host" port:"$port" path:"$path"; do
        [ -z "${pair#*:}" ] || cmd+=("--${pair%%:*}" "${pair#*:}")
      done
    fi ;;
  offsite-now)
    [ -n "$(st offsite)" ] || refuse_code backup.no-offsite "There is no off-site repository yet: set one first."
    needs_disk; cmd=(bash "$backup" offsite now) ;;
  offsite-off)
    [ -n "$(st offsite)" ] || refuse_code backup.no-offsite "The off-site copy is off already."
    cmd=(bash "$backup" offsite off) ;;
  browse)
    if [ "$to" = on ]; then
      needs_disk
      [ "$(st browse)" != on ] || refuse_code backup.browse-state "Browsing is on already."
      cmd=(bash "$backup" browse)
    else
      [ "$(st browse)" = on ] || refuse_code backup.browse-state "Browsing is off already."
      cmd=(bash "$backup" browse --off)
    fi ;;
esac

if [ "$verb" = start ] && [ "$action" = offsite-config ]; then
  # no job: the secrets are lines on stdin and must not travel through a unit; creating the repository takes seconds
  errf=$(mktemp); trap 'rm -f "$errf"' EXIT
  rc=0
  out=$("${cmd[@]}" --machine 2>"$errf") || rc=$?
  if [ "$rc" -ne 0 ]; then
    printf 'status\trefused\n'
    sed -e 's/\x1b\[[0-9;]*m//g' -e 's/^[[:space:]]*//' "$errf" | awk 'NF { sub(/^[^A-Za-z0-9]+/, ""); print "reason\t" $0; exit }'
    exit 1
  fi
  printf '%s\n' "$out"
  exit 0
fi
if [ "$verb" = start ]; then
  if [ "$action" = init ] && [ "$confirm" != "$diskname" ]; then refuse_code confirm.missing "type the name of the disk to confirm: $diskname"; fi
  . "$here/lib/job.sh"
  unit=$(hs_job "backup-$action" "hs backup $action" -- "${cmd[@]}") || refuse_code job.start-failed "the job could not be started"
  printf 'status\tstarted\nunit\t%s\n' "$unit"
  exit 0
fi

echo "status	ok"
case "$action" in
  toggle)
    if [ "$kind" = ct ]; then
      if [ "$to" = on ]; then
        printf 'heading\tput the instance %s into the backup\nstep\tinclude the files of %s in the nightly backup\nnote\tIts files are read from the mounted disk, so they are only backed up while it runs.\n' "$name" "$name"
      else
        printf 'heading\ttake the instance %s out of the backup\nstep\tleave %s out of the nightly backup (existing backups stay until they age out)\n' "$name" "$name"
      fi
    elif [ "$to" = on ]; then
      printf 'heading\tput %s into the backup\nstep\tinclude %s in the nightly backup\n' "$name" "$name"
    else
      printf 'heading\ttake %s out of the backup\nstep\tleave %s out of the nightly backup (existing backups stay until they age out)\n' "$name" "$name"
    fi ;;
  rules)
    printf 'heading	choose what of %s is backed up
' "$name"
    for s in "${sets[@]}"; do
      case "$s" in
        include=*) printf 'step	back up %s
' "${s#include=}" ;;
        exclude=*) printf 'step	leave out %s
' "${s#exclude=}" ;;
        reset=all) printf 'step	forget all rules: the whole instance is backed up again
' ;;
        reset=*)   printf 'step	forget the rule for %s
' "${s#reset=}" ;;
      esac
    done
    printf 'note	With rules the instance is backed up as a partial backup: only the chosen paths (and its database dump files). It cannot boot from its backup: a restore runs the recipe again and puts the paths back.
' ;;
  now)
    shares=$(awk -F'\t' '$1 != "ct" && $1 != "always" && $3 == "on" { n++ } END { print n + 0 }' <<<"$overview")
    cts=$(awk -F'\t' '$1 == "ct" && $3 == "on" { n++ } END { print n + 0 }' <<<"$overview")
    printf 'heading\tback up now\nstep\tback up %s share(s) and %s instance(s)\nstep\tback up the domain controller and the host files\nstep\tcopy to the off-site repository if one is set, and prune old snapshots\n' "$shares" "$cts"
    printf 'note\tShares stay usable. The nightly run does the same at 04:00.\n'
    next=${HS_BACKUP_NEXT:-$(st next)}
    if [[ "$next" =~ ^[0-9]+$ ]]; then
      left=$(( next - $(date +%s) ))
      if [ "$left" -ge 0 ] && [ "$left" -le 1800 ]; then
        printf 'warn\tThe nightly backup starts in %s min: it skips while this one holds the repository lock, or runs right after it.\n' "$(( left / 60 ))"
      fi
    fi ;;
  verify)
    printf 'heading\tcheck the stored data\nstep\tread a tenth of the stored data and compare it with its checksums\nnote\tThe backup disk is busy for a while; nothing is changed.\n' ;;
  prune)
    printf 'heading\tgive space back on the backup disk\nstep\tdelete leftovers of a run that ran out of space\nstep\tkeep 7 daily, 4 weekly and 6 monthly snapshots per kind, forget the rest\nstep\tprune the data no snapshot uses any more\nnote\tThe backup disk is busy for a while (the nightly run does this on Sundays). Nothing a kept snapshot needs is deleted.\n' ;;
  drill)
    printf 'heading\trestore drill\nstep\trestore %s random file(s) of the newest shares backup into a temporary folder\nstep\tcompare each with the original and delete the temporary folder\nnote\tThe result counts for the health check (a drill is expected every 45 days).\n' "$count" ;;
  init)
    printf 'heading\tmake %s the backup disk\n' "$diskname"
    printf 'step\terase %s and format it ext4 with the label backup\n' "$diskname"
    if [ -e "$state_dir/restic-password" ]; then printf 'step\tkeep the existing backup password\n'; else printf 'step\tcreate the backup password (root only, inside the vault when there is one)\n'; fi
    printf 'step\tcreate the backup repository on it\n'
    printf '%s\n' "$dry" | awk '/^[ \t]*Disk[ \t]/ { sub(/^[ \t]+/, ""); print "note\t" $0; exit }'
    printf 'note\tAfterwards read the password once with: sudo cat %s/restic-password, and SAVE IT elsewhere: without it a backup cannot be opened, also not after the system disk dies.\n' "$state_dir"
    [ "$(st configured)" != yes ] || printf 'warn\tA backup was set up before: the password is reused, but the old backups are not on this disk.\n' ;;
  offsite-set)
    printf 'heading\tcopy every backup to a second repository\nstep\tuse %s as the off-site repository (created when it does not exist yet, with the same password)\nstep\tcopy every new backup there after each nightly run\n' "$repo"
    case "$repo" in
      s3:*|b2:*|azure:*|gs:*|rest:*|swift:*|rclone:*)
        [ -s "$state_dir/backup-offsite.env" ] || printf 'warn\tThis repository needs credentials: write them into %s/backup-offsite.env first (root only), or creating it fails.\n' "$state_dir" ;;
    esac
    if [ -n "$(st offsite)" ] && [ "$(st offsite)" != "$repo" ]; then printf 'warn\tThe current off-site repository (%s) is replaced; what is there stays there.\n' "$(st offsite)"; fi
    printf 'note\tThe first copy sends the whole backup: that can take a long time and a lot of traffic.\n' ;;
  offsite-config)
    printf 'heading\tcopy every backup to a second repository (%s)\nstep\twrite the repository address and the keys into root-only files (inside the vault when there is one)\nstep\tcreate the repository when it does not exist yet, with its OWN password\nstep\tcopy every new backup there after each nightly run\n' "$kind"
    case "$kind" in
      s3) printf 'note\tThe access key id and the secret key are asked for next; they are not part of any command line.\n' ;;
      rest) [ -z "$user" ] || printf 'note\tThe password of the REST server is asked for next. The server should run as: rest-server --append-only (this server then cannot delete there; the target prunes itself).\n' ;;
      sftp) printf 'note\tSFTP uses the ssh key of root on this server: put it on the target first (no password).\n' ;;
    esac
    case "$kind" in rest) ;; *) printf 'note\tOld backups there are forgotten (7 daily, 4 weekly, 6 monthly) and pruned on Sundays from this server.\n' ;; esac
    if [ -n "$(st offsite)" ]; then printf 'warn\tThe current off-site repository (%s) is replaced; what is there stays there.\n' "$(st offsite)"; fi
    printf 'note\tA new repository gets its own password: write it down when it is shown (once). The first copy is a separate step: Copy off-site now.\n' ;;
  offsite-now)
    printf 'heading\tcopy to the off-site repository now\nstep\tcopy the backups the off-site repository does not have yet to %s\nnote\tA failed copy only warns: the backup itself is fine.\n' "$(st offsite)" ;;
  offsite-off)
    printf 'heading\tswitch the off-site copy off\nstep\tstop copying to %s\nnote\tWhat is already there stays there.\n' "$(st offsite)" ;;
  browse)
    if [ "$to" = on ]; then
      printf 'heading\tbrowse the backup\nstep\tmount the whole backup read-only\nstep\tpublish it as the share backup-browse (Domain Admins only)\nwarn\tThe backup disk stays mounted until you switch browsing off again.\n'
    else
      printf 'heading\tstop browsing the backup\nstep\tremove the share backup-browse and unmount the backup\n'
    fi ;;
esac
printf 'command\t%s\n' "${cmd[*]}"
if [ "$action" = init ]; then
  printf 'danger\tThis ERASES everything on %s and makes it the backup disk.\nconfirm_name\t%s\n' "$diskname" "$diskname"
fi
case "$action" in toggle|browse|rules|offsite-off|offsite-config|init) printf 'long\tno\n' ;; *) printf 'long\tyes\n' ;; esac
exit 0
