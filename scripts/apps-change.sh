#!/usr/bin/env bash
# help: install an app (or an extension) in one guided job: read the plan from the signed release, meet its needs, ask, run, check; what would happen (plan), then do it (start)
# help.de: eine App (oder Erweiterung) in einem geführten Auftrag installieren: Plan aus dem signierten Release lesen, Voraussetzungen erfüllen, fragen, ausführen, prüfen; was passieren würde (plan), dann ausführen (start)
# args: plan|start install <package> [--repo R] [--tag T] [--name <container>] [--set KEY=value]... [--ask] [--from <step>] [--by <user>] [--role <role>] [--confirm <name>]
# System command (hs sys apps plan|start install): ONE Install for every kind of package (docs/PLAN-app-lifecycle.md Q2, step 8a, #465). It never asks
# and prints plain key<TAB>value lines like pkg-change.sh. The work is the job's (`run`, never called by a person).
#
# plan   Reads the manifest of the newest VERIFIED release from the local clone (hs sys pkg show: nothing is installed, nothing is written) and says
#        what installing would do. Lines: status ok|refused, reason, heading, package/kind/repo/version/tag/commit/title/description,
#        creates <text>, need <name> <present|missing|recipe> <text> <long yes|no>, ask (as pkg show), jobstep <name> <text> (the steps of the job),
#        step|note|warn|danger <text>, confirm_name <name> (a package of an ADDED repository: the typed name), command, long yes. Exit 0 ok, 1 refused.
#        The tag and version in the plan are what the job installs (decision D4): `start --tag <tag>` refuses when the newest verified release is another.
# start  The same checks, then ONE orchestration job (ADR 0018): status started, unit, job (the record id). The questions the recipe asks while it runs
#        reach the person as `waiting` in the record (hs sys jobs answer); --set KEY=value answers one up front (it reaches the recipe as RECIPE_<KEY>,
#        so it is never asked again); ONE secret answer is a line on standard input (a root-only file, `answer KEY`). --ask asks every preference again
#        (RECIPE_ASK=1), also on an app that exists. A secret or value is never printed. --by/--role: who starts it (the web server sets them).
#
# The step contract of the job (the record's `step` is {n, of, text}; text is one of these words, never translated, `of` counts the recipe phases):
#   read    fetch the release the plan showed (`hs pkg install --tag`); refused when the newest verified tag is another; skipped when the copy is there
#   needs   what the package needs (recipe: docker = the core recipe docker is installed and run; share = nothing to do here, the recipe makes or uses
#           one; tailscale = switch the part on and rebuild, as pkg-bundle.sh does; any other kind: what it requires must be installed and on already).
#           A need that needs a rebuild is a plan line with `long yes`; the job stops at the first failure (D5)
#   ask     check the answers given up front; the questions that are left are asked WHILE the recipe runs (RECIPE_ASK, ask_q) and wait in the record
#   run:<phase>  the recipe, one sub-job per `# phases:` word, else `run:run` (scripts/recipe-orchestrate.sh reports them as steps of this record)
#   check   the declared health (`[app.health]`): hs sys apps health; no declaration = nothing to check; unhealthy = the job fails here
#   done    the `result` of the record: package, kind, version, tag, instance, open (the first address), data, backup (what pkg show said)
#   on, rebuild   (extension and capability) switch it on; rebuild only for a capability with a Nix module (same code as pkg-bundle.sh)
# `--from <step>` starts the job at that step (read|needs|ask|run|check|done|on|rebuild): the steps before it are not run again. Step 9 (retry) uses it.
# The job writes only through the helpers that fill the created ledger (scripts/lib/created.sh): what this run made is recorded, nothing else.
# A package that says `instances = "one"` (the default) refuses --name other than itself; `many` takes --name <package>-<word>, free among instances and services.
# Test knobs: HS_SERVICES_DIR, HS_PKG (pkg.sh), HS_PARTS (parts.sh), HS_PART_CHANGE (part-change.sh), HS_REBUILD (rebuild.sh), HS_RECIPE (recipe.sh), HS_ORCHESTRATE
#   (recipe-orchestrate.sh), HS_APPS_LIST (apps-list.sh), HS_INCUS, HS_JOB_LIB, HS_RUN_DIR, HS_BUNDLE_NET (ok|fail), HS_LOCKED_MARKER, HS_CHECK_WAIT (seconds
#   the check waits for a healthy app, default 60), HS_RECIPES_DIR.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
pkg=${HS_PKG:-$here/pkg.sh}
parts=${HS_PARTS:-$here/parts.sh}
recipe=${HS_RECIPE:-$here/recipe.sh}
alist=${HS_APPS_LIST:-$here/apps-list.sh}
incus=${HS_INCUS:-incus}

refuse() { printf 'status\trefused\nreason\t%s\n' "$1"; exit 1; }
. "$here/lib/refuse-code.sh"   # refuse_code (ADR 0028)
word='^[a-z0-9][a-z0-9-]{0,40}$'
a_fqdn='([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}'
steps_all=(read needs ask run check done on rebuild)

verb=${1:-}; action=${2:-}; name=${3:-}
case "$verb" in plan|start|run) ;; *) echo "usage: apps-change.sh plan|start install <package> [--repo R] [--tag T] [--name <container>] [--set KEY=value]... [--ask] [--from <step>]" >&2; exit 1 ;; esac
case "$action" in retry|cleanup) exec bash "${HS_APPS_RECOVER:-$here/apps-recover.sh}" "$verb" "$action" "${@:3}" ;; esac   # a failed install (step 9, #466)
case "$action" in update) exec bash "${HS_APPS_VERSION:-$here/apps-version.sh}" "$verb" update "${@:3}" ;; esac   # the update plan (step 12, #470)
case "$action" in remove) exec bash "${HS_APPS_REMOVE:-$here/apps-remove.sh}" "$verb" remove "${@:3}" ;; esac   # Remove with keep/delete data (step 11, #466)
[ "$action" = install ] || refuse_code action.unknown "unknown action (install, retry, cleanup, remove, update)"
[[ "$name" =~ $word ]] || refuse "not a package name (lower case letters, digits and dashes)"
shift 3 || true

repo="" tag="" ct="" ask_again=false from="" from_phase="" by="" role="" confirm=""
declare -A given=()
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)    [ $# -ge 2 ] && [[ "$2" =~ $word ]] || refuse "--repo needs a repository name"; repo=$2; shift 2 ;;
    --tag)     [ $# -ge 2 ] && [[ "$2" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([-.][A-Za-z0-9.]{1,20})?$ ]] || refuse "--tag needs a release tag like v1.2.0"; tag=$2; shift 2 ;;
    --name)    [ $# -ge 2 ] && [[ "$2" =~ $word ]] || refuse "'${2:-}' is not a container name (lower-case letters, digits and dashes)"; ct=$2; shift 2 ;;
    --ask)     ask_again=true; shift ;;
    --from)    [ $# -ge 2 ] || refuse "--from needs a step"
               if [[ "$2" =~ ^run:([a-z0-9][a-z0-9-]{0,30})$ ]]; then from=run; from_phase=${BASH_REMATCH[1]}   # a recipe phase: that phase and the ones after it
               else [[ " ${steps_all[*]} " == *" $2 "* ]] || refuse "--from names one of: ${steps_all[*]}, run:<phase>"; from=$2; fi
               shift 2 ;;
    --by)      [ $# -ge 2 ] && [[ "$2" =~ ^[A-Za-z0-9._@\\-]{1,64}$ ]] || refuse "--by needs a user name"; by=$2; shift 2 ;;
    --role)    [ $# -ge 2 ] && [[ "$2" =~ ^(viewer|app-manager|admin)$ ]] || refuse "--role needs a role"; role=$2; shift 2 ;;
    --confirm) [ $# -ge 2 ] || refuse_code confirm.missing "--confirm needs a value"; confirm=$2; shift 2 ;;
    --set)     [ $# -ge 2 ] && [[ "$2" =~ ^([A-Z][A-Z0-9_]{0,30})=(.*)$ ]] || refuse "--set needs KEY=value"
               given[${BASH_REMATCH[1]}]=${BASH_REMATCH[2]}; shift 2 ;;
    *) refuse_code option.unknown "unknown option $1" ;;
  esac
done
[ "$verb" = plan ] || [ -n "$tag" ] || refuse "start needs --tag <the tag of the plan>: the job installs the release the plan showed, not whatever is newest"

export HS_PLAIN=1 HS_LANG=en HS_CALLER=${HS_CALLER:-ui}
unset HS_GUIDED_TTY

# ── what the verified release says (no install, nothing written) ──
rcs=0; show=$(bash "$pkg" --show "$name" ${repo:+--repo "$repo"} 2>/dev/null </dev/null) || rcs=$?
if [ "$rcs" -ne 0 ] || ! grep -q $'^status\tok' <<<"$show"; then
  why=$(awk -F'\t' '$1=="reason"{print $2; exit}' <<<"$show")
  refuse "${why:-$name has no verified release (hs pkg fetch reads the repositories again)}"
fi
sv() { awk -F'\t' -v k="$1" '$1 == k { print $2; exit }' <<<"$show"; }
kind=$(sv kind); srepo=$(sv repo); version=$(sv version); stag=$(sv tag); title=$(sv title); desc=$(sv description)
needs_csv=$(sv needs); input=$(sv input)
[ -z "$repo" ] || [ "$repo" = "$srepo" ] || refuse "$name is not in the repository $repo"
if [ -n "$tag" ] && [ "$tag" != "$stag" ]; then
  refuse "The release moved: the plan showed $tag but the newest verified release is $stag now. Read the plan again."
fi
tag=$stag; repo=$srepo
mapfile -t jsteps < <(awk -F'\t' '$1=="step"{print $2}' <<<"$show")
[ ${#jsteps[@]} -gt 0 ] || refuse "the release names no steps"
[ -z "$from" ] || [[ " ${jsteps[*]} " == *" $from "* ]] || refuse "--from $from is not a step of $name (${jsteps[*]})"

market_row=$(bash "$pkg" --market 2>/dev/null </dev/null | awk -F'\t' -v n="$name" -v r="$repo" '$1 == n && $3 == r { print; exit }' || true)
mstate=$(cut -f6 <<<"$market_row"); minst=$(cut -f5 <<<"$market_row")
[ -z "$market_row" ] || case "$mstate" in
  waits)  refuse "$name $version needs a newer core than this server has: hs update first" ;;
  update) refuse "$name is installed (version $minst) and a newer release is out: update it instead" ;;
esac
have_copy=false; { [ -n "$market_row" ] && [ "$minst" != - ]; } && have_copy=true
if $have_copy && [ "$kind" != recipe ] && [ "$verb" != run ]; then refuse "$name is installed already (version $minst): an extension or capability is switched on from its own page"; fi
if [ "$kind" = recipe ]; then
  [ "$input" != terminal ] || refuse "$name needs a person at a terminal (a password is typed into the setup): hs pkg install $name, then hs recipe $name"
elif [ -n "$ct" ] || [ ${#given[@]} -gt 0 ]; then
  refuse "$name is an $kind: it takes no container name and no answers"
fi

# several instances (D16, #471): only a package that says `instances = "many"` may have more than the one named after it; the name is checked here
if [ "$kind" = recipe ] && [ -n "$ct" ] && [ "$ct" != "$name" ]; then
  [ "$(sv instances)" = many ] || refuse "$name runs once on a server: its package does not allow a second instance (--name $ct)"
  [[ "$ct" =~ ^$name-[a-z0-9][a-z0-9-]*$ ]] && [ ${#ct} -le 40 ] || refuse "an instance of $name is named $name-<word> (lower case letters, digits and dashes, at most 40 characters): '$ct' does not fit"
  if "$incus" info "$ct" >/dev/null 2>&1 || [ -e "${HS_SERVICES_DIR:-${HS_STATE_DIR:-/var/lib/hs}/services.d}/$ct.toml" ]; then
    refuse "the name $ct is taken already by an instance or a service: choose another word"
  fi
fi

# ── the answers up front: every --set names a question; values fit their pattern or choices ──
ak=() al=() at=() ad=() ap=() ach=() aw=()
while IFS=$'\t' read -r _ k l t c d p w; do
  ak+=("$k"); al+=("$l"); at+=("$t"); ach+=("$c"); ad+=("$d"); ap+=("$p"); aw+=("$w")
done < <(awk -F'\t' '$1=="ask"' <<<"$show")
unfield() { [ "$1" = - ] || printf '%s' "$1"; }
value_of() { local i; if [ -n "${given[$1]+x}" ]; then printf '%s' "${given[$1]}"; return; fi
  for i in "${!ak[@]}"; do [ "${ak[$i]}" = "$1" ] && { unfield "${ad[$i]}"; return; }; done; }
active() { local w; w=$(unfield "${aw[$1]}"); [ -z "$w" ] && return 0; [ "$(value_of "${w%%=*}")" = "${w#*=}" ]; }
for k in "${!given[@]}"; do
  found=false
  for i in "${!ak[@]}"; do [ "${ak[$i]}" = "$k" ] && [ "${at[$i]}" != secret ] && found=true; done
  if [[ "$k" =~ ^PUBLIC_NAME_[A-Z0-9_]+$ ]]; then [[ "${given[$k]}" =~ ^($a_fqdn)$ ]] || refuse "the answer to $k is not a host name (like media.example.org)"; found=true
  elif [[ "$k" =~ ^(DASH|PUBLIC)_[A-Z0-9_]+$ ]]; then [[ "${given[$k]}" =~ ^(yes|no)$ ]] || refuse "the answer to $k must be yes or no"; found=true; fi
  $found || refuse "$name does not ask '$k'"
done
secret_key="" secret_label="" open_q=0
for i in "${!ak[@]}"; do
  active "$i" || continue
  k=${ak[$i]}; t=${at[$i]}
  if [ "$t" = secret ]; then secret_key=$k; secret_label=${al[$i]}; continue; fi
  v=$(value_of "$k")
  if [ -z "$v" ]; then open_q=$((open_q + 1)); continue; fi
  case "$t" in
    choice) [[ ",${ach[$i]}," == *",$v,"* ]] || refuse "'$v' is not one of: ${ach[$i]} ($k)" ;;
    *) pat=$(unfield "${ap[$i]}"); [[ "$v" =~ ^(${pat:-.*})$ ]] || refuse "the answer to $k does not fit ($k)" ;;
  esac
  [[ "$v" != *[[:cntrl:]]* ]] || refuse "the answer to $k has a control character"
done

# ── needs (D5): present or missing, and what is done about it ──
need_lines=() rebuild_need=false need_docker=false need_tailscale=false
if [ "$kind" = recipe ] && [ -n "$needs_csv" ] && [ "$needs_csv" != - ]; then
  IFS=, read -ra nl <<<"$needs_csv"
  for n in "${nl[@]}"; do
    case "$n" in
      docker)
        if "$incus" info docker >/dev/null 2>&1; then need_lines+=("need	docker	present	Docker is set up already.	no")
        else need_docker=true; need_lines+=("need	docker	missing	Docker is installed and set up first (the core recipe docker), as part of this job.	yes"); fi ;;
      share) need_lines+=("need	share	recipe	A share: the app uses an existing one, or makes its default share and records that it did.	no") ;;
      tailscale)
        if awk -F'\t' '$1=="tailscale" && $2=="on" { f=1 } END { exit !f }' < <(bash "$parts" --list 2>/dev/null </dev/null); then need_lines+=("need	tailscale	present	Tailscale is on already.	no")
        else need_tailscale=true; rebuild_need=true; need_lines+=("need	tailscale	missing	Tailscale is switched on and the server is rebuilt (a few minutes to half an hour).	yes"); fi ;;
      *) refuse "$name needs '$n', which this server does not know how to provide" ;;
    esac
  done
elif [ "$kind" != recipe ] && [ -n "$needs_csv" ] && [ "$needs_csv" != - ]; then
  IFS=, read -ra nl <<<"$needs_csv"
  for n in "${nl[@]}"; do
    awk -F'\t' -v n="$n" '$1==n && $2=="on" { f=1 } END { exit !f }' < <(bash "$parts" --list 2>/dev/null </dev/null) \
      || refuse "$name requires $n: switch $n on first (hs sys pkg bundle plan $name installs and switches on everything it requires)"
    need_lines+=("need	$n	present	$n is on already.	no")
  done
fi
if $need_tailscale || [ "$kind" = capability ]; then
  [ ! -e "${HS_LOCKED_MARKER:-/run/hs/storage-locked}" ] || refuse "The storage is locked: unlock it first (hs unlock), a rebuild would refuse."
fi
if [[ " ${jsteps[*]} " == *" rebuild "* ]]; then rebuild_need=true; fi
net_ok() { case "${HS_BUNDLE_NET:-}" in ok) return 0 ;; fail) return 1 ;; esac; . "$here/lib/netcheck.sh"; netcheck_ok >/dev/null 2>&1; }
if $rebuild_need; then
  net_ok || refuse "This needs the network (the rebuild reads the binary cache)."
fi
if $need_docker && [ "$name" = docker ]; then refuse "docker is the core recipe itself: install it from Docker, not as a need of itself"; fi

# a package of an ADDED repository runs as root: the typed name (same rule as pkg-change.sh)
red=""
if [ "$(bash "$pkg" --repos 2>/dev/null </dev/null | awk -F'\t' -v r="$repo" '$1 == r { print $4; exit }')" = added ]; then red=$name; fi

# the secret: one line on standard input, only while a secret question counts (optional: it may be asked while the run goes)
secret=""
if [ -n "$secret_key" ] && [ "$verb" = start ]; then
  IFS= read -r -t 3 secret || true
  [[ "$secret" != *[[:cntrl:]]* ]] || refuse "the secret has a control character"
fi

# ── the job body ──
if [ "$verb" = run ]; then
  . "$here/lib/ui.sh"
  . "$here/lib/job.sh"
  . "$here/lib/install-steps.sh"
  total=${#jsteps[@]}
  from=${APPS_FROM:-$from}
  . "$here/lib/created.sh"
  # a failed run leaves its step and reason on the record (the Retry and Remove buttons read them; docs/PLAN-app-lifecycle.md Q3)
  cur_step=read; last_reason=""
  _ui_fail_body=$(declare -f fail | sed '1s/^fail/_ui_fail/'); eval "$_ui_fail_body"
  fail() { last_reason=$*; _ui_fail "$@"; }
  on_exit() {
    local rc=$? st rec
    [ "$rc" -ne 0 ] && [ -n "${HS_JOB_ID:-}" ] || return 0
    st=$cur_step
    if [[ "$cur_step" = run* ]]; then   # the orchestrator names the phase in the record
      rec=$(hs_job_record get "$HS_JOB_ID" 2>/dev/null || true)
      st=$(python3 -c 'import json,sys
t=(json.loads(sys.argv[1]).get("step") or {}).get("text","")
print(t if t.startswith("run:") else "run")' "$rec" 2>/dev/null || echo run)
    fi
    [ -n "$last_reason" ] || last_reason="the step $st did not finish (exit $rc)"
    install_failed_note "$st" "$last_reason"
  }
  install_failed_note() {   # install_failed_note <step> <reason>: the record's result names the step, the reason and the last lines of its log
    local tail="" json
    tail=$(failed_tail 2>/dev/null || true)
    json=$(python3 -c 'import json,sys
k=["status","failed_step","reason","tail","package","repo","tag","instance","kind","version"]
v=[x[:900] for x in sys.argv[1:]]
print(json.dumps(dict(zip(k,["failed"]+v),code="install.failed")))   # ADR 0028: the web shows the code' "$1" "$2" "$tail" "$name" "$repo" "$tag" "${ct:-$name}" "$kind" "$version")
    hs_job_record result "$HS_JOB_ID" --json "$json" >/dev/null 2>&1 || true
  }
  failed_tail() {   # the last lines of the log of the failed phase's sub-job (its unit's journal), best effort
    local u
    u=$(python3 - "$HS_JOB_ID" <<'PY' 2>/dev/null || true
import json,os,sys,glob
d=os.environ.get("HS_JOBS_DIR","/var/lib/hs/jobs"); best=None
for f in glob.glob(os.path.join(d,"*.json")):
    try: r=json.load(open(f))
    except Exception: continue
    if r.get("parent")==sys.argv[1] and r.get("state") in ("failed","interrupted") and (best is None or r.get("ended","")>=best.get("ended","")): best=r
print((best or {}).get("unit",""))
PY
)
    [ -n "$u" ] || return 0
    if [ -n "${HS_JOB_TAIL:-}" ]; then bash "$HS_JOB_TAIL" "$u"; else journalctl -u "$u.service" -n 6 --no-pager -o cat 2>/dev/null; fi | tr -d '
' | tail -n 6 | cut -c1-200 | paste -sd'|' | sed 's/|/ | /g'
  }
  trap on_exit EXIT
  recipe_file=""
  nphase=1
  n=0; skipping=false; [ -z "$from" ] || skipping=true
  result_open="-"
  for s in "${jsteps[@]}"; do
    n=$((n + 1))
    if $skipping; then
      if [ "$s" != "$from" ]; then
        note "$(t 'Step %s: done before.' "$s")"
        if [ "$s" = run ] && recipe_file=$(. "$here/lib/recipe-path.sh"; recipe_script "$name" 2>/dev/null); then   # its phases still count in the record
          ph=$(sed -n 's/^# phases: //p' "$recipe_file" | head -n1 || true); [ -n "$ph" ] || ph=run
          # shellcheck disable=SC2206
          pl=($ph); total=$((total - 1 + ${#pl[@]})); n=$((n + ${#pl[@]} - 1))
        fi
        continue
      fi
      skipping=false
    fi
    cur_step=$s
    case "$s" in
      read)
        hs_job_step "$n" "$total" read
        if $have_copy; then note "$(t '%s %s is on this server already.' "$name" "$minst")"
        else inst_fetch "$name" --repo "$repo" --tag "$tag"; fi ;;
      needs)
        hs_job_step "$n" "$total" needs
        if $need_docker; then
          step "Docker"
          if ! bash "$pkg" --market 2>/dev/null </dev/null | awk -F'\t' '$1=="docker" && $5 != "-" { f=1 } END { exit !f }'; then inst_fetch docker; fi
          unset_env=(); while IFS= read -r v; do unset_env+=(-u "$v"); done < <(env | grep -o '^RECIPE_[A-Z0-9_]*' || true)
          env ${unset_env[@]+"${unset_env[@]}"} -u HS_SECRETS_DIR bash "$recipe" docker </dev/null || fail "Setting up Docker failed: nothing after it was done."
          ok "Docker is set up"
        fi
        if $need_tailscale; then inst_enable tailscale; inst_rebuild; fi
        { $need_docker || $need_tailscale; } || note "$(t 'Nothing to do for what it needs.')" ;;
      ask)
        hs_job_step "$n" "$total" ask
        if [ "$open_q" -gt 0 ]; then note "$(t '%s question(s) are asked while it runs, in the dialog.' "$open_q")"
        else note "$(t 'Everything the form asked is answered.')"; fi ;;
      run)
        recipe_file=$(. "$here/lib/recipe-path.sh"; recipe_script "$name") || fail "$(t "There is no recipe called '%s'." "$name")"
        ph=$(sed -n 's/^# phases: //p' "$recipe_file" | head -n1 || true); [ -n "$ph" ] || ph=run
        # shellcheck disable=SC2206
        pl=($ph); nphase=${#pl[@]}
        total=$((total - 1 + nphase))   # the record counts the phases of the recipe as steps
        HS_STEP_BASE=$((n - 1)) HS_STEP_TOTAL=$total HS_STEP_PREFIX='run:' \
          bash "${HS_ORCHESTRATE:-$here/recipe-orchestrate.sh}" "$name" ${ct:+--name "$ct"} ${from_phase:+--from-phase "$from_phase"} || exit $?
        n=$((n + nphase - 1)) ;;
      on)
        hs_job_step "$n" "$total" on
        inst_enable "$name" ;;
      rebuild)
        hs_job_step "$n" "$total" rebuild
        inst_rebuild ;;
      check)
        hs_job_step "$n" "$total" check
        step "Check"
        wait_s=${HS_CHECK_WAIT:-60}; waited=0; h=""
        if [ "$kind" = recipe ]; then
          while :; do
            h=$(bash "$alist" --health 2>/dev/null </dev/null | awk -F'\t' -v n="${ct:-$name}" '$1 == n { print $2; exit }' || true)
            case "$h" in unhealthy|stopped) ;; *) break ;; esac
            [ "$waited" -lt "$wait_s" ] || fail "$(t '%s does not answer its health check (%s).' "${ct:-$name}" "$h")"
            sleep 2; waited=$((waited + 2))
          done
          if [ -n "$h" ]; then ok "$(t '%s is healthy.' "${ct:-$name}")"; else note "$(t 'It declares no health check.')"; fi
        else
          awk -F'\t' -v n="$name" '$1==n && $2=="on" { f=1 } END { exit !f }' < <(bash "$parts" --list 2>/dev/null </dev/null) || fail "$(t '%s is not on.' "$name")"
          ok "$(t '%s is on.' "$name")"
        fi ;;
      done)
        hs_job_step "$n" "$total" done
        ;;
    esac
  done
  # what was installed and where to open it: first route, else address and port from the plan lines
  first=$(awk -F'\t' '$1=="route" && $6=="yes" { print $3; exit }' <<<"$show")
  [ -n "$first" ] || first=$(awk -F'\t' '$1=="route" { print $3; exit }' <<<"$show")
  inst_name=${ct:-$name}
  if [ -n "$first" ]; then open_at="$inst_name:$first"; else open_at="-"; fi
  if [ "$kind" = recipe ]; then
    addr=$("$incus" list "$inst_name" -f csv -c 4 2>/dev/null </dev/null | grep -o '[0-9.]* (eth0)' | head -n1 | sed 's/ .*//' || true)
    [ -z "$addr" ] || [ -z "$first" ] || open_at="$addr:$first"
  fi
  json=$(python3 -c 'import json,sys
k=["package","kind","version","tag","instance","open","data","backup"]
print(json.dumps(dict(zip(k,sys.argv[1:9]))))' "$name" "$kind" "$version" "$tag" "$([ "$kind" = recipe ] && echo "$inst_name" || echo -)" "$open_at" \
    "$([ "$kind" = recipe ] && echo "inside the instance $inst_name" || echo -)" "$([ "$kind" = recipe ] && echo "instance snapshots (hs backup ct)" || echo -)")
  [ -z "${HS_JOB_ID:-}" ] || hs_job_record result "$HS_JOB_ID" --json "$json" 2>/dev/null || true
  ok "$(t '%s %s is installed.' "$name" "$version")"
  exit 0
fi

# ── plan and start: the checks are done, now the answer ──
if [ "$verb" = start ]; then
  if [ -n "$red" ]; then [ "$confirm" = "$red" ] || refuse_code confirm.missing "type the name ($red) to confirm"; fi
  . "${HS_JOB_LIB:-$here/lib/job.sh}"
  env_lines=""
  for i in "${!ak[@]}"; do
    active "$i" || continue
    [ "${at[$i]}" != secret ] || continue
    v=$(value_of "${ak[$i]}")
    [ -z "$v" ] || env_lines+="RECIPE_${ak[$i]}=$v"$'\n'
  done
  for k in "${!given[@]}"; do [[ "$k" =~ ^(DASH|PUBLIC|PUBLIC_NAME)_[A-Z0-9_]+$ ]] && env_lines+="RECIPE_$k=${given[$k]}"$'\n'; done
  ! $ask_again || env_lines+="RECIPE_ASK=1"$'\n'
  sdir=""
  if [ -n "$secret" ]; then
    run=${HS_RUN_DIR:-/run/hs}
    mkdir -p "$run"; chmod 700 "$run" 2>/dev/null || true
    sdir=$(mktemp -d "$run/recipe-secret.XXXXXX"); chmod 700 "$sdir" 2>/dev/null || true
    ( umask 077; printf '%s\n' "$secret" > "$sdir/$secret_key" ); chmod 600 "$sdir/$secret_key" 2>/dev/null || true
    env_lines+="HS_SECRETS_DIR=$sdir"$'\n'
  fi
  export HS_JOB_ENV=$env_lines HS_JOB_KIND=orchestration HS_JOB_INITIATOR=${by:-${SUDO_USER:-${USER:-}}}
  rargs=(run install "$name" --repo "$repo" --tag "$tag")
  [ -z "$ct" ] || rargs+=(--name "$ct")
  [ -z "$from" ] || rargs+=(--from "$from${from_phase:+:$from_phase}")
  unit=$(hs_job "app-install-$name${ct:+-$ct}" "hs apps install $name${ct:+ --name $ct}" -- bash -c 'd=$1; shift; "$@"; rc=$?; [ -z "$d" ] || rm -rf "$d"; exit $rc' _ "$sdir" \
          bash "$here/apps-change.sh" "${rargs[@]}") || { [ -z "$sdir" ] || rm -rf "$sdir"; refuse_code job.start-failed "the job could not be started"; }
  jid=$(hs_job_record find-unit "$unit" 2>/dev/null) || jid=""
  printf 'status\tstarted\nunit\t%s\njob\t%s\n' "$unit" "${jid:--}"
  exit 0
fi

printf 'status\tok\nheading\tinstall %s %s\n' "$name" "$version"
printf 'package\t%s\nkind\t%s\nrepo\t%s\nversion\t%s\ntag\t%s\ncommit\t%s\ntitle\t%s\ndescription\t%s\n' "$name" "$kind" "$repo" "$version" "$tag" "$(sv commit)" "${title:--}" "${desc:--}"
if [ "$kind" = recipe ]; then
  printf 'creates\tan instance named %s (RAM %s MB, disk %s GB)\n' "${ct:-$name}" "$(sv ram_mb)" "$(sv disk_gb)"
  awk -F'\t' '$1=="route" { printf "creates\ta route to port %s (%s, %s)\n", $3, $4, $5 }' <<<"$show"
fi
for l in ${need_lines[@]+"${need_lines[@]}"}; do printf '%s\n' "$l"; done
awk -F'\t' '$1=="ask"' <<<"$show"
awk -F'\t' '$1=="step" { print "jobstep\t" $2 "\t" $3 }' <<<"$show"
printf 'step\tfetch the signed release %s of %s (the one shown here, never another)\n' "$tag" "$repo"
[ "$kind" != recipe ] || printf 'step\tset the app up: it runs the recipe, which asks what is left while it runs\n'
[ "$kind" = recipe ] || printf 'step\tswitch it on\n'
[ "$open_q" -eq 0 ] || printf 'note\t%s question(s) are asked in the dialog while it runs.\n' "$open_q"
awk -F'\t' '$1=="slot_off" { printf "note\tThe %s of this package adds a card once %s is on.\n", $2, $3 }' <<<"$show"
[ -z "$secret_key" ] || printf 'note\t%s is kept secret: it goes only into the container, never into the log.\n' "$secret_label"
if $rebuild_need; then
  . "$here/lib/effect.sh"
  printf 'warn\tThis rebuilds the server (a few minutes to half an hour). If a step fails the job stops there.\n'
  printf 'note\t%s\n' "$(effect_rebuild)"
fi
printf 'note\tSafe to run again: a second run repairs or updates the setup.\n'
if [ -n "$red" ]; then
  printf 'danger\tThe repository %s was added by you, not by the project. This package runs as root on this server.\n' "$repo"
  printf 'confirm_name\t%s\n' "$name"
fi
printf 'command\ths sys apps start install %s --tag %s\n' "$name" "$tag"
printf 'long\tyes\n'
exit 0
