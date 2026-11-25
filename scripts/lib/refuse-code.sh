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
  # a caller that also runs at a terminal defines refuse_terminal: it ends the command there and returns for the interface
  if declare -F refuse_terminal >/dev/null; then refuse_terminal "$text"; fi
  # a caller whose texts come from a package defines refuse_clean (blueprint-change.sh): it makes one safe line of the reason
  if declare -F refuse_clean >/dev/null; then text=$(refuse_clean "$text"); fi
  printf 'status\trefused\nreason\t%s\n' "${text:-${cat_text:-The server did not do this.}}"
  [ "$fix" = - ] || printf 'fix\t%s\n' "$fix"
  printf 'code\t%s\n' "$code"
  # a job that ends on this refusal: its record gets the code (hs_job_record finish reads the file). Only the job's own top-level script counts
  # (its parent is the job unit's shell, HS_JOB_PID, and it is no subshell): a refusal a job catches in a child must not name the job's code.
  # Best effort, never changes the output or the exit.
  if [ -n "${HS_JOB_ID:-}" ] && [ "${HS_JOB_PID:-}" = "$PPID" ] && [ "$BASH_SUBSHELL" = 0 ] \
     && [[ "$HS_JOB_ID" =~ ^[0-9]{8}-[0-9]{6}-[A-Za-z0-9-]+-[a-z]{4}$ ]]; then
    local dir=${HS_JOBS_DIR:-/var/lib/hs/jobs} tmp
    if [ -d "$dir" ] && [ ! -L "$dir/$HS_JOB_ID.code" ] && tmp=$(umask 077; mktemp "$dir/.code.XXXXXX" 2>/dev/null); then
      { printf '%s\n' "$code" >"$tmp" && mv -f "$tmp" "$dir/$HS_JOB_ID.code"; } 2>/dev/null || rm -f "$tmp"
    fi
  fi
  exit 1
}
