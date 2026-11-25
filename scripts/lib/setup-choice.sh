# shellcheck shell=bash
# The setup choice: what a new server is to be set up for after the first boot (#1075). hs-install records it, hs first-run reads it.
# File <state>/setup-choice, mode 644, two lines: choice<TAB>blueprint|parts|core|wizard|done and name<TAB><blueprint name, parts csv or ->.
# Only the shape of a name is checked here; a blueprint is verified against the signed index when it is planned. Sourced, prints nothing else.

setup_name_ok() { [[ "$1" =~ ^[a-z0-9][a-z0-9-]{0,40}$ ]]; }
setup_parts_ok() { [[ "$1" =~ ^[a-z0-9][a-z0-9-]{0,40}(,[a-z0-9][a-z0-9-]{0,40})*$ ]]; }

setup_choice_write() {   # setup_choice_write <file> <choice> <name|->
  printf 'choice\t%s\nname\t%s\n' "$2" "$3" > "$1" && chmod 644 "$1"
}

# setup_choice_read <file>: "<choice> <name>" of a well-formed record, else nothing (a damaged or edited file counts as no record)
setup_choice_read() {
  local c n
  [ -r "$1" ] || return 0
  c=$(awk -F'\t' '$1 == "choice" { print $2; exit }' "$1")
  n=$(awk -F'\t' '$1 == "name" { print $2; exit }' "$1")
  case "$c" in
    blueprint) setup_name_ok "$n" || return 0 ;;
    parts) setup_parts_ok "$n" || return 0 ;;
    core|wizard|done) n=- ;;
    *) return 0 ;;
  esac
  printf '%s %s\n' "$c" "$n"
}
