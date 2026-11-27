#!/usr/bin/env bash
# File size ratchet for rust/ (docs/CODE-PRACTICES.md "Rust: size"): the lines of a .rs file before its `#[cfg(test)]` module (the whole
# file when it has none). Integration tests (rust/*/tests/) and build output are not counted. Developer tool and CI helper (job `rust`).
#   rust-size-ratchet.sh check   a file not in the baseline has at most 400 lines; a listed file not more than its baseline (exit 1 otherwise)
#   rust-size-ratchet.sh lower   lower the baseline to what the files have now; drops files that are back under the limit. Never raises.
#   rust-size-ratchet.sh list    "<lines>\t<path>" for every counted file
# The baseline is tests/rust-size-ratchet.tsv: "<lines>\t<path relative to the repository>", one line per file over the limit.
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
root=${HS_RUST_SIZE_ROOT:-$repo}
base=${HS_RUST_SIZE_BASELINE:-$repo/tests/rust-size-ratchet.tsv}
limit=400

count() { awk '/^#\[cfg\(test\)\]/ { exit } { n++ } END { print n + 0 }' "$1"; }
files() {
  (cd "$root" && find rust -name '*.rs' -not -path '*/target/*' -not -path 'rust/*/tests/*' | LC_ALL=C sort)
}
list() { files | while read -r f; do printf '%s\t%s\n' "$(count "$root/$f")" "$f"; done; }
allowed() { [ -f "$base" ] && awk -F'\t' -v f="$1" '$2 == f { print $1; exit }' "$base"; }

case "${1:-}" in
  list) list ;;
  check)
    bad=0
    while IFS=$'\t' read -r n f; do
      max=$(allowed "$f"); max=${max:-$limit}
      if [ "$n" -gt "$max" ]; then
        if [ "$max" = "$limit" ]; then echo "$f: $n lines before its tests, the limit is $limit: split it" >&2
        else echo "$f: $n lines before its tests, more than its ratchet $max (tests/rust-size-ratchet.tsv): it may not grow" >&2; fi
        bad=1
      elif [ "$max" != "$limit" ] && [ "$n" -lt "$max" ]; then
        echo "$f: $n lines, ratchet $max: run scripts/dev/rust-size-ratchet.sh lower and commit the baseline" >&2
      fi
    done < <(list)
    [ "$bad" = 0 ] && echo "rust file sizes ok"
    exit "$bad" ;;
  lower)
    [ -f "$base" ] || { echo "no baseline at $base" >&2; exit 1; }
    tmp=$(mktemp)
    while IFS=$'\t' read -r max f; do
      [ -n "$f" ] && [ -f "$root/$f" ] || continue
      n=$(count "$root/$f")
      [ "$n" -gt "$limit" ] || continue
      [ "$n" -lt "$max" ] && max=$n
      printf '%s\t%s\n' "$max" "$f"
    done < "$base" > "$tmp"
    mv "$tmp" "$base"
    echo "baseline lowered: $(wc -l < "$base") files" ;;
  *) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
