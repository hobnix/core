#!/usr/bin/env bash
# help: take over the disks of an Unraid server in one guided flow: one plan, the old parity disk typed by name, then a background job
# help.de: die Platten eines Unraid-Servers in einem geführten Ablauf übernehmen: ein Plan, die alte Paritätsplatte per Name getippt, dann ein Hintergrundjob
# args: [--disks <id,...>] [--parity <id,...>] [--spare <id>] [--pool <name>] [--per-disk] [--chown] [--dry-run] [--yes]
# docs/PLAN-storage-nas.md Q3, step 9 (#460 c). A layer over `hs pool <pool> add --role adopt` (manage-pool.sh), which keeps the technique: read-only
# mounts by UUID while a spare disk builds the parity (/var/lib/hs/adopting/<fs-uuid>), labels and folder moves only after the sync.
# This script adds what is Unraid's: the folders of the disks are MERGED (Unraid's user shares), reserved names get a suffix, files stay nobody:users
# (99:100) unless --chown, encrypted disks (D11), and the OLD parity disk(s) become parity only after the first sync has finished.
#
#   hs migrate unraid [options]            asks what is missing, shows the plan, asks the typed word, offers a background job
#   hs sys migrate plan unraid [options]   the plan as data, never asks. Exit 0 ok, 1 refused, 2 something is missing. Lines (tab separated, empty = -):
#       status<TAB>ok|refused|needs
#       needs<TAB>disks|unlock                      (status needs)
#       candidate<TAB><id><TAB><size bytes><TAB>data|encrypted|empty|refused<TAB><note>     (status needs disks: what can be picked)
#       reason<TAB><text>                           (status refused)
#       disk<TAB><id><TAB>data|old-parity|spare<TAB><size bytes><TAB><file system or ->     (status ok)
#       heading|step|note|warn|danger|section|text<TAB><line>
#       confirm_name<TAB><word>     long<TAB>yes     option<TAB><name><TAB><values separated by |><TAB><default>
#   hs sys migrate start unraid [options] --confirm <word>   the same checks, then a background job; status started + unit
# --unlock (encrypted disks): standard input is ONE line, {"unraid":"<passphrase of the Unraid disks>","server":"<this server's, optional>"}.
# It goes into 0600 files that the job reads and deletes, never into an argument.
# `run` is the job itself (internal). Test knobs: HS_MANAGE_POOL (stand-in for manage-pool.sh), HS_BULK_SYNC, HS_RUN_DIR.
set -euo pipefail
here=$(dirname "$0")
. "$here/lib/ui.sh"
. "$here/lib/pools.sh"
manage=${HS_MANAGE_POOL:-$here/manage-pool.sh}
syncs=${HS_BULK_SYNC:-$here/bulk-sync.sh}
run_dir=${HS_RUN_DIR:-/run/hs}

verb=""
case "${1:-}" in plan|start|run) verb=$1; shift ;; esac
machine=false; { [ -z "$verb" ] || [ "$verb" = run ]; } || machine=true

disks="" parity="" spare="" pool="" merge=true chown=false unlock=false dry=false yes=false confirm=""
while [ $# -gt 0 ]; do
  case "$1" in
    --disks)    disks=${2:-}; shift 2 ;;
    --parity)   parity=${2:-}; shift 2 ;;
    --spare)    spare=${2:-}; shift 2 ;;
    --pool)     pool=${2:-}; shift 2 ;;
    --per-disk) merge=false; shift ;;
    --chown)    chown=true; shift ;;
    --unlock)   unlock=true; shift ;;
    --dry-run)  dry=true; shift ;;
    --yes)      yes=true; shift ;;
    --confirm)  confirm=${2:-}; shift 2 ;;
    -h|--help)  say "usage: hs migrate unraid [--disks <id,...>] [--parity <id,...>] [--spare <id>] [--pool <name>] [--per-disk] [--chown] [--dry-run]"; exit 1 ;;
    *) if $machine; then printf 'status\trefused\nreason\tunknown option %s\n' "$1"; exit 1; else fail "unknown option $1"; fi ;;
  esac
done

refuse() {   # refuse <text>
  if $machine; then printf 'status\trefused\nreason\t%s\n' "$1"; exit 1; fi
  fail "$1"
}
[ -n "$pool" ] || pool=$(pool_names data | sed -n 1p)   # the pool that holds the data (--pool names another one)
[ -n "$pool" ] || refuse "no pool for data found: name one with --pool"
[[ "$pool" =~ ^[a-z][a-z0-9_-]*$ ]] || refuse "invalid pool name"
if pool_exists "$pool" && ! pool_is_snapraid "$pool"; then refuse "$pool is not a SnapRAID pool: disks from Unraid are adopted into one (a ZFS pool can not take them)"; fi

human() { numfmt --to=si --suffix=B --format='%.1f' "$1"; }

# the file system of a disk (the first partition that holds one), read by blkid
fs_of() {   # fs_of <by-id name>: xfs|ext4|btrfs|crypto_LUKS|zfs_member|<other>|-
  local dev=/dev/disk/by-id/$1 p t
  while read -r p; do
    t=$(blkid -p -o value -s TYPE "$p" 2>/dev/null || true)
    [ -z "$t" ] || { echo "$t"; return; }
  done < <(lsblk -nr -o PATH "$dev" 2>/dev/null)
  echo -
}

declare -A cand_size cand_fs role_of
cand_ids=()
load_candidates() {
  local id size _r
  while IFS=$'\t' read -r id size _r; do
    [ -n "$id" ] || continue
    cand_size[$id]=$size; cand_fs[$id]=$(fs_of "$id"); cand_ids+=("$id")
  done < <(ADOPT_LISTING=1 bash "$manage" --list-disks </dev/null 2>/dev/null || true)
}
kind_of() {   # data|encrypted|empty|refused for a candidate
  case "${cand_fs[$1]}" in
    xfs|ext4|btrfs) echo data ;; crypto_LUKS) echo encrypted ;; -) echo empty ;; *) echo refused ;;
  esac
}
load_candidates

# ── nothing picked yet ──
if [ -z "$disks" ]; then
  if $machine; then
    echo "status	needs"; echo "needs	disks"
    for id in "${cand_ids[@]}"; do
      k=$(kind_of "$id"); n=-
      case "$k" in refused) n="holds ${cand_fs[$id]}: it can not be adopted (see hs migrate check)" ;; encrypted) n="encrypted: needs the Unraid passphrase" ;; esac
      printf 'candidate\t%s\t%s\t%s\t%s\n' "$id" "${cand_size[$id]}" "$k" "$n"
    done
    exit 2
  fi
  [ "$verb" != run ] || fail "no disks given"
  step "Disks of the Unraid server"
  rows=()
  for id in "${cand_ids[@]}"; do rows+=("$id"$'\t'"$(human "${cand_size[$id]}")"$'\t'"${cand_fs[$id]}"$'\t'"$(kind_of "$id")"); done
  [ ${#rows[@]} -gt 0 ] || fail "No other disk found. Plug the old disks in first (hs migrate check looks at them)."
  { thead disk size filesystem use; printf '%s\n' "${rows[@]}"; } | table
  def=""
  for id in "${cand_ids[@]}"; do case "$(kind_of "$id")" in data|encrypted) def+="$id," ;; esac; done
  disks=$(ask "Disks that hold the files, separated by commas" "${def%,}")
  if [ -z "$parity" ]; then parity=$(ask "The old Unraid parity disk(s), typed by name, separated by commas (empty = none)" ""); fi
  if [ -z "$spare" ]; then
    spare=$(ask "A spare disk at least as large as the largest data disk, to build the parity first (empty = none: the old parity disk is used, with a window without protection)" "")
  fi
fi

# ── checks on what was named ──
IFS=',' read -r -a want_data <<<"$disks"
IFS=',' read -r -a want_par <<<"$parity"
enc=false; max_data=0
for id in "${want_data[@]}"; do
  [ -n "$id" ] || continue
  [ -n "${cand_fs[$id]:-}" ] || refuse "$id is not a free disk this server sees"
  case "$(kind_of "$id")" in
    data) ;;
    encrypted) enc=true ;;
    empty) refuse "$id holds no file system: it is not a data disk (is it the old parity disk? name it with --parity)" ;;
    *) refuse "$id holds ${cand_fs[$id]}: it can not be adopted as it is (hs migrate check says more)" ;;
  esac
  role_of[$id]=data
  [ "${cand_size[$id]}" -le "$max_data" ] || max_data=${cand_size[$id]}
done
for id in "${want_par[@]}"; do
  [ -n "$id" ] || continue
  [ -n "${cand_fs[$id]:-}" ] || refuse "$id is not a free disk this server sees"
  [ -z "${role_of[$id]:-}" ] || refuse "$id is named twice"
  [ "$(kind_of "$id")" = empty ] || refuse "$id holds ${cand_fs[$id]}: an Unraid parity disk has no file system. It is not erased; check the name"
  [ "${cand_size[$id]}" -ge "$max_data" ] || refuse "the old parity disk $id ($(human "${cand_size[$id]}")) is smaller than the largest data disk ($(human "$max_data"))"
  role_of[$id]=old-parity
done
if [ -n "$spare" ]; then
  [ -n "${cand_fs[$spare]:-}" ] || refuse "$spare is not a free disk this server sees"
  [ -z "${role_of[$spare]:-}" ] || refuse "$spare is also named as a data or parity disk"
  [ "$(kind_of "$spare")" = empty ] || refuse "$spare holds ${cand_fs[$spare]}: a spare disk is erased, so it must be empty. Erase it first or take another"
  [ "${cand_size[$spare]}" -ge "$max_data" ] || refuse "the spare disk ($(human "${cand_size[$spare]}")) is smaller than the largest data disk ($(human "$max_data"))"
  role_of[$spare]=spare
fi
if $enc && ! $unlock && [ "$verb" != run ]; then
  if $machine; then echo "status	needs"; echo "needs	unlock"; exit 2; fi
fi

adopt_args=("$pool" --role adopt --disks "$disks")
if $merge; then adopt_args+=(--merge); fi
if $chown; then adopt_args+=(--chown); fi
[ -z "$spare" ] || adopt_args+=(--spare "$spare")

# ── the job: adopt (in the order of the plan), then the old parity disks, each followed by a sync ──
if [ "$verb" = run ]; then
  step "Adopt the disks"
  bash "$manage" "${adopt_args[@]}" --yes || fail "Adopting stopped. Read what it said above, fix the cause and run hs migrate unraid again."
  for id in "${want_par[@]}"; do
    [ -n "$id" ] || continue
    step "The old parity disk $id becomes parity"
    bash "$manage" "$pool" --role parity --disks "$id" --yes || fail "Could not add $id as a parity disk. Add it by hand: hs pool $pool add --role parity"
    bash "$syncs" --no-mover --force || fail "The parity sync after adding $id did not finish: run hs pool $pool sync"
    ok "$id is parity and in sync"
  done
  if [ -z "$parity" ] && [ -z "$spare" ]; then
    warn "No parity disk was named: the data is NOT protected. Add one: hs pool $pool add --role parity"
  fi
  ok "Done. The folders of the disks are shares now: publish them with hs share repair."
  exit 0
fi

# ── the passphrases: files (0600) that the adopt code reads and deletes ──
pass_files=()
cleanup_pass() { [ ${#pass_files[@]} -eq 0 ] || rm -f "${pass_files[@]}"; }
trap cleanup_pass EXIT
make_pass_files() {   # machine mode: from the one JSON line on stdin; a person is asked. Sets HS_UNRAID_PASSPHRASE_FILE (and HS_DISK_PASSPHRASE_FILE)
  $enc || return 0
  mkdir -p "$run_dir"; chmod 700 "$run_dir"
  local uf sf line a
  uf=$(mktemp "$run_dir/job-unraid-pass.XXXXXX"); sf=$(mktemp "$run_dir/job-pass.XXXXXX"); pass_files+=("$uf" "$sf")
  if $machine; then
    IFS= read -r line || line=""
    [ -n "$line" ] || refuse "no passphrase on standard input"
    printf '%s' "$line" | python3 -I -c '
import json, os, sys
raw = sys.stdin.read()
try:
    d = json.loads(raw)
    u, s = d.get("unraid", ""), d.get("server", "")
except Exception:
    u, s = raw, ""
for path, val in ((sys.argv[1], u), (sys.argv[2], s)):
    fd = os.open(path, os.O_WRONLY | os.O_TRUNC, 0o600)
    os.write(fd, val.encode()); os.close(fd)
' "$uf" "$sf"
  else
    a=$(ask_secret "Passphrase of the encrypted Unraid disks:")
    printf %s "$a" > "$uf"
    if [ -s /var/lib/hs/luks-uuids ] && [ ! -f /var/lib/hs/disk-key ]; then
      a=$(ask_secret "This server's disk passphrase (the Unraid disks get it as one more key slot):")
      printf %s "$a" > "$sf"
    fi
  fi
  [ -s "$uf" ] || refuse "the passphrase of the Unraid disks is empty"
  export HS_UNRAID_PASSPHRASE_FILE=$uf
  if [ -s "$sf" ]; then export HS_DISK_PASSPHRASE_FILE=$sf; else rm -f "$sf"; fi
}

# ── the plan ──
make_pass_files
export HS_PLAIN=1 HS_LANG=en HS_CALLER=${HS_CALLER:-ui}
unset HS_GUIDED_TTY
dry_out=""; rc=0
# the dry run opens the disks too and deletes the files it reads: it gets copies, the originals are for the job
real_u=${HS_UNRAID_PASSPHRASE_FILE:-}; real_s=${HS_DISK_PASSPHRASE_FILE:-}
if [ -n "$real_u" ]; then
  du=$(mktemp "$run_dir/job-unraid-pass.XXXXXX"); cp "$real_u" "$du"; pass_files+=("$du"); export HS_UNRAID_PASSPHRASE_FILE=$du
  if [ -n "$real_s" ]; then ds=$(mktemp "$run_dir/job-pass.XXXXXX"); cp "$real_s" "$ds"; pass_files+=("$ds"); export HS_DISK_PASSPHRASE_FILE=$ds; fi
fi
dry_out=$(bash "$manage" "${adopt_args[@]}" --dry-run </dev/null 2>&1) || rc=$?
if [ -n "$real_u" ]; then
  export HS_UNRAID_PASSPHRASE_FILE=$real_u
  if [ -n "$real_s" ]; then export HS_DISK_PASSPHRASE_FILE=$real_s; else unset HS_DISK_PASSPHRASE_FILE; fi
fi
if [ "$rc" -ne 0 ]; then
  if $machine; then
    echo "status	refused"
    printf '%s\n' "$dry_out" | awk 'NF { sub(/^[ \t]+/, ""); print "reason\t" $0 }'
  else
    printf '%s\n' "$dry_out" >&2; fail "Not possible: see above. Nothing was changed."
  fi
  exit 1
fi

# the word to type: the first disk that is erased (the spare, else the first old parity disk); with none, the pool
word=$pool
if [ -n "$spare" ]; then word=$spare; elif [ -n "${want_par[0]:-}" ]; then word=${want_par[0]}; fi

extra=()   # tag<TAB>text: what this flow adds to the plan of the adopt code
if [ -n "$spare" ]; then
  extra+=("step"$'\t'"The adopted disks stay read-only while the parity is built on the spare disk $spare; only then labels are written and the folders merged into shares/")
else
  extra+=("warn"$'\t'"No spare disk: labels are written and folders move first. Until the old parity disk is erased, added and synced, the data is NOT protected")
fi
for id in "${want_par[@]}"; do
  [ -n "$id" ] || continue
  extra+=("step"$'\t'"After the parity above is complete: the old Unraid parity disk $id is erased and added as parity, then a sync")
  extra+=("danger"$'\t'"ALL DATA on $id (the old Unraid parity) will be erased.")
done
if $merge; then
  extra+=("note"$'\t'"Folders with the same name on several disks become one share, like Unraid's user shares. Reserved names (shares, sensitive, global, homes, printers) get the suffix -adopted")
else
  extra+=("note"$'\t'"Every folder becomes its own share <disk>-<folder>")
fi
if $chown; then extra+=("note"$'\t'"All files are given to the share owner (chown, slow on big disks)")
else extra+=("note"$'\t'"Files keep their owner nobody:users (99:100); Samba reads them as the share owner. Use --chown to hand them over"); fi
if $enc; then extra+=("note"$'\t'"Encrypted disks: the Unraid passphrase opens them (it becomes this server's when none exists yet; otherwise this server's passphrase is added as a key slot after a header backup in /var/lib/hs/luks-headers). A disk that only a key file opens is refused"); fi

start_job() {   # the real work as a background job; the secrets stay in their files for it
  . "$here/lib/job.sh"
  local jargs unit
  jargs=(--disks "$disks" --pool "$pool")
  [ -z "$parity" ] || jargs+=(--parity "$parity")
  [ -z "$spare" ] || jargs+=(--spare "$spare")
  $merge || jargs+=(--per-disk)
  ! $chown || jargs+=(--chown)
  $enc && jargs+=(--unlock)
  unit=$(HS_UNRAID_PASSPHRASE_FILE=${HS_UNRAID_PASSPHRASE_FILE:-} hs_job "migrate-unraid" "hs migrate unraid" -- bash "$here/migrate-unraid.sh" run "${jargs[@]}") || return 1
  echo "$unit"
}

if $machine; then
  if [ "$verb" = start ]; then
    [ "$confirm" = "$word" ] || { printf 'status\trefused\nreason\ttype the name to confirm: %s\n' "$word"; exit 1; }
    unit=$(start_job) || { printf 'status\trefused\nreason\tthe job could not be started\n'; exit 1; }
    pass_files=()   # the job owns the files now (start_job runs in a subshell: it could not say so)
    printf 'status\tstarted\nunit\t%s\n' "$unit"
    exit 0
  fi
  echo "status	ok"
  for id in "${!role_of[@]}"; do printf 'disk\t%s\t%s\t%s\t%s\n' "$id" "${role_of[$id]}" "${cand_size[$id]}" "${cand_fs[$id]}"; done | sort
  printf '%s\n' "$dry_out" | awk '
    /^Dry run:/ || /^[ \t]*$/ { next }
    /^Plan: /          { sub(/^Plan: /, ""); print "heading\t" $0; next }
    /^Plan:$/          { print "section\tPlan"; next }
    /^Note: /          { sub(/^Note: /, ""); print "note\t" $0; next }
    /^WARNING: /       { sub(/^WARNING: /, ""); print "warn\t" $0; next }
    /^ALL DATA/        { print "danger\t" $0; next }
    /^[ \t]*[0-9]+\. / { sub(/^[ \t]*[0-9]+\. /, ""); print "step\t" $0; next }
    { sub(/^[ \t]+/, ""); print "text\t" $0 }'
  printf '%s\n' "${extra[@]}"
  printf 'confirm_name\t%s\nlong\tyes\n' "$word"
  printf 'option\tshares\tmerged|per-disk\t%s\n' "$($merge && echo merged || echo per-disk)"
  printf 'option\tchown\tno|yes\t%s\n' "$($chown && echo yes || echo no)"
  exit 0
fi

# a person at a terminal
step "Plan: take over the Unraid disks into $pool"
printf '%s\n' "$dry_out" | sed '/^Dry run/d'
for l in "${extra[@]}"; do
  tag=${l%%$'\t'*}; txt=${l#*$'\t'}
  case "$tag" in danger) danger "$txt" ;; warn) warn "$txt" ;; note) note "$txt" ;; *) say "  $txt" ;; esac
done
if $dry; then note "Dry run: nothing was changed."; exit 0; fi
$yes || confirm_name "$word" "the disk that is erased first" || fail "cancelled"
if confirm "Run it as a background job (hs job log shows it)?"; then
  unit=$(start_job) || fail "The job could not be started"
  pass_files=()
  ok "Started: $unit"
else
  rargs=(--disks "$disks" --pool "$pool")
  [ -z "$parity" ] || rargs+=(--parity "$parity")
  [ -z "$spare" ] || rargs+=(--spare "$spare")
  $merge || rargs+=(--per-disk)
  ! $chown || rargs+=(--chown)
  bash "$here/migrate-unraid.sh" run "${rargs[@]}"
fi
