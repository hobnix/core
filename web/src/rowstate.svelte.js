// One place for the pending state of a row (#483, docs/PLAN-live-interface.md step 2). A page asks
//   rowstate.pending('apps', ['remove', name])   // true while any job with that key is queued, running or waiting
//   rowstate.failed('apps', ['remove', name])    // { id, error } of the newest failed job of the row, or null; show it with <ErrorNote error={f.error} ondismiss=... />
//   rowstate.dismiss(id)                         // clear a failure by hand; a later job of the same key replaces it by itself
// The answer comes from the job records and the job events of the stream, not from this browser's tasks only: a job started in a terminal shows too.
// A failed job is not pending any more, so the row shows its last real state again (decision D10). `args` left out = any job of the area.
// A page that reads the row's own topic may call rowstate.clear() when that topic changes, to drop the failures it has shown.
import { get } from './api.js';
import { live } from './live.svelte.js';
import { tasks } from './ui.svelte.js';
import { parseRecord, lastJobEvent, latestOnly } from './jobrecords.js';
import { fromRecords, applyEvents, isPending, failureOf, activeKeys, failureOfLead, activeJobOf, activeJobs } from './rowstate.js';

const state = $state({ base: new Map(), dismissed: new Set(), baseline: 0, started: false });

const readRecords = latestOnly(() => get('/api/sys/jobs/records?n=100'), (d) => {
  state.base = fromRecords((d.rows ?? []).map(parseRecord));
  state.baseline = live.lastId;   // the events up to here are in the records
});

export async function refresh() { try { await readRecords(); } catch { /* the events still tell the state */ } }

const jobs = $derived(applyEvents(state.base, live.events, state.baseline));

// Start following (once, from the shell): read the records, again on a job event or a bump of the records topic, and by a slow timer only while the stream is down.
export function startRowState() {
  if (state.started) return;
  state.started = true;
  $effect.root(() => {
    refresh();
    let lastJob = lastJobEvent(live.events)?.id ?? 0;
    $effect(() => { const ev = lastJobEvent(live.events); if (!ev || ev.id === lastJob) return; lastJob = ev.id; refresh(); });
    let lastGen = live.gen['reads:jobs-records'];
    $effect(() => { const g = live.gen['reads:jobs-records']; if (g === lastGen) return; lastGen = g; refresh(); });
    $effect(() => { if (live.open) return; const t = setInterval(refresh, 15000); return () => clearInterval(t); });
  });
}

export const rowstate = {
  pending: (area, args) => isPending(jobs, tasks.list, area, args),
  failed: (area, args) => failureOf(jobs, state.dismissed, area, args),
  // by the leading arguments (a pool or disk: any job that starts with its name): the keys of the running jobs, and the newest failure
  active: (area, lead) => activeKeys(jobs, tasks.list, area, lead),
  failedLead: (area, lead) => failureOfLead(jobs, state.dismissed, area, lead),
  // the newest active job of a row ({ id, state, started, description } or null), and every active job (the Tasks tab)
  activeJob: (area, args) => activeJobOf(jobs, area, args),
  activeJobs: () => activeJobs(jobs),
  dismiss: (id) => { state.dismissed = new Set([...state.dismissed, id]); },
  clear: () => { state.dismissed = new Set([...state.dismissed, ...[...jobs].filter(([, j]) => j.state === 'failed' || j.state === 'interrupted').map(([id]) => id)]); },
};
