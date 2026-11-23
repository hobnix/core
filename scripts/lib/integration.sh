#!/usr/bin/env bash
# What packages offer to each other: [integrations.<name>] in package.toml (docs/PLAN-packages.md "Integrations", hobnix/core#926). Sourced after ui.sh:
#   . "$(dirname "$0")/lib/integration.sh"      (needs $here = the scripts folder)
#   integration_available            names of the packages that are there: recipes installed, extensions and capabilities on
#   integration_credentials <caller>  "<name>	<key file>" lines for the declared integration:<name> permissions (for systemd LoadCredential=, see ext.sh svc-run)
#   integration_key <name> <caller>  writes the key of the integration <name> on stdout when <caller> (an extension) declares
#                                    permissions = ["integration:<name>"] or is a capability; the key is read through secret.sh, never put in
#                                    argv or the environment: the caller reads stdout (a pipe or a file it redirects to). Returns 1 with a note
#                                    on stderr when refused or the key is locked or missing. The permission is a declared check only: it is not
#                                    enforced (hobnix/server#239), a caller that reads the key file itself is not stopped.
. "${BASH_SOURCE[0]%/*}/secret.sh"

integration_available() {
  { bash "$here/recipes-list.sh" --list 2>/dev/null | awk -F'\t' '$4=="installed"{print $1}'
    bash "$here/parts.sh" --list 2>/dev/null | awk -F'\t' '$2=="on"{print $1}'; } || true
}

integration_credentials() {   # integration_credentials <caller>: "<name><TAB><key file><TAB><providing package>" for each declared integration:<name> whose key is readable
  # The file is only named here, never read. The bridge (ext_service.py) reads it once, checks it and hands a private copy to systemd LoadCredential=
  # ($CREDENTIALS_DIRECTORY/integration-<name> in the service). The providing package comes from its registered manifest, never from the path.
  local caller=$1 perm name on path prov
  on=$(integration_available)
  while IFS= read -r perm; do
    case "$perm" in integration:*) name=${perm#integration:} ;; *) continue ;; esac
    # shellcheck disable=SC2086
    path=$(python3 -I "$here/pkg.py" integration-grant "$name" "$caller" $on) || { warn "$path" >&2; continue; }
    prov=${path#*$'\t'}; path=${path%%$'\t'*}
    case "$(secret_state "$path")" in
      ok) printf '%s\t%s\t%s\n' "$name" "$path" "$prov" ;;
      locked) warn "The key of $name is locked: unlock the vault first." >&2 ;;
      *) warn "The key file of $name is missing." >&2 ;;
    esac
  done < <(python3 "$here/pkg.py" perms "$caller" 2>/dev/null)
}

integration_key() {
  local name=$1 caller=$2 on path st
  on=$(integration_available)
  # shellcheck disable=SC2086
  path=$(python3 -I "$here/pkg.py" integration-key "$name" "$caller" $on) || { warn "$path" >&2; return 1; }
  st=$(secret_state "$path")
  case "$st" in
    ok) cat -- "$path" ;;
    locked) warn "The key of $name is locked: unlock the vault first." >&2; return 1 ;;
    *) warn "The key file of $name is missing." >&2; return 1 ;;
  esac
}
