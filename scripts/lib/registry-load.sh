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
#   - the names list, enable, disable, status, start, stop and svc-run are reserved (they are core commands of `hs ext`).
#   - a sys row with the word `start` needs its twin with `plan` in the same file (`sys x start y` needs `sys x plan y`): the plan shows
#     what changes first. The typed name of a destructive command stays a review rule (#1072).
#   - a package whose package.toml says `protocol = [1]` gets the flag `proto` on every row (docs/PLAN-extensions-access.md step 2).
#   - a CAPABILITY package (package.toml kind = "capability", docs/PLAN-capabilities-repo.md, decision O4) that was installed from a DEFAULT
#     repository may also own its name as the first word: user rows `<name> <command...>`, sys rows `sys <name> <command...>`. A row whose
#     first word is also the first word of a core row is refused (no shadowing). Packages from an added repository keep `ext <name>` only.
#   - `words = ["edge"]` in capability.toml / package.toml: extra first words the package owns (rows `edge <command...>`, `sys edge <command...>`),
#     so a command keeps its name when it moves into the package. Allowed for an in-tree capability.toml folder and for a capability package of
#     a default repository; refused when a core row or another package uses the word (docs/PLAN-packages.md, #1072).
# Test knobs: HS_REGISTRY (core file), HS_PACKAGES_DIR (the folder that holds the packages; only that one is read).
. "${BASH_SOURCE[0]%/*}/capability.sh"

_ext_lib=$(cd "${BASH_SOURCE[0]%/*}" && pwd)
unset _ix_base   # only _ext_with_index sets it, never the environment
ext_core_file() { echo "${HS_REGISTRY:-$_ext_lib/registry.tsv}"; }

_ext_base() {   # the checkout the core registry file belongs to (empty when it cannot be entered)
  local f
  f=$(ext_core_file)
  case "$f" in */*) f=${f%/*} ;; *) f=. ;; esac
  (cd "$f/../.." 2>/dev/null && pwd) || true
}

# The folders that hold packages, in order. On the server the scripts run from a copy in /nix/store that has no capabilities/:
# the checkout in /etc/nixos is the source then. A later /var/lib/hs/packages/<name>@<commit> location is added in ext_package_dir.
_ext_roots() {
  local r
  if [ -n "${HS_PACKAGES_DIR:-}" ]; then echo "$HS_PACKAGES_DIR"; return 0; fi
  # extensions live in capabilities/, recipes in packages/ (a recipe package carries commands.tsv and a page just like an extension)
  local base sub
  base=${_ix_base:-$(_ext_base)}
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

# The package index of ONE call. The words and manifest facts of every package are needed to judge one (a word may be used by only one
# package), so they are read once: one awk over all manifests and installed.toml, not one walk over all packages per word.
# It is never kept: _ext_with_index declares the arrays `local`, so they are gone when the public call returns, and the next call
# reads the disk again (a shell that installs or stages packages, or changes HS_*, cannot see an old state). No cache file.
#   _ix_names                every package (what ext_package_names prints)   _ix_dir[name]     its folder
#   _ix_id[manifest file]    the number of the file in the scan              _ix_fact[id tag]  recipe, cap, extension, protocol
#   _ix_words[id]            the words the file declares                     _ix_sec[line]     a [table] line of installed.toml
#   _ix_repo[line]           the repo of that table                          _ix_claim[word]   who has the word, in name order
_ext_with_index() {   # _ext_with_index <staged folder or -> <function> [args]: run it with a fresh index
  local extra=$1
  shift
  local _ix_core _ix_base="" _ix_claimed=0 _ix_ret=""
  local -a _ix_names=()
  local -A _ix_dir=() _ix_id=() _ix_fact=() _ix_words=() _ix_sec=() _ix_repo=() _ix_claim=() _ix_def=()
  _ix_core=$(ext_core_file)
  _ix_base=$(_ext_base)
  # a package that is replaced while it is read makes awk fail: read once more, then it is a failure (never "no packages")
  _ext_index "$extra" || _ext_index "$extra" || return 1
  "$@"
}

_ext_index() {   # _ext_index <staged folder or ->: fill the arrays of _ext_with_index
  local r d f n out line tag id=0 names=""
  local -a roots=() found=() scan=() args=()
  _ix_id=() _ix_fact=() _ix_words=() _ix_sec=() _ix_repo=() _ix_dir=() _ix_names=()
  mapfile -t roots < <(_ext_roots)
  for r in ${roots[@]+"${roots[@]}"}; do
    for d in "$r"/*/; do
      d=${d%/}
      [ -f "$d/capability.toml" ] || { [ -f "$d/package.toml" ] && [ -f "$d/commands.tsv" ]; } || continue
      found+=("$d")
    done
  done
  scan=(${found[@]+"${found[@]}"})
  [ "$1" = - ] || scan+=("$1")
  for d in ${scan[@]+"${scan[@]}"}; do
    for f in "$d/capability.toml" "$d/package.toml"; do
      [ -f "$f" ] && [ -r "$f" ] && [ -z "${_ix_id[$f]:-}" ] || continue
      id=$((id + 1)); _ix_id[$f]=$id
      case "$f" in /*) args+=("_i=$id" "$f") ;; *) args+=("_i=$id" "./$f") ;; esac   # a path is never read as an awk assignment
    done
  done
  f=${HS_STATE_DIR:-/var/lib/hs}/packages/installed.toml
  if [ -f "$f" ] && [ -r "$f" ]; then
    case "$f" in /*) args+=("_i=0" "$f") ;; *) args+=("_i=0" "./$f") ;; esac
  fi
  if [ "${#args[@]}" -gt 0 ]; then
    out=$(awk '
      FNR == 1 { sec = "" }
      _i == 0 {   # installed.toml: its [table] lines, and the first repo line of each
        if (/^\[/) { sec = $0; if (!index(sec, "\t")) print 0 "\tsec\t" sec }
        else if (sec != "" && !index(sec, "\t") && !(sec in got) && /^repo[[:space:]]*=/) { got[sec] = 1; v = $0; sub(/^[^"]*"/, "", v); sub(/".*$/, "", v); print 0 "\trepo\t" sec "\t" v }
        next
      }
      /^kind[[:space:]]*=[[:space:]]*"recipe"/ { print _i "\trecipe" }
      /^kind[[:space:]]*=[[:space:]]*"capability"/ { print _i "\tcap" }
      /^extension[[:space:]]*=[[:space:]]*true/ { print _i "\textension" }
      /^protocol[[:space:]]*=/ { print _i "\tprotocol" }
      /^words[[:space:]]*=/ {
        s = $0
        while (match(s, /"[a-z][a-z0-9-]*"/)) {
          v = substr(s, RSTART + 1, RLENGTH - 2); s = substr(s, RSTART + RLENGTH)
          if (v != "ext" && v != "sys") print _i "\tword\t" v
        }
      }' "${args[@]}" < /dev/null) || return 1
    if [ -n "$out" ]; then
      while IFS= read -r line; do
        n=${line%%$'\t'*}; line=${line#*$'\t'}; tag=${line%%$'\t'*}; line=${line#*$'\t'}
        case "$tag" in
          sec) _ix_sec[$line]=1 ;;
          repo) _ix_repo[${line%%$'\t'*}]=${line#*$'\t'} ;;
          word) _ix_words[$n]+=" $line" ;;
          *) _ix_fact["$n $tag"]=1 ;;
        esac
      done <<< "$out" || return 1
    fi
  fi
  for d in ${found[@]+"${found[@]}"}; do
    if [ ! -f "$d/capability.toml" ]; then _ext_fact "$d/package.toml" recipe || _ext_fact "$d/package.toml" cap || continue; fi
    n=${d##*/}
    [ -n "${_ix_dir[$n]:-}" ] || _ix_dir[$n]=$d   # the first root wins (ext_package_dir)
    if [ -f "$d/commands.tsv" ] || _ext_fact "$d/capability.toml" extension; then names+=$n$'\n'; fi
  done
  [ -n "$names" ] || return 0
  out=$(printf '%s' "$names" | sort -u) || return 1
  mapfile -t _ix_names <<< "$out" || return 1
}

_ext_fact() {   # _ext_fact <manifest file> <tag>: true when the scan saw it
  local id=${_ix_id[$1]:-}
  [ -n "$id" ] && [ -n "${_ix_fact["$id $2"]:-}" ]
}

# Is repository <name> one of the default ones (config/package-repos.toml of the checkout)? Asked once per repository and call.
_ext_repo_is_default() {   # inside _ext_with_index
  local f
  if [ -z "${_ix_def[$1]:-}" ]; then
    _ix_def[$1]=no
    for f in "${HS_PACKAGE_REPOS_FILE:-}" "$_ix_base/config/package-repos.toml" /etc/nixos/config/package-repos.toml; do
      [ -n "$f" ] && [ -f "$f" ] || continue
      ! grep -qxF "name = \"$1\"" "$f" || _ix_def[$1]=yes
      break
    done
  fi
  [ "${_ix_def[$1]}" = yes ]
}

# The first words package <name> in <dir> owns beyond `ext <name>`, into _ix_ret (a word may repeat): its own name when it is a
# capability package installed from a default repository, and its `words = ["a", "b"]` (capability.toml, else package.toml).
# `words` count for an in-tree folder (capability.toml) and for a capability package of a default repository.
_ext_owned_words() {   # _ext_owned_words <name> <dir>, inside _ext_with_index
  local r="" f id own=0
  _ix_ret=""
  if [ ! -f "$2/capability.toml" ] && _ext_fact "$2/package.toml" cap; then
    # the repository it was installed from (installed.toml); HS_STAGE_*: a package being checked before it is installed
    if [ "${HS_STAGE_PKG:-}" = "$1" ] && [ -n "${HS_STAGE_REPO:-}" ]; then r=$HS_STAGE_REPO; else r=${_ix_repo["[package.$1]"]:-}; fi
    if [ -n "$r" ] && _ext_repo_is_default "$r"; then own=1; _ix_ret=$1; fi
  fi
  if [ -f "$2/capability.toml" ] || [ "$own" = 1 ]; then
    f=$2/capability.toml
    [ -f "$f" ] || f=$2/package.toml
    id=${_ix_id[$f]:-}
    [ -z "$id" ] || _ix_ret+=${_ix_words[$id]:-}
    _ix_ret=${_ix_ret# }
  fi
  return 0
}

# Who has which word: every package has its name and the words it owns. Built once, when the first package that owns a word is read.
_ext_claims() {   # inside _ext_with_index
  local n d w
  [ "$_ix_claimed" = 0 ] || return 0
  _ix_claimed=1
  for n in ${_ix_names[@]+"${_ix_names[@]}"}; do
    _ix_claim[$n]+=" $n"
    [[ "$n" =~ ^[a-z][a-z0-9-]{0,30}$ ]] && d=${_ix_dir[$n]:-} && [ -n "$d" ] || continue
    _ext_owned_words "$n" "$d"
    for w in $_ix_ret; do
      [[ " ${_ix_claim[$w]:-} " == *" $n "* ]] || _ix_claim[$w]+=" $n"
    done
  done
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

ext_package_names() { _ext_with_index - _ext_print_names; }
# cat writes the list in one piece: bash writes line by line, so `ext_package_names | grep -q` under pipefail could die of SIGPIPE
_ext_print_names() { local IFS=$'\n'; [ "${#_ix_names[@]}" = 0 ] || cat <<< "${_ix_names[*]}"; }

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
  _ext_with_index "$2" _ext_filter_ix "$@"
}

_ext_filter_ix() {   # the same inside _ext_with_index, with <dir> in the index
  [ -f "$2/commands.tsv" ] || return 0
  local proto=0 words w t taken=""
  _ext_owned_words "$1" "$2"
  words=$_ix_ret
  [[ "$words" != *" "* ]] || words=$(printf '%s\n' $words | sort -u | paste -sd' ' -)
  [ -z "$words" ] || _ext_claims
  for w in $words; do
    for t in ${_ix_claim[$w]:-}; do   # the first OTHER package that has the word
      [ "$t" != "$1" ] || continue
      taken="$taken $w:$t"
      break
    done
  done
  # a package that says `protocol = [1]` has its rows run through scripts/lib/ext_proto.py: the row gets the flag `proto` (hs.sh)
  ! _ext_fact "$2/package.toml" protocol || proto=1
  # a start row needs an ACCEPTED plan row. One awk keeps the rows and goes over them twice: pass 1 (without that rule) lists the
  # accepted paths, pass 2 applies the rule against that list and prints.
  awk -F'\t' -v OFS='\t' -v name="$1" -v dir="$2" -v report="$3" -v words="$words" -v taken="$taken" -v proto="$proto" '
    BEGIN {
      now = split(words, ow, " "); for (i = 1; i <= now; i++) owned[ow[i]] = 1
      nt = split(taken, tk, " "); for (i = 1; i <= nt; i++) { split(tk[i], kv, ":"); takenby[kv[1]] = kv[2] }
      alt = ""; for (i = 1; i <= now; i++) alt = alt (i > 1 ? " or " : "") ow[i]
    }
    NR == FNR {   # the core registry: which first words it uses
      if ($0 ~ /^#/ || $0 ~ /^[ \t\r]*$/) next
      n = split($2, cw, " ")
      if ($1 == "user" && n >= 1) corefirst["user " cw[1]] = 1
      else if ($1 == "sys" && n >= 2) corefirst["sys " cw[2]] = 1
      next
    }
    /^#/ || /^[ \t\r]*$/ { next }
    { sub(/\r$/, ""); rows++; text[rows] = $0; at[rows] = FNR }
    END {
      for (pass = 1; pass <= 2; pass++) {
        split("", seen)
        for (r = 1; r <= rows; r++) {
          $0 = text[r]
          kind = $1; path = $2; script = $3; reason = ""
          nw = split(path, w, " ")
          if (name == "list" || name == "enable" || name == "disable" || name == "status" || name == "start" || name == "stop" || name == "svc-run") reason = "the name " name " is reserved (hs ext " name ")"
          else if (kind == "user") {
            if (w[1] in owned && nw >= 2) { if (("user " w[1]) in corefirst) reason = "the word " w[1] " is also a core command"; else if (w[1] in takenby) reason = "the word " w[1] " is also used by the package " takenby[w[1]] }
            else if (w[1] != "ext" || w[2] != name || nw < 3) reason = "a user row must be: ext " name " <command>" (now > 0 ? " or " alt " <command>" : "")
          }
          else if (kind == "sys")  {
            if (w[1] == "sys" && (w[2] in owned) && nw >= 3) { if (("sys " w[2]) in corefirst) reason = "the word " w[2] " is also a core command"; else if (w[2] in takenby) reason = "the word " w[2] " is also used by the package " takenby[w[2]] }
            else if (w[1] != "sys" || w[2] != "ext" || w[3] != name || nw < 4) reason = "a sys row must be: sys ext " name " <command>" (now > 0 ? " or sys " alt " <command>" : "")
          }
          else reason = "the kind must be user or sys"
          if (reason == "" && NF < 6) reason = "a row has at least 6 columns (kind path script args help help.de)"
          if (reason == "" && (script == "" || script ~ /(^|\/)\.\.(\/|$)/ || (script ~ /^\// ))) reason = "the script must be a path under scripts/ or @/file in the package, without .."
          if (reason == "" && script ~ /^@/ && script !~ /^@\/./) reason = "the script must be a path under scripts/ or @/file in the package, without .."
          if (reason == "" && script ~ /^rust:/) reason = "rust: rows belong to the core registry"
          if (reason == "" && $7 ~ /(^|,)legacy:/) reason = "a legacy: flag belongs to the core registry"
          if (reason == "" && kind == "sys" && pass == 2) {   # a start row needs its plan row (words alike, start -> plan): the plan shows what changes before it does
            for (i = 1; i <= nw; i++) if (w[i] == "start") { tw = ""; for (j = 1; j <= nw; j++) tw = tw (j > 1 ? " " : "") (j == i ? "plan" : w[j]); if (!(tw in accepted)) reason = "a start row needs its plan row" }
          }
          if (reason == "" && (path in seen)) reason = "the words are used twice"
          if (reason != "") { if (pass == 2 && report == 1) print "REFUSED", at[r], path, reason; continue }
          seen[path] = 1
          if (pass == 1) { accepted[path] = 1; continue }
          if (report == 1) continue
          if (script ~ /^@\//) $3 = dir "/" substr(script, 3)
          if (proto == 1) { $7 = ($7 == "" || $7 == "-") ? "proto" : $7 ",proto"; }
          print
        }
      }
    }' "$_ix_core" "$2/commands.tsv" || return 1
  # an awk that failed (no registry, unreadable file) is a failure of the filter (|| return 1), never "no rows"
}

registry_rows() {
  grep -av '^#' "$(ext_core_file)" | tr -d '\r' || true
  _ext_with_index - _ext_all_rows
}

_ext_all_rows() {   # inside _ext_with_index
  local n d
  for n in ${_ix_names[@]+"${_ix_names[@]}"}; do
    [[ "$n" =~ ^[a-z][a-z0-9-]{0,30}$ ]] && d=${_ix_dir[$n]:-} && [ -n "$d" ] || continue
    [ -f "$d/commands.tsv" ] || continue
    # the rule of ext_package_on, answered from the index
    if [ -f "$d/capability.toml" ] || _ext_fact "$d/package.toml" cap; then capability_on "$n" || continue
    else [ -n "${_ix_sec["[package.$n]"]:-}" ] || continue
    fi
    _ext_filter_ix "$n" "$d" 0
  done
}

registry_rows_of() {   # registry_rows_of <name>
  local d
  d=$(ext_package_dir "$1") || return 1
  _ext_filter "$1" "$d" 0
}

registry_refused() { _ext_with_index - _ext_all_refused "${1:-}"; }   # registry_refused [<name>]

_ext_all_refused() {   # inside _ext_with_index
  local n d
  for n in ${_ix_names[@]+"${_ix_names[@]}"}; do
    [ -z "$1" ] || [ "$1" = "$n" ] || continue
    [[ "$n" =~ ^[a-z][a-z0-9-]{0,30}$ ]] && d=${_ix_dir[$n]:-} && [ -n "$d" ] || continue
    _ext_filter_ix "$n" "$d" 1 | awk -F'\t' -v OFS='\t' -v n="$n" '{ print n, $2, $3, $4 }'
  done
}
