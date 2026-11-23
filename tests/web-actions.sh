#!/usr/bin/env bash
# No action row (`{#snippet actions()}` or an element with class actions/acts/*-actions) with more than three visible Buttons, and a file
# over three may not rise above tests/web-actions.tsv (#457, scripts/dev/web-actions.py): the real tree passes, a fixture with four visible
# buttons fails, a Menu does not count, rising and lowered numbers fail, --update fixes it.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
AC=$ROOT/scripts/dev/web-actions.py
python3 "$AC" >/dev/null 2>&1; check_eq "real tree matches the baseline" 0 "$?"
FX=$WORK/fixture
BASE=$WORK/base.tsv
mkdir -p "$FX/pages"
printf 'file\tbuttons\n' > "$BASE"
three='{#snippet actions()}<Button>A</Button><Button>B</Button><Button>C</Button>{/snippet}'
four='{#snippet actions()}<Button>A</Button><Button>B</Button><Button>C</Button><Button>D</Button>{/snippet}'
printf '<PageHeader title="x">%s</PageHeader>\n' "$three" > "$FX/pages/A.svelte"
python3 "$AC" --root "$FX" --baseline "$BASE" >/dev/null 2>&1; check_eq "three visible buttons pass" 0 "$?"
printf '<PageHeader title="x">%s</PageHeader>\n' "$four" > "$FX/pages/A.svelte"
out=$(python3 "$AC" --root "$FX" --baseline "$BASE" 2>&1); rc=$?
check_eq "four visible buttons fail" 1 "$rc"
check_match "the file and the count are named" 'pages/A.svelte: 4 visible buttons in an action row > 3' "$out"
printf '<div class="head-actions"><Button>A</Button><Button>B</Button><Button>C</Button><Button>D</Button></div>\n' > "$FX/pages/A.svelte"
python3 "$AC" --root "$FX" --baseline "$BASE" >/dev/null 2>&1; check_eq "four buttons in a div.actions row fail" 1 "$?"
printf '<PageHeader>{#snippet actions()}<Button>A</Button><Button>B</Button><Menu><Button>C</Button><Button>D</Button></Menu>{/snippet}</PageHeader>\n' > "$FX/pages/A.svelte"
python3 "$AC" --root "$FX" --baseline "$BASE" >/dev/null 2>&1; check_eq "buttons inside a Menu do not count" 0 "$?"
printf '<div class="row"><Button>A</Button><Button>B</Button><Button>C</Button><Button>D</Button></div>\n' > "$FX/pages/A.svelte"
python3 "$AC" --root "$FX" --baseline "$BASE" >/dev/null 2>&1; check_eq "a row that is not an action row is not counted" 0 "$?"
printf '<PageHeader title="x">%s</PageHeader>\n' "$four" > "$FX/pages/A.svelte"
python3 "$AC" --root "$FX" --baseline "$BASE" --update >/dev/null 2>&1
python3 "$AC" --root "$FX" --baseline "$BASE" >/dev/null 2>&1; check_eq "a baseline of four lets four pass" 0 "$?"
printf '<PageHeader title="x">%s</PageHeader>\n' "${four/<Button>D<\/Button>/<Button>D<\/Button><Button>E<\/Button>}" > "$FX/pages/A.svelte"
out=$(python3 "$AC" --root "$FX" --baseline "$BASE" 2>&1); rc=$?
check_eq "five visible buttons above a baseline of four fail" 1 "$rc"
check_match "the rise is named" 'pages/A.svelte: 5 visible buttons in an action row > 4' "$out"
printf '<PageHeader title="x">%s</PageHeader>\n' "$three" > "$FX/pages/A.svelte"
out=$(python3 "$AC" --root "$FX" --baseline "$BASE" 2>&1); rc=$?
check_eq "a lowered count fails until the baseline is lowered" 1 "$rc"
check_match "the lowered count gives the hint" 'lower the number' "$out"
python3 "$AC" --root "$FX" --baseline "$BASE" --update >/dev/null 2>&1
python3 "$AC" --root "$FX" --baseline "$BASE" >/dev/null 2>&1; check_eq "after --update it passes" 0 "$?"
finish
