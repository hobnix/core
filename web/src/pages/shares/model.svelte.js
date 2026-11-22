// The data of the shares, shared by the list with its quick look (pages/Shares.svelte) and the page of one share (pages/shares/Share.svelte): the same reads, the same words.
// Call it while a component is initialised (it makes polls and deriveds). `sel()` is the name of the share the page or the quick look is about; `detail: true` also reads the
// permissions, the visibility, the snapshots and (on the Snapshots tab) the restore points of that share (the page does, the quick look does not).
import { poll, rows } from '../../data.svelte.js';
import { bytes } from '../../format.js';
import { rowstate } from '../../rowstate.svelte.js';
import { sharePending, shareFailed } from '../rows.js';
import { parseSize } from '../storage/pool.js';
import { poolOfRole } from '../../pools.svelte.js';

export const dash = (v) => (v && v !== '-' ? v : '');
export const sizeText = (n) => (!n ? '' : n >= 1e12 ? `${(n / 1e12).toFixed(2)} TB` : n >= 1e9 ? `${Math.round(n / 1e9)} GB` : bytes(n));
export const mountedBy = (s) => (dash(s.mounted) ? s.mounted.split(',').map((x) => x.trim()).filter(Boolean).map((x) => ({ text: x, name: x.replace(/\s*\(.*$/, '') })) : []);
export const editable = (s) => !!s && !s.volume && s.kind !== 'other';
export const isZfs = (s) => !!s && !s.volume && !!s.disks && s.disks !== '-' && !s.disks.startsWith('data-') && !s.measured;

export function shareModel({ sel = () => '', detail = false, tab = () => '' } = {}) {
  const overview = poll('/api/sys/shares/overview', 30000, 'shares-overview');
  const cts = poll('/api/sys/ct/list', 30000);

  // name, kind, path, cache, size_bytes, measured, backup, disks, mounted_in (name(ro|rw), comma separated)
  const samba = $derived(rows(overview).map((r) => ({
    name: r[0], kind: r[1], path: r[2], cache: r[3], size: Number(r[4]) || 0, measured: r[5], backup: r[6], disks: r[7], mounted: r[8],
    pool: (r[2] ?? '').split('/')[1] || poolOfRole('data'), volume: false,
  })));
  // ct list: name, type, state, ..., disk (col 9): the instances' own volumes on fast (read only here; the instance owns them)
  const volumes = $derived(rows(cts).filter((r) => r[9] && r[9] !== '-').map((r) => ({
    name: r[0], kind: 'volume', path: '', cache: '-', size: parseSize(r[9]), measured: '', backup: '-', disks: poolOfRole('apps'), mounted: r[0], pool: poolOfRole('apps'), volume: true,
  })));
  const all = $derived([...samba, ...volumes]);
  const share = $derived(all.find((s) => s.name === sel()) ?? null);
  const measured = $derived(samba.find((s) => s.measured)?.measured ?? '');
  const snapraid = $derived(samba.some((s) => s.measured));
  const hasCache = $derived(samba.some((s) => s.cache === 'on' || s.cache === 'off'));
  const doing = (s) => (s ? sharePending(s.name, rowstate.pending) : '');
  const failure = (s) => (s && !doing(s) ? shareFailed(s.name, rowstate.failed) : null);

  // per share, read only for the one the page names (ACL, visibility, snapshots); the restore points only on the Snapshots tab
  const one = (path) => poll(() => (detail && editable(share) ? `/api/sys/shares/${path}/${encodeURIComponent(share.name)}` : ''), 30000, 'shares-overview');
  const acl = one('acl');
  const vis = one('visible');
  const hist = one('history');
  const backups = poll(() => (detail && editable(share) && tab() === 'snapshots' ? '/api/sys/backup/snapshots?tag=shares' : ''), 60000, 'backup-state');
  // sid, name, user|group, level
  const entries = $derived(rows(acl).map((r) => ({ sid: r[0], name: r[1], type: r[2], level: r[3] })));
  // name, created, auto|manual (sorted oldest first)
  const snaps = $derived([...rows(hist)].map((r) => ({ name: r[0], created: r[1], how: r[2] })).sort((a, b) => (a.created < b.created ? -1 : a.created > b.created ? 1 : 0)));
  const auto = $derived(snaps.some((x) => x.how === 'auto'));
  const newest = $derived(snaps.length ? snaps[snaps.length - 1] : null);
  // backup restore points: id, time, tags
  const points = $derived(rows(backups).map((r) => ({ id: r[0], time: r[1] })).reverse().slice(0, 10));
  // `visible` | `hidden`: whether the share is listed when someone browses the server (hidden: only by typing its path)
  const visibility = $derived(String(rows(vis)[0]?.[0] ?? '') === 'hidden' ? 'hidden' : 'visible');

  return {
    overview, cts, samba, all, doing, failure, acl, vis, hist, backups,
    get share() { return share; }, get measured() { return measured; }, get snapraid() { return snapraid; }, get hasCache() { return hasCache; },
    get entries() { return entries; }, get snaps() { return snaps; }, get auto() { return auto; }, get newest() { return newest; }, get points() { return points; },
    get visibility() { return visibility; }, get zfs() { return isZfs(share); },
  };
}
