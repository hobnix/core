#!/usr/bin/env bash
# shellcheck findings at warning level per shell file may only go down (baseline tests/shellcheck-ratchet.tsv, the same file<TAB>count
# shape as tests/pool-names-ratchet.tsv and tests/web-ratchet.tsv). CI runs it on the shell files a pull request changed.
#   scripts/dev/shellcheck-ratchet.sh [--root DIR] [--baseline FILE] [FILE...]    check these files (no FILE: every shell file)
#   scripts/dev/shellcheck-ratchet.sh [--root DIR] [--baseline FILE] --update [FILE...]   write the counts into the baseline
# A file that is not in the baseline counts as 0. More findings than the baseline: exit 1. Fewer: exit 1 too, with the hint to lower
# the number (--update), so the baseline always shows what is left. A file that is gone but still in the baseline is reported the same way.
set -uo pipefail
here=$(dirname "$0"); . "$here/../lib/ui.sh"
root=$(cd "$here/../.." && pwd); baseline=; update=0; files=()
while [ $# -gt 0 ]; do
  case "$1" in
    --root) root=$2; shift 2 ;;
    --baseline) baseline=$2; shift 2 ;;
    --update) update=1; shift ;;
    -*) say "usage: shellcheck-ratchet.sh [--root DIR] [--baseline FILE] [--update] [FILE...]"; exit 2 ;;
    *) files+=("$1"); shift ;;
  esac
done
baseline=${baseline:-$root/tests/shellcheck-ratchet.tsv}
command -v shellcheck >/dev/null 2>&1 || { warn "$(t 'shellcheck is not installed.')"; exit 2; }
cd "$root" || exit 2
all=0
if [ ${#files[@]} -eq 0 ]; then
  all=1
  # the same list as the "errors only" step of .github/workflows/ci.yml
  for f in scripts/*.sh scripts/lib/*.sh scripts/recipes/*.sh vps/*.sh tests/*.sh; do [ -f "$f" ] && files+=("$f"); done
fi

declare -A base=() now=()
if [ -f "$baseline" ]; then
  while IFS=$'\t' read -r f n; do [ "$f" = file ] || [ -z "$f" ] || base[$f]=$n; done < "$baseline"
fi
for f in "${files[@]}"; do
  [ -f "$f" ] || continue
  now[$f]=$(shellcheck -x -S warning -f gcc "$f" 2>/dev/null | grep -c ': \(warning\|error\):')
done

if [ "$update" = 1 ]; then
  for f in "${!now[@]}"; do base[$f]=${now[$f]}; done
  # a whole run also drops rows of files that are gone
  if [ "$all" = 1 ]; then for f in "${!base[@]}"; do [ -f "$f" ] || unset "base[$f]"; done; fi
  {
    printf 'file\tcount\n'
    for f in "${!base[@]}"; do [ "${base[$f]}" -gt 0 ] && printf '%s\t%s\n' "$f" "${base[$f]}"; done | LC_ALL=C sort
  } > "$baseline"
  ok "$(t 'Baseline written: %s' "${baseline#"$root"/}")"
  exit 0
fi

rc=0
for f in "${files[@]}"; do
  if [ ! -f "$f" ]; then
    [ -n "${base[$f]:-}" ] && { warn "$f: $(t 'the file is gone, remove the row from the baseline (--update)')"; rc=1; }
    continue
  fi
  n=${now[$f]}; b=${base[$f]:-0}
  if [ "$n" -gt "$b" ]; then warn "$f: shellcheck findings $n > $b"; rc=1
  elif [ "$n" -lt "$b" ]; then warn "$f: shellcheck findings $n < $b: lower the number (scripts/dev/shellcheck-ratchet.sh --update $f)"; rc=1
  fi
done
if [ "$rc" = 0 ]; then ok "$(t 'Shellcheck findings are not above the baseline.')"; else
  note "$(t 'Fix the findings (shellcheck -x -S warning FILE); the baseline only goes down.')"
fi
exit "$rc"
