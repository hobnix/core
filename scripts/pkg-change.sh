#!/usr/bin/env bash
# help: install, update or remove a package, fetch the repositories, add or remove a repository, without asking anything: what would happen (plan), then do it (start)
# help.de: ein Paket installieren, aktualisieren oder entfernen, die Repositories abrufen, ein Repository hinzufügen oder entfernen, ohne etwas zu fragen: was passieren würde (plan), dann ausführen (start)
# args: plan|start install <name> [--repo R] | update <name> | remove <name> | fetch [<repo>] | repo-add <name> <url> | repo-remove <name> | check-draft
# System command (hs sys pkg plan|start): for the interface (Marketplace) and tests. It never asks and prints plain key<TAB>value lines like
# node-change.sh. The work is pkg.sh's (hs pkg install|update|remove|fetch|repo ...); this script checks the input and says what would happen.
#   install <name> [--repo R]  fetch the package at the verified release into /var/lib/hs/packages/current (it is not run: a recipe is run from Apps)
#   update <name>              install the newer release; the plan shows what changed in the code (it runs as root)
#   remove <name>              forget a package installed from a repository; a container made by a recipe stays
#   fetch [<repo>]             read the repositories again and find the newest verified release (needs the network)
#   repo-add <name> <url>      add a repository; its public signing key is ONE line on standard input (ssh-ed25519 AAAA..., or a whole
#                              allowed-signers line). Only signed repositories can be added here (an unsigned one is `hs pkg repo add --unsigned`).
#                              The release is fetched at once; if nothing verifies the repository is taken out again. Red: the typed word is the name.
#   check-draft                (plan only) check a package.toml draft given on stdin with the checks of hs pkg validate (ADR 0020, the web package
#                              builder): status ok|refused, `finding<TAB>error|warn<TAB>where<TAB>text` lines; nothing is written anywhere
#   repo-remove <name>         take an added repository out (the defaults stay); installed packages stay as they are. Red: the typed word is the name.
# A package from a repository that was ADDED (not recipes/extensions of this project) runs as root once installed: install and update are red
# for it, the typed word is the package name. For the default repositories the plan is the confirmation.
# An update that asks for NEW permissions is red for every repository: one `danger` line per permission and confirm_name. An update plan also has
# tag<TAB><release> and seen<TAB><word>: start takes them back (--tag T --seen S) and refuses with plan.changed when the release or the permissions
# are not the shown ones. --accept-permissions reaches pkg.sh only when such a plan was started with its typed name (hobnix/core#1237).
# plan: exit 0 = allowed, 1 = refused. Output: status ok|refused, reason<TAB><text>, heading|step|note|warn|danger|command|diff<TAB><line>,
#   confirm_name<TAB><name>, long<TAB>yes|no (yes = it runs as a job: fetch).
# start: the same checks, then status<TAB>done (or refused with the reason). `start fetch` reads the network for a long time, so it runs as a job:
#   status<TAB>started, unit<TAB><unit> (follow it with hs job follow; the Marketplace shows it as running). `repo-add` stays inline: the person needs
#   its answer at once (accepted, or refused with the reason and the repository not kept), so its plan says long no.
# Test knobs: HS_PKG (stand-in for pkg.sh), HS_PKG_ALLOW_LOCAL=1 (a repository may be a local path or file://), HS_JOB_LIB (stand-in for lib/job.sh).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
pkg=${HS_PKG:-$here/pkg.sh}
pkgpy="python3 -I $here/pkg.py"

. "$here/lib/refuse-code.sh"   # refuse_code (ADR 0028)
# Texts of a package or an index reach the lines below: web-serve.py also splits on CR, U+0085 and U+2028, so every one goes through clean_text
# (scripts/pkg_repo.py). clean keep = a stream of finished lines (tabs and newlines stay); clean one = one value, made one safe line.
clean() {
  python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); from pkg_repo import clean_text
sys.stdout.buffer.write(clean_text(sys.stdin.buffer.read().decode("utf-8", "replace"), sys.argv[2] == "keep").encode("utf-8"))' "$here" "$1"
}
refuse_clean() { printf '%s' "$1" | clean one; }   # the reason of a refusal (lib/refuse-code.sh)

verb=${1:-}; action=${2:-}; name=${3:-}
case "$verb" in plan|start) ;; *) echo "usage: pkg-change.sh plan|start install|update|remove <name> | fetch [<repo>] | repo-add <name> <url> | repo-remove <name>" >&2; exit 1 ;; esac
case "$action" in install|update|remove|fetch|repo-add|repo-remove|check-draft) ;; *) refuse_code action.unknown "unknown action (install, update, remove, fetch, repo-add or repo-remove)" ;; esac
shift 2 || true
if [ "$action" = check-draft ]; then
  [ "$verb" = plan ] || refuse_code pkg.draft-readonly "a draft is only checked (plan); nothing is started"
  [ $# -eq 0 ] || refuse_code args.unexpected "unexpected extra arguments"
  rc=0; out=$(head -c 262144 | python3 -I "$here/pkg.py" check-draft 2>/dev/null) || rc=$?
  errs=$(printf '%s\n' "$out" | awk -F'\t' '$1 == "error"' | wc -l)
  if [ "$rc" -ne 0 ] && [ "$errs" -eq 0 ]; then refuse_code pkg.draft-unchecked "the draft could not be checked"; fi
  if [ "$errs" -gt 0 ]; then printf 'status\trefused\nreason\t%s\ncode\tpkg.draft-invalid\n' "The draft has $errs problem(s)."; else printf 'status\tok\n'; fi
  printf 'heading\tcheck a package draft\n'
  printf '%s\n' "$out" | awk -F'\t' 'NF == 3 { printf "finding\t%s\t%s\t%s\n", $1, $2, $3 }' | clean keep
  printf 'long\tno\n'
  [ "$errs" -eq 0 ] || exit 1
  exit 0
fi
name=${1:-}; [ $# -eq 0 ] || shift

# the web interface appends --confirm <word> to start (the typed name of a red change); take it out of the arguments
confirm="" rest=()
while [ $# -gt 0 ]; do
  case "$1" in
    --confirm) [ $# -ge 2 ] || refuse_code confirm.missing "--confirm needs a value"; confirm=$2; shift 2 ;;
    *) rest+=("$1"); shift ;;
  esac
done
set -- ${rest[@]+"${rest[@]}"}

export HS_PLAIN=1 HS_LANG=en HS_CALLER=${HS_CALLER:-ui}
unset HS_GUIDED_TTY

word='^[a-z0-9][a-z0-9-]{0,40}$'
market() { bash "$pkg" --market 2>/dev/null || true; }
repos() { bash "$pkg" --repos 2>/dev/null || true; }
# one line per fact: name, kind, repo, available, installed, state, core, audience, title
row_of() { market | awk -F'\t' -v n="$1" '$1 == n { print; exit }'; }
repo_row() { repos | awk -F'\t' -v n="$1" '$1 == n { print; exit }'; }   # name, address, signed|unsigned, default|added
# pkg.sh may have refused in the ADR 0028 form already (pkg_refused: status, reason, fix, code, through refuse_code): then exactly those lines
# are the answer (its own code, not pkg.action-failed) and this exits 1. Returns when the output holds no such refusal.
relay_coded() {   # relay_coded <output of pkg.sh>
  local lines
  lines=$(awk -F'\t' '$1 == "status" && $2 == "refused" { buf = $0; code = 0; next }
    buf != "" && ($1 == "reason" || $1 == "fix" || $1 == "code") { buf = buf "\n" $0; if ($1 == "code") code = 1 }
    END { if (code) print buf }' <<<"$1")
  [ -n "$lines" ] || return 0
  printf '%s\n' "$lines"; exit 1
}

repo="" cmd=() red="" long=no fresh=() ftag="" fseen="" wtag="" wseen=""
case "$action" in
  install|update|remove)
    [[ "$name" =~ $word ]] || refuse_code name.invalid "not a package name (lower case letters, digits and dashes)"
    row=$(row_of "$name")
    [ -n "$row" ] || refuse_code pkg.unknown "There is no package $name in the repositories (fetch them again first)."
    IFS=$'\t' read -r _ kind repo avail inst state core _ title <<<"$row"
    [ "$kind" != blueprint ] || refuse_code pkg.blueprint "$name is a blueprint: hs blueprint apply $name"
    r_from=$(repo_row "$repo" | cut -f4)
    [ "$r_from" = added ] && red=$name
    case "$action" in
      install)
        while [ $# -gt 0 ]; do
          case "$1" in
            --repo) repo=${2:-}; [ -n "$repo" ] || refuse_code pkg.value-missing "--repo needs a name"; shift 2 ;;
            *) refuse_code option.unknown "unknown option $1" ;;
          esac
        done
        [ "$state" = new ] || refuse_code pkg.installed "$name is installed already (version $inst); use update."
        cmd=(bash "$pkg" install "$name" --repo "$repo") ;;
      update)
        while [ $# -gt 0 ]; do
          [ "$verb" = start ] && [ $# -ge 2 ] || refuse_code args.unexpected "unexpected extra arguments"
          case "$1" in
            --tag) wtag=$2; shift 2 ;;
            --seen) wseen=$2; shift 2 ;;
            *) refuse_code option.unknown "unknown option $1" ;;
          esac
        done
        [ "$inst" != - ] || refuse_code pkg.not-installed "$name is not installed from a repository; install it first."
        [ "$state" = update ] || refuse_code pkg.up-to-date "$name is up to date (version $inst)."
        # the facts of the update as lines of the package reader (never read from the human diff); no facts, no update
        errfile=$(mktemp "${TMPDIR:-/tmp}/hs-pkg-facts.XXXXXX")
        rc=0; facts=$($pkgpy update "$name" --facts </dev/null 2>"$errfile") || rc=$?
        why=$(awk '!/^code\t/ && NF { l = $0 } END { print l }' "$errfile"); rm -f "$errfile"
        [ "$rc" -eq 0 ] || refuse_code pkg.action-failed "${why:-the new release of $name could not be read}"
        while IFS=$'\t' read -r key val; do
          case "$key" in
            current) refuse_code pkg.up-to-date "$name is up to date (version $inst)." ;;
            tag) ftag=$val ;;
            seen) fseen=$val ;;
            perm) fresh+=("$val") ;;
          esac
        done <<<"${facts//$'\r'/}"
        [ -n "$ftag" ] && [ -n "$fseen" ] || refuse_code pkg.action-failed "the new release of $name could not be read"
        [ "${#fresh[@]}" -eq 0 ] || red=$name
        cmd=(bash "$pkg" update "$name" --yes) ;;
      remove)
        [ $# -eq 0 ] || refuse_code args.unexpected "unexpected extra arguments"
        [ "$inst" != - ] || refuse_code pkg.not-installed "$name is not installed from a repository."
        [ "$core" != yes ] || refuse_code pkg.core "$name is a core package: other parts of the server refer to it by name, so it stays."
        red=""
        if ! why=$(bash "$pkg" remove "$name" --dry-run </dev/null 2>&1); then refuse_code pkg.remove-refused "$(printf '%s' "$why" | sed -e 's/^[[:space:]]*//' -e 's/^[✗!] *//' | awk 'NF' | head -n 1)"; fi
        cmd=(bash "$pkg" remove "$name" --yes) ;;
    esac ;;
  fetch)
    repo=$name; name=""
    [ $# -eq 0 ] || refuse_code args.unexpected "unexpected extra arguments"
    if [ -n "$repo" ]; then [[ "$repo" =~ $word ]] && [ -n "$(repo_row "$repo")" ] || refuse_code pkg.repo-unknown "There is no repository $repo."; fi
    long=yes
    cmd=(bash "$pkg" fetch); [ -z "$repo" ] || cmd+=("$repo") ;;
  repo-add)
    url=${1:-}; [ $# -eq 0 ] || shift
    [ $# -eq 0 ] || refuse_code args.unexpected "unexpected extra arguments"
    [[ "$name" =~ $word ]] || refuse_code name.invalid "the repository name is a lower case word (letters, digits and dashes)"
    [ -z "$(repo_row "$name")" ] || refuse_code pkg.repo-exists "There is a repository called $name already."
    [ -n "$url" ] || refuse_code pkg.value-missing "the address of the repository is needed"
    if [ "${HS_PKG_ALLOW_LOCAL:-}" = 1 ]; then ok_url='^(https://|ssh://|git@|file://|/)[A-Za-z0-9._:/@~+-]{2,200}$'; else ok_url='^(https://|ssh://git@|git@)[A-Za-z0-9._:/@~+-]{3,200}$'; fi
    [[ "$url" =~ $ok_url ]] && [[ "$url" != *..* ]] || refuse_code pkg.repo-url-invalid "the address must be https://..., ssh://git@... or git@host:path"
    red=$name ;;
  repo-remove)
    [[ "$name" =~ $word ]] || refuse_code name.invalid "not a repository name"
    r=$(repo_row "$name"); [ -n "$r" ] || refuse_code pkg.repo-unknown "There is no repository $name."
    [ "$(cut -f4 <<<"$r")" = added ] || refuse_code pkg.repo-default "$name is one of the default repositories: those stay."
    red=$name ;;
esac

if [ "$verb" = start ]; then
  if [ "$action" = update ]; then
    if { [ -n "$wtag" ] && [ "$wtag" != "$ftag" ]; } || { [ -n "$wseen" ] && [ "$wseen" != "$fseen" ]; }; then
      refuse_code plan.changed "The release or its permissions changed: the plan showed something else than an update to $ftag would do now. Read the plan again."
    fi
    if [ "${#fresh[@]}" -gt 0 ] && { [ -z "$wtag" ] || [ -z "$wseen" ]; }; then
      refuse_code confirm.missing "$name asks for new permissions: update it on its own (its Update button), read them and type the name ($name)."
    fi
  fi
  if [ -n "$red" ]; then [ "$confirm" = "$red" ] || refuse_code confirm.missing "type the name ($red) to confirm"; fi
  case "$action" in
    repo-add)
      # the signing key: one line on standard input, rebuilt as an allowed-signers line (principal, git namespace, type, key)
      IFS= read -r line || true
      [ -n "$line" ] || refuse_code pkg.key-invalid "the public signing key of the repository is needed"
      if ! [[ "$line" =~ (ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh\.com)[[:space:]]+([A-Za-z0-9+/]{20,}={0,3}) ]]; then
        refuse_code pkg.key-invalid "that is not an SSH public key (it starts with ssh-ed25519 or ssh-rsa)"
      fi
      keyfile=$(mktemp "${TMPDIR:-/tmp}/hs-pkg-key.XXXXXX"); trap 'rm -f "$keyfile"' EXIT
      printf 'release@%s namespaces="git" %s %s\n' "$name" "${BASH_REMATCH[1]}" "${BASH_REMATCH[3]}" > "$keyfile"
      rc=0; out=$(bash "$pkg" repo add "$name" "$url" --key "$keyfile" --confirm-name "$name" </dev/null 2>&1) || rc=$?
      if [ "$rc" -ne 0 ]; then
        refuse_code pkg.repo-add-failed "$(printf '%s' "$out" | sed -e 's/^[[:space:]]*//' -e 's/^[✗!] *//' | awk 'NF' | tail -n 1)"
      fi
      rc=0; out=$(bash "$pkg" fetch "$name" </dev/null 2>&1) || rc=$?
      if [ "$rc" -ne 0 ] || ! market | awk -F'\t' -v r="$name" '$3 == r { f = 1 } END { exit !f }'; then
        bash "$pkg" repo remove "$name" </dev/null >/dev/null 2>&1 || true
        refuse_code pkg.repo-unreadable "no signed release could be read from that address with that key (the repository was not kept)"
      fi
      printf 'status\tdone\n'; exit 0 ;;
    repo-remove)
      rc=0; out=$(bash "$pkg" repo remove "$name" </dev/null 2>&1) || rc=$? ;;
    fetch)
      . "${HS_JOB_LIB:-$here/lib/job.sh}"
      unit=$(hs_job "pkg-fetch${repo:+-$repo}" "hs pkg fetch${repo:+ $repo}" -- bash -c '"$@" </dev/null' _ "${cmd[@]}") || refuse_code job.start-failed "the job could not be started"
      printf 'status\tstarted\nunit\t%s\n' "$unit"; exit 0 ;;
    *)
      if [ "$action" = update ]; then
        cmd+=(--tag "$ftag" --seen "$fseen")      # the package reader checks both again and installs exactly that commit
        # new permissions: the plan that showed them was named (--tag and --seen above) and its name typed (red above); nothing else accepts them
        if [ "${#fresh[@]}" -gt 0 ] && [ "$confirm" = "$name" ]; then cmd+=(--accept-permissions); fi
      fi
      rc=0; out=$("${cmd[@]}" </dev/null 2>&1) || rc=$? ;;
  esac
  if [ "$rc" -ne 0 ]; then
    relay_coded "$out"
    refuse_code pkg.action-failed "$(printf '%s' "$out" | sed -e 's/^[[:space:]]*//' -e 's/^[✗!] *//' | awk 'NF' | tail -n 1)"
  fi
  printf 'status\tdone\n'
  exit 0
fi

plan_lines() {
printf 'status\tok\n'
case "$action" in
  install)
    printf 'heading\tinstall %s %s\n' "$name" "$avail"
    printf 'step\tfetch %s %s from the signed release of the repository %s\n' "$kind" "$name" "$repo"
    printf 'note\t%s\n' "$title"
    if [ "$kind" = recipe ]; then printf 'note\tThis only puts the recipe on the server. Run it from Apps to set the app up.\n'; else printf 'note\tAn extension is off until you switch it on.\n'; fi
    if [ -n "$red" ]; then
      printf 'danger\tThe repository %s was added by you, not by the project. This package runs as root on this server.\n' "$repo"
      printf 'confirm_name\t%s\n' "$name"
    fi ;;
  update)
    printf 'heading\tupdate %s %s -> %s\n' "$name" "$inst" "$avail"
    printf 'step\tinstall the newer signed release; the code below changed and runs as root\n'
    $pkgpy update "$name" --tag "$ftag" --seen "$fseen" </dev/null 2>/dev/null | head -n 60 | while IFS= read -r l; do printf 'diff\t%s\n' "$l"; done || true
    [ "$r_from" != added ] || printf 'danger\tThe repository %s was added by you, not by the project.\n' "$repo"
    if [ "${#fresh[@]}" -gt 0 ]; then     # after the cut diff, one line each: never truncated
      printf 'danger\t%s %s asks for permissions the installed version does not have. It runs as root; declared permissions are not enforced.\n' "$name" "$avail"
      for p in "${fresh[@]}"; do printf 'danger\tNew permission: %s\n' "$p"; done
    fi
    [ -z "$red" ] || printf 'confirm_name\t%s\n' "$name"
    printf 'tag\t%s\nseen\t%s\n' "$ftag" "$fseen" ;;
  remove)
    printf 'heading\tremove %s\n' "$name"
    printf 'step\tforget the installed copy of %s (version %s)\n' "$name" "$inst"
    printf 'note\tA container or data made by the recipe stays; hs pkg install brings the package back.\n' ;;
  fetch)
    printf 'heading\tread the repositories again\n'
    printf 'step\tfetch %s and find the newest release whose signature verifies\n' "${repo:-every repository}"
    printf 'note\tNothing is installed or changed; the list of packages is refreshed.\n' ;;
  repo-add)
    printf 'heading\tadd the repository %s\n' "$name"
    printf 'step\tuse %s as a source of packages; only releases signed with the key you give are accepted\n' "$url"
    printf 'step\tfetch its newest release at once; if nothing verifies, the repository is not kept\n'
    printf 'danger\tPackages run as root on this server. Only add a repository whose owner you trust.\n'
    printf 'confirm_name\t%s\n' "$name" ;;
  repo-remove)
    printf 'heading\tremove the repository %s\n' "$name"
    printf 'step\tstop using %s and delete its cache and its key\n' "$name"
    printf 'danger\tPackages already installed from it stay as they are, but get no updates.\n'
    printf 'confirm_name\t%s\n' "$name" ;;
esac
[ "${#cmd[@]}" -eq 0 ] || printf 'command\t%s\n' "${cmd[*]}"
printf 'long\t%s\n' "$long"
}
plan_lines | clean keep      # every line of the plan, whatever it was made from
