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

# Every folder with a manifest counts, not only the ones with a command list: a dependent that has just a package.toml and a `requires` is seen.
_pd_dir() {   # _pd_dir <name>: the folder of a package that has a capability.toml or a package.toml
  local r
  [[ "${1:-}" =~ ^[a-z][a-z0-9-]{0,40}$ ]] || return 1
  while IFS= read -r r; do
    if [ -f "$r/$1/capability.toml" ] || [ -f "$r/$1/package.toml" ]; then echo "$r/$1"; return 0; fi
  done < <(_ext_roots)
  return 1
}

_pd_names() {   # every package folder name, once
  local r d
  while IFS= read -r r; do
    for d in "$r"/*/; do
      [ -f "${d}capability.toml" ] || [ -f "${d}package.toml" ] || continue
      basename "$d"
    done
  done < <(_ext_roots) | sort -u
}

_pd_on() {   # _pd_on <name> <dir>: an extension is on when its capability is; a recipe once it was applied here (installed.toml)
  if [ -f "$2/capability.toml" ] || grep -qE '^kind[[:space:]]*=[[:space:]]*"(capability|extension)"' "$2/package.toml" 2>/dev/null; then capability_on "$1"; return; fi
  grep -qxF "[package.$1]" "${HS_STATE_DIR:-/var/lib/hs}/packages/installed.toml" 2>/dev/null
}

_pd_other_provider() {   # _pd_other_provider <interface> <name> <on...>: true when a package that is on, not <name>, provides the interface
  local w=$1 name=$2 p pd
  shift 2
  for p in "$@"; do
    [ "$p" != "$name" ] || continue
    pd=$(_pd_dir "$p") || continue
    if _pd_list "$pd" provides | grep -qxF -- "$w"; then return 0; fi
  done
  return 1
}

pkg_dependents() {   # pkg_dependents <name>
  local name=$1 n d w
  local -a names=() on=() provided=()
  mapfile -t names < <(_pd_names)
  for n in ${names[@]+"${names[@]}"}; do
    d=$(_pd_dir "$n") || continue
    if _pd_on "$n" "$d"; then on+=("$n"); fi
  done
  if d=$(_pd_dir "$name"); then mapfile -t provided < <(_pd_list "$d" provides); fi
  for n in ${on[@]+"${on[@]}"}; do
    [ "$n" != "$name" ] || continue
    d=$(_pd_dir "$n") || continue
    while IFS= read -r w; do
      if [ "$w" = "$name" ]; then printf '%s\n' "$n"; break; fi
      printf '%s\n' ${provided[@]+"${provided[@]}"} | grep -qxF -- "$w" || continue
      if ! _pd_other_provider "$w" "$name" "${on[@]}"; then printf '%s\n' "$n"; break; fi
    done < <(_pd_list "$d" requires; _pd_list "$d" needs)
  done
  return 0
}
