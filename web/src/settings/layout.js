// Which Settings subpage shows which key (pure, no imports: tests/web-settings-layout.mjs runs it in node). `layout` is
// settings/layout.gen.json (scripts/schema-gen.py): { pages: [ids], keys: { key: page }, caps: { name: { title, icon, entry } } }.
// A page is one of layout.pages or `cap:<name>`. Every key is ALSO on the page `advanced` (the full list).

export const pageOf = (layout, key) => layout.keys[key] ?? null;

// the options (any object with a `key`) that belong on a page; Advanced shows all of them
export const fieldsFor = (layout, page, opts) => (page === 'advanced' ? opts : opts.filter((o) => layout.keys[o.key] === page));

// the label of a capability in the tree: its manifest title without the explanation in brackets
export const shortTitle = (title) => title.replace(/\s*\(.*$/, '');

// Tree items for the capabilities that are ON (names = ui.features.capabilities) and have a page of their own, sorted by title.
// null/undefined names (the server did not say): none, the Capabilities overview lists them all.
export function capEntries(layout, names) {
  if (!Array.isArray(names)) return [];
  return Object.entries(layout.caps)
    .filter(([n, c]) => c.entry && names.includes(n))
    .map(([n, c]) => ({ label: shortTitle(c.title), icon: c.icon, path: `/settings/capabilities/${n}` }))
    .sort((a, b) => a.label.localeCompare(b.label));
}

// layout.gen.json plus layout.overlay.json (GET /api/settings-layout: { keys, caps } of the capability packages installed on this machine). The core
// wins: an overlay key or capability that the core already has is ignored. A bad or empty overlay leaves the core layout as it is.
export function mergeLayout(core, overlay) {
  if (!overlay || typeof overlay !== 'object') return core;
  const keys = { ...core.keys };
  const caps = { ...core.caps };
  for (const [k, p] of Object.entries(overlay.keys ?? {})) if (!(k in core.keys) && typeof p === 'string' && p.startsWith('cap:')) keys[k] = p;
  for (const [n, c] of Object.entries(overlay.caps ?? {})) if (!(n in core.caps) && c && typeof c.title === 'string') caps[n] = { title: c.title, icon: c.icon || 'puzzle-piece', entry: c.entry !== false };
  return { ...core, keys, caps };
}
