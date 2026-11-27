// The parse and filter of the server-aware form fields (ShareField, DiskField, PoolField, InstanceField, UserField). Plain JS so node can test it.
// Each function turns the rows of one `hs sys ... list` read into Combobox options { value, label, detail, group? } and applies the filter props of its field.
import { sizeTxt } from '../pages/storage/pool.js';
import { userOf, stateOf } from '../pages/identity/user.js';
import { freeDisks, shortId } from '../forms/storage/disks.js';

const asList = (v) => (v == null || v === '' ? [] : Array.isArray(v) ? v : [v]);
// `ct list` rows: name, type, state ... (pages/instances/ct.js has the full parse, but it pulls in the router, which plain node cannot load)
const ctOf = (r) => ({ name: r[0], type: r[1] ?? '', state: r[2] ?? '' });
const isRunning = (c) => /running/i.test(c.state);
const KIND_WORD = { shares: 'share', sensitive: 'sensitive' };

// The name of a share that exists: up to 80 characters, Samba's limit (a NEW share has at most 41; scripts/web-serve.py SHARE_EXISTING).
export const EXISTING_SHARE = /^[a-z0-9][a-z0-9-]{0,79}$/;

// `shares overview` rows: name, kind (shares|sensitive|other), path, cache, size_bytes ... ; "other" rows are no shares of the file server
export function shareOf(r) {
  return { name: r[0] ?? '', kind: r[1] ?? '', bytes: Number(r[4]) || 0 };
}
export function shareOptions(rowList, { kind, exclude } = {}) {
  const kinds = asList(kind), skip = asList(exclude);
  return rowList.map(shareOf)
    .filter((s) => EXISTING_SHARE.test(s.name) && s.kind !== 'other' && (!kinds.length || kinds.includes(s.kind)) && !skip.includes(s.name))
    .map((s) => ({ value: s.name, label: s.name, detail: [KIND_WORD[s.kind] ?? s.kind, s.bytes ? sizeTxt(s.bytes) : ''].filter(Boolean).join(' · ') }));
}

// The value of a ShareField that offers the remote group: { scope: 'local'|'remote', peer, share }. The local-only field keeps the plain name.
export const LOCAL = 'local';
export const REMOTE = 'remote';
export const shareValue = (scope, peer, share) => ({ scope, peer: scope === REMOTE ? peer : '', share });
// the option value of a share in the combined list: a name cannot hold a slash, so `<peer>/<share>` is unambiguous
export const encodeShare = (v) => (!v?.share ? '' : v.scope === REMOTE ? `${REMOTE}:${v.peer}/${v.share}` : `${LOCAL}:${v.share}`);
export function decodeShare(s) {
  if (!s) return shareValue(LOCAL, '', '');
  if (s.startsWith(`${REMOTE}:`)) {
    const rest = s.slice(REMOTE.length + 1), i = rest.indexOf('/');
    return shareValue(REMOTE, rest.slice(0, i), rest.slice(i + 1));
  }
  return shareValue(LOCAL, '', s.startsWith(`${LOCAL}:`) ? s.slice(LOCAL.length + 1) : s);
}
// Both groups in one list. `remote`: [{ peer, share, state? }] (the remote group is a stub until issue 1149 names and reads them).
export function shareGroups(local, remote, groups) {
  const out = [];
  if (groups.includes(LOCAL)) out.push(...local.map((o) => ({ ...o, value: `${LOCAL}:${o.value}`, group: 'On this server' })));
  if (groups.includes(REMOTE)) out.push(...remote.map((r) => ({ value: `${REMOTE}:${r.peer}/${r.share}`, label: `${r.peer} / ${r.share}`, detail: r.state ?? '', group: 'On other servers' })));
  return out;
}

// scope 'free': `pool disks` rows (the disks no pool uses, by-id names, parsed by forms/storage/disks.js). scope 'all': `monitor disks` rows: name, bytes, SSD|HDD, role ...
export function diskOptions(rowList, { scope = 'free', exclude } = {}) {
  const skip = asList(exclude);
  if (scope === 'all') {
    return rowList.filter((r) => r[0] && !skip.includes(r[0]))
      .map((r) => ({ value: r[0], label: r[0], detail: [sizeTxt(Number(r[1])), r[2], r[3] && r[3] !== '-' ? r[3] : 'free'].filter((x) => x && x !== '–').join(' · ') }));
  }
  return freeDisks(rowList).filter((d) => !skip.includes(d.id)).map((d) => ({ value: d.id, label: shortId(d.id), detail: [d.space ?? d.size, d.type, ...d.notes].join(' · ') }));
}

// `pool list` rows parsed by pools.svelte.js: { name, role, kind, state }
export function poolOptions(poolRows, { role, kind } = {}) {
  return poolRows.filter((p) => (!role || p.role === role) && (!kind || p.kind === kind))
    .map((p) => ({ value: p.name, label: p.name, detail: [p.role, p.kind === 'zfs' ? 'ZFS' : 'SnapRAID', p.state && p.state !== '-' ? p.state : ''].filter(Boolean).join(' · ') }));
}

// `ct list` rows; `running: true` offers only the running ones, `type` = 'ct' | 'vm'
export function instanceOptions(rowList, { running = false, type = '', exclude } = {}) {
  const skip = asList(exclude);
  const vm = (c) => /virtual|VM/i.test(c.type);
  return rowList.map(ctOf).filter((c) => c.name && !skip.includes(c.name) && (!running || isRunning(c)) && (!type || (type === 'vm') === vm(c)))
    .map((c) => ({ value: c.name, label: c.name, detail: [vm(c) ? 'VM' : 'CT', (c.state || '').toLowerCase()].filter(Boolean).join(' · ') }));
}

// `users list` rows; `enabled: true` leaves out the locked accounts
export function userOptions(rowList, { enabled = false, exclude } = {}) {
  const skip = asList(exclude);
  return rowList.map(userOf).filter((u) => u.name && !skip.includes(u.name) && (!enabled || u.enabled))
    .map((u) => ({ value: u.name, label: u.name, detail: [u.full, u.enabled ? '' : stateOf(u)].filter(Boolean).join(' · ') }));
}
// `shares principals` rows: sid, name, user|group. The value is the SID (what `perm --set` takes), the label the name.
export function principalOptions(rowList, { taken = [] } = {}) {
  return rowList.filter((r) => r[0] && !taken.includes(r[0])).map((r) => ({ value: r[0], label: r[1], detail: r[2] }));
}
