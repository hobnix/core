#!/usr/bin/env bash
# help: packages (recipes and extensions): list them with their version, see which have an update, check the manifests
# help.de: Pakete (Rezepte und Erweiterungen): mit Version auflisten, Updates sehen, die Manifeste prüfen
# args: --market | --show <name> [--repo R] | --asset <name> <file> [--repo R] | --states [--kind K] | --capabilities | --repos | list [--all] [--kind recipe|extension|capability] | updates | validate | new <name> --template recipe|extension|capability [--dir <path>] | fetch | available | install <name> | update <name> | remove <name> [--dry-run] | rollback <name> | repo list|add|remove | --list
# A package is a recipe (packages/<name>/package.toml) or an extension (capabilities/<name>/package.toml) with a semver `version`
# (docs/PLAN-packages.md). This is step 1: the manifests of this repository only; repositories and `install` come later.
#   list        name, kind, version in the tree, version last applied here, who it is for; personal ones only with --all
#   --list      the same as data (hs sys pkg list): name, kind, version, installed (- = never), audience, title; every package
#   updates     the packages whose version in the tree is newer than the one last applied (`hs recipe <name>` applies a recipe)
#   validate    check every manifest (and that a recipe's header lines agree); lists the problems, exit 1 when there are any
#   new <name> --template recipe|extension|capability [--dir <path>] [--title <text>] [--title-de <text>]   write a package that passes the checks into a
#               checkout of a package repository (recipes/<name> or extensions/<name>, plus its index.toml entry); never overwrites (pkg_new.py)
#   repo list|add|remove   the package repositories: the two defaults (config/package-repos.toml) and the ones a person added. Adding one
#                          shows the address and the signer key(s) and asks to TYPE the repository's name (--confirm-name <name> without a terminal);
#                          releases must be signed (--key <allowed_signers file>); --unsigned is marked everywhere and asks twice
#   fetch [<repo>]         update the local clones, find the newest release tag whose signature verifies
#   available              what the repositories offer (from the last fetch)
#   install --core         fetch every package the core refers to by name (core = true in the index) or that was applied here, when it is not there yet
#   install <name> [--repo R] [--tag T]  fetch a package at the verified tag (T: only that one, else refused) into /var/lib/hs/packages/current (read-only, root-owned)
#   update <name> [--yes]  show what changed since the installed tag (it is code that runs as root), then install the new one
#   remove <name> [--dry-run] [--yes|--confirm-name <name>]
#                          uninstall a repository package: refused while it is switched on or another package that is on `requires` it
#                          (ADR 0009 rule 7). Shows what goes (the copy, its event declarations, its on/off marks) and what stays (containers
#                          and data, never deleted); --dry-run changes nothing; asks to type the name, or --yes / --confirm-name without a terminal
#   rollback <name> [--yes]  put the copy from before the last update back (previous/, and for a vendored package the old lock); then hs rebuild
#   install and update refuse a package whose `requires_core` is above this server's API level (also checked against package.toml, not only the index)
#   --states    the lifecycle stage (available|installed|on|running) and flags of every package as data (hs sys pkg states): name, kind, stage, flags
#               (comma list, - = none), repo, available, installed, instances, title; --kind K keeps one kind (ADR 0027, pkg_states.py)
# Test knobs: HS_PACKAGES_ROOT, HS_STATE_DIR, HS_LANG, HS_INCUS.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib/ui.sh"
. "$here/lib/live.sh"
py() { python3 -I "$here/pkg.py" "$@"; }
# a change of the packages or the repositories changes what the web interface shows (Marketplace, repositories, recipes, parts): the live
# state reads those topics again after it succeeded (a fetch always: one repository may have failed while the others moved); never fails it
pkg_changed() { trap 'rc=$?; [ "$rc" -ne 0 ] || live_refresh event:pkg.changed; exit "$rc"' EXIT; }

case "${1:-list}" in
  --list) py list --all ;;
  --market) py market ;;
  --show) shift; py show "$@" ;;
  --asset) shift; py asset "$@" ;;
  --states)
    shift
    # the five inputs of the merge; one that fails is an empty file (the stage then comes from what is left)
    d=$(mktemp -d); trap 'rm -rf "$d"' EXIT
    py market >"$d/market" 2>/dev/null || : >"$d/market"
    bash "$here/parts.sh" --list >"$d/parts" 2>/dev/null || : >"$d/parts"
    bash "$here/parts.sh" --pending >"$d/pending" 2>/dev/null || : >"$d/pending"
    bash "$here/recipes-list.sh" --list >"$d/recipes" 2>/dev/null || : >"$d/recipes"
    ${HS_INCUS:-incus} list -f csv -c ns >"$d/running" 2>/dev/null || : >"$d/running"
    py states --market "$d/market" --parts "$d/parts" --pending "$d/pending" --recipes "$d/recipes" --running "$d/running" "$@" ;;
  --capabilities) py capabilities ;;
  --repos) py repo list ;;
  list)
    shift
    rows=$(py list "$@")
    if [ -z "$rows" ]; then note "No packages."; exit 0; fi
    { thead 'Package' 'Kind' 'Version' 'Applied' 'For' 'What it is'; printf '%s\n' "$rows"; } | table
    next_step "hs pkg updates" ;;
  updates)
    rows=$(py updates)
    waits=$(py updates --waits)
    if [ -z "$rows" ] && [ -z "$waits" ]; then ok "$(t 'Every package is up to date.')"; exit 0; fi
    if [ -n "$rows" ]; then { thead 'Package' 'Applied' 'Available'; printf '%s\n' "$rows"; } | table; fi
    while IFS=$'\t' read -r n v w; do
      [ -n "$n" ] || continue
      note "$(t '%s %s waits for core: it needs %s. Run: hs update' "$n" "$v" "$w")"
    done <<<"$waits"
    [ -z "$rows" ] || next_step "hs recipe <name>" ;;
  validate)
    if out=$(py validate); then ok "$(t 'Every manifest is valid.')"; else
      while IFS=$'\t' read -r n p; do warn "$n: $p"; done <<<"$out"
      exit 1
    fi ;;
  new)
    shift
    name=${1:-}
    rc=0; out=$(py new "$@") || rc=$?
    if [ "$rc" -ne 0 ]; then
      line=$(sed -n 's/^error\t//p' <<<"$out"); code=${line%%$'\t'*}; detail=${line#*$'\t'}
      case "$code" in
        usage) say "usage: hs pkg new <name> --template recipe|extension|capability [--protocol shell|python] [--dir <path>] [--title <text>] [--title-de <text>] [--description <text>] [--icon ph:<name>] [--category <id>] [--app-version <text>] [--instances one|many]"; exit 1 ;;
        template) fail "$(t 'Unknown template %s: use recipe, extension or capability.' "$detail")" ;;
        name) fail "$(t 'The name %s is not allowed: lower case letters, digits and -, starting with a letter, at most 41 characters, and not list, enable or disable.' "$detail")" ;;
        title) fail "$(t 'A title is one line of at most 100 characters, without spaces at its ends.')" ;;
        field) fail "$(t 'The value of %s is not allowed: an icon like ph:image, a category of config/package-categories.toml, a short app version, one or many, shell or python for --protocol (extensions only), one short paragraph; a capability has no store fields.' "$detail")" ;;
        notrepo) fail "$(t '%s is not a checkout of a package repository: it needs index.toml and the folder recipes/ (recipe), extensions/ (extension) or capabilities/ (capability). Use --dir <path>.' "$detail")" ;;
        exists) fail "$(t 'There is a package %s already (its folder or its index.toml entry); nothing was changed.' "$detail")" ;;
        *) fail "$(t 'The package could not be written (%s); nothing was left behind.' "$detail")" ;;
      esac
    fi
    folder=$(sed -n 's/^folder\t//p' <<<"$out"); name=$(basename "$folder"); index=$(sed -n 's/^index\t//p' <<<"$out")
    step "$(t 'New package %s' "$name")"
    kv "$(t 'Folder')" "$folder"
    while IFS= read -r f; do ok "$(t 'Created %s' "$f")"; done < <(sed -n 's/^file\t//p' <<<"$out")
    ok "$(t 'Added %s to %s' "$name" "$index")"
    note "$(t 'It passes the checks as it is. Replace the example step or command with your own, then check again:')"
    next_step "python3 -I $here/pkg.py repo-check $(dirname "$index")" ;;
  fetch)
    shift
    trap 'live_refresh event:pkg.changed' EXIT
    hs_job_step 1 1 "Fetching the package repositories and checking their signatures"
    out=$(py fetch "$@") || rc=$?
    { thead 'Repository' 'Release' 'Commit' 'Result'; printf '%s\n' "$out"; } | table
    exit "${rc:-0}" ;;
  available)
    rows=$(py available)
    if [ -z "$rows" ]; then note "Nothing yet: hs pkg fetch"; exit 0; fi
    { thead 'Repository' 'Package' 'Kind' 'Version' 'Applied'; printf '%s\n' "$rows"; } | table
    next_step "hs pkg install <name>" ;;
  remove)
    shift; pkg_changed
    . "$here/lib/capability.sh"
    name=""; dry=0; yes=0; confirmed=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --dry-run) dry=1; shift ;;
        --yes) yes=1; shift ;;
        --confirm-name) confirmed=${2:-}; shift 2 ;;
        -*) fail "$(t 'Unknown option %s' "$1")"; exit 1 ;;
        *) [ -z "$name" ] || { say "usage: hs pkg remove <name> [--dry-run] [--yes | --confirm-name <name>]"; exit 1; }; name=$1; shift ;;
      esac
    done
    [[ "$name" =~ ^[a-z][a-z0-9-]{0,40}$ ]] || { say "usage: hs pkg remove <name> [--dry-run] [--yes | --confirm-name <name>]"; exit 1; }
    st=${HS_STATE_DIR:-/var/lib/hs}
    dir=$st/packages/current/$name
    [ -d "$dir" ] || { fail "$(t '%s was not installed from a repository.' "$name")"; exit 1; }
    mf() { sed -n "s/^$1[[:space:]]*=[[:space:]]*\"\(.*\)\"[[:space:]]*\$/\1/p" "$2/package.toml" 2>/dev/null | head -n1; }
    kind=$(mf kind "$dir")
    # what keeps it: it is switched on itself, or a package that is on requires it (ADR 0009 rule 7)
    deps=""
    if [ "$kind" != recipe ] && capability_on "$name"; then
      fail "$(t "'%s' is switched on: switch it off first." "$name")"; next_step "hs ext disable $name"; exit 1
    fi
    for d in "$st"/packages/current/*/ "${HS_PACKAGES_ROOT:-$(dirname "$here")}"/capabilities/*/; do
      [ -d "$d" ] || continue
      n=$(basename "$d")
      [ "$n" != "$name" ] || continue
      f=$d/capability.toml; [ -f "$f" ] || f=$d/package.toml
      [ -f "$f" ] || continue
      sed -n 's/^requires[[:space:]]*=[[:space:]]*\[\(.*\)\][[:space:]]*$/\1/p' "$f" | head -n1 | tr ',' '\n' | tr -d ' "' | grep -qxF -- "$name" || continue
      ! capability_on "$n" || deps+="${deps:+ }$n"
    done
    if [ -n "$deps" ]; then
      fail "$(t "'%s' cannot be removed: %s needs it." "$name" "$deps")"; next_step "hs ext disable ${deps%% *}"; exit 1
    fi
    step "$(t 'Remove package %s' "$name")"
    kv "$(t 'Version')" "$(mf version "$dir")"
    note "$(t 'Removed: the installed copy, its event declarations and its switch-on/off marks.')"
    note "$(t 'Stays: containers and data the package made (hs ct remove is for those).')"
    note "$(t 'To remove an app with its route and address and choose to keep or delete its data: the Apps page (Remove), or hs sys apps plan remove <instance>.')"
    if [ "$dry" = 1 ]; then
      note "$(t 'Nothing was changed (dry run).')"
      exit 0
    fi
    if [ -n "$confirmed" ]; then
      [ "$confirmed" = "$name" ] || { fail "$(t 'The name does not match.')"; exit 1; }
    elif [ "$yes" = 0 ]; then
      if [ -t 0 ]; then
        confirm_name "$name" "$(t 'the package')" || { fail "$(t 'Not removed.')"; exit 1; }
      else
        fail "$(t 'Removing needs a person at a terminal, --yes or --confirm-name <name>.')"; exit 1
      fi
    fi
    # the keys of its options become "retired" (hs config check says "unused", not "unknown"): written before the folder is gone
    PYTHONUTF8=1 "${HS_PYTHON:-python3}" "$here/schema-gen.py" overlay retire "$name" --packages "$st/packages/current" --out "$st/generated" >/dev/null \
      || warn "$(t 'The options of this package could not be remembered.')"
    py remove "$name"
    for o in on off; do
      f=$st/capabilities-$o
      [ -f "$f" ] || continue
      grep -vxF -- "$name" "$f" > "$f.tmp" || true
      mv "$f.tmp" "$f"
    done
    # a package that brought options or a capability row leaves none behind (ADR 0017 rule 16): the generated overlay is rewritten
    # without it, but only where an overlay exists already (nothing is created for a server that never had a capability package)
    if [ -f "$st/generated/capabilities.tsv" ]; then
      PYTHONUTF8=1 "${HS_PYTHON:-python3}" "$here/schema-gen.py" overlay write --packages "$st/packages/current" --out "$st/generated" >/dev/null \
        || warn "$(t 'The generated capability list could not be refreshed.')"
    fi
    ok "$(t 'Package %s removed.' "$name")" ;;
  install)
    cmd=$1; shift
    pkg_changed
    if res=$(py "$cmd" "$@"); then
      if [ -z "$res" ]; then ok "$(t 'Done.')"; else while IFS= read -r l; do ok "$l"; done <<<"$res"; fi
    else exit 1; fi ;;
  update)
    shift; pkg_changed
    python3 -I "$here/pkg.py" update "$@" ;;
  rollback)
    # put the copy from before the last update back (plan first, the name to confirm); the rebuild is a separate step
    shift; name="${1:-}"; [ -n "$name" ] || fail "$(t 'Usage: hs pkg rollback <name>')"
    plan=$(py rollback "$name" --plan) || exit 1
    IFS=$'\t' read -r _ from to <<<"$plan"
    note "$(t '%s: %s goes back to %s (its copy in vendor/ and the lock line).' "$name" "$from" "$to")"
    [ "${2:-}" = --yes ] || confirm_name "$name" "$(t 'the package')" || fail "$(t 'Left as it is.')"
    pkg_changed
    py rollback "$name" >/dev/null && ok "$(t '%s is back at %s.' "$name" "$to")" && next_step "hs rebuild" ;;
  repo)
    shift
    case "${1:-list}" in
      list)
        { thead 'Repository' 'Address' 'Signed' 'From'; py repo list; } | table ;;
      add)
        pkg_changed
        name=${2:-}; url=${3:-}; [ -n "$name" ] && [ -n "$url" ] || { say "usage: hs pkg repo add <name> <url> (--key <allowed_signers file> | --unsigned) [--confirm-name <name>]"; exit 1; }
        shift 3; confirmed=""; extra=()
        while [ $# -gt 0 ]; do
          case "$1" in
            --confirm-name) confirmed=${2:-}; shift 2 ;;
            *) extra+=("$1"); shift ;;
          esac
        done
        step "$(t 'Package repository %s' "$name")"
        kv "$(t 'Address')" "$url"
        key=""; unsigned=false
        for ((i = 0; i < ${#extra[@]}; i++)); do
          [ "${extra[i]}" != --key ] || key=${extra[i + 1]:-}
          [ "${extra[i]}" != --unsigned ] || unsigned=true
        done
        if [ -n "$key" ] && [ -r "$key" ]; then
          while read -r line; do
            kv "$(t 'Signer')" "$(sed -E 's/^.*(ssh-[a-z0-9]+|ecdsa-sha2-[a-z0-9]+|sk-[a-z0-9@.-]+) /\1 /' <<<"$line" | ssh-keygen -lf /dev/stdin 2>/dev/null || echo "$line")"
          done < <(grep -v '^#' "$key" | grep -v '^[[:space:]]*$')
        fi
        if $unsigned; then
          danger "$(t 'UNSIGNED: anyone who controls this address can run code on this server as root.')"
        fi
        danger "$(t 'Packages run as root. Only add a repository you trust.')"
        if [ -n "$confirmed" ]; then
          [ "$confirmed" = "$name" ] || { fail "$(t 'The name does not match.')"; exit 1; }
        elif [ -t 0 ]; then
          confirm_name "$name" "$(t 'the repository')" || { fail "$(t 'Not added.')"; exit 1; }
          if $unsigned; then confirm_name "$name" "$(t 'the repository, again: it is unsigned')" || { fail "$(t 'Not added.')"; exit 1; }; fi
        else
          fail "$(t 'Adding a repository needs a person at a terminal, or --confirm-name <name>.')"; exit 1
        fi
        py repo add "$name" "$url" "${extra[@]}" && ok "$(t 'Repository %s added.' "$name")" && next_step "hs pkg fetch $name" ;;
      remove) shift; pkg_changed; py repo remove "${1:-}" && ok "$(t 'Repository removed.')" ;;
      *) say "usage: hs pkg repo list | add <name> <url> (--key <file> | --unsigned) | remove <name>"; exit 1 ;;
    esac ;;
  *) say "usage: hs pkg list [--all] [--kind recipe|extension|capability] | updates | validate | new | fetch | available | install | update | remove | repo"; exit 1 ;;
esac
