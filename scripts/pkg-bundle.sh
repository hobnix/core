#!/usr/bin/env bash
# help: install capability packages with what they require, switch them on and rebuild, as one background job: what would happen (plan), then do it (start)
# help.de: Capability-Pakete mit allem, was sie brauchen, installieren, einschalten und neu bauen, als ein Hintergrundjob: was passieren würde (plan), dann ausführen (start)
# args: plan|start <name>[,<name>...]
# System command (hs sys pkg bundle plan|start): the Optional parts step of the first-run wizard (docs/PLAN-capabilities-repo.md step 14, #229).
# The names are ONE comma list. What a package requires is added in front of it (installed, or switched on when it is a part already).
# plan: key<TAB>value lines as pkg-change.sh (status ok|refused, reason, heading|step|note|command, long yes); exit 0 = allowed, 1 = refused.
# start: the same checks, then `status started` and `unit <name>`: ONE background job installs, switches on and rebuilds, and stops at the first failure.
# `run <install-csv|-> <enable-csv|->` is what the job runs (never called by a person).
# Only the default repositories: a package of an added repository is installed from the Marketplace. Needs the network (O7).
# Test knobs: HS_PKG (pkg.sh), HS_PARTS (parts.sh), HS_PART_CHANGE (part-change.sh), HS_REBUILD (rebuild.sh), HS_JOB_LIB (lib/job.sh),
# HS_BUNDLE_NET (ok|fail: stands in for the network check), HS_LOCKED_MARKER, HS_MACHINE_FILE.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib/machine.sh"
. "$here/lib/effect.sh"
pkg=${HS_PKG:-$here/pkg.sh}
parts=${HS_PARTS:-$here/parts.sh}
partchange=${HS_PART_CHANGE:-$here/part-change.sh}
rebuild=${HS_REBUILD:-$here/rebuild.sh}

refuse() { printf 'status\trefused\nreason\t%s\n' "$1"; exit 1; }

verb=${1:-}
namelist='^[a-z0-9][a-z0-9-]{0,40}(,[a-z0-9][a-z0-9-]{0,40}){0,15}$'
case "$verb" in plan|start|run) ;; *) echo "usage: pkg-bundle.sh plan|start <name>[,<name>...]" >&2; exit 1 ;; esac

if [ "$verb" = run ]; then
  [ $# -eq 3 ] || { echo "usage: pkg-bundle.sh run <install-csv|-> <enable-csv|->" >&2; exit 1; }
  for a in "$2" "$3"; do
    if [ "$a" != - ] && ! [[ "$a" =~ $namelist ]]; then echo "pkg-bundle.sh: bad name list" >&2; exit 1; fi
  done
  . "$here/lib/ui.sh"
  inst_csv=$2; en_csv=$3
  if [ "$inst_csv" != - ]; then
    IFS=, read -ra todo <<<"$inst_csv"
    for n in "${todo[@]}"; do
      step "Install $n"
      bash "$pkg" install "$n" </dev/null || fail "Installing $n failed: nothing after it was done."
      ok "$n installed"
    done
  fi
  if [ "$en_csv" != - ]; then
    IFS=, read -ra todo <<<"$en_csv"
    for n in "${todo[@]}"; do
      step "Switch $n on"
      out=$(bash "$partchange" start enable "$n" </dev/null 2>&1) || true
      grep -q $'^status\tdone' <<<"$out" || fail "Switching $n on failed: $(awk -F'\t' '$1=="reason"{print $2}' <<<"$out")"
      ok "$n is switched on"
    done
  fi
  step "Rebuild"
  bash "$rebuild" </dev/null || fail "The rebuild failed: the parts are switched on in machine.toml; hs rebuild tries again."
  ok "Done"
  exit 0
fi

[ $# -ge 2 ] || refuse "give the packages as one comma list of names"
arg=$2
shift 2
if [ $# -gt 0 ]; then
  if [ "$1" = --confirm ] && [ $# -eq 2 ]; then :; else refuse "unexpected extra arguments"; fi
fi
[[ "$arg" =~ $namelist ]] || refuse "give the packages as one comma list of names"
picked=()
declare -A pk=()
IFS=, read -ra raw <<<"$arg"
for n in "${raw[@]}"; do [ -z "${pk[$n]:-}" ] || continue; pk[$n]=1; picked+=("$n"); done
export HS_PLAIN=1 HS_LANG=en HS_CALLER=${HS_CALLER:-ui}
unset HS_GUIDED_TTY

[ ! -e "${HS_LOCKED_MARKER:-/run/hs/storage-locked}" ] || refuse "The storage is locked: unlock it first (hs unlock), a rebuild would refuse."
net_ok() { case "${HS_BUNDLE_NET:-}" in ok) return 0 ;; fail) return 1 ;; esac; . "$here/lib/netcheck.sh"; netcheck_ok >/dev/null 2>&1; }
net_ok || refuse "This needs the network (installing reads the signed releases, the rebuild the binary cache). Skip this step and add parts later with hs pkg install."

caps=$(bash "$pkg" --capabilities 2>/dev/null || true)
repos=$(bash "$pkg" --repos 2>/dev/null || true)
plist=$(bash "$parts" --list 2>/dev/null || true)
mcaps=""
if machine_has capabilities; then mcaps=$(machine_get capabilities 2>/dev/null || true); fi

inst=(); en=(); why=()
declare -A done_=() busy=()
visit() {   # visit <name> <required by or empty>
  local n=$1 by=${2:-} crow prow cnt repo kind r reqs st sw rl
  [ -z "${done_[$n]:-}" ] || return 0
  [ -z "${busy[$n]:-}" ] || refuse "the packages require each other in a circle ($n)"
  busy[$n]=1
  crow=$(awk -F'\t' -v n="$n" '$1 == n { print; exit }' <<<"$caps")
  prow=$(awk -F'\t' -v n="$n" '$1 == n { print; exit }' <<<"$plist")
  st=""; sw=""
  if [ -n "$prow" ]; then st=$(cut -f2 <<<"$prow"); sw=$(cut -f5 <<<"$prow"); fi
  if [ -n "$crow" ]; then
    cnt=$(awk -F'\t' -v n="$n" '$1 == n { c++ } END { print c + 0 }' <<<"$caps")
    [ "$cnt" -le 1 ] || refuse "$n is in more than one repository: install it with hs pkg install $n --repo <repo>"
    repo=$(cut -f2 <<<"$crow")
    kind=$(awk -F'\t' -v r="$repo" '$1 == r { print $4; exit }' <<<"$repos")
    [ "$kind" != added ] || refuse "$n comes from a repository you added: install it from the Marketplace"
    reqs=$(cut -f6 <<<"$crow")
    if [ "$reqs" != - ]; then
      IFS=, read -ra rl <<<"$reqs"
      for r in "${rl[@]}"; do visit "$r" "$n"; done
    fi
    if [ "$(cut -f4 <<<"$crow")" = - ]; then
      inst+=("$n")
      if [ -n "$by" ]; then why+=("also install $n: $by requires it"); fi
    fi
    if [ "$st" = on ] || grep -qxF -- "$n" <<<"$mcaps"; then :; else en+=("$n"); fi
  elif [ -n "$prow" ]; then
    if [ "$st" = on ] || grep -qxF -- "$n" <<<"$mcaps"; then :; else
      [ "$sw" = yes ] || refuse "$by requires $n, which follows the role of this server"
      en+=("$n")
      if [ -n "$by" ]; then why+=("also switch on $n: $by requires it"); fi
    fi
  else
    if [ -n "$by" ]; then refuse "$by requires $n, which this server does not have and no repository offers (hs pkg fetch reads them again)"; fi
    refuse "There is no capability package $n in the repositories (fetch them again first)."
  fi
  unset "busy[$n]"
  done_[$n]=1
}
for n in "${picked[@]}"; do visit "$n" ""; done

join() { local sep=$1 out="" x; shift; for x in "$@"; do out=${out:+$out$sep}$x; done; printf '%s' "$out"; }
csv() { if [ $# -eq 0 ]; then printf '%s' -; else join , "$@"; fi; }
if [ ${#inst[@]} -eq 0 ] && [ ${#en[@]} -eq 0 ]; then refuse "$(join ', ' "${picked[@]}") installed and on already."; fi

if [ "$verb" = start ]; then
  . "${HS_JOB_LIB:-$here/lib/job.sh}"
  unit=$(hs_job "pkg-bundle" "hs pkg bundle $(join , "${picked[@]}")" -- bash "$here/pkg-bundle.sh" run "$(csv ${inst[@]+"${inst[@]}"})" "$(csv ${en[@]+"${en[@]}"})") || refuse "the job could not be started"
  printf 'status\tstarted\nunit\t%s\n' "$unit"
  exit 0
fi

printf 'status\tok\n'
printf 'heading\tinstall and switch on %s\n' "$(join ', ' "${picked[@]}")"
for n in ${inst[@]+"${inst[@]}"}; do
  crow=$(awk -F'\t' -v n="$n" '$1 == n { print; exit }' <<<"$caps")
  printf 'step\tinstall %s %s from the signed release of %s\n' "$n" "$(cut -f3 <<<"$crow")" "$(cut -f2 <<<"$crow")"
done
for w in ${why[@]+"${why[@]}"}; do printf 'note\t%s\n' "$w"; done
for n in ${en[@]+"${en[@]}"}; do printf 'step\tswitch %s on (machine.toml capabilities)\n' "$n"; done
printf 'step\trebuild the server (hs rebuild): the new parts take effect\n'
printf 'note\tOne background job does all of it, in this order. If a step fails the job stops there: what was installed stays, off until you switch it on.\n'
printf 'note\t%s\n' "$(effect_rebuild)"
cmds=()
for n in ${inst[@]+"${inst[@]}"}; do cmds+=("hs pkg install $n"); done
for n in ${en[@]+"${en[@]}"}; do cmds+=("hs sys parts start enable $n"); done
cmds+=("hs rebuild")
printf 'command\t%s\n' "$(join '; ' "${cmds[@]}")"
printf 'long\tyes\n'
