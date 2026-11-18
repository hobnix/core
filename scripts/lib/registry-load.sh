# shellcheck shell=bash
# The command list as every reader sees it: scripts/lib/registry.tsv (the core) plus the commands.tsv of every ENABLED package
# (docs/PLAN-extensions.md). A package is a folder capabilities/<name>/ (later also /var/lib/hs/packages/<name>@<commit>); it is
# enabled when the capability <name> is on (scripts/lib/capability.sh). The hs dispatcher, `hs help`, completion, docs-build,
# the cheat sheet, smoke, tests/commands.sh and the web allowlists all read the list through registry_rows, never the file.
#
#   registry_rows                   the merged rows (kind path script args help help.de flags), comment lines removed
#   registry_rows_of <name>         the valid rows of ONE package, also while it is off (hs ext <name>)
#   registry_refused [<name>]       the rows a package may not carry, one per line: package TAB line TAB path TAB reason
#   ext_package_names               every package (a folder with commands.tsv or `extension = true`), one per line
#   ext_package_dir <name>          the folder of a package (the ONE place that knows where packages live)
#   ext_package_on <name>           true when the package is enabled
#   ext_core_file                   the core registry file
#
# Rules for the rows of a package (anything else is refused and left out, never loaded):
#   - user rows are `ext <name> <command...>`, sys rows `sys ext <name> <command...>`: the folder name is the namespace, so a package
#     can neither collide with another one nor shadow a core command. `hs ext <name>` alone lists the package, it is not a row.
#   - the script is a path under scripts/ (like the core), or `@/file` = a file inside the package folder (rewritten to the folder).
#     No `..`, no other absolute path.
#   - no rust:<subcommand> script (Rust implementations are core rows, docs/adr/0001-rust-strangler.md).
#   - no `legacy:` flag (the old words of a moved command are rows of the core registry), no second row for the same words.
#   - the names list, enable and disable are reserved (they are the core commands `hs ext list|enable|disable`).
#   - a package whose package.toml says `protocol = [1]` gets the flag `proto` on every row (docs/PLAN-extensions-access.md step 2).
#   - a CAPABILITY package (package.toml kind = "capability", docs/PLAN-capabilities-repo.md, decision O4) that was installed from a DEFAULT
#     repository may also own its name as the first word: user rows `<name> <command...>`, sys rows `sys <name> <command...>`. A row whose
#     first word is also the first word of a core row is refused (no shadowing). Packages from an added repository keep `ext <name>` only.
# Test knobs: HS_REGISTRY (core file), HS_PACKAGES_DIR (the folder that holds the packages; only that one is read).
. "${BASH_SOURCE[0]%/*}/capability.sh"

_ext_lib=$(cd "${BASH_SOURCE[0]%/*}" && pwd)
ext_core_file() { echo "${HS_REGISTRY:-$_ext_lib/registry.tsv}"; }

# The folders that hold packages, in order. On the server the scripts run from a copy in /nix/store that has no capabilities/:
# the checkout in /etc/nixos is the source then. A later /var/lib/hs/packages/<name>@<commit> location is added in ext_package_dir.
_ext_roots() {
  local r
  if [ -n "${HS_PACKAGES_DIR:-}" ]; then echo "$HS_PACKAGES_DIR"; return 0; fi
  # extensions live in capabilities/, recipes in packages/ (a recipe package carries commands.tsv and a page just like an extension)
  local base sub
  base=$(cd "$(dirname "$(ext_core_file)")/../.." 2>/dev/null && pwd)
  for sub in capabilities packages; do
    r=$base/$sub
    [ ! -d "$r" ] || echo "$r"
    if [ -z "${HS_REGISTRY:-}" ] && [ "$r" != "/etc/nixos/$sub" ] && [ -d "/etc/nixos/$sub" ]; then echo "/etc/nixos/$sub"; fi
  done
  # the packages installed from a repository (hs pkg install): a read-only copy per package, written by scripts/pkg_repo.py
  r=${HS_STATE_DIR:-/var/lib/hs}/packages/current
  [ ! -d "$r" ] || echo "$r"
  return 0
}

# A package folder: an extension (capability.toml) or a recipe that brings commands (package.toml with kind = "recipe" and a commands.tsv).
_ext_is_package() { [ -f "$1/capability.toml" ] || { [ -f "$1/package.toml" ] && [ -f "$1/commands.tsv" ] && grep -qE '^kind[[:space:]]*=[[:space:]]*"(recipe|capability)"' "$1/package.toml"; }; }

# A package of the kind capability (no capability.toml, its fields are in package.toml).
_ext_is_cap_package() { [ ! -f "$1/capability.toml" ] && [ -f "$1/package.toml" ] && grep -qE '^kind[[:space:]]*=[[:space:]]*"capability"' "$1/package.toml"; }

# The repository a package was installed from (installed.toml), empty when unknown.
_ext_installed_repo() {
  awk -v sec="[package.$1]" '
    /^\[/ { on = ($0 == sec); next }
    on && /^repo[[:space:]]*=/ { v = $0; sub(/^[^"]*"/, "", v); sub(/".*$/, "", v); print v; exit }'     "${HS_STATE_DIR:-/var/lib/hs}/packages/installed.toml" 2>/dev/null
}

# Is repository <name> one of the default ones (config/package-repos.toml of the checkout)?
_ext_repo_is_default() {
  local f base
  base=$(cd "$(dirname "$(ext_core_file)")/../.." 2>/dev/null && pwd)
  for f in "${HS_PACKAGE_REPOS_FILE:-}" "$base/config/package-repos.toml" /etc/nixos/config/package-repos.toml; do
    [ -n "$f" ] && [ -f "$f" ] || continue
    grep -qxF "name = \"$1\"" "$f" && return 0
    return 1
  done
  return 1
}

# May the package <name> in <dir> own its name as the first command word? Capability kind, installed from a default repository.
_ext_owns_name() {
  local r
  _ext_is_cap_package "$2" || return 1
  r=$(_ext_installed_repo "$1")
  [ -n "$r" ] && _ext_repo_is_default "$r"
}

ext_package_dir() {   # ext_package_dir <name>
  local r
  [[ "${1:-}" =~ ^[a-z][a-z0-9-]{0,30}$ ]] || return 1
  while IFS= read -r r; do
    if _ext_is_package "$r/$1"; then echo "$r/$1"; return 0; fi
  done < <(_ext_roots)
  # later: /var/lib/hs/packages/$1@<pinned commit> (docs/PLAN-extensions.md, "Packages from a repository")
  return 1
}

ext_package_names() {
  local r d n
  while IFS= read -r r; do
    for d in "$r"/*/; do
      _ext_is_package "${d%/}" || continue
      n=$(basename "$d")
      if [ -f "${d}commands.tsv" ] || grep -qE '^extension[[:space:]]*=[[:space:]]*true' "${d}capability.toml" 2>/dev/null; then echo "$n"; fi
    done
  done < <(_ext_roots) | sort -u
}

# An extension is on when its capability is; a recipe package is "on" once the recipe has been applied on this server (installed.toml).
ext_package_on() {
  local d
  d=$(ext_package_dir "$1") || return 1
  if [ -f "$d/capability.toml" ] || _ext_is_cap_package "$d"; then capability_on "$1"; return; fi
  grep -qxF "[package.$1]" "${HS_STATE_DIR:-/var/lib/hs}/packages/installed.toml" 2>/dev/null
}

# Reads one commands.tsv. Valid rows go to stdout, or with report=1 the refused ones as REFUSED TAB line TAB path TAB reason.
_ext_filter() {   # _ext_filter <name> <dir> <report 0|1>
  [ -f "$2/commands.tsv" ] || return 0
  local own=0 proto=0
  ! _ext_owns_name "$1" "$2" || own=1
  # a package that says `protocol = [1]` has its rows run through scripts/lib/ext_proto.py: the row gets the flag `proto` (hs.sh)
  ! grep -qE '^protocol[[:space:]]*=' "$2/package.toml" 2>/dev/null || proto=1
  awk -F'\t' -v OFS='\t' -v name="$1" -v dir="$2" -v report="$3" -v own="$own" -v proto="$proto" '
    NR == FNR {   # the core registry: which first words it uses
      if ($0 ~ /^#/ || $0 ~ /^[ \t\r]*$/) next
      n = split($2, cw, " ")
      if ($1 == "user" && n >= 1) corefirst["user " cw[1]] = 1
      else if ($1 == "sys" && n >= 2) corefirst["sys " cw[2]] = 1
      next
    }
    /^#/ || /^[ \t\r]*$/ { next }
    {
      sub(/\r$/, "")
      kind = $1; path = $2; script = $3; reason = ""
      nw = split(path, w, " ")
      if (name == "list" || name == "enable" || name == "disable") reason = "the name " name " is reserved (hs ext " name ")"
      else if (kind == "user") {
        if (own == 1 && w[1] == name && nw >= 2) { if (("user " name) in corefirst) reason = "the word " name " is also a core command" }
        else if (w[1] != "ext" || w[2] != name || nw < 3) reason = "a user row must be: ext " name " <command>" (own == 1 ? " or " name " <command>" : "")
      }
      else if (kind == "sys")  {
        if (own == 1 && w[1] == "sys" && w[2] == name && nw >= 3) { if (("sys " name) in corefirst) reason = "the word " name " is also a core command" }
        else if (w[1] != "sys" || w[2] != "ext" || w[3] != name || nw < 4) reason = "a sys row must be: sys ext " name " <command>" (own == 1 ? " or sys " name " <command>" : "")
      }
      else reason = "the kind must be user or sys"
      if (reason == "" && NF < 6) reason = "a row has at least 6 columns (kind path script args help help.de)"
      if (reason == "" && (script == "" || script ~ /(^|\/)\.\.(\/|$)/ || (script ~ /^\// ))) reason = "the script must be a path under scripts/ or @/file in the package, without .."
      if (reason == "" && script ~ /^@/ && script !~ /^@\/./) reason = "the script must be a path under scripts/ or @/file in the package, without .."
      if (reason == "" && script ~ /^rust:/) reason = "rust: rows belong to the core registry"
      if (reason == "" && $7 ~ /(^|,)legacy:/) reason = "a legacy: flag belongs to the core registry"
      if (reason == "" && (path in seen)) reason = "the words are used twice"
      if (reason != "") { if (report == 1) print "REFUSED", FNR, path, reason; next }
      seen[path] = 1
      if (report == 1) next
      if (script ~ /^@\//) $3 = dir "/" substr(script, 3)
      if (proto == 1) { $7 = ($7 == "" || $7 == "-") ? "proto" : $7 ",proto"; }
      print
    }' "$(ext_core_file)" "$2/commands.tsv"
}

registry_rows() {
  local n d
  grep -av '^#' "$(ext_core_file)" | tr -d '\r' || true
  while IFS= read -r n; do
    d=$(ext_package_dir "$n") || continue
    [ -f "$d/commands.tsv" ] || continue
    ext_package_on "$n" || continue
    _ext_filter "$n" "$d" 0
  done < <(ext_package_names)
}

registry_rows_of() {   # registry_rows_of <name>
  local d
  d=$(ext_package_dir "$1") || return 1
  _ext_filter "$1" "$d" 0
}

registry_refused() {   # registry_refused [<name>]
  local n d
  while IFS= read -r n; do
    [ -z "${1:-}" ] || [ "$1" = "$n" ] || continue
    d=$(ext_package_dir "$n") || continue
    _ext_filter "$n" "$d" 1 | awk -F'\t' -v OFS='\t' -v n="$n" '{ print n, $2, $3, $4 }'
  done < <(ext_package_names)
}
