// The pages' first reads (web/src/readsfor.js) must all be allowlisted reads of the web server (READS in scripts/web-serve.py), or the prefetch asks for nothing.
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { readsFor } from '../web/src/readsfor.js';
import { parsePoolRows, ofRole } from '../web/src/pages/storage/pool.js';

let ok = 0, bad = 0;
const check = (name, cond, extra = '') => { if (cond) { ok++; console.log(`  ok    ${name}`); } else { bad++; console.log(`  FAIL  ${name} ${extra}`); } };

const src = readFileSync(new URL('../scripts/web-serve.py', import.meta.url), 'utf8');
const reads = src.slice(src.indexOf('READS = {'), src.indexOf('\nCHANGES = {') > 0 ? src.indexOf('\nCHANGES = {') : undefined);
const known = new Set([...reads.matchAll(/^\s*\("([^"]+)"(?:,\s*"([^"]+)")?,?\):\s*\{/gm)].map((m) => [m[1], m[2]].filter(Boolean).join('/')));
// the reads of the extension packages are declared in their manifests ([[web.reads]] words = "list" -> ext/<name>/list), registered while the package is on
const capDir = new URL('../capabilities/', import.meta.url);
for (const name of readdirSync(capDir)) {
  const f = new URL(`../capabilities/${name}/capability.toml`, import.meta.url);
  if (!existsSync(f)) continue;
  for (const m of readFileSync(f, 'utf8').matchAll(/\[\[web\.reads\]\][^\[]*?^words\s*=\s*"([^"]+)"/gms)) known.add(['ext', name, ...m[1].split(' ')].join('/'));
}
check('the allowlist was read', known.size > 50 && known.has('ct/list') && known.has('status'), String(known.size));

const routes = ['/', '/instances', '/network', '/identity/users', '/identity/groups', '/identity/certificates', '/monitoring/hardware', '/protection/backup', '/storage/pools', '/storage/pools/bulk', '/storage/pools/fast', '/storage/disks', '/storage/shares', '/storage/files',
  '/protection/expiry', '/operations/health', '/instances/apps', '/marketplace', '/instances/services', '/storage/encryption', '/storage/vault',
  '/settings', '/settings/general', '/settings/capabilities', '/settings/capabilities/gateway', '/setup', '/nodes', '/monitoring/diagnostics', '/storage', '/protection', '/operations'];
const missing = [];
let total = 0;
for (const r of routes) {
  const paths = readsFor(r);
  if (!paths.length) missing.push(`${r}: nothing`);
  for (const p of paths) {
    total++;
    const m = p.match(/^\/api\/sys\/([^?]+)/);
    // the words of the read: the path up to a segment that is an argument (none of these pages prefetches one)
    if (!m || !known.has(m[1])) missing.push(`${r}: ${p}`);
  }
}
check(`every one of the ${total} prefetched paths is an allowlisted read`, missing.length === 0, '\n    ' + missing.join('\n    '));
const pages = [{ name: 'demo', blocks: [{ type: 'table', read: 'list' }, { type: 'stats', read: 'disk state' }, { type: 'x', read: 'list' }] }];
check('an extension page reads what its declaration names, once each', JSON.stringify(readsFor('/extensions/demo', pages)) === JSON.stringify(['/api/sys/ext/demo/list', '/api/sys/ext/demo/disk/state']));
check('an extension that is off reads nothing', readsFor('/extensions/demo').length === 0 && readsFor('/extensions/other', pages).length === 0);
const tank = readsFor('/storage/pools', [], false, [{ name: 'tank', role: 'data', kind: 'zfs', state: 'online' }]);
check('the pools page reads the list, not the fixed pools', tank.includes('/api/sys/pool/list') && !tank.some((p) => p.includes('pool=bulk')) && !tank.some((p) => p.includes('pool=tank')));
check('a SnapRAID pool is read for its facts', readsFor('/storage/pools', [], false, [{ name: 'tank', role: 'data', kind: 'snapraid', state: 'online' }]).includes('/api/sys/pool/info?pool=tank'));
check('the disks page reads the members of the SnapRAID pool by name', readsFor('/storage/disks', [], false, [{ name: 'tank', role: 'data', kind: 'snapraid', state: 'online' }]).includes('/api/sys/pool/members?pool=tank') && !readsFor('/storage/disks', [], false, []).some((p) => p.includes('pool=bulk')));
check('the page of one disk prefetches what the list reads (a tab and an encoded name too)', JSON.stringify(readsFor('/storage/disks/sda')) === JSON.stringify(readsFor('/storage/disks', [], false, [])) && readsFor('/node/x/storage/disks/a%20b/smart').length === 4);
const parsed = parsePoolRows([['tank', 'data', 'zfs', 'online'], ['Bad', 'data', 'zfs', 'x'], ['a1234567890123', 'data', 'zfs', 'x'], ['x', 'other', 'zfs', 'x'], ['y', 'apps', 'ext4', 'x'], ['ssd', 'apps', 'snapraid']]);
check('parsePoolRows drops bad rows', parsed.length === 2 && parsed[0].name === 'tank' && parsed[1].state === '-');
check('ofRole lists the names of a role', JSON.stringify(ofRole(parsed, 'apps')) === JSON.stringify(['ssd']));
check('an unknown page prefetches nothing', readsFor('/nowhere').length === 0);
check('the new pool address names its pool', readsFor('/node/hs/storage/pools/fast').some((p) => p.endsWith('pool=fast')) && readsFor('/storage/pools/bulk').some((p) => p.endsWith('pool=bulk')));
const storagePages = ['/storage/pools', '/storage/pools/bulk', '/storage/pools/fast', '/storage/disks', '/storage/shares', '/storage/files', '/storage/encryption', '/storage/vault'];
check('storage prefetch lists are identical with live mode off and on', storagePages.every((r) => JSON.stringify(readsFor(r)) === JSON.stringify(readsFor(r, [], true))));
check('storage pages still prefetch URLs, none named like a topic', storagePages.every((r) => readsFor(r).length > 0 && readsFor(r).every((p) => p.startsWith('/api/sys/') && !/\/(pool-(info|members|state)-|shares-overview|monitor-disks)/.test(p))));
check('storage prefetch is unchanged by live mode', JSON.stringify(readsFor('/storage/pools/bulk')) === JSON.stringify(readsFor('/storage/pools/bulk', [], true)));
check('Diagnostics reads the live status, with live mode off or on', JSON.stringify(readsFor('/monitoring/diagnostics', [], true)) === JSON.stringify(['/api/sys/live/status']) && JSON.stringify(readsFor('/monitoring/diagnostics')) === JSON.stringify(['/api/sys/live/status']));

// a group page reads only reads its places already use (pages/groups/): every path is in the reads of some page below the group
const group = (g, places) => { const own = new Set(places.flatMap((r) => readsFor(r))); return readsFor(g).length > 0 && readsFor(g).every((p) => own.has(p)); };
check('the Storage group page reads only what its places read', group('/storage', ['/storage/pools', '/storage/disks', '/storage/shares', '/storage/encryption']));
check('the Backup group page reads only what its places read', group('/protection', ['/protection/backup', '/protection/expiry']));
check('the System group page reads only what its places read', group('/operations', ['/operations/health', '/identity/certificates', '/monitoring/hardware', '/operations/events', '/settings/updates']));

console.log(`  -> ${ok} ok, ${bad} failed`);
process.exit(bad ? 1 : 0);
