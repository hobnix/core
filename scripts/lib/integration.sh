#!/usr/bin/env bash
# What packages offer to each other: [integrations.<name>] in package.toml (docs/PLAN-packages.md "Integrations", hobnix/core#926). Sourced after ui.sh:
#   . "$(dirname "$0")/lib/integration.sh"      (needs $here = the scripts folder)
#   integration_available            names of the packages that are there: recipes installed, extensions and capabilities on
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
