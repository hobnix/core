// The selection foundation (docs/PLAN-navigation.md step 0): ?sel= and its history rule with a fake browser, the pure query helpers, the table of
// named places (web/src/paths.js) and the object registry (objects.js). Run with node; no framework needed.
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { P, poolPath, dockerAppPath, capabilityPath, nodePath, withQuery } from '../web/src/paths.js';
import { mergeQuery, toSearch } from '../web/src/query.js';
import { makeSelection } from '../web/src/selection-core.js';
import { objectOf, objects } from '../web/src/objects.js';
import { itemOf, titleOf, poolItems } from '../web/src/nav.js';

let ok = 0, bad = 0;
const eq = (name, got, want) => { if (JSON.stringify(got) === JSON.stringify(want)) { ok++; console.log(`  ok    ${name}`); } else { bad++; console.log(`  FAIL  ${name}: got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`); } };

// ── the query helpers
eq('merge adds', mergeQuery({ pool: 'tank' }, { sel: 'a b' }), { pool: 'tank', sel: 'a b' });
eq('merge removes null, undefined and empty', mergeQuery({ sel: 'x', tab: 'y', pool: 'p' }, { sel: null, tab: undefined, pool: '' }), {});
eq('merge writes strings', mergeQuery({}, { n: 3 }), { n: '3' });
eq('an empty query is no search', toSearch({}), '');
eq('names are encoded', toSearch({ sel: 'a b/c&d' }), '?sel=a%20b%2Fc%26d');

// ── a fake browser: a history list with a cursor, as the real one behaves for push, replace, back and forward
function browser(start = '/storage/disks') {
  const h = { entries: [{ url: start, state: {} }], i: 0 };
  const parse = (u) => { const [path, s = ''] = u.split('?'); return { path, query: Object.fromEntries(new URLSearchParams(s)) }; };
  const env = {
    query: () => parse(h.entries[h.i].url).query,
    state: () => h.entries[h.i].state,
    setQuery(patch, { replace = false, state } = {}) {
      const cur = parse(h.entries[h.i].url);
      const to = cur.path + toSearch(mergeQuery(cur.query, patch));
      if (to === h.entries[h.i].url) return;
      if (replace) h.entries[h.i] = { url: to, state: state ?? h.entries[h.i].state ?? {} };
      else { h.entries.splice(h.i + 1); h.entries.push({ url: to, state: state ?? {} }); h.i++; }
    },
    back() { if (h.i > 0) h.i--; },
  };
  return { h, env, forward() { if (h.i < h.entries.length - 1) h.i++; }, url: () => h.entries[h.i].url };
}

{
  const b = browser(); const s = makeSelection(b.env);
  eq('nothing selected at first', s.selected(), '');
  s.select('sda');
  eq('opening writes ?sel=', [s.selected(), b.url()], ['sda', '/storage/disks?sel=sda']);
  eq('opening pushed ONE entry', b.h.entries.length, 2);
  s.select('sdb'); s.select('sdc'); s.select('sdd', { tab: 'smart' });
  eq('switching rows replaces: still two entries', b.h.entries.length, 2);
  eq('the tab is in the address', b.url(), '/storage/disks?sel=sdd&tab=smart');
  s.select('sde');
  eq('a row switch without a tab drops the old tab', b.url(), '/storage/disks?sel=sde');
  s.close();
  eq('close goes back one entry (the quick look added it)', [s.selected(), b.url(), b.h.i], ['', '/storage/disks', 0]);
  b.forward();
  eq('Forward opens it again', [s.selected(), b.url()], ['sde', '/storage/disks?sel=sde']);
  b.env.back();
  eq('Back closes it', s.selected(), '');
}
{
  const b = browser('/storage/disks?sel=sda&pool=tank'); const s = makeSelection(b.env);   // a pasted link or a reload: nothing was pushed by us
  eq('a pasted link starts open', s.selected(), 'sda');
  s.select('sdb');
  eq('switching on a pasted link replaces', [b.h.entries.length, b.url()], [1, '/storage/disks?sel=sdb&pool=tank']);
  s.close();
  eq('close on a pasted link replaces (no Back out of the app), the filter stays', [b.h.entries.length, b.url()], [1, '/storage/disks?pool=tank']);
  s.close();
  eq('closing a closed quick look does nothing', b.h.entries.length, 1);
}
{
  const b = browser('/storage/disks?pool=tank'); const s = makeSelection(b.env);
  s.select('sda');
  eq('opening keeps the other query keys', b.url(), '/storage/disks?pool=tank&sel=sda');
  s.select('a b/c');
  eq('a name with a space and a slash is encoded and read back', [b.url(), s.selected()], ['/storage/disks?pool=tank&sel=a%20b%2Fc', 'a b/c']);
}

// ── the table of places
const values = Object.values(P);
eq('every place has its own path', new Set(values).size, values.length);
eq('every path is an inner path', values.filter((v) => !v.startsWith('/')), []);
eq('pool path', poolPath('tank'), '/storage/pools/tank');
eq('docker app path is encoded', dockerAppPath('a b'), '/apps/docker/app/a%20b');
eq('capability path', capabilityPath('docker'), '/settings/capabilities/docker');
eq('node path', nodePath('home server'), '/node/home%20server');
eq('a list with a filter', withQuery(P.disks, { pool: 'none' }), '/storage/disks?pool=none');
eq('a list without a filter', withQuery(P.disks, {}), '/storage/disks');

// ── the object registry: pools are the one kind today
eq('a pool address is an object', objectOf('/storage/pools/tank'), { kind: 'pool', id: 'tank', tab: '' });
eq('a tab after the id', objectOf('/storage/pools/tank/members'), { kind: 'pool', id: 'tank', tab: 'members' });
eq('the list is not an object', objectOf('/storage/pools'), null);
eq('another path is not an object', objectOf('/storage/disks'), null);
eq('the registry points at the list', objects.pool.list, P.pools);
eq('a pool page is a page of the Pools item', itemOf('/storage/pools/tank')?.path, P.pools);
eq('a pool page title ends with its name', titleOf('/storage/pools/tank').slice(-2), ['Pools', 'tank']);
eq('a pool tree item is its address', poolItems([{ name: 'tank', role: 'apps' }])[0].path, '/storage/pools/tank');

// ── no literal inner path is left in a go(...) or url(...) call under web/src (a path is spelled through paths.js)
const src = join(dirname(fileURLToPath(import.meta.url)), '..', 'web', 'src');
const left = [];
(function walk(d) {
  for (const n of readdirSync(d)) {
    const p = join(d, n);
    if (statSync(p).isDirectory()) { walk(p); continue; }
    if (!/\.(svelte|js)$/.test(n)) continue;
    readFileSync(p, 'utf8').split('\n').forEach((line, i) => {
      if (/^\s*(\/\/|\*)/.test(line)) return;
      if (/\b(go|url)\(\s*[`'"]\/(?!node\/)[a-z]/.test(line)) left.push(`${p.slice(src.length + 1)}:${i + 1}`);
    });
  }
})(src);
eq('no literal path in go() or url()', left, []);

console.log(`  -> ${ok} ok, ${bad} failed`);
process.exit(bad ? 1 : 0);
