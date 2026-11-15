// The pool rows of this server (`hs sys pool list`), read once per page load; no timer. A server without that list has the two legacy pools.
import { get } from './api.js';
import { LEGACY_POOLS, parsePoolRows } from './pages/storage/pool.js';

export const pools = $state({ rows: [], loaded: false, legacy: false });

let pending = null;

export function loadPools(force = false) {
  if (pending && !force) return pending;
  pending = get('/api/sys/pool/list')
    .then((d) => {
      pools.rows = parsePoolRows(d.rows ?? []);
      pools.legacy = false;
    })
    .catch(() => {
      pools.rows = LEGACY_POOLS;
      pools.legacy = true;
    })
    .finally(() => {
      pools.loaded = true;
    });
  return pending;
}

export const poolNames = () => pools.rows.map((p) => p.name);
export const poolsOfRole = (role) => pools.rows.filter((p) => p.role === role).map((p) => p.name);
export const poolOfRole = (role) => poolsOfRole(role)[0] ?? '';
// the Shares page of the data pool (the shares live there); the bare page while there is none
export const sharesPath = () => (poolOfRole('data') ? `/storage/shares?pool=${poolOfRole('data')}` : '/storage/shares');
export const poolRow = (name) => pools.rows.find((p) => p.name === name) ?? null;
