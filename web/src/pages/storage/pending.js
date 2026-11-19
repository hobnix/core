// What a pool or a disk is doing, from rowstate (web/src/rowstate.svelte.js; plain JS so node can test it, tests/web-rowstate.mjs).
// `active(area, lead)` is rowstate.active: the keys of the running jobs whose arguments start with `lead` (the pool, the disk or the member).
// A job started in a terminal counts too: the answer comes from the job records and events.
const POOL = { add: 'Adding disks', adopt: 'Adopting a disk', replace: 'Replacing a disk', remove: 'Removing a disk', convert: 'Converting a disk', close: 'Closing a disk', open: 'Opening a disk' };
const DISK = { wipe: 'Formatting', test: 'Testing', forget: 'Forgetting', detach: 'Detaching', attach: 'Attaching', recover: 'Recovering', 'recover-finish': 'Giving back', move: 'Moving files' };

const word = (map, key) => map[key.split(' ')[2]] ?? 'Working';

// 'Replacing a disk' | 'Adding disks' | ... of a pool with a running job (area pool, or a sync / scrub of it), else ''
export function poolPending(pool, active) {
  const k = active('pool', [pool])[0];
  if (k) return word(POOL, k);
  if (active('system', ['scrub', '--pool', pool]).length) return 'Scrubbing';
  return '';
}
// the same for a SnapRAID pool's parity sync (`system sync` names no pool)
export const syncPending = (active) => (active('system', ['sync']).length ? 'Syncing parity' : '');

// 'Formatting' | 'Testing' | ... of a disk; `names` = the device and its pool member / serial (the jobs name either)
export function diskPending(names, active) {
  for (const n of names.filter(Boolean)) {
    const k = active('disk', [n])[0];
    if (k) return word(DISK, k);
  }
  return '';
}
// the newest failure ({ id, error }) among the leads of an area, or null
export function failedOf(area, leads, failedLead) {
  let best = null;
  for (const l of leads.filter(Boolean)) { const f = failedLead(area, [l]); if (f && (!best || f.id > best.id)) best = f; }
  return best;
}
