#!/usr/bin/env bash
# The shellcheck findings per file may only go down (scripts/dev/shellcheck-ratchet.sh, baseline tests/shellcheck-ratchet.tsv): a fixture
# shows rising, new, lowered and removed files failing and --update fixing it. The real baseline is checked on one small file.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
have shellcheck || { skip "shellcheck is not installed"; finish; exit 0; }
RT=$ROOT/scripts/dev/shellcheck-ratchet.sh
FX=$WORK/fixture
BASE=$WORK/base.tsv
mkdir -p "$FX/scripts"
printf '#!/bin/bash\ncd /a\ncd /b\n' > "$FX/scripts/x.sh"
bash "$RT" --root "$FX" --baseline "$BASE" --update >/dev/null 2>&1
check_eq "baseline counts the warnings" "$(printf 'file\tcount\nscripts/x.sh\t2\n')" "$(cat "$BASE")"
bash "$RT" --root "$FX" --baseline "$BASE" scripts/x.sh >/dev/null 2>&1; check_eq "fresh baseline passes" 0 "$?"
printf '#!/bin/bash\ncd /a\ncd /b\ncd /c\n' > "$FX/scripts/x.sh"
out=$(bash "$RT" --root "$FX" --baseline "$BASE" scripts/x.sh 2>&1); rc=$?
check_eq "rising count fails" 1 "$rc"
check_match "rising count names the file" 'scripts/x.sh: shellcheck findings 3 > 2' "$out"
printf '#!/bin/bash\ncd /a\ncd /b\n' > "$FX/scripts/x.sh"
printf '#!/bin/bash\ncd /a\n' > "$FX/scripts/y.sh"
out=$(bash "$RT" --root "$FX" --baseline "$BASE" scripts/x.sh scripts/y.sh 2>&1); rc=$?
check_eq "new file with a finding fails" 1 "$rc"
check_match "new file is named" 'scripts/y.sh: shellcheck findings 1 > 0' "$out"
rm "$FX/scripts/y.sh"
printf '#!/bin/bash\ncd /a || exit\ncd /b\n' > "$FX/scripts/x.sh"
out=$(bash "$RT" --root "$FX" --baseline "$BASE" scripts/x.sh 2>&1); rc=$?
check_eq "lowered count fails" 1 "$rc"
check_match "lowered count gives the hint" 'scripts/x.sh: shellcheck findings 1 < 2: lower the number' "$out"
rm "$FX/scripts/x.sh"
out=$(bash "$RT" --root "$FX" --baseline "$BASE" scripts/x.sh 2>&1); rc=$?
check_eq "removed file fails" 1 "$rc"
check_match "removed file asks to remove the row" 'scripts/x.sh: .*remove the row' "$out"
bash "$RT" --root "$FX" --baseline "$BASE" --update >/dev/null 2>&1
check_eq "after --update the row is gone" "$(printf "file	count")" "$(cat "$BASE")"
(cd "$ROOT" && bash "$RT" scripts/lib/i18n.sh) >/dev/null 2>&1; check_eq "the real baseline holds for a real file" 0 "$?"
finish
