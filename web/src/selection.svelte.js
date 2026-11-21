// The selected row of the current list page, kept in the address (`?sel=<name>[&tab=<tab>]`) so that a reload, a pasted link and Back/Forward work.
// The rules are in selection-core.js (tested in node). `selected()` is reactive: it reads route.query.
import { route, setQuery } from './route.svelte.js';
import { makeSelection } from './selection-core.js';

const sel = makeSelection({
  query: () => route.query,
  state: () => history.state,
  setQuery,
  back: () => history.back(),
});

export const selected = sel.selected;
export const select = sel.select;
export const close = sel.close;
