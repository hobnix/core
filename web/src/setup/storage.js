// The Storage step of the first-run wizard (pure). Rows are `hs sys storage discover` (disk, size, bus, model, kind, label, state) and the pool rows.
const RESERVED = 'mirror raidz raidz1 raidz2 raidz3 draid spare log cache special dedup default dir none system incus boot nix etc var home root tmp usr bin sbin lib lib64 srv mnt run proc sys dev opt media'.split(' ');   // lib/pools.sh pool_name_ok
const val = (v) => (v === undefined || v === '-' ? '' : v);

export const parseDiscover = (rows) => (rows || []).filter((r) => r && r[0]).map((r) => ({
  id: r[0], size: Number(r[1]) || 0, bus: val(r[2]), model: val(r[3]), kind: val(r[4]), label: val(r[5]), state: val(r[6]),
}));

// importable: ZFS pools whose every row is importable; empty: free disks; shown: everything else except the system disk
export function groups(discoverRows) {
  const all = parseDiscover(discoverRows);
  const byPool = new Map();
  for (const d of all) {
    if (d.kind !== 'zfs' || !d.label) continue;
    if (!byPool.has(d.label)) byPool.set(d.label, []);
    byPool.get(d.label).push(d);
  }
  const importable = [];
  const ok = new Set();
  for (const [pool, ds] of byPool) {
    if (ds.every((d) => d.state === 'importable')) { importable.push({ pool, disks: ds.map((d) => d.id) }); ok.add(pool); }
  }
  const empty = all.filter((d) => d.kind === 'empty').map(({ id, size, bus, model }) => ({ id, size, bus, model }));
  const shown = all
    .filter((d) => d.kind !== 'os' && d.kind !== 'empty' && !(d.kind === 'zfs' && ok.has(d.label)))
    .map((d) => ({ id: d.id, kind: d.kind, label: d.label, state: d.state }));
  return { importable, empty, shown };
}

export const poolNameOk = (name) => /^[a-z][a-z0-9]{0,11}$/.test(name || '') && !RESERVED.includes(name);

export function suggestName(taken = []) {
  if (!taken.includes('data')) return 'data';
  for (let i = 2; ; i++) if (!taken.includes('data' + i)) return 'data' + i;
}

export const nothingText = (g, poolRows = []) => (!poolRows.length && !g.importable.length && !g.empty.length ? 'No storage pool yet; shares need one.' : '');

// a ZFS pool here is a mirror: an even number of disks, at least two
export const evenPair = (n) => n >= 2 && n % 2 === 0;
