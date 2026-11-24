# shellcheck shell=bash
# The resolver of "install these packages and switch them on": what a package requires goes in front of it (installed, or switched on when it is a part
# already). Sourced by scripts/pkg-bundle.sh (hs sys pkg bundle) and scripts/blueprint-change.sh (hs sys blueprint), so both plan the same way.
# The caller sets (before visit): refuse() (prints status/reason and exits 1), caps (pkg.sh --capabilities), repos (pkg.sh --repos), plist (parts.sh --list),
# mcaps (the capabilities of machine.toml, one per line). `visit <name> ""` fills inst (to install), en (to switch on) and why (notes), in order.
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
