// Arrow-key movement in a menu, free of Svelte so it can be tested. `items` are [{ disabled }]; returns the index to focus next, or -1 when there is none.
export function menuNext(items, from, key) {
  const ok = (i) => !items[i]?.disabled;
  const n = items.length;
  if (!items.some((_, i) => ok(i))) return -1;
  if (key === 'Home') return items.findIndex((_, i) => ok(i));
  if (key === 'End') { for (let i = n - 1; i >= 0; i--) if (ok(i)) return i; }
  const step = key === 'ArrowUp' ? -1 : 1;
  let i = from;
  for (let k = 0; k < n; k++) { i = (i + step + n) % n; if (ok(i)) return i; }
  return -1;
}
