#!/usr/bin/env bash
# help: extension packages (optional parts such as Games and Posters): list them, switch them on or off, show their commands
# help.de: Erweiterungspakete (optionale Teile wie Spiele und Poster): auflisten, an- oder ausschalten, ihre Befehle zeigen
# args: list | enable <package> | disable <package> | <package> | status | start <package> | stop <package> | --list | --status
# An extension is a package folder capabilities/<name>/ with a capability.toml (`extension = true`) and a commands.tsv; its commands are
# `hs ext <name> <command>` and the machine-readable `hs sys ext <name> <command>` (docs/PLAN-extensions.md). The folder name is the
# namespace. A package is off until it is named in machine.toml (`capabilities = [...]`); its commands do not exist while it is off.
#   list              the packages, whether each is on, and how many commands it brings
#   --list            the same as data (hs sys ext list): name, on|off, commands, nix (yes = a rebuild is needed to switch it), title
#   enable <name>     machine.toml gets the name in `capabilities`. A package without a Nix module is on at once (the file
#                     $HS_STATE_DIR/capabilities-on says so until the next rebuild); one with a module needs `hs rebuild`, and is told so
#   disable <name>    the reverse (capabilities-off wins over everything until the next rebuild); refused while another package that is on requires it
#   enable also refuses a package whose `requires` names a capability that is off, or whose `requires_core = ">=N"` is above scripts/lib/api-level
#   <name>            the commands of the package (also while it is off, marked as such); a word after it that is no command is named
#   boot              (run by hs-ext-boot.service at boot) for each package that is on and has a `sys ext <name> boot` row: run it, print
#                     `<name><TAB>ok|failed` (journal only); one failing or hanging package never stops the others; exits 0 always
#   status            the services of the packages that are on: state (starting|running|degraded|stopping|stopped|failed), reason, since (--status = hs sys ext status: name, state, reason, since)
#   start|stop <name> start or stop the service of a package (ADR 0011 rule 3); a stop by hand survives a reboot until start
#   (start also writes the confinement drop-in of the unit from the permissions: scripts/lib/ext_confine.py, ADR 0014)
#   svc-run <name>    (run by hs-ext-svc@<name>.service) supervise the service of the package: scripts/lib/ext_service.py
# Test knobs: HS_CONFINE_DIR (where the drop-ins of the units go), HS_SYSTEMCTL, HS_MACHINE_FILE, HS_STATE_DIR, HS_PACKAGES_DIR, HS_CAPABILITIES_FILE, HS_LANG.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib/ui.sh"
. "$here/lib/machine.sh"
. "$here/lib/registry-load.sh"
. "$here/lib/effect.sh"
. "$here/lib/integration.sh"
state=${HS_STATE_DIR:-/var/lib/hs}
lang=${HS_LANG:-$(setting_get language 2>/dev/null || echo en)}

usage() {
  say "usage: hs ext list"
  say "       hs ext enable <package>"
  say "       hs ext disable <package>"
  say "       hs ext <package>"
  say "       hs ext status | start <package> | stop <package>"
  exit 1
}

script_file() { case "$1" in /*) printf '%s' "$1" ;; *) printf '%s' "$here/$1" ;; esac; }
manifest() {   # manifest <dir> <key>: a plain string of capability.toml (package.toml for a recipe)
  local f=$1/capability.toml
  [ -f "$f" ] || f=$1/package.toml
  sed -n "s/^$2[[:space:]]*=[[:space:]]*\"\(.*\)\"[[:space:]]*$/\1/p" "$f" | head -n1
}
manifest_list() {   # manifest_list <dir> <key>: the names of a one-line array `key = ["a", "b"]`, one per line
  local f=$1/capability.toml
  [ -f "$f" ] || f=$1/package.toml
  sed -n "s/^$2[[:space:]]*=[[:space:]]*\[\(.*\)\][[:space:]]*\$/\1/p" "$f" | head -n1 | tr ',' '\n' | tr -d ' "'"'"'' | sed '/^$/d'
}
perms_of() {   # perms_of <name>: the declared permissions, comma separated; "not declared" when the manifest has none (ADR 0014: shown, not enforced)
  local out
  out=$(python3 "$here/pkg.py" perms "$1" 2>/dev/null) || out=-
  if [ "$out" = "-" ]; then t "not declared"; elif [ -z "$out" ]; then t "none"; else printf '%s' "$out" | paste -sd, - | sed 's/,/, /g'; fi
}
core_level() { cat "$here/lib/api-level" 2>/dev/null || echo 0; }
compat_problem() {   # compat_problem <name> <dir>: prints why the package cannot be switched on (a capability it requires is off, or it needs a newer core); nothing when fine
  local r need
  need=$(manifest "$2" requires_core | sed -n 's/^>=[[:space:]]*\([0-9][0-9]*\)$/\1/p')
  if [ -n "$need" ] && [ "$need" -gt "$(core_level)" ]; then
    t "needs core API level %s, this server has %s (hs update first)" "$need" "$(core_level)"; return 0
  fi
  while IFS= read -r r; do
    capability_on "$r" || { t "needs the capability '%s', which is off" "$r"; return 0; }
  done < <(manifest_list "$2" requires)
  return 0
}
dependents_on() {   # dependents_on <name>: the packages that are on and require it, one per line
  local n d
  while IFS= read -r n; do
    [ "$n" != "$1" ] || continue
    d=$(ext_package_dir "$n") || continue
    [ -f "$d/capability.toml" ] || continue
    ext_package_on "$n" || continue
    manifest_list "$d" requires | grep -qxF -- "$1" && printf '%s\n' "$n"
  done < <(ext_package_names)
  return 0
}
title_of() {   # title_of <dir>
  local t=""
  [ "$lang" = en ] || t=$(manifest "$1" "title_$lang")
  [ -n "$t" ] || t=$(manifest "$1" title)
  printf '%s' "$t"
}
has_nix() { [ -f "$1/module.nix" ]; }
n_commands() {   # n_commands <name>: user commands of the package
  registry_rows_of "$1" | awk -F'\t' '$1 == "user" { n++ } END { print n + 0 }'
}
exists() {   # exists <name>: a package of this server
  [[ "${1:-}" =~ ^[a-z][a-z0-9-]{0,30}$ ]] || return 1
  ext_package_names | grep -qxF -- "$1"
}
is_recipe() {   # is_recipe <name>: a recipe package (it is applied with hs recipe, not switched with hs ext enable)
  local d; d=$(ext_package_dir "$1") || return 1
  [ ! -f "$d/capability.toml" ]
}
need_package() {
  exists "${1:-}" || fail_fix "$(t "No extension called '%s'" "${1:-}")" "hs ext list"
}

# Services (ADR 0011): the unit hs-ext-svc@<name>.service of configuration.nix runs `hs ext svc-run <name>`.
svc_state=$state/ext-svc
svc_py() { python3 "$here/lib/ext_service.py" "$@"; }
ctl() { "${HS_SYSTEMCTL:-systemctl}" "$@"; }
has_service() { local d; d=$(ext_package_dir "$1") || return 1; svc_py has-service "$d"; }
need_service() {
  need_package "${1:-}"
  has_service "$1" || fail_fix "$(t "The extension '%s' has no service." "$1")" "hs ext $1"
  ext_package_on "$1" || fail_fix "$(t "The extension '%s' is off." "$1")" "hs ext enable $1"
}
svc_rows() {   # name, state, reason, since of every package that is on and has a service
  local n act stopped
  while IFS= read -r n; do
    ext_package_on "$n" && has_service "$n" || continue
    act=no; ctl is-active --quiet "hs-ext-svc@$n.service" 2>/dev/null && act=yes
    stopped=no; [ ! -e "$svc_state/$n.stopped" ] || stopped=yes
    printf '%s	%s
' "$n" "$(svc_py status --name "$n" --state-dir "$svc_state" --active "$act" --stopped "$stopped")"
  done < <(ext_package_names)
}
confine_dir=${HS_CONFINE_DIR:-/run/systemd/system}   # where the drop-ins of hs-ext-svc@<name>.service go (runtime only: gone at reboot, rewritten at every start)
svc_confine() {   # svc_confine <name>: check the permissions of the package (scripts/lib/ext_confine.py); refuses a path that is not allowed.
  # The unit itself is NOT confined (the bridge writes state.db, snapshots and cursors): the bridge runs the service as a transient confined unit.
  local perms=() dir
  mapfile -t perms < <(python3 "$here/pkg.py" perms "$1" 2>/dev/null || echo -)
  dir=$confine_dir/hs-ext-svc@$1.service.d
  if [ -e "$dir/10-confine.conf" ]; then   # a drop-in of an older version would confine the bridge too: remove it, reload, restart a running bridge
    rm -f "$dir/10-confine.conf"
    ctl daemon-reload >/dev/null 2>&1 || true
    if ctl is-active --quiet "hs-ext-svc@$1.service" 2>/dev/null; then
      ctl restart --no-block "hs-ext-svc@$1.service" >/dev/null 2>&1 || true
      note "$(t "The service of '%s' restarts once: an older version of the core had confined its supervisor." "$1")"
    fi
  fi
  python3 -I "$here/lib/ext_confine.py" dropin --name "$1" -- "${perms[@]}" >/dev/null || return 1
  if [ "${perms[0]:-}" = "-" ]; then
    warn "$(t "'%s' does not declare permissions: its service gets the strict defaults and may write nothing but its own state." "$1")"
  fi
}
svc_start() {   # svc_start <name> [--no-block]: confine, forget an old failure and start the unit
  svc_confine "$1" || { warn "$(t "The confinement of '%s' could not be written, so its service is not started." "$1")"; return 1; }
  rm -f "$svc_state/$1.stopped"
  svc_py reset --name "$1" --state-dir "$svc_state"
  ctl reset-failed "hs-ext-svc@$1.service" >/dev/null 2>&1 || true
  ctl start ${2:+"$2"} "hs-ext-svc@$1.service"
}

cmd_status() {
  local rows
  rows=$(svc_rows)
  if [ -z "$rows" ]; then note "No service extension is on."; return 0; fi
  { thead 'Package' 'State' 'Why' 'Since'; printf '%s
' "$rows" | awk -F'	' -v OFS='	' '{ w = ($3 == "-" ? "" : $3); s = $4; if (s != "-") { c = "date -d @" s " +\"%Y-%m-%d %H:%M\""; c | getline s; close(c) } else s = ""; print $1, $2, w, s }'; } | table
}
cmd_start() {
  need_service "${1:-}"
  svc_start "$1" || fail "$(t "The service of '%s' did not start." "$1")"
  ok "$(t "The service of '%s' is started." "$1")"
  next_step "hs ext status"
}
cmd_stop() {
  need_service "${1:-}"
  mkdir -p "$svc_state"; : > "$svc_state/$1.stopped"
  ctl stop "hs-ext-svc@$1.service" || fail "$(t "The service of '%s' did not stop." "$1")"
  ok "$(t "The service of '%s' is stopped. It stays stopped until: hs ext start %s" "$1" "$1")"
}
cmd_svc_run() {   # run by the unit; exec so that systemd's signals reach the supervisor
  local n=${1:-} d name path prov first= cred=() perm listing=
  exists "$n" && ext_package_on "$n" && has_service "$n" || { printf '%s
' "hs ext svc-run: '$n' is not a service extension that is on" >&2; exit 1; }
  d=$(ext_package_dir "$n")
  # the keys of the declared integration:<name> permissions go to the service as systemd credentials (never argv or environment)
  # one per keyed provider: integration-<name>-<provider> (hobnix/core#1135). The old integration-<name> (the first provider) stays for one release (deprecated).
  while IFS=$'	' read -r name path prov; do
    cred+=(--credential "integration-$name-$prov=$prov=$path")
    case " $first " in *" $name "*) ;; *) first="$first $name"; cred+=(--credential "integration-$name=$prov=$path") ;; esac
  done < <(integration_credentials "$n")
  # the rows of the declared integrations go into `init` (a confined service cannot run hs): what `hs sys pkg integrations <name>` prints, no keys.
  # The bridge keeps only the integrations the package declared; the rows hold no secret, so argv is fine here.
  while IFS= read -r perm; do
    case "$perm" in integration:*) listing+=$(bash "$here/pkg.sh" --integrations "${perm#integration:}" 2>/dev/null)$'
' ;; esac
  done < <(python3 "$here/pkg.py" perms "$n" 2>/dev/null)
  exec python3 "$here/lib/ext_service.py" svc-run --name "$n" --dir "$d" --state-dir "$svc_state" --integrations "$listing" ${cred[@]+"${cred[@]}"}
}

overlay_add() { mkdir -p "$state"; grep -qxF -- "$2" "$state/capabilities-$1" 2>/dev/null || printf '%s\n' "$2" >> "$state/capabilities-$1"; }
overlay_del() {
  [ -f "$state/capabilities-$1" ] || return 0
  grep -vxF -- "$2" "$state/capabilities-$1" > "$state/capabilities-$1.tmp" || true
  mv "$state/capabilities-$1.tmp" "$state/capabilities-$1"
}

caps_list() {   # the names in machine.toml `capabilities`, one per line
  machine_has capabilities || return 0
  machine_get capabilities 2>/dev/null || true
}
caps_write() {   # caps_write <name>...: the list back as a TOML array
  local v="" n
  for n in "$@"; do v+="${v:+, }\"$n\""; done
  machine_set capabilities "[$v]" ext
}

cmd_list() {   # people list
  local n d st rows=""
  while IFS= read -r n; do
    d=$(ext_package_dir "$n") || continue
    [ -f "$d/capability.toml" ] || continue
    if ext_package_on "$n"; then st=on; else st=off; fi
    rows+="$n"$'\t'"$st"$'\t'"$(n_commands "$n")"$'\t'"$(title_of "$d")"$'\t'"$(perms_of "$n")"$'\n'
  done < <(ext_package_names)
  if [ -z "$rows" ]; then note "No extension packages on this server."; return 0; fi
  { thead 'Package' 'State' 'Commands' 'What it is' 'Permissions it declares'; printf '%s' "$rows"; } | table
  note "$(t "Permissions are what a package says it needs. They are not enforced: every command runs as root, so install only packages you trust.")"
  next_step "hs ext enable <package>"
}

cmd_data() {   # hs sys ext list
  local n d st
  while IFS= read -r n; do
    d=$(ext_package_dir "$n") || continue
    [ -f "$d/capability.toml" ] || continue
    if ext_package_on "$n"; then st=on; else st=off; fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$n" "$st" "$(n_commands "$n")" "$(has_nix "$d" && echo yes || echo no)" "$(manifest "$d" title)"
  done < <(ext_package_names)
}

cmd_enable() {
  local n=${1:-} d cur=() x found=0 why
  [ -n "$n" ] || usage
  need_package "$n"
  d=$(ext_package_dir "$n")
  if is_recipe "$n"; then fail_fix "$(t "'%s' is a recipe: it is applied, not switched on." "$n")" "hs recipe $n"; fi
  if ext_package_on "$n"; then note "$(t "The extension '%s' is on already." "$n")"; return 0; fi
  why=$(compat_problem "$n" "$d")
  if [ -n "$why" ]; then fail_fix "$(t "'%s' %s." "$n" "$why")" "hs ext list"; fi
  why=$(python3 "$here/pkg.py" perms-check "$d" "$n" 2>&1 | head -n1) || true
  if [ -n "$why" ]; then fail_fix "$(t "'%s' uses more than it declares in permissions: %s" "$n" "$why")" "hs ext list"; fi
  if ! grep -q '^permissions[[:space:]]*=' "$d/package.toml" 2>/dev/null; then
    warn "$(t "'%s' does not declare permissions. Today it still turns on; a later release will refuse it." "$n")"
  fi
  mapfile -t cur < <(caps_list)
  for x in ${cur[@]+"${cur[@]}"}; do [ "$x" != "$n" ] || found=1; done
  if has_nix "$d"; then effect_say rebuild; else effect_say now; fi
  if [ "$found" = 0 ]; then caps_write ${cur[@]+"${cur[@]}"} "$n"; fi
  if has_nix "$d"; then
    ok "$(t "Extension '%s' is in machine.toml." "$n")"
    warn "$(t "It brings a NixOS module: it is on after a rebuild.")"
    next_step "hs rebuild"
  else
    overlay_del off "$n"; overlay_add on "$n"
    if has_service "$n"; then svc_start "$n" --no-block || warn "$(t "The service of '%s' did not start." "$n")"; fi
    ok "$(t "Extension '%s' is on." "$n")"
    next_step "hs ext $n"
  fi
}

cmd_disable() {
  local n=${1:-} d cur=() keep=() x deps found=0
  [ -n "$n" ] || usage
  if ! exists "$n" && [[ "$n" =~ ^[a-z][a-z0-9-]{0,30}$ ]]; then
    # a name that is still switched on but whose package is gone (removed by hand, or moved to another repository): take the leftover out
    mapfile -t cur < <(caps_list)
    for x in ${cur[@]+"${cur[@]}"}; do [ "$x" != "$n" ] || found=1; done
    grep -qxF -- "$n" "$state/capabilities-on" 2>/dev/null && found=1
    if [ "$found" = 1 ]; then
      for x in ${cur[@]+"${cur[@]}"}; do [ "$x" = "$n" ] || keep+=("$x"); done
      if [ ${#keep[@]} -ne ${#cur[@]} ]; then caps_write ${keep[@]+"${keep[@]}"}; fi
      overlay_del on "$n"
      ok "$(t "'%s' is not installed on this server; the leftover switch is out of the settings." "$n")"
      next_step "hs rebuild"
      return 0
    fi
  fi
  need_package "$n"
  d=$(ext_package_dir "$n")
  if is_recipe "$n"; then fail_fix "$(t "'%s' is a recipe: its container is managed with hs ct." "$n")" "hs ct"; fi
  deps=$(dependents_on "$n" | paste -sd' ' -)
  if [ -n "$deps" ]; then fail_fix "$(t "'%s' cannot be switched off: %s needs it." "$n" "$deps")" "hs ext disable ${deps%% *}"; fi
  if has_service "$n"; then ctl stop "hs-ext-svc@$n.service" >/dev/null 2>&1 || true; fi   # a package that is off has no unit running (ADR 0011 rule 3)
  mapfile -t cur < <(caps_list)
  for x in ${cur[@]+"${cur[@]}"}; do [ "$x" = "$n" ] || keep+=("$x"); done
  if has_nix "$d"; then effect_say rebuild; else effect_say now; fi
  if [ ${#keep[@]} -ne ${#cur[@]} ]; then caps_write ${keep[@]+"${keep[@]}"}; fi
  if has_nix "$d"; then
    ok "$(t "Extension '%s' is out of machine.toml." "$n")"
    warn "$(t "It brings a NixOS module: it is off after a rebuild.")"
    next_step "hs rebuild"
  else
    overlay_del on "$n"; overlay_add off "$n"
    ok "$(t "Extension '%s' is off." "$n")"
  fi
}

help_of() {   # help_of <script> <help_en> <help_de>
  local d="" f
  f=$(script_file "$1")
  if [ "$lang" != en ]; then
    d=$3
    [ "$d" != "-" ] || d=$(sed -n "s/^# help\.$lang: //p" "$f" 2>/dev/null | head -n1)
  fi
  if [ -z "$d" ] || [ "$d" = "-" ]; then
    d=$2
    [ "$d" != "-" ] || d=$(sed -n 's/^# help: //p' "$f" 2>/dev/null | head -n1)
  fi
  printf '%s' "$d"
}

cmd_show() {   # cmd_show <name> [<word that is no command>...]
  local n=${1:-} d kind path script args hen hde flags a
  shift || true
  case "$n" in ""|enable|disable|status|start|stop|svc-run) usage ;; esac
  need_package "$n"
  d=$(ext_package_dir "$n")
  if [ $# -gt 0 ] && ! ext_package_on "$n"; then
    if is_recipe "$n"; then warn "$(t "The recipe '%s' has not been applied yet." "$n")"; next_step "hs recipe $n"; exit 1; fi
    warn "$(t "The extension '%s' is off." "$n")"; next_step "hs ext enable $n"; exit 1
  fi
  if [ $# -gt 0 ]; then warn "$(t "No command '%s' in the extension '%s'." "$*" "$n")"; fi
  help_usage "$(t 'usage: hs ext %s <command>' "$n")"
  if ext_package_on "$n"; then status_line "$n" "$(title_of "$d")" ok
  elif is_recipe "$n"; then status_line "$n" "$(title_of "$d") ($(t 'not applied yet'))" warn
  else status_line "$n" "$(title_of "$d") ($(t 'off'))" warn; fi
  help_section "$(t 'commands:')"
  while IFS=$'\t' read -r kind path script args hen hde flags; do
    [ "$kind" = user ] || continue
    a=""
    [ "$hen" != "-" ] || a=$(sed -n 's/^# args: //p' "$(script_file "$script")" 2>/dev/null | head -n1)
    help_item "$path" "$(help_of "$script" "$hen" "$hde")" "$a"
  done < <(registry_rows_of "$n")
  if is_recipe "$n"; then ext_package_on "$n" || next_step "hs recipe $n"
  elif ! ext_package_on "$n"; then next_step "hs ext enable $n"; fi
  [ $# -eq 0 ]
}

# One static unit (hs-ext-boot, configuration.nix) calls this; a package brings its services back with a `sys ext <name> boot` row.
cmd_boot() {
  local n tab=$'	'
  while IFS= read -r n; do
    ext_package_on "$n" || continue
    # a service starts unless a person stopped it; boot does not wait for `ready`
    if has_service "$n" && [ ! -e "$svc_state/$n.stopped" ]; then
      if ctl start --no-block "hs-ext-svc@$n.service" </dev/null >/dev/null 2>&1; then say "$n${tab}service ok"; else say "$n${tab}service failed"; fi
    fi
    registry_rows_of "$n" | awk -F'	' -v p="sys ext $n boot" '$1 == "sys" && $2 == p { f = 1 } END { exit !f }' || continue
    if timeout 60 bash "$here/lib/hs.sh" sys ext "$n" boot </dev/null >/dev/null 2>&1; then say "$n${tab}ok"; else say "$n${tab}failed"; fi
  done < <(ext_package_names)
  return 0
}

verb=${1:-}
[ $# -eq 0 ] || shift
case "$verb" in
  list) cmd_list ;;
  --list) cmd_data ;;
  --status) svc_rows ;;
  status) cmd_status ;;
  start) cmd_start "$@" ;;
  stop) cmd_stop "$@" ;;
  svc-run) cmd_svc_run "$@" ;;
  enable) cmd_enable "$@" ;;
  disable) cmd_disable "$@" ;;
  boot) cmd_boot ;;
  show) cmd_show "$@" ;;
  *) usage ;;
esac
