// The registry of objects that can have a page of their own (docs/PLAN-navigation.md, #453): a kind -> where its list is, where its pages live, its name and its tabs.
// Data only (no component), so that nav.js and the node tests can import it. The component of a kind is one line in `objectPages` of routes.js.
// `pageFor` (routes.js), `itemOf` and `titleOf` (nav.js) read it, so a new object adds one line here and one there, not a special case per function.
// An object page is /<group>/<kind>/<id>[/<tab>] (D6): `base` is the path up to the id. `tabs` is [] while the page has none (the pool page has no tabs yet).
import { P } from './paths.js';

export const objects = {
  pool: { label: 'Pool', list: P.pools, base: `${P.pools}/`, tabs: [] },
};

// the object an INNER path names: { kind, id, tab } (id decoded, tab '' when there is none), or null
export function objectOf(path) {
  for (const [kind, def] of Object.entries(objects)) {
    if (!path.startsWith(def.base) || path.length === def.base.length) continue;
    const [id, tab = ''] = path.slice(def.base.length).split('/');
    let name = id;
    try { name = decodeURIComponent(id); } catch { /* a malformed name stays as written */ }
    return { kind, id: name, tab };
  }
  return null;
}
