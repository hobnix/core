#!/usr/bin/env bash
# What packages offer to each other: [integrations.<name>] in package.toml (docs/PLAN-packages.md "Integrations", hobnix/core#926). Sourced after ui.sh:
#   . "$(dirname "$0")/lib/integration.sh"      (needs $here = the scripts folder)
#   integration_available            names of the packages that are there: recipes installed, extensions and capabilities on
#   integration_available_strict <name>  the same for the watcher of a running service: fails instead of leaving out a provider Incus did not answer for
#   integration_credentials <caller>  "<name>, <key file>, <providing package>" tab-separated lines for the declared integration:<name> permissions (for systemd LoadCredential=, see ext.sh svc-run)
#   integration_key <name> <provider> <caller>   writes the key of the package <provider> (it must be there and offer <name> with a key_file:
#                                    one integration can have several providers, e.g. jellyfin and radarr under media) on stdout when <caller>
#                                    (an extension) declares
#                                    permissions = ["integration:<name>"] or is a capability; the key is read through secret.sh, never put in
#                                    argv or the environment: the caller reads stdout (a pipe or a file it redirects to). Returns 1 with a note
#                                    on stderr when refused or the key is locked or missing, and a line "code<TAB>..." (scripts/lib/error-codes.tsv) when refused.
#                                    The old form integration_key <name> <caller> (first provider with a key file) still works for one release. The permission is a declared check only: it is not
#                                    enforced (hobnix/server#239), a caller that reads the key file itself is not stopped.
. "${BASH_SOURCE[0]%/*}/secret.sh"

integration_available() {
  { bash "$here/recipes-list.sh" --list 2>/dev/null | awk -F'\t' '$4=="installed"{print $1}'
    bash "$here/parts.sh" --list 2>/dev/null | awk -F'\t' '$2=="on"{print $1}'; } || true
}

integration_available_strict() {   # integration_available_strict <integration>: the same names, but fails when Incus did not answer and a recipe that offers <integration> is therefore "unknown"
  local recipes unknown offers
  recipes=$(bash "$here/recipes-list.sh" --list 2>/dev/null) || return 1
  unknown=$(awk -F'\t' '$4=="unknown"{print $1}' <<<"$recipes")
  if [ -n "$unknown" ]; then   # without --services this asks Incus nothing
    # shellcheck disable=SC2086
    offers=$(python3 -I "$here/pkg.py" integrations --only "$1" $unknown) || return 1
    [ -z "$offers" ] || return 1
  fi
  awk -F'\t' '$4=="installed"{print $1}' <<<"$recipes"
  { bash "$here/parts.sh" --list 2>/dev/null | awk -F'\t' '$2=="on"{print $1}'; } || true
}

integration_credentials() {   # integration_credentials <caller>: "<name><TAB><key file><TAB><providing package>" for each declared integration:<name> whose key is readable
  # The file is only named here, never read. The bridge (ext_service.py) reads it once, checks it and hands a private copy to systemd LoadCredential=
  # ($CREDENTIALS_DIRECTORY/integration-<name>-<provider> in the service, one per keyed provider, hobnix/core#1135). The providing package comes from its registered manifest, never from the path.
  local caller=$1 perm name on path prov grants line
  on=$(integration_available)
  while IFS= read -r perm; do
    case "$perm" in integration:*) name=${perm#integration:} ;; *) continue ;; esac
    # one line per provider that offers the integration with a key file; one without a key file gives nothing (no failure)
    # shellcheck disable=SC2086
    grants=$(python3 -I "$here/pkg.py" integration-grants "$name" "$caller" $on 2> >(while IFS=$'\t' read -r _ msg; do warn "$msg" >&2; done)) || { warn "${grants#*$'\t'}" >&2; continue; }
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      prov=${line#*$'\t'}; path=${line%%$'\t'*}
      case "$(secret_state "$path")" in
        ok) printf '%s\t%s\t%s\n' "$name" "$path" "$prov" ;;
        locked) warn "The key of $name ($prov) is locked: unlock the vault first." >&2 ;;
        *) warn "The key file of $name ($prov) is missing." >&2 ;;
      esac
    done <<< "$grants"
  done < <(python3 "$here/pkg.py" perms "$caller" 2>/dev/null)
}

integration_key() {
  local name=$1 provider=- caller on path st code
  if [ "$#" -ge 3 ]; then provider=$2 caller=$3; else caller=$2; fi
  on=$(integration_available)
  # shellcheck disable=SC2086
  path=$(python3 -I "$here/pkg.py" integration-key "$name" "$caller" "$provider" $on) || {
    code=${path%%$'	'*}
    warn "${path#*$'	'}" >&2; printf 'code	%s
' "$code" >&2; return 1; }
  st=$(secret_state "$path")
  case "$st" in
    ok) cat -- "$path" ;;
    locked) warn "The key of $name is locked: unlock the vault first." >&2; return 1 ;;
    *) warn "The key file of $name is missing." >&2; return 1 ;;
  esac
}
