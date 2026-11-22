# web/

- A page is built from the components in `web/src/ui` (and `shell/`). If one is missing, add it to `ui` first, then use it.
- Raw `<input>`, `<select>`, `<textarea>`, an own `<style>` block and hex colours may only go down per file: `tests/web-ratchet.sh`
  compares against `tests/web-ratchet.tsv`. A new raw one fails; removing one also fails until you lower the number
  (`python3 tests/web-ratchet-test.py --update`), so a win is locked in.
- Every button is `ui/Button.svelte` (tests/web-buttons.sh).
- An action row (`{#snippet actions()}`, class `actions`/`acts`/`*-actions`) shows at most three visible `Button`s, the rest go in a `Menu`:
  `tests/web-actions.sh` (counter `scripts/dev/web-actions.py`) holds the files still over three in `tests/web-actions.tsv`; the number only
  goes down (`python3 scripts/dev/web-actions.py --update` after you lower one).
- Colours, spacing and fonts come from the tokens in `src/tokens.css`, never a hex value in a page.
- `python3 scripts/dev/web-inventory.py` counts shared components vs raw markup per folder (`--tsv`, `--classes [N]`, `--files` per file).
