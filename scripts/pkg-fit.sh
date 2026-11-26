#!/usr/bin/env bash
# help: does an app that is not installed yet fit this server? what its package states it needs, next to the memory, the disk space and the devices here
# help.de: passt eine noch nicht installierte App auf diesen Server? was ihr Paket als Bedarf angibt, neben Arbeitsspeicher, Plattenplatz und Geräten hier
# args: (none)
# System command (hs sys pkg fit): reads only, tab separated, one line per package, repository and check, for the apps (recipes) of `pkg --market`
# in state new or waits (an installed app already uses what it needs: no line):
#   name, repo, verdict, check, level, need, have, total
# verdict (the same on every line of a package and repository, the first that applies):
#   no        a check says no
#   unknown   memory or disk could not be compared (the manifest or the server fact could not be read)
#   unstated  the package states neither memory nor disk: never "fits"
#   note      fits, with at least one note
#   fits
# check and level (ok|note|no|unstated|unknown):
#   core      only for state waits: no
#   memory    need = declared ([app.uses] ram_mb) in bytes, have = available now, total = all memory (/proc/meminfo; ZFS cache counts as used there).
#             no: more than the server has at all; note: more than is available now
#   disk      need = declared (disk_gb) in bytes, have/total = free and total of the Incus storage pool of the default profile's root disk (where
#             a new container's disk goes; files on shares are not counted). no: more than is free
#   gpu       only when the package says it uses one (never "no": it is optional); have = nvidia|other|none, - = could not be told. ok only with an
#             NVIDIA card (the one the recipe helper passes into a container)
#   share     need = share: always ok (the manifest names no share; the app uses an existing one or makes its default one)
#   docker, tailscale   have = present|missing|-; note: the install job sets it up
#   need      any other word of `needs`: no (hs sys apps refuses to install it); need = the word
# A number or word that is not known is -.
# Test knobs: HS_PKG (pkg.sh), HS_PARTS (parts.sh), HS_CT_POOLS (ct-pools.sh), HS_INCUS, HS_PROC. Disk and GPU need jq.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
pkg=${HS_PKG:-$here/pkg.sh}
parts=${HS_PARTS:-$here/parts.sh}
pools=${HS_CT_POOLS:-$here/ct-pools.sh}
incus=${HS_INCUS:-incus}

# the apps there is something to check for: name TAB repo TAB state
open=$(bash "$pkg" --market </dev/null | awk -F'\t' '$2 == "recipe" && ($6 == "new" || $6 == "waits") { print $1 "\t" $3 "\t" $6 }') || exit 1
[ -n "$open" ] || exit 0
cards=$(bash "$pkg" --cards </dev/null) || exit 1

num() { [[ "$1" =~ ^[0-9]{1,18}$ ]] && printf '%s' "$((10#$1))" || printf -- '-'; }

# ── the facts of this server, once ──
read -r mt ma < <(awk '$1 == "MemTotal:" { t = $2 } $1 == "MemAvailable:" { a = $2 } END { if (t != "" && a != "") printf "%.0f %.0f\n", t * 1024, a * 1024; else print "- -" }' \
  "${HS_PROC:-/proc}/meminfo" 2>/dev/null || echo "- -")
mt=$(num "${mt:--}"); ma=$(num "${ma:--}")

dfree=- dtotal=- gpu=-
if command -v jq >/dev/null 2>&1; then
  root_pool=$("$incus" query /1.0/profiles/default </dev/null 2>/dev/null |
    jq -r '[.devices[]? | select(.type == "disk" and .path == "/") | .pool][0] // empty' 2>/dev/null) || root_pool=
  if [ -n "$root_pool" ]; then
    row=$(bash "$pools" </dev/null 2>/dev/null | awk -F'\t' -v p="$root_pool" '$1 == p { print $4 " " $5; exit }') || row=
    read -r a b <<<"${row:-- -}"; dfree=$(num "$a"); dtotal=$(num "$b")
  fi
  gpu=$("$incus" query /1.0/resources </dev/null 2>/dev/null | jq -r 'if (.gpu | type) != "object" then "-"
    elif any(.gpu.cards[]?; .driver == "nvidia") then "nvidia" elif ((.gpu.cards // []) | length) > 0 then "other" else "none" end' 2>/dev/null) || gpu=-
  [[ "$gpu" =~ ^(nvidia|other|none)$ ]] || gpu=-
fi
# docker: the container of the core recipe docker, as hs sys apps asks; `incus list` tells "not there" from "incus does not answer"
docker=-
if names=$("$incus" list -f csv -c n </dev/null 2>/dev/null); then
  if grep -qx docker <<<"$names"; then docker=present; else docker=missing; fi
fi
tailscale=-
if list=$(bash "$parts" --list </dev/null 2>/dev/null); then
  if awk -F'\t' '$1 == "tailscale" && $2 == "on" { f = 1 } END { exit !f }' <<<"$list"; then tailscale=present; else tailscale=missing; fi
fi

# ── the comparison ──
rows=() lv=()
add() { rows+=("$1"$'\t'"$2"$'\t'"$3"$'\t'"$4"$'\t'"$5"); lv+=("$2"); }   # check level need have total

while IFS=$'\t' read -r name repo state; do
  [ -n "$name" ] || continue
  line=$(awk -F'\t' -v n="$name" -v r="$repo" '$1 == n && $2 == r { print; exit }' <<<"$cards")
  IFS=$'\t' read -r _ _ _ _ _ needs ram disk usesgpu <<<"$line"
  needs=${needs:-?} ram=${ram:-?} disk=${disk:-?}
  rows=() lv=()
  [ "$state" != waits ] || add core no - - -

  mneed=- level=unstated
  if [ "$ram" = '?' ]; then level=unknown
  elif [ "$(num "$ram")" != - ]; then
    mneed=$(( $(num "$ram") * 1048576 ))
    if [ "$mt" = - ] || [ "$ma" = - ]; then level=unknown
    elif [ "$mneed" -gt "$mt" ]; then level=no
    elif [ "$mneed" -gt "$ma" ]; then level=note
    else level=ok; fi
  fi
  add memory "$level" "$mneed" "$ma" "$mt"; mlevel=$level

  dneed=- level=unstated
  if [ "$disk" = '?' ]; then level=unknown
  elif [ "$(num "$disk")" != - ]; then
    dneed=$(( $(num "$disk") * 1073741824 ))
    if [ "$dfree" = - ]; then level=unknown
    elif [ "$dneed" -gt "$dfree" ]; then level=no
    else level=ok; fi
  fi
  add disk "$level" "$dneed" "$dfree" "$dtotal"; dlevel=$level

  if [ "${usesgpu:-}" = yes ]; then
    if [ "$gpu" = nvidia ]; then add gpu ok - "$gpu" -; else add gpu note - "$gpu" -; fi
  fi

  if [ "$needs" != - ] && [ "$needs" != '?' ]; then
    IFS=, read -ra words <<<"$needs"
    for w in "${words[@]}"; do
      case "$w" in
        share) add share ok share - - ;;
        docker|tailscale)
          have=$docker; [ "$w" = docker ] || have=$tailscale
          if [ "$have" = present ]; then add "$w" ok "$w" "$have" -
          elif [ "$have" = missing ]; then add "$w" note "$w" "$have" -
          else add "$w" unknown "$w" - -; fi ;;
        *) add need no "$w" - - ;;
      esac
    done
  fi

  all=" ${lv[*]} "
  if [[ "$all" == *' no '* ]]; then verdict=no
  elif [ "$mlevel" = unknown ] || [ "$dlevel" = unknown ]; then verdict=unknown
  elif [ "$mlevel" = unstated ] && [ "$dlevel" = unstated ]; then verdict=unstated
  elif [[ "$all" == *' note '* ]] || [[ "$all" == *' unknown '* ]]; then verdict=note
  else verdict=fits; fi
  for row in "${rows[@]}"; do printf '%s\t%s\t%s\t%s\n' "$name" "$repo" "$verdict" "$row"; done
done <<<"$open"
