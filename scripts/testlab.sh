#!/usr/bin/env bash
# help: the test-lab: fetch a Hobnix ref, build the installer ISO, install it in a nested VM and smoke check it (stages 1 to 6, and the upgrade test 7); plan first, runs as a job
# help.de: das Testlabor: einen Hobnix-Stand holen, die Installer-ISO bauen, in einer verschachtelten VM installieren und prüfen (Stufen 1 bis 6, dazu der Update-Test 7); erst der Plan, läuft als Job
# args: run [--ref <branch|tag|commit>] [--stage 1|2|3|4|5|6|7|<name>|all] [--from <vX.Y.Z>] [--dry-run] [--yes] [--background|--foreground] | results [--list [N]]
# UNVERIFIED: written without Incus, KVM or nix. Not tested on hardware yet. Design: capabilities/testlab/NOTES.md, docs/adr/0023-nested-test-harness.md.
#
#   run      builds the ISO of the ref and runs scripts/dev/nested.sh of THAT checkout. Stage 1: the ISO boots and installs unattended. Stage 2: the
#            installed system boots and passes the smoke check (needs stage 1, so --stage 2 and all run both). --dry-run prints the plan and
#            changes nothing. On a terminal it asks once, then whether to run as a background job; a job, --yes and the timer ask nothing.
#            Stage 3 (rollback): a bad update goes back by itself. Stage 4 (backup): back up on the VM, restore onto a second clean VM.
#            Stage 5 (pool): a pool and the file manager on virtual disks. Stage 6 (browser): a headless browser opens every web page.
#            Stage 7 (upgrade, #435; never part of `all`, it needs no stages 1 and 2): builds the ISO of the LAST release (--from vX.Y.Z, default the
#            newest tag), installs it, sets up a share (and an app, HS_NESTED_UPGRADE_APP), runs `hs update` to --ref (a BRANCH of the Hobnix repository)
#            and checks health, shares, state.db and the app. Takes two ISO builds (an ISO of a commit already built is taken from $state/iso-cache: the last 3 are kept, HS_TESTLAB_ISO_KEEP). Not tested on hardware yet.
#            A stage is a number or its name (install smoke rollback backup pool browser); stages 3 to 6 need 1 and 2 and run them first.
#   results  the last runs, one line per run and stage; --list: machine-readable (run, stage, result, exit, ref, commit, started, ended; `-` = empty)
#
# The ref is fetched by this script and only from the Hobnix repositories (testlab_url_ok): a branch, a tag or a commit. A pull request ref, a
# fork or any other address is refused, so code of a stranger never runs here. It is not a GitHub runner: nothing starts from outside.
# Every run: /var/lib/hs/testlab/runs/<run-id>/ with stage-<n>.json per stage (result ok|failed|skipped|error) and run.log; the last HS_TESTLAB_KEEP
# (14) are kept. The VM is deleted at the end (also after a failure or a cancel). A failure or error sends a push message and the event testlab.failed.
# Exit codes: 0 passed, 1 a stage failed, 2 usage or refused, 3 cannot run here (skipped, no push message), 4 infrastructure error (fetch, build, Incus).
# Test knobs: HS_TESTLAB_DIR, HS_TESTLAB_REPO (still checked against the allowlist), HS_TESTLAB_GIT, HS_TESTLAB_BUILD_TIMEOUT, HS_TESTLAB_RUN_TIMEOUT,
# HS_TESTLAB_KEEP, HS_TESTLAB_ISO_KEEP (ISOs kept in $state/iso-cache, default 3), HS_TESTLAB_STORAGE (Incus storage pool for the virtual disks, default "default"), HS_NESTED_INCUS, HS_NOTIFY (stand-in for notify.sh), HS_GUIDED_TTY=1 (there is a terminal; answers on stdin).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib/ui.sh"
. "$here/lib/capability.sh"
. "$here/lib/event.sh"
. "$here/lib/job.sh"

state=${HS_TESTLAB_DIR:-${HS_STATE_DIR:-/var/lib/hs}/testlab}
git=${HS_TESTLAB_GIT:-git}
incus=${HS_NESTED_INCUS:-incus}
repo_url=${HS_TESTLAB_REPO:-https://github.com/hobnix/core.git}

# The stages. Adding one (#435 does the upgrade test): a case line in stage_name, its number in STAGES_ALL, a function stage_<name> in the run part.
stage_name() { case "$1" in 1) echo install ;; 2) echo smoke ;; 3) echo rollback ;; 4) echo backup ;; 5) echo pool ;; 6) echo browser ;; 7) echo upgrade ;; *) return 1 ;; esac; }
STAGES_ALL="1 2 3 4 5 6"
stage_number() {   # a number, or a name, to the number; fails for anything else
  local n
  for n in $STAGES_ALL 7; do if [ "$1" = "$n" ] || [ "$1" = "$(stage_name "$n")" ]; then echo "$n"; return 0; fi; done
  return 1
}

usage() {
  say "usage: hs testlab run [--ref <branch|tag|commit>] [--stage 1|2|3|4|5|6|7|<name>|all] [--from <vX.Y.Z>] [--dry-run] [--yes] [--background|--foreground]"
  say "       hs testlab results [--list [N]]"
  exit 2
}
interactive() { [ -t 0 ] && [ -t 1 ] && [ -z "${HS_CALLER:-}" ] || [ -n "${HS_GUIDED_TTY:-}" ]; }

# The allowlist: only https addresses of repositories of the organisation hobnix on GitHub (no credentials, no other host, no path tricks).
testlab_url_ok() {
  case "$1" in https://github.com/hobnix/*) ;; *) return 1 ;; esac
  [[ "${1#https://github.com/hobnix/}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$ ]]
}
# A ref is a branch, a tag or a commit name. Never a pull request, a refspec or something git could read as an option.
testlab_ref_ok() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]{0,99}$ ]] || return 1
  case "$1" in refs/*|pull/*|*..*|*//*|*/|*.lock) return 1 ;; esac
  return 0
}

cmd=${1:-}
[ $# -eq 0 ] || shift
case "$cmd" in run|results) ;; *) usage ;; esac

capability_on testlab || fail "The test-lab is off. Switch it on with the capability testlab (hs config set capabilities, then hs rebuild)."

# ---------------------------------------------------------------- results
if [ "$cmd" = results ]; then
  list=false; n=10
  while [ $# -gt 0 ]; do
    case "$1" in
      --list) list=true; shift; if [[ "${1:-}" =~ ^[0-9]{1,3}$ ]]; then n=$1; shift; fi ;;
      *) usage ;;
    esac
  done
  rows=$(python3 -I - "$state/runs" "$n" <<'PY'
import json, os, sys
runs, n = sys.argv[1], int(sys.argv[2])
try:
    names = sorted(d for d in os.listdir(runs) if os.path.isdir(os.path.join(runs, d)))[-n:]
except OSError:
    names = []
def clean(v):
    s = str(v if v not in (None, "") else "-")
    return s.replace("\t", " ").replace("\n", " ")
for name in names:
    for stage in range(1, 21):
        try:
            with open(os.path.join(runs, name, "stage-%d.json" % stage)) as f:
                d = json.load(f)
        except (OSError, ValueError):
            continue
        print("\t".join(clean(x) for x in (name, stage, d.get("result"), d.get("exit"), d.get("ref"), d.get("commit"), d.get("started"), d.get("ended"))))
PY
)
  if $list; then [ -z "$rows" ] || printf '%s\n' "$rows"; exit 0; fi
  if [ -z "$rows" ]; then note "No test-lab run yet. Start one with: hs testlab run"; exit 0; fi
  { thead 'Run' 'Stage' 'Result' 'Exit' 'Ref' 'Commit' 'Started' 'Ended'; printf '%s\n' "$rows"; } | table
  exit 0
fi

# ---------------------------------------------------------------- run
ref=develop; stage=all; from=; dry=false; yes=false; bg=ask
while [ $# -gt 0 ]; do
  case "$1" in
    --ref) [ $# -ge 2 ] || usage; ref=$2; shift 2 ;;
    --stage) [ $# -ge 2 ] || usage; stage=$2; shift 2 ;;
    --from) [ $# -ge 2 ] || usage; from=$2; shift 2 ;;
    --dry-run) dry=true; shift ;;
    --yes) yes=true; shift ;;
    --background) bg=yes; shift ;;
    --foreground) bg=no; shift ;;
    *) usage ;;
  esac
done
# the selected stages: a stage above 2 needs the installed VM of 1 and 2
if [ "$stage" = all ]; then sel=$STAGES_ALL; else
  sn=$(stage_number "$stage") || usage
  if [ "$sn" = 7 ]; then sel=7; elif [ "$sn" -le 2 ]; then sel=$(seq -s ' ' 1 "$sn"); else sel="1 2 $sn"; fi
fi
[ -z "$from" ] || [ "$sel" = 7 ] || usage
[ -z "$from" ] || [[ "$from" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail_fix "The release '$from' is not accepted." "use a release tag like v0.1.0"
sel_has() { case " $sel " in *" $1 "*) return 0 ;; esac; return 1; }
testlab_ref_ok "$ref" || fail_fix "The ref '$ref' is not accepted." "use a branch, a tag or a commit of the Hobnix repository (never refs/pull/...)"
testlab_url_ok "$repo_url" || fail_fix "The repository address is not on the allowlist." "only https://github.com/hobnix/<repository> is fetched"
nested_stage=all; [ "$sel" != 1 ] || nested_stage=iso
extras=""; for n in $sel; do [ "$n" -le 2 ] || extras="$extras $n"; done
keep=${HS_TESTLAB_KEEP:-14}; [[ "$keep" =~ ^[0-9]{1,4}$ ]] || keep=14

step "$(t 'Plan: test-lab run of %s' "$ref")"
kv "Repository" "$repo_url"
kv "Ref" "$ref"
kv "Stages" "$(for n in $sel; do printf '%s ' "$n ($(stage_name "$n"))"; done)"
if [ "$sel" = 7 ]; then
  kv "From release" "${from:-the newest vX.Y.Z tag}"
  note "1. fetch the candidate $ref (it holds the harness) and the release tag"
  note "2. check that this machine can run nested VMs (KVM, Incus)"
  note "3. build the installer ISO of the RELEASE (nix, long) and install it in a throwaway VM"
  note "4. set up a share and an app, run hs update to $ref, check health, shares, state.db and the app"
  note "5. delete the VM; write stage-7.json to $state/runs/<run-id>/"
  note "A failure sends a push message. Not tested on hardware yet."
  if $dry; then note "Dry run: nothing was fetched, built or started."; exit 0; fi
fi
note "1. fetch the ref from the Hobnix repository (shallow, into $state/src)"
note "2. check that this machine can run nested VMs (KVM, Incus)"
note "3. build the installer ISO (nix, can take a long time and needs tens of GiB; skipped when the ISO of this commit is in the cache)"
note "4. $([ "$sel" = 1 ] && echo 'boot the ISO in a throwaway VM and install unattended' || echo 'install in a throwaway VM, boot the result and run the smoke check')"
sel_has 3 && note "   stage 3: break an update on purpose and check that it goes back by itself"
sel_has 4 && note "   stage 4: back up onto a virtual disk, install a second clean VM and restore there"
sel_has 5 && note "   stage 5: add virtual disks, make a pool, copy a file with the file manager"
sel_has 6 && note "   stage 6: open every page of the web interface in a headless browser (needs playwright on this server)"
note "5. delete the VMs and the virtual disks; write the result per stage to $state/runs/<run-id>/"
note "A failure sends a push message. Not tested on hardware yet."
if $dry; then note "Dry run: nothing was fetched, built or started."; exit 0; fi

if ! $yes && [ -z "${HS_CALLER:-}" ]; then
  interactive || fail "Nothing is started without --yes when there is no terminal."
  warn "This builds an installer image and boots virtual machines: it takes a long time and puts load on this server."
  confirm "Run the test-lab now?" || fail "cancelled"
fi

if [ "${HS_CALLER:-}" != job ] && [ "$bg" != no ]; then
  if [ "$bg" = ask ] && interactive && confirm "Run it as a background job (you can close the terminal)?"; then bg=yes; fi
  if [ "$bg" = yes ]; then
    unit=$(hs_job testlab "hs testlab run $ref" -- bash "$here/testlab.sh" run --ref "$ref" --stage "$stage" ${from:+--from "$from"} --yes --foreground) || exit 1
    ok "$(t 'Started as job %s.' "$unit")"
    next_step "hs job follow $unit"
    exit 0
  fi
fi

# ---- the run itself (foreground, or inside the job)
mkdir -p "$state/runs" "$state/src"
exec 9>"$state/lock"
flock -n 9 || fail "Another test-lab run is going on (the lock $state/lock is held)."
runid=$(date +%Y%m%d-%H%M%S)
rundir=$state/runs/$runid
mkdir -p "$rundir"
exec > >(tee -a "$rundir/run.log") 2>&1
vm=hs-testlab-$runid
src=$state/src
started=$(date -u +%Y-%m-%dT%H:%M:%SZ)
commit=-
nrc=0
payload() { printf '{"ref":"%s","stage":"%s"}' "$ref" "$1"; }
cleanup() {
  "$incus" delete -f "$vm" >/dev/null 2>&1 || true   # nested.sh deletes it too; this is for an interrupted run
  [ -z "${vm2:-}" ] || "$incus" delete -f "$vm2" >/dev/null 2>&1 || true
  local v; for v in ${vols[@]+"${vols[@]}"}; do "$incus" storage volume delete "${spool:-default}" "$v" >/dev/null 2>&1 || true; done
  rm -f "$rundir/.backup-pass" 2>/dev/null || true
  rm -f "$src/result-iso" 2>/dev/null || true       # the ISO is a store path: let the next garbage collection free it
  # keep the last runs only
  local old; old=$(ls -1 "$state/runs" 2>/dev/null | sort | head -n "-$keep" || true)
  [ -z "$old" ] || while IFS= read -r d; do rm -rf "${state:?}/runs/${d:?}"; done <<<"$old"
}
trap cleanup EXIT

write_stage() {   # write_stage <1|2> <ok|failed|skipped|error> <exit>
  python3 -I - "$rundir/stage-$1.json" "$runid" "$1" "$2" "$3" "$ref" "$commit" "$started" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" <<'PY'
import json, sys
f, run, stage, result, rc, ref, commit, started, ended = sys.argv[1:10]
with open(f, "w") as fh:
    json.dump({"run": run, "stage": int(stage), "result": result, "exit": int(rc), "ref": ref, "commit": commit,
               "started": started, "ended": ended}, fh, indent=1)
PY
}
write_all() { local n; for n in $sel; do write_stage "$n" "$1" "$2"; done; }   # every selected stage gets the same result
fail_run() {   # fail_run <exit> <stage> <text>: an infrastructure problem before a stage ran
  local rc=$1 st=$2 txt=$3 res=error
  [ "$rc" -ne 3 ] || res=skipped
  write_all "$res" "$rc"
  warn "$txt"
  finish "$rc" "$st" "$txt"
}
finish() {   # finish <exit> <stage> <text>
  local rc=$1 st=$2 txt=$3
  case "$rc" in
    0) event_emit testlab.ok "$runid" "test-lab passed on $ref" --payload "$(payload all)" ;;
    3) event_emit testlab.skipped "$runid" "test-lab could not run here: $txt" --payload "$(payload "$st")" ;;
    *) event_emit testlab.failed "$runid" "test-lab failed at stage $st on $ref" --payload "$(payload "$st")"
       bash "${HS_NOTIFY:-$here/notify.sh}" --category problem "Test-lab failed" "Stage $st of the test-lab run on $ref failed: $txt. Log: $rundir/run.log" >/dev/null 2>&1 || true ;;
  esac
  exit "$rc"
}
stopped() {   # a cancelled job stops cleanly at a step border
  if hs_job_cancelled; then warn "The job was cancelled."; write_all skipped 130; exit 130; fi
}

event_emit testlab.started "$runid" "test-lab started on $ref" --payload "$(payload "$stage")"

hs_job_step 1 4 "Fetching $ref"; hs_job_progress 0 4 steps
step "$(t 'Fetching %s' "$ref")"
command -v "$git" >/dev/null 2>&1 || fail_run 4 1 "git is not installed"
# the global and system git configuration (insteadOf rewrites, credential helpers) is not read; only https is allowed
gitc() { GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_TERMINAL_PROMPT=0 "$git" -c protocol.allow=never -c protocol.https.allow=always -c core.hooksPath=/dev/null "$@"; }
if [ ! -d "$src/.git" ]; then gitc -C "$src" init -q || fail_run 4 1 "git init failed"; fi
gitc -C "$src" remote remove origin >/dev/null 2>&1 || true
gitc -C "$src" remote add origin "$repo_url" || fail_run 4 1 "git remote failed"
gitc -C "$src" fetch -q --depth 1 origin "$ref" || fail_run 4 1 "could not fetch $ref from $repo_url"
gitc -C "$src" checkout -q -f --detach FETCH_HEAD || fail_run 4 1 "could not check out $ref"
gitc -C "$src" clean -q -fdx -e .work -e result-iso >/dev/null 2>&1 || true
commit=$(gitc -C "$src" rev-parse HEAD 2>/dev/null || echo -)
ok "$(t 'Checked out %s' "$commit")"
stopped

hs_job_step 2 4 "Checking that nested VMs can run"; hs_job_progress 1 4 steps
step "$(t 'Run %s: can this machine run nested VMs?' "$runid")"
[ -f "$src/scripts/dev/nested.sh" ] && [ -f "$src/scripts/dev/build-iso.sh" ] || fail_run 4 1 "this ref has no scripts/dev/nested.sh or build-iso.sh"
if ! bash "$src/scripts/dev/nested.sh" preflight; then fail_run 3 1 "this machine cannot run nested VMs (no KVM, nested virtualization or incus)"; fi
stopped

json_ok() {   # json_ok <file>: ok|failed|error from a harness result file
  python3 -I -c 'import json,sys; print("ok" if json.load(open(sys.argv[1])).get("ok") else "failed")' "$1" 2>/dev/null || echo error
}
xrun() {   # xrun <stage> <vm> "<name=device ...>": a console scenario of the harness on an installed VM; echoes ok|failed|skipped|error
  local st=$1 on=$2 disks=$3 rc=0 d
  (cd "$src" && HS_NESTED_PASSWORD_FILE=$4 HS_NESTED_DISKS=$disks HS_NESTED_BACKUP_PASS_FILE=${5:-} timeout "${HS_TESTLAB_RUN_TIMEOUT:-2700}" \
     bash scripts/dev/nested.sh run --stage "$st" --name "$on" --keep) || rc=$?
  d=$(cd "$src/.work/nested/latest" 2>/dev/null && pwd -P || true)
  [ -z "$d" ] || { mkdir -p "$rundir/harness-$st"; cp "$d"/*.log "$d"/result-*.json "$rundir/harness-$st/" 2>/dev/null || true; }
  if [ -n "$d" ] && [ -f "$d/result-$st.json" ]; then json_ok "$d/result-$st.json"; return; fi
  case "$rc" in 0) echo ok ;; 3) echo skipped ;; *) echo error ;; esac
}

# ---- the ISO cache: $state/iso-cache/<full commit sha>/ holds the ISO built from exactly that commit (about 1.5 GB), the last HS_TESTLAB_ISO_KEEP (3)
# are kept. The key is the full sha of the checkout; a folder counts only with its .complete file that names the same sha (an interrupted copy is never served).
iso_cache=$state/iso-cache
iso_keep=${HS_TESTLAB_ISO_KEEP:-3}; [[ "$iso_keep" =~ ^[0-9]{1,3}$ ]] && [ "$iso_keep" -ge 1 ] || iso_keep=3
iso_find() {   # iso_find <folder>: the one .iso file in it
  local f; for f in "$1"/*.iso; do [ -f "$f" ] && { echo "$f"; return 0; }; done; return 1
}
iso_prune() {   # the newest $iso_keep complete folders stay; everything else (older, or a leftover of an interrupted copy) goes
  local d n=0 name
  [ -d "$iso_cache" ] || return 0
  for d in "$iso_cache"/.tmp-*; do [ ! -e "$d" ] || rm -rf "${d:?}"; done
  while IFS= read -r name; do
    [[ "$name" =~ ^[0-9a-f]{40}$ ]] || continue
    n=$((n + 1))
    [ "$n" -le "$iso_keep" ] || rm -rf "${iso_cache:?}/${name:?}"
  done < <(ls -1t "$iso_cache" 2>/dev/null || true)
}
iso_get() {   # iso_get <checkout> <sha> <what>: sets $isofile (the ISO of that commit), from the cache or built; fails when the build fails
  local dir=$1 sha=$2 what=$3 hit built tmp
  isofile=
  if [[ "$sha" =~ ^[0-9a-f]{40}$ ]]; then
    hit=$iso_cache/$sha
    if [ -f "$hit/.complete" ] && [ "$(cat "$hit/.complete" 2>/dev/null)" = "$sha" ] && isofile=$(iso_find "$hit"); then
      touch "$hit"; iso_prune
      ok "$(t 'ISO of %s from the cache (%s)' "$sha" "$what")"
      return 0
    fi
    isofile=
  fi
  (cd "$dir" && SPIN_STREAM=1 timeout "${HS_TESTLAB_BUILD_TIMEOUT:-5400}" bash scripts/dev/build-iso.sh) || return 1
  built=$(iso_find "$dir/result-iso/iso") || return 2
  if [[ "$sha" =~ ^[0-9a-f]{40}$ ]]; then   # no sha (git failed): built, but not cached
    tmp=$iso_cache/.tmp-$sha
    rm -rf "${tmp:?}"; mkdir -p "$tmp"
    if cp -L "$built" "$tmp/" && printf '%s' "$sha" > "$tmp/.complete" && rm -rf "${iso_cache:?}/${sha:?}" && mv "$tmp" "$iso_cache/$sha"; then
      isofile=$(iso_find "$iso_cache/$sha") || isofile=$built
      iso_prune
    else rm -rf "${tmp:?}"; warn "$(t 'The ISO could not be put in the cache (disk full?); it is used from the build.')"; isofile=$built; fi
  else isofile=$built; fi
  ok "$(t 'ISO of %s built (%s)' "$sha" "$what")"
}

if [ "$sel" = 7 ]; then
  # ---- stage 7: the harness (and the scenario) is the candidate's (src); the ISO is the last release's (src-old). Own path: needs no stage 1 and 2.
  hs_job_step 3 4 "Building the ISO of the last release"; hs_job_progress 2 4 steps
  if [ -z "$from" ]; then
    from=$(gitc ls-remote --tags --refs "$repo_url" 'v*' 2>/dev/null | sed 's|.*refs/tags/||' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1 || true)
    if [ -z "$from" ]; then warn "no release tag (vX.Y.Z) exists yet: nothing to upgrade from"; write_stage 7 skipped 3; finish 3 7 "no release to upgrade from"; fi
  fi
  note "$(t 'Upgrading from %s to %s' "$from" "$ref")"
  old=$state/src-old; mkdir -p "$old"
  up_fail() { write_stage 7 error 4; finish 4 7 "$1"; }
  [ -d "$old/.git" ] || gitc -C "$old" init -q || up_fail "git init failed"
  gitc -C "$old" remote remove origin >/dev/null 2>&1 || true
  gitc -C "$old" remote add origin "$repo_url" || up_fail "git remote failed"
  gitc -C "$old" fetch -q --depth 1 origin "refs/tags/$from" || up_fail "could not fetch the release $from"
  gitc -C "$old" checkout -q -f --detach FETCH_HEAD || up_fail "could not check out $from"
  gitc -C "$old" clean -q -fdx -e result-iso >/dev/null 2>&1 || true
  oldsha=$(gitc -C "$old" rev-parse HEAD 2>/dev/null || echo -)
  iso_get "$old" "$oldsha" "release $from" || up_fail "the ISO build of $from failed (see run.log)"
  oldiso=$isofile
  [ -n "$oldiso" ] || up_fail "the ISO of $from is missing after the build"
  stopped
  hs_job_step 4 4 "Install $from, update to $ref"; hs_job_progress 3 4 steps
  step "$(t 'Installing %s in VM %s' "$from" "$vm")"
  nrc=0
  (cd "$src" && timeout "${HS_TESTLAB_RUN_TIMEOUT:-2700}" bash scripts/dev/nested.sh run --stage iso --iso "$oldiso" --name "$vm" --keep) || nrc=$?
  ndir=$(cd "$src/.work/nested/latest" 2>/dev/null && pwd -P || true)
  ur=error
  if [ "$nrc" = 0 ]; then
    export HS_NESTED_CANDIDATE=$ref
    ur=$(xrun upgrade "$vm" "" "$ndir/password")
  elif [ "$nrc" = 3 ]; then ur=skipped
  elif [ -n "$ndir" ] && [ -f "$ndir/result-iso.json" ] && [ "$(json_ok "$ndir/result-iso.json")" = failed ]; then ur=failed; fi
  [ -z "$ndir" ] || { mkdir -p "$rundir/harness"; cp "$ndir"/*.log "$ndir"/result-*.json "$rundir/harness/" 2>/dev/null || true; }
  write_stage 7 "$ur" "$nrc"
  hs_job_progress 4 4 steps
  step "$(t 'Result')"
  status_line "Upgrade $from to $ref" "$ur" "$([ "$ur" = ok ] && echo ok || echo bad)"
  note "$(t 'Commit %s, run folder %s' "$commit" "$rundir")"
  case "$ur" in ok) finish 0 7 "" ;; failed) finish 1 7 "the upgrade from $from failed" ;; skipped) finish 3 7 "the harness cannot run here" ;; *) finish 4 7 "upgrade $ur" ;; esac
fi

if sel_has 4 || sel_has 5; then export HS_NESTED_ROLE=homeserver; fi   # restic, mkfs and SnapRAID come with the homeserver role (after `hs rebuild`)
# ---- the golden VM: $state/golden/<sha>-<role>/ (password, vm) and the stopped Incus VM hs-golden-<sha12>-<role> are the installed system as it is after
# stages 1 and 2 passed. A later run of stage 3 or higher on the same commit copies it instead of building the ISO and installing again (about
# 30 minutes less). HS_TESTLAB_GOLDEN=0 turns it off, HS_TESTLAB_GOLDEN_KEEP (2) is the number kept.
golden_dir=$state/golden
gold_on=true; [ "${HS_TESTLAB_GOLDEN:-1}" != 0 ] || gold_on=false
[[ "$commit" =~ ^[0-9a-f]{40}$ ]] || gold_on=false
gold_key=$commit-${HS_NESTED_ROLE:-default}
gold_vm=hs-golden-${commit:0:12}-${HS_NESTED_ROLE:-default}
gold_keep=${HS_TESTLAB_GOLDEN_KEEP:-2}; [[ "$gold_keep" =~ ^[0-9]{1,2}$ ]] && [ "$gold_keep" -ge 1 ] || gold_keep=2
golden_prune() {   # the newest $gold_keep stay (by the time of last use); the others lose their VM and folder
  local d n=0 name
  [ -d "$golden_dir" ] || return 0
  while IFS= read -r name; do
    [ -d "$golden_dir/$name" ] || continue
    n=$((n + 1))
    [ "$n" -le "$gold_keep" ] && continue
    "$incus" delete -f "$(cat "$golden_dir/$name/vm" 2>/dev/null || echo hs-golden-none)" >/dev/null 2>&1 || true
    rm -rf "${golden_dir:?}/${name:?}"
  done < <(ls -1t "$golden_dir" 2>/dev/null || true)
}
golden_make() {   # the VM is stopped (the console log then starts at the login, as after any boot) and copied; nested.sh starts it again
  "$incus" stop "$vm" --timeout 120 >/dev/null 2>&1 || "$incus" stop "$vm" --force >/dev/null 2>&1 || { warn "$(t 'The golden copy was not made (the VM did not stop).')"; return 0; }
  "$incus" delete -f "$gold_vm" >/dev/null 2>&1 || true
  if "$incus" copy "$vm" "$gold_vm" >/dev/null 2>&1; then
    mkdir -p "$golden_dir/$gold_key"; chmod 700 "$golden_dir" "$golden_dir/$gold_key"
    ( umask 077; cp "$ndir/password" "$golden_dir/$gold_key/password" && printf '%s' "$gold_vm" > "$golden_dir/$gold_key/vm" )       && { ok "$(t 'Golden copy of %s kept (a later run of a stage from 3 on starts from it)' "$commit")"; golden_prune; }       || { warn "$(t 'The golden copy was not made (the password could not be kept).')"; "$incus" delete -f "$gold_vm" >/dev/null 2>&1 || true; rm -rf "${golden_dir:?}/${gold_key:?}"; }
  else warn "$(t 'The golden copy was not made (incus copy failed).')"; fi
}
golden_used=false
if $gold_on && [ -n "$extras" ] && [ -f "$golden_dir/$gold_key/password" ] && "$incus" info "$gold_vm" >/dev/null 2>&1; then
  step "$(t 'The installed system of %s comes from the golden copy' "$commit")"
  if "$incus" copy "$gold_vm" "$vm" >/dev/null 2>&1; then
    golden_used=true; touch "$golden_dir/$gold_key"
    ok "$(t 'No ISO build and no install: stages 1 and 2 passed on this commit before')"
  else warn "$(t 'The golden copy could not be copied; installing from the ISO.')"; fi
fi

if $golden_used; then
  nrc=0; ndir=$golden_dir/$gold_key; pwfile=$ndir/password
else
hs_job_step 3 4 "Building the installer ISO"; hs_job_progress 2 4 steps
step "$(t 'Building the installer ISO (this takes a long time)')"
iso_get "$src" "$commit" "$ref" || fail_run 4 2 "the ISO build failed (see run.log)"
stopped

hs_job_step 4 4 "Running the nested harness (stages $(echo $sel | tr ' ' ','))"; hs_job_progress 3 4 steps
step "$(t 'Running the nested harness, VM %s' "$vm")"
nrc=0
keepvm=(); [ -z "$extras" ] || keepvm=(--keep)   # stages 3 to 6 work on the installed VM: it stays until the end (cleanup deletes it)
(cd "$src" && timeout "${HS_TESTLAB_RUN_TIMEOUT:-2700}" bash scripts/dev/nested.sh run --stage "$nested_stage" --iso "$isofile" --name "$vm" ${keepvm[@]+"${keepvm[@]}"}) || nrc=$?
ndir=$(cd "$src/.work/nested/latest" 2>/dev/null && pwd -P || true)
[ -z "$ndir" ] || cp -r "$ndir" "$rundir/harness" 2>/dev/null || true
[ -z "$ndir" ] || rm -f "$rundir/harness/key" "$rundir/harness/password"   # a throwaway key and password of the VM: not kept
pwfile=$ndir/password   # the password of the installed VM: the later stages log in with it (the copy in the run folder is deleted)
fi

stage_res() {   # stage_res <iso|smoke>: ok|failed|skipped|error from the harness result file, else from its exit code
  local f=$ndir/result-$1.json
  if [ -n "$ndir" ] && [ -f "$f" ]; then json_ok "$f"; return; fi
  case "$nrc" in 0) echo ok ;; 3) echo skipped ;; *) echo error ;; esac
}
if $golden_used; then r1=ok; else r1=$(stage_res iso); fi
write_stage 1 "$r1" "$nrc"
if sel_has 2; then
  if $golden_used; then r2=ok
  elif [ "$r1" = ok ]; then r2=$(stage_res smoke); else r2=skipped; fi   # no installed system without stage 1
  write_stage 2 "$r2" "$nrc"
else r2=-; fi
hs_job_progress 4 4 steps
if ! $golden_used && $gold_on && [ -n "$extras" ] && [ "$r1" = ok ] && [ "${r2:--}" = ok ]; then golden_make; fi

# ---- stages 3 to 6 on the installed VM. res[n] = ok|failed|skipped|error
declare -A res
spool=${HS_TESTLAB_STORAGE:-default}
vols=()
vm2=
vdisk_add() {   # vdisk_add <vm> <device> <size>: a virtual disk (an Incus block volume) as a disk device of the VM
  "$incus" storage volume create "$spool" "$1-$2" --type=block "size=$3" >/dev/null || return 1
  vols+=("$1-$2")
  "$incus" config device add "$1" "$2" disk "pool=$spool" "source=$1-$2" >/dev/null
}
worst() {   # worst <result>...: the first that is not ok
  local r; for r in "$@"; do [ "$r" = ok ] || { echo "$r"; return; }; done; echo ok
}

stage_rollback() {
  local d=""
  if [ "${HS_NESTED_ROLE:-}" = homeserver ]; then   # the full configuration needs the pool fast (see stage_backup)
    fast_disks "$vm" || { res[3]=error; return; }
    d="fast1=f1 fast2=f2"
  fi
  res[3]=$(xrun rollback "$vm" "$d" "$pwfile")
}
fast_on=
fast_disks() {   # fast_disks <vm>: two small virtual disks for the pool `fast` (the full configuration of the storage part always imports it)
  case " $fast_on " in *" $1 "*) return 0 ;; esac
  vdisk_add "$1" f1 2GiB && vdisk_add "$1" f2 2GiB && fast_on="$fast_on $1"
}
stage_backup() {
  local a b
  vdisk_add "$vm" bk 2GiB && fast_disks "$vm" || { res[4]=error; return; }
  a=$(xrun backup "$vm" "backup=bk fast1=f1 fast2=f2" "$pwfile")
  [ "$a" = ok ] || { res[4]=$a; return; }
  ( umask 077; "$incus" file pull "$vm/var/lib/hs/restic-password" "$rundir/.backup-pass" ) || { res[4]=error; return; }
  vm2=$vm-b
  step "$(t 'Stage 4: a second, clean VM %s' "$vm2")"
  (cd "$src" && timeout "${HS_TESTLAB_RUN_TIMEOUT:-2700}" bash scripts/dev/nested.sh run --stage all --name "$vm2" --keep) || { res[4]=error; return; }
  local d2; d2=$(cd "$src/.work/nested/latest" 2>/dev/null && pwd -P)
  "$incus" config device remove "$vm" bk >/dev/null || { res[4]=error; return; }
  "$incus" config device add "$vm2" bk disk "pool=$spool" "source=$vm-bk" >/dev/null || { res[4]=error; return; }
  fast_disks "$vm2" || { res[4]=error; return; }
  b=$(xrun restore "$vm2" "backup=bk fast1=f1 fast2=f2" "$d2/password" "$rundir/.backup-pass")
  rm -f "$rundir/.backup-pass"
  res[4]=$(worst "$a" "$b")
}
stage_pool() {
  vdisk_add "$vm" p1 14GiB && vdisk_add "$vm" p2 14GiB && fast_disks "$vm" || { res[5]=error; return; }
  res[5]=$(xrun pool "$vm" "pool1=p1 pool2=p2 fast1=f1 fast2=f2" "$pwfile")
}
stage_browser() {
  local ip rc=0 ar
  # the VM has no incus agent and sits on a LAN bridge, so `incus list` shows no address: ask the VM on its serial console (scenario address)
  ar=$(xrun address "$vm" "" "$pwfile")
  ip=$(python3 -I -c 'import json,re,sys
for s in json.load(open(sys.argv[1])).get("steps", []):
    v = s.get("value", "")
    if re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+", v): print(v); break' "$rundir/harness-address/result-address.json" 2>/dev/null || true)
  if [ -z "$ip" ]; then warn "Could not read an IPv4 address from the VM's console (scenario address: $ar)."; res[6]=error; return; fi
  note "$(t 'The VM answers on %s' "$ip")"
  [ -f "$src/scripts/dev/testlab-browser.py" ] || { warn "this ref has no scripts/dev/testlab-browser.py"; res[6]=error; return; }
  mkdir -p "$rundir/harness-browser"
  HS_NESTED_PASSWORD=$(cat "$pwfile") python3 -I "$src/scripts/dev/testlab-browser.py" run --url "http://$ip:${HS_TESTLAB_WEB_PORT:-8480}" \
    --nav "$src/web/src/nav.js" --out "$rundir/harness-browser/result-browser.json" \n    ${HS_TESTLAB_AXE_JS:+--axe-js "$HS_TESTLAB_AXE_JS" --axe-baseline "$src/scripts/dev/axe-baseline.tsv"} || rc=$?
  # #485: the live scenarios (an open page follows a change made over ssh); only with HS_TESTLAB_LIVE_SSH=<user@host> (a key the VM accepts), limit 0 must fail
  if [ "$rc" = 0 ] && [ -n "${HS_TESTLAB_LIVE_SSH:-}" ]; then
    HS_NESTED_PASSWORD=$(cat "$pwfile") python3 -I "$src/scripts/dev/testlab-browser.py" live --url "http://$ip:${HS_TESTLAB_WEB_PORT:-8480}"       --scenarios "$src/scripts/dev/testlab-live.tsv" --limits "$src/scripts/lib/live-limits.tsv" --ssh "$HS_TESTLAB_LIVE_SSH"       ${HS_TESTLAB_LIVE_LIMIT:+--limit "$HS_TESTLAB_LIVE_LIMIT"} --out "$rundir/harness-browser/result-live.json" || rc=$?
  fi
  case "$rc" in 0) res[6]=ok ;; 1) res[6]=failed ;; 3) res[6]=skipped ;; *) res[6]=error ;; esac
}

for n in $extras; do
  if [ "$r1" != ok ] || [ "$r2" != ok ]; then res[$n]=skipped; else
    stopped
    step "$(t 'Stage %s: %s' "$n" "$(stage_name "$n")")"
    "stage_$(stage_name "$n")"
  fi
  write_stage "$n" "${res[$n]:-error}" 0
done

step "$(t 'Result')"
status_line "Stage 1" "$r1" "$([ "$r1" = ok ] && echo ok || echo bad)"
[ "$r2" = - ] || status_line "Stage 2" "$r2" "$([ "$r2" = ok ] && echo ok || echo bad)"
for n in $extras; do status_line "Stage $n ($(stage_name "$n"))" "${res[$n]}" "$([ "${res[$n]}" = ok ] && echo ok || echo bad)"; done
note "$(t 'Commit %s, run folder %s' "$commit" "$rundir")"

# the first stage that is not ok decides the exit code
first=0; firstres=ok
for n in 1 $([ "$r2" = - ] || echo 2) $extras; do
  case "$n" in 1) r=$r1 ;; 2) r=$r2 ;; *) r=${res[$n]} ;; esac
  if [ "$r" != ok ]; then first=$n; firstres=$r; break; fi
done
[ "$first" != 0 ] || finish 0 all ""
# a skipped stage 1 means this machine cannot run nested VMs; a skipped later stage (no browser here) is not a failure of the system
if [ "$firstres" = skipped ] && [ "$first" = 1 ]; then finish 3 1 "the harness cannot run here"; fi
if [ "$firstres" = skipped ]; then finish 3 "$first" "stage $first was skipped"; fi
finish "$([ "$firstres" = failed ] && echo 1 || echo 4)" "$first" "stage $first ($(stage_name "$first")) $firstres"
