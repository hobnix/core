// The query part of an address as pure functions (route.svelte.js applies them; tests/web-select.mjs runs them in plain node).

// `patch` over `query` (both plain objects). A key whose value is null, undefined or '' is removed; the others are written as strings.
export function mergeQuery(query, patch) {
  const out = { ...query };
  for (const [k, v] of Object.entries(patch ?? {})) {
    if (v === null || v === undefined || v === '') delete out[k];
    else out[k] = String(v);
  }
  return out;
}

// '?a=1&b=x%20y' or '' for an empty object; names and values go through encodeURIComponent
export function toSearch(query) {
  const parts = Object.entries(query ?? {}).map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`);
  return parts.length ? `?${parts.join('&')}` : '';
}
