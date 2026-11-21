// The selected row of a list as one query key (`?sel=<name>`, D6) and its history rule (docs/PLAN-navigation.md, #455), without any framework:
// `env` is { query(), state(), setQuery(patch, {replace, state}), back() }. selection.svelte.js wires it to route.svelte.js; tests/web-select.mjs to a fake browser.
//   select(name)  no quick look open: PUSH one entry marked { ql: 1 }; one already open: REPLACE it (Back must not walk over every row)
//   close()       the entry was pushed by the quick look: go Back one entry (so Back and Close are the same); otherwise (a pasted link, a reload of
//                 an address that was not pushed) take `sel` out of the address by replacing it
export const SEL = 'sel';
export const TAB = 'tab';

export function makeSelection(env) {
  const selected = () => env.query()[SEL] ?? '';
  return {
    selected,
    select(name, { tab } = {}) {
      const patch = { [SEL]: name, [TAB]: tab ?? null };
      if (selected()) env.setQuery(patch, { replace: true });
      else env.setQuery(patch, { replace: false, state: { ql: 1 } });
    },
    close() {
      if (!selected()) return;
      if (env.state()?.ql) env.back();
      else env.setQuery({ [SEL]: null, [TAB]: null }, { replace: true });
    },
  };
}
