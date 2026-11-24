# shellcheck shell=bash
# Who depends on a package (docs/PLAN-packages.md, #1072). A library sourced by scripts/ext.sh (and later scripts/pkg.sh), not a command:
# it has no registry.tsv row and prints data only.
#
#   pkg_dependents <name>   the packages that are ON and need <name>, one per line. A package needs <name> when its `requires` (a recipe: its
#                           `needs`) names <name>, or names an interface that <name> `provides` and that no OTHER package that is on provides.
#
# The lists are one-line arrays (`requires = ["a", "b"]`) of capability.toml, or package.toml for a recipe.
. "${BASH_SOURCE[0]%/*}/registry-load.sh"

_pd_list() {   # _pd_list <dir> <key>: the names of a one-line array, one per line
  local f=$1/capability.toml
  [ -f "$f" ] || f=$1/package.toml
  [ -f "$f" ] || return 0
  sed -n "s/^$2[[:space:]]*=[[:space:]]*\[\(.*\)\][[:space:]]*\$/\1/p" "$f" | head -n1 | tr ',' '\n' | tr -d ' "'"'"'' | sed '/^$/d'
}

_pd_other_provider() {   # _pd_other_provider <interface> <name> <on...>: true when a package that is on, not <name>, provides the interface
  local w=$1 name=$2 p pd
  shift 2
  for p in "$@"; do
    [ "$p" != "$name" ] || continue
    pd=$(ext_package_dir "$p") || continue
    if _pd_list "$pd" provides | grep -qxF -- "$w"; then return 0; fi
  done
  return 1
}

pkg_dependents() {   # pkg_dependents <name>
  local name=$1 n d w
  local -a names=() on=() provided=()
  mapfile -t names < <(ext_package_names)
  for n in ${names[@]+"${names[@]}"}; do
    if ext_package_on "$n"; then on+=("$n"); fi
  done
  if d=$(ext_package_dir "$name"); then mapfile -t provided < <(_pd_list "$d" provides); fi
  for n in ${on[@]+"${on[@]}"}; do
    [ "$n" != "$name" ] || continue
    d=$(ext_package_dir "$n") || continue
    while IFS= read -r w; do
      if [ "$w" = "$name" ]; then printf '%s\n' "$n"; break; fi
      printf '%s\n' ${provided[@]+"${provided[@]}"} | grep -qxF -- "$w" || continue
      if ! _pd_other_provider "$w" "$name" "${on[@]}"; then printf '%s\n' "$n"; break; fi
    done < <(_pd_list "$d" requires; _pd_list "$d" needs)
  done
  return 0
}
