#!/usr/bin/env bash
# refuse_code, alone so that a change script can use it without the rest of ui.sh (ui.sh sources this file). ADR 0028.

# refuse_code <code> [<reason>]: a refused plan or start for the web interface (ADR 0028), then exit 1. Prints the lines status, reason (the
# given text, else the text of the catalogue), fix (only when the catalogue has one) and code. The code must be in scripts/lib/error-codes.tsv
# (tests/error-codes.sh). Plain machine lines, not terminal output: no colour, no translation.
_ERROR_CODES=${BASH_SOURCE[0]%/*}/error-codes.tsv
refuse_code() {
  local code=$1 text=${2:-} fix=- row cat_text
  row=$(awk -F'\t' -v c="$code" '$1 == c { print $4 "\t" $5; exit }' "$_ERROR_CODES" 2>/dev/null) || row=
  cat_text=${row%%$'\t'*}
  [ -z "$row" ] || fix=${row#*$'\t'}
  printf 'status\trefused\nreason\t%s\n' "${text:-${cat_text:-The server did not do this.}}"
  [ "$fix" = - ] || printf 'fix\t%s\n' "$fix"
  printf 'code\t%s\n' "$code"
  exit 1
}
