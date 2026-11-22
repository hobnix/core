// The data of the instances, shared by the list with its quick look (pages/Instances.svelte) and the page of one instance (pages/instances/Instance.svelte): the same reads and
// the same words. Call it while a component is initialised (it makes polls and deriveds). `sel()` is the name of the instance the page or the quick look is about;
// `detail: true` also reads its storage bindings and (on the Config tab) its snapshots; the quick look does not.
import { poll, rows } from '../../data.svelte.js';
import { rowstate } from '../../rowstate.svelte.js';
import { ctPending, ctFailed } from './pending.js';
import { ctOf, isVm, isRunning, servicesOf } from './ct.js';

export const kindOf = (c) => (isVm(c) ? 'VM' : 'CT');
export const word = (s) => (s ? s.charAt(0).toUpperCase() + s.slice(1).toLowerCase() : '');
export const dot = (s) => (/running/i.test(s) ? 'ok' : /partial/i.test(s) ? 'warn' : 'off');
export const boots = (c) => /^(true|yes|on)$/i.test(c.autostart || '');
export const spaced = (v) => (v || '').replace(/^(\d+)([A-Za-z]+)$/, '$1 $2');
export const dash = (v) => (v && v !== '-' ? v : '');

export function instanceModel({ sel = () => '', detail = false, tab = () => '' } = {}) {
  const ctl = poll('/api/sys/ct/list', 5000);
  const bk = poll('/api/sys/backup/overview', 60000);
  const svc = poll('/api/sys/services/list', 30000);
  const rec = poll('/api/sys/recipes/list', 60000);

  const all = $derived(rows(ctl).map(ctOf));
  const ct = $derived(all.find((c) => c.name === sel()) ?? null);
  // backup overview: kind, name, on|off, bytes. Empty while the backup disk or the storage is not there
  const backupOf = $derived(Object.fromEntries(rows(bk).filter((r) => r[0] === 'ct').map((r) => [r[1], r[2] === 'on'])));
  const backupKnown = $derived(bk.loaded && !bk.error);
  // services list: name, title, target, exposure, names, wants
  const services = $derived(rows(svc).map((r) => ({ name: r[0], title: r[1], target: r[2], exposure: r[3], names: r[4], wants: r[5] })));
  // recipes list: name, description, containers (comma separated, - for none), state
  const recipes = $derived(rows(rec).map((r) => ({ name: r[0], cts: r[2] === '-' ? [] : r[2].split(',') })));
  const myServices = $derived(ct ? servicesOf(ct, services) : []);
  const myRecipes = $derived(ct ? recipes.filter((r) => r.cts.includes(ct.name)) : []);

  const doing = (c) => (c ? ctPending(c.name, rowstate.pending) : '');
  const failure = (c) => (c && !doing(c) ? ctFailed(c.name, rowstate.failed) : null);
  const busyOf = (c, ...a) => !!c && a.some((x) => rowstate.pending('ct', [c.name, ...x]));

  // per instance, read only for the one the page names
  const bind = poll(() => (detail && ct ? `/api/sys/ct/bindings/${encodeURIComponent(ct.name)}` : ''), 15000, 'ct-list');
  // binding, kind, pool, source, inside, mode, cache, backup, share, used_bytes, disks, also_used_by
  const bindings = $derived(rows(bind).map((r) => ({ device: r[0], kind: r[1], pool: r[2], source: r[3], inside: r[4], mode: r[5], backup: r[7], share: r[8], also: r[11] })));
  const snap = poll(() => (detail && ct && tab() === 'config' ? `/api/sys/ct/snapshots/${encodeURIComponent(ct.name)}` : ''), 15000, 'ct-list');
  // name, created; newest first ("YYYY-MM-DD HH:MM" sorts as text)
  const snaps = $derived([...rows(snap)].sort((a, b) => (a[1] < b[1] ? 1 : a[1] > b[1] ? -1 : 0)).map((r) => ({ name: r[0], created: r[1] })));

  return {
    ctl, svc, all, doing, failure, busyOf, bind, snap, isRunning, isVm,
    get ct() { return ct; }, get backupOf() { return backupOf; }, get backupKnown() { return backupKnown; }, get services() { return services; },
    get myServices() { return myServices; }, get myRecipes() { return myRecipes; }, get bindings() { return bindings; }, get snaps() { return snaps; },
  };
}
