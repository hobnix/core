#!/usr/bin/env bash
# help: the optional parts (capabilities) of this server as data: which are on, which bring a NixOS module
# help.de: die optionalen Teile (Capabilities) dieses Servers als Daten: welche an sind, welche ein NixOS-Modul mitbringen
# args: --list|--pending
# System command (hs sys parts list), read only, for the Settings page of the web interface (part switches). One part per line, tab separated, no empty field:
#   name, state (on|off), kind (extension|part), nix (yes = switching it needs hs rebuild), switch (yes = machine.toml can switch it; no = it follows the role or an old
#   setting), title. A part is `extension` when its capability.toml says extension = true (hs ext enable|disable switches it at once when it has no module).
# --pending (hs sys parts pending): the parts switched on in machine.toml and not built yet, one per line, sorted: name<TAB>on. Empty output: nothing waits.
# A capability package (package.toml kind = "capability", installed into packages/current) is a part too.
# Test knobs: HS_PACKAGES_DIR, HS_CAPABILITIES_FILE, HS_STATE_DIR, HS_MACHINE_FILE.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib/registry-load.sh"

mode=${1:-}
case "$mode" in --list|--pending) ;; *) echo "usage: parts.sh --list|--pending" >&2; exit 1 ;; esac

title_of() { sed -n 's/^title[[:space:]]*=[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$1" | head -n 1; }

if [ "$mode" = --pending ]; then
  . "$here/lib/machine.sh"
  caps=""
  if machine_has capabilities; then caps=$(machine_get capabilities 2>/dev/null || true); fi
  built=$(cat "$(capability_file)" 2>/dev/null || true)
  declare -A pseen=()
  while IFS= read -r root; do
    for d in "$root"/*/; do
      if [ ! -f "${d}module.nix" ]; then
        { _ext_is_cap_package "${d%/}" && grep -qE '^module[[:space:]]*=' "${d}package.toml"; } || continue
      fi
      n=$(basename "$d")
      [[ "$n" =~ ^[a-z][a-z0-9-]{0,30}$ ]] || continue
      case "$n" in edge-*) continue ;; esac
      [ -z "${pseen[$n]:-}" ] || continue
      pseen[$n]=1
      if grep -qxF -- "$n" <<<"$caps" && ! grep -qxF -- "$n" <<<"$built"; then printf '%s	on
' "$n"; fi
    done
  done < <(_ext_roots) | sort
  exit 0
fi

declare -A seen=()
while IFS= read -r root; do
  for d in "$root"/*/; do
    if [ -f "${d}capability.toml" ]; then mf="${d}capability.toml"; elif _ext_is_cap_package "${d%/}"; then mf="${d}package.toml"; else continue; fi
    n=$(basename "$d")
    [[ "$n" =~ ^[a-z][a-z0-9-]{0,30}$ ]] || continue
    [ -z "${seen[$n]:-}" ] || continue
    seen[$n]=1
    if capability_on "$n"; then st=on; else st=off; fi
    if grep -qE '^extension[[:space:]]*=[[:space:]]*true' "$mf" 2>/dev/null; then kind=extension; else kind=part; fi
    if [ -f "${d}module.nix" ] || grep -qE '^module[[:space:]]*=' "$mf" 2>/dev/null; then nix=yes; else nix=no; fi
    # the edge parts follow the role; they are not switched here
    case "$n" in edge-*) sw=no ;; *) sw=yes ;; esac
    t=$(title_of "$mf"); [ -n "$t" ] || t=$n
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$n" "$st" "$kind" "$nix" "$sw" "${t//$'\t'/ }"
  done
done < <(_ext_roots) | sort
