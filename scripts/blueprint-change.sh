#!/usr/bin/env bash
# help: apply a blueprint without asking anything: what would happen (plan), then do it as one background job (start); only fills what is not set yet
# help.de: einen Bauplan ohne Rückfragen anwenden: was passieren würde (plan), dann als ein Hintergrundjob ausführen (start); füllt nur, was noch nicht gesetzt ist
# args: plan|start apply <name> [--confirm <name>]...
# System command (hs sys blueprint plan|start): for the interface, first-run and tests. It never asks and prints plain key<TAB>value lines like pkg-bundle.sh.
# A blueprint (kind = "blueprint", docs/PLAN-registry.md) is read through `hs pkg blueprint show` (signed index, tree hash checked). ONE job applies it, in this
# order: config (machine.toml and settings that are not set), parts (install and switch on), one rebuild, docker (only with a [docker] table), then the apps.
# Fill-only: a value that is set is kept. config, parts, rebuild and docker stop the job at the first failure (the rest is `skipped`); an app that fails does
# not stop the next one. The result of the job record is one flat object: <part>[:<name>] -> done|kept|later|failed|skipped[: reason].
# plan: status ok|refused, reason, heading, blueprint<TAB>name<TAB>repo<TAB>version<TAB>tag, part<TAB>n<TAB>config|parts|rebuild|docker|app<TAB>name|-<TAB>
#   set|kept|install|enable|present|later<TAB>text, step|note|warn<TAB>text, confirm_name<TAB>name (zero or more), command, long yes. Exit 0 ok, 1 refused.
# start: the same checks, `--confirm` once for every confirm_name line, then status started, unit, job. `run <name> --tag <tag>` is the job's body (never called by a person).
# Never: a blueprint does not install the recipe docker, never turns Docker off, never moves apps, never creates storage, never carries a secret.
# Test knobs: HS_PKG (pkg.sh), HS_PARTS (parts.sh), HS_PART_CHANGE (part-change.sh), HS_REBUILD (rebuild.sh), HS_DOCKER_SCRIPT (docker.sh), HS_APPS_CHANGE
#   (apps-change.sh), HS_APPS_LIST (apps-list.sh), HS_JOB_LIB (lib/job.sh), HS_BUNDLE_NET (ok|fail), HS_LOCKED_MARKER, HS_MACHINE_FILE, HS_SETTINGS_DIR,
#   HS_BLUEPRINT_POLL (seconds between looks at an app job, default 5), HS_BLUEPRINT_APP_LIMIT (seconds one app may take, default 7200).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib/machine.sh"
. "$here/lib/setting.sh"
. "$here/lib/effect.sh"
pkg=${HS_PKG:-$here/pkg.sh}
parts=${HS_PARTS:-$here/parts.sh}
dockersh=${HS_DOCKER_SCRIPT:-$here/docker.sh}
appschange=${HS_APPS_CHANGE:-$here/apps-change.sh}
alist=${HS_APPS_LIST:-$here/apps-list.sh}
tab=$'\t'

# the reason is one line whatever a package text put into it: no C0 or DEL, no C1 and no U+2028/2029 (the web interface splits lines on them)
refuse() {
  local r
  r=$(printf '%s' "$1" | LC_ALL=C tr -d '\000-\037\177' | LC_ALL=C sed -E 's/\xc2[\x80-\x9f]//g; s/\xe2\x80[\xa8\xa9]//g')
  printf 'status\trefused\nreason\t%s\n' "$r"; exit 1
}
. "$here/lib/refuse-code.sh"   # refuse_code (ADR 0028)

verb=${1:-}; action=${2:-}; name=${3:-}
case "$verb" in plan|start|run) ;; *) echo "usage: blueprint-change.sh plan|start apply <name> [--confirm <name>]..." >&2; exit 1 ;; esac
[ "$action" = apply ] || refuse_code action.unknown "unknown action (apply)"
[[ "$name" =~ ^[a-z0-9][a-z0-9-]{0,40}$ ]] || refuse "No blueprint called '$name'."
shift 3 || true
confirmed=(); want_tag=""
while [ $# -gt 0 ]; do
  case "$1" in
    --confirm) [ $# -ge 2 ] || refuse "--confirm needs a name"; confirmed+=("$2"); shift 2 ;;
    --tag) [ $# -ge 2 ] || refuse "--tag needs a value"; want_tag=$2; shift 2 ;;
    *) refuse "unexpected extra arguments" ;;
  esac
done
export HS_PLAIN=1 HS_LANG=en HS_CALLER=${HS_CALLER:-ui}
unset HS_GUIDED_TTY

# ── the facts: the blueprint (signed, checked), what this server has ──
rc=0; show=$(bash "$pkg" blueprint show "$name" en 2>/dev/null </dev/null) || rc=$?
if [ "$rc" != 0 ]; then
  refuse "$(awk -F'\t' '$1 == "error" { printf "%s%s", (n++ ? "; " : ""), $2 }' <<<"$show")"
fi
sv() { awk -F'\t' -v k="$1" '$1 == k { print $2; exit }' <<<"$show"; }
repo=$(sv repo); version=$(sv version); tag=$(sv tag); title=$(sv title); roles=$(sv roles); added=$(sv added)
[ -n "$want_tag" ] && [ "$want_tag" != "$tag" ] && refuse "The blueprint is at $tag now, the plan was made for $want_tag: read the plan again."

role=""; if machine_has role; then role=$(machine_get role 2>/dev/null || true); fi
if [ -n "$role" ] && ! grep -qxF -- "$role" < <(tr , '\n' <<<"$roles"); then
  refuse "This blueprint is for the role $(sed 's/,/ or /g' <<<"$roles"); this server is $role."
fi
[ ! -e "${HS_LOCKED_MARKER:-/run/hs/storage-locked}" ] || refuse "The storage is locked: unlock it first (hs unlock), a rebuild would refuse."
net_ok() { case "${HS_BUNDLE_NET:-}" in ok) return 0 ;; fail) return 1 ;; esac; . "$here/lib/netcheck.sh"; netcheck_ok >/dev/null 2>&1; }
net_ok || refuse "This needs the network (installing reads the signed releases, the rebuild the binary cache)."

# config rows: kind<TAB>key<TAB>value<TAB>state (set|kept), as preset.sh
cfg=""
while IFS=$'\t' read -r kind key val; do
  [ -n "$kind" ] || continue
  st="set"
  if [ "$kind" = machine ]; then machine_has "$key" && st=kept
  else cur=$(setting_get "$key" 2>/dev/null || true); [ -z "$cur" ] || st=kept; fi
  cfg+="$kind$tab$key$tab$val$tab$st"$'\n'
done < <(awk -F'\t' '$1 == "machine" || $1 == "setting"' <<<"$show")

# parts: capabilities through the bundle resolver, extensions beside it
caps=$(bash "$pkg" --capabilities 2>/dev/null || true)
repos=$(bash "$pkg" --repos 2>/dev/null || true)
plist=$(bash "$parts" --list 2>/dev/null || true)
mcaps=""; if machine_has capabilities; then mcaps=$(machine_get capabilities 2>/dev/null || true); fi
# shellcheck source=scripts/lib/bundle-resolve.sh
# shellcheck source-path=SCRIPTDIR/..
. "$here/lib/bundle-resolve.sh"
bundle_inputs "$caps" "$repos" "$plist" "$mcaps"
while IFS= read -r n; do [ -z "$n" ] || visit "$n" ""; done < <(awk -F'\t' '$1 == "part" && $2 == "capabilities" { print $3 }' <<<"$show")
while IFS=$'\t' read -r _ _ n st; do
  [ -n "$n" ] || continue
  [ "$st" != new ] || inst+=("$n")
  prow=$(awk -F'\t' -v n="$n" '$1 == n { print; exit }' <<<"$plist")
  if [ "$(cut -f2 <<<"$prow")" = on ] || grep -qxF -- "$n" <<<"$mcaps"; then :; else en+=("$n"); fi
done < <(awk -F'\t' '$1 == "part" && $2 == "extensions"' <<<"$show")

# docker: the core capability, fill-only (on = kept, nothing changes)
dline=$(awk -F'\t' '$1 == "docker"' <<<"$show")
docker_on=false
if bash "$dockersh" --status 2>/dev/null </dev/null | grep -qx "owned${tab}yes"; then docker_on=true; fi
dmanager=$(cut -f2 <<<"$dline"); dsize=$(cut -f3 <<<"$dline")
dplan=""; dconfirm=()
if [ -n "$dline" ] && ! $docker_on && [ "$verb" != run ]; then   # the job turns Docker on with the same words, it does not plan it again
  dargs=(--set "dockerManager=$dmanager"); [ "$dsize" = - ] || dargs+=(--set "dockerSize=$dsize")
  rc=0; dplan=$(bash "${HS_DOCKER_SETUP:-$here/docker-setup.sh}" plan setup "${dargs[@]}" 2>/dev/null </dev/null) || rc=$?
  [ "$rc" = 0 ] || refuse "Docker cannot be turned on: $(awk -F'\t' '$1 == "reason" { print $2; exit }' <<<"$dplan")"
  while IFS= read -r c; do [ -z "$c" ] || dconfirm+=("$c"); done < <(awk -F'\t' '$1 == "confirm_name" { print $2 }' <<<"$dplan")
fi

# apps: in order; one that needs a person is `later`; one that needs Docker needs Docker on (now or by this blueprint)
apps=()   # name<TAB>state (install|present|later)<TAB>text<TAB>repository (the blueprint's own or official, as the reader found it)
present=$(bash "$alist" --list 2>/dev/null </dev/null | awk -F'\t' '$3 == "on" || $3 == "running" { print $1 }' || true)
while IFS=$'\t' read -r _ _ n st; do
  [ -n "$n" ] || continue
  if [ "${st%%:*}" = later ]; then apps+=("$n${tab}later${tab}${st#later:}"); continue; fi
  if grep -qxF -- "$n" <<<"$present"; then apps+=("$n${tab}present${tab}already installed"); continue; fi
  if tr , '\n' < <(awk -F'\t' -v n="$n" '$1 == "needs" && $2 == n { print $3 }' <<<"$show") | grep -qx docker && [ -z "$dline" ] && ! $docker_on; then
    refuse "$n needs Docker: add a [docker] table to the blueprint or turn Docker on first (hs docker enable)."
  fi
  apps+=("$n${tab}install${tab}install $n${tab}$(awk -F'\t' -v n="$n" '$1 == "from" && $2 == n { print $3; exit }' <<<"$show")")
done < <(awk -F'\t' '$1 == "part" && $2 == "recipes"' <<<"$show")

# the typed names: the blueprint's own when it comes from an added repository, then the ones the docker plan asks for
need_names=()
[ "$added" != yes ] || need_names+=("$name")
need_names+=(${dconfirm[@]+"${dconfirm[@]}"})
for c in ${confirmed[@]+"${confirmed[@]}"}; do
  grep -qxF -- "$c" < <(printf '%s\n' ${need_names[@]+"${need_names[@]}"}) || refuse "'$c' is not a name this plan asks for."
done
if [ "$verb" = start ]; then
  for c in ${need_names[@]+"${need_names[@]}"}; do
    grep -qxF -- "$c" < <(printf '%s\n' ${confirmed[@]+"${confirmed[@]}"}) || refuse "Type the name '$c' to confirm."
  done
fi

edge_warn="edge-ports opens public game and call ports of this server to the internet."
join() { local sep=$1 out="" x; shift; for x in "$@"; do out=${out:+$out$sep}$x; done; printf '%s' "$out"; }
config_todo() { awk -F'\t' '$4 == "set"' <<<"$cfg"; }
need_rebuild=false
if [ -n "$(config_todo | awk -F'\t' '$1 == "machine"')" ] || [ ${#inst[@]} -gt 0 ] || [ ${#en[@]} -gt 0 ]; then need_rebuild=true; fi

# ── plan ──
if [ "$verb" = plan ]; then
  printf 'status\tok\nheading\tapply the blueprint %s\n' "$title"
  printf 'blueprint\t%s\t%s\t%s\t%s\n' "$name" "$repo" "$version" "$tag"
  n=0
  while IFS=$'\t' read -r kind key val st; do
    [ -n "$kind" ] || continue
    n=$((n + 1))
    if [ "$st" = set ]; then printf 'part\t%d\tconfig\t%s\tset\tset %s = %s\n' "$n" "$key" "$key" "$val"
    else printf 'part\t%d\tconfig\t%s\tkept\t%s is set already and is kept\n' "$n" "$key" "$key"; fi
  done <<<"$cfg"
  for p in ${inst[@]+"${inst[@]}"}; do n=$((n + 1)); printf 'part\t%d\tparts\t%s\tinstall\tinstall %s from the signed release\n' "$n" "$p" "$p"; done
  for p in ${en[@]+"${en[@]}"}; do n=$((n + 1)); printf 'part\t%d\tparts\t%s\tenable\tswitch %s on\n' "$n" "$p" "$p"; done
  for w in ${why[@]+"${why[@]}"}; do printf 'note\t%s\n' "$w"; done
  if printf '%s\n' ${en[@]+"${en[@]}"} ${inst[@]+"${inst[@]}"} | grep -qx edge-ports; then printf 'warn\t%s\n' "$edge_warn"; fi
  if $need_rebuild; then n=$((n + 1)); printf 'part\t%d\trebuild\t-\tset\trebuild the server (hs rebuild): one rebuild for all of it\n' "$n"; fi
  if [ -n "$dline" ]; then
    n=$((n + 1))
    if $docker_on; then
      printf 'part\t%d\tdocker\t-\tkept\tDocker is on already and is not changed\n' "$n"
      printf 'note\tDocker is on: its manager and size are not changed by a blueprint.\n'
    else
      printf 'part\t%d\tdocker\t-\tenable\tturn Docker on (manager %s)\n' "$n" "$dmanager"
      awk -F'\t' '$1 == "step" || $1 == "note" || $1 == "warn"' <<<"$dplan"
    fi
  fi
  for a in ${apps[@]+"${apps[@]}"}; do
    IFS=$'\t' read -r an ast atext _ <<<"$a"
    n=$((n + 1))
    case "$ast" in
      later) printf 'part\t%d\tapp\t%s\tlater\t%s needs you: %s (hs apps install %s)\n' "$n" "$an" "$an" "$atext" "$an" ;;
      present) printf 'part\t%d\tapp\t%s\tpresent\t%s\n' "$n" "$an" "$atext" ;;
      *) printf 'part\t%d\tapp\t%s\tinstall\t%s\n' "$n" "$an" "$atext" ;;
    esac
  done
  printf 'note\tOne background job does all of it, in this order; config, parts, the rebuild and Docker stop it at the first failure, an app that fails does not stop the next one.\n'
  $need_rebuild && printf 'note\t%s\n' "$(effect_rebuild)"
  for p in $(printf '%s\n' ${need_names[@]+"${need_names[@]}"}); do printf 'confirm_name\t%s\n' "$p"; done
  printf 'command\ths blueprint apply %s --yes\nlong\tyes\n' "$name"
  exit 0
fi

# ── start: one job ──
if [ "$verb" = start ]; then
  # shellcheck source=scripts/lib/job.sh
  . "${HS_JOB_LIB:-$here/lib/job.sh}"
  utmp=$(mktemp)   # not a subshell: hs_job leaves the record id in HS_JOB_LAST_ID
  hs_job "blueprint-$name" "hs blueprint apply $name" -- bash "$here/blueprint-change.sh" run apply "$name" --tag "$tag" >"$utmp" || { rm -f "$utmp"; refuse "the job could not be started"; }
  unit=$(cat "$utmp"); rm -f "$utmp"
  printf 'status\tstarted\nunit\t%s\n' "$unit"
  [ -z "${HS_JOB_LAST_ID:-}" ] || printf 'job\t%s\n' "$HS_JOB_LAST_ID"
  exit 0
fi

# ── run: the job ──
# ui.sh `fail` exits: a step that can fail runs in a subshell or reports with `warn`, so the result of the record is always written
. "$here/lib/ui.sh"
. "$here/lib/install-steps.sh"
# shellcheck source=scripts/lib/job.sh
. "${HS_JOB_LIB:-$here/lib/job.sh}"
declare -A res=()
order=()
mark() { local k=$1 v=$2; [ -n "${res[$k]:-}" ] || order+=("$k"); res[$k]=$v; }
finish_record() {   # the result of the record: one flat object
  local json="{" k first=1
  for k in ${order[@]+"${order[@]}"}; do
    json+="$([ "$first" = 1 ] || printf ,)\"${k//[^A-Za-z0-9:_.-]/}\":\"$(printf %s "${res[$k]}" | tr -d '"\\' | cut -c1-200)\""
    first=0
  done
  hs_job_record result "${HS_JOB_ID:-}" --json "$json}" >/dev/null 2>&1 || true
}
stopped() {   # stopped <part...>: the rest is skipped
  local p
  for p in "$@"; do [ -n "${res[$p]:-}" ] || mark "$p" skipped; done
  for a in ${apps[@]+"${apps[@]}"}; do mark "app:${a%%$tab*}" skipped; done
  finish_record; exit 1
}
all_parts=(config parts rebuild docker)

step "Blueprint: $title"
hs_job_step 1 5 config
mark config "done"
while IFS=$'\t' read -r kind key val st; do
  [ "$st" = set ] || continue
  if [ "$kind" = machine ]; then
    if [ -f "$(machine_file)" ] && machine_set "$key" "$val" blueprint >/dev/null; then ok "$(t '%s is set' "$key")"
    else warn "$(t "'%s' could not be written to machine.toml. Nothing else was changed." "$key")"; mark config "failed: $key"; stopped "${all_parts[@]}"; fi
  else setting_set "$key" "$val"; ok "$(t '%s is set' "$key")"; fi
done <<<"$cfg"
[ -n "$(config_todo)" ] || mark config kept

hs_job_step 2 5 parts
mark parts "done"
for p in ${inst[@]+"${inst[@]}"}; do ( inst_fetch "$p" ) || { mark parts "failed: install $p"; stopped "${all_parts[@]}"; }; done
for p in ${en[@]+"${en[@]}"}; do [ "$p" != edge-ports ] || warn "$edge_warn"; ( inst_enable "$p" ) || { mark parts "failed: switch $p on"; stopped "${all_parts[@]}"; }; done
[ ${#inst[@]} -gt 0 ] || [ ${#en[@]} -gt 0 ] || mark parts kept

hs_job_step 3 5 rebuild
if $need_rebuild; then
  if ( inst_rebuild ); then mark rebuild "done"; else mark rebuild "failed: the rebuild"; stopped "${all_parts[@]}"; fi
else mark rebuild kept; fi

hs_job_step 4 5 docker
if [ -z "$dline" ]; then :
elif $docker_on; then mark docker kept; note "$(t 'Docker is on already: not changed.')"
else
  step "Turn Docker on"
  dargs=(enable --manager "$dmanager" --yes); [ "$dsize" = - ] || dargs+=(--size "$dsize")
  if bash "$dockersh" "${dargs[@]}" </dev/null; then mark docker "done"; ok "Docker is on"
  else warn "Docker could not be turned on: the apps after it are not installed."; mark docker "failed: hs docker enable"; stopped docker; fi
fi

# an app job is a job of its own (apps-change.sh start install); look at its record until it ends, at most HS_BLUEPRINT_APP_LIMIT seconds
job_state() { hs_job_record get "$1" 2>/dev/null | grep -o '"state": *"[a-z]*"' | head -n1 | sed 's/.*: *"//; s/"//' || true; }
hs_job_step 5 5 apps
failed=0
for a in ${apps[@]+"${apps[@]}"}; do
  IFS=$'\t' read -r an ast atext arepo <<<"$a"
  case "$ast" in
    later) mark "app:$an" "later: $atext"; note "$an needs you: hs apps install $an"; continue ;;
    present) mark "app:$an" "kept: $atext"; continue ;;
  esac
  step "Install $an"
  sets=()
  while IFS=$'\t' read -r _ _ k v; do [ -z "$k" ] || sets+=(--set "$k=$v"); done < <(awk -F'\t' -v n="$an" '$1 == "answer" && $2 == n' <<<"$show")
  # apps-change.sh wants the repository and the tag its own plan shows (never a typed name: an app of an added repository is `later`, see the reader)
  rc=0; aplan=$(bash "$appschange" plan install "$an" --repo "${arepo:-official}" </dev/null 2>&1) || rc=$?
  atag=$(sed -n 's/^command\t.* --tag \(v[^ ]*\)$/\1/p' <<<"$aplan" | head -n1)
  if [ "$rc" != 0 ] || [ -z "$atag" ]; then rc=1; out=$aplan
  else out=$(bash "$appschange" start install "$an" --repo "${arepo:-official}" --tag "$atag" ${sets[@]+"${sets[@]}"} </dev/null 2>&1) || rc=$?; fi
  jid=$(awk -F'\t' '$1 == "job" { print $2; exit }' <<<"$out")
  if [ "$rc" != 0 ] || [ -z "$jid" ]; then
    mark "app:$an" "failed: $(awk -F'\t' '$1 == "reason" { print $2; exit }' <<<"$out")"; warn "$an: $(awk -F'\t' '$1 == "reason" { print $2; exit }' <<<"$out")"; failed=1; continue
  fi
  waited=0; limit=${HS_BLUEPRINT_APP_LIMIT:-7200}; poll=${HS_BLUEPRINT_POLL:-5}; st=""
  while :; do
    st=$(job_state "$jid")
    case "$st" in ok|failed|cancelled|interrupted|skipped|"") break ;; esac
    [ "$waited" -lt "$limit" ] || { st=timeout; break; }
    sleep "$poll"; waited=$((waited + poll))
  done
  if [ "$st" = ok ] || [ "$st" = skipped ]; then mark "app:$an" "done"; ok "$an installed"
  else mark "app:$an" "failed: the install job ended as ${st:-unknown} (hs job log)"; warn "$an did not install ($st): the next app goes on."; failed=1; fi
done

# the blueprint is applied when everything before the apps worked; an app that failed is in the result and is tried again by the next apply
bash "$pkg" blueprint record "$name" >/dev/null 2>&1 || warn "$(t 'The applied blueprint could not be recorded.')"
finish_record
[ "$failed" = 0 ] || exit 1
ok "Blueprint applied"
