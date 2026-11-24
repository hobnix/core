#!/usr/bin/env bash
# help: blueprints: ready-made choices for a server, signed in a package repository (list, show, apply; apply only fills what is not set yet)
# help.de: Baupläne: fertige Entscheidungen für einen Server, signiert in einem Paket-Repository (list, show, apply; apply füllt nur, was noch nicht gesetzt ist)
# args: list | show <name> | apply <name> [--dry-run] [--yes]   (--list: the machine-readable list of hs sys blueprint list)
set -euo pipefail
here=$(dirname "$0")
. "$here/lib/ui.sh"
pkg=${HS_PKG:-$here/pkg.sh}
change=${HS_BLUEPRINT_CHANGE:-$here/blueprint-change.sh}

# A blueprint (kind = "blueprint") is a package that is never installed: an ordered list of capabilities, extensions and recipes plus config that is
# filled in where it is not set yet. `apply` shows the plan, asks, and starts ONE background job (blueprint-change.sh), which can take a while.
# Test knobs: those of pkg.sh and blueprint-change.sh, HS_BLUEPRINT_CHANGE (stands in for blueprint-change.sh).
usage() {
  say "usage: hs blueprint list                    the blueprints the repositories offer"
  say "       hs blueprint show <name>             what a blueprint contains and what applying it would do here"
  say "       hs blueprint apply <name> [--dry-run] [--yes]   set up what is missing (asks first, never overwrites)"
  exit 1
}

cmd=${1:-}; shift || true
case "$cmd" in
  --list) bash "$pkg" blueprint list ;;   # hs sys blueprint list: machine-readable, never translated
  list)
    rows=$(bash "$pkg" blueprint list "${hs_lang:-en}")
    [ -n "$rows" ] || { note "No blueprint is offered: the repositories have none, or hs pkg fetch has not read them yet."; exit 0; }
    { thead 'Blueprint' 'For' 'Version' 'Here' 'What'
      awk -F'\t' '{ printf "%s\t%s\t%s\t%s\t%s\n", $1, $4, $3, $6, $7 }' <<<"$rows"
    } | table ;;
  show|apply)
    name=${1:-}; [ -n "$name" ] || usage; shift
    dry=false; yes=false
    for a in "$@"; do
      case "$a" in --dry-run) [ "$cmd" = apply ] || usage; dry=true ;; --yes) [ "$cmd" = apply ] || usage; yes=true ;; *) usage ;; esac
    done
    rc=0; plan=$(bash "$change" plan apply "$name" </dev/null) || rc=$?
    if [ "$rc" != 0 ]; then fail "$(awk -F'\t' '$1 == "reason" { print $2; exit }' <<<"$plan")"; fi
    step "$(awk -F'\t' '$1 == "heading" { print $2; exit }' <<<"$plan")"
    { thead 'Step' 'What' 'Here'
      awk -F'\t' '$1 == "part" { printf "%s\t%s\t%s\n", ($3 == "app" ? "app" : $3), ($4 == "-" ? "" : $4), $6 }' <<<"$plan"
    } | table
    while IFS=$'\t' read -r kind text; do
      case "$kind" in step|note) note "$text" ;; warn) warn "$text" ;; esac
    done < <(awk -F'\t' '$1 == "step" || $1 == "note" || $1 == "warn"' <<<"$plan")
    [ "$cmd" = apply ] || exit 0
    $dry && { note "Dry run: nothing changed."; exit 0; }
    names=(); while IFS= read -r c; do [ -z "$c" ] || names+=("$c"); done < <(awk -F'\t' '$1 == "confirm_name" { print $2 }' <<<"$plan")
    args=()
    if ! $yes; then
      [ -t 0 ] && [ -t 1 ] || fail "Applying a blueprint asks first: run it in a terminal, or add --yes."
      for c in ${names[@]+"${names[@]}"}; do confirm_name "$c" "$(t 'the blueprint or Docker')" || { note "Nothing changed."; exit 0; }; done
      [ ${#names[@]} -gt 0 ] || confirm "$(t 'Apply the blueprint %s now?' "$name")" || { note "Nothing changed."; exit 0; }
    elif [ ${#names[@]} -gt 0 ]; then
      fail "This blueprint asks for a typed name ($(IFS=,; echo "${names[*]}")): run it in a terminal."
    fi
    for c in ${names[@]+"${names[@]}"}; do args+=(--confirm "$c"); done
    rc=0; out=$(bash "$change" start apply "$name" ${args[@]+"${args[@]}"} </dev/null) || rc=$?
    [ "$rc" = 0 ] || fail "$(awk -F'\t' '$1 == "reason" { print $2; exit }' <<<"$out")"
    ok "$(t 'Started as a job: hs job follow %s' "$(awk -F'\t' '$1 == "unit" { print $2; exit }' <<<"$out")")" ;;
  *) usage ;;
esac
