// The pending state of a row, derived from the job records and the job events (docs/PLAN-live-interface.md step 2, #483). Plain JS so node can test it
// (tests/web-rowstate.mjs); the reactive part is rowstate.svelte.js. A job counts for a row by its key (jobkey.js: area and arguments, "apps remove nextcloud"),
// the same key a button of this browser puts on its task, so a job started in a terminal makes the row pending too.
import { jobMatches, jobMatchesLead } from './jobkey.js';

export const ACTIVE = ['queued', 'running', 'waiting'];
export const FAILED = ['failed', 'interrupted'];

// The payload of a job event row (an object, or the JSON text of the log, or "-"). Never throws.
export function eventPayload(ev) {
  let p = ev?.payload;
  if (typeof p === 'string') { try { p = p === '-' || p === '' ? null : JSON.parse(p); } catch { p = null; } }
  return p && typeof p === 'object' ? p : {};
}

const KINDS = { queued: 'queued', running: 'running', waiting: 'waiting', resumed: 'running', ok: 'ok', failed: 'failed', cancelled: 'cancelled', interrupted: 'interrupted' };

// A job event row -> { id (job id), state, key, exit } or null for an event that is not a state change of a job. Row: source "job", kind "running" (or "job.running").
export function jobEventState(ev) {
  if (!ev) return null;
  const kind = ev.source === 'job' ? ev.kind : typeof ev.kind === 'string' && ev.kind.startsWith('job.') ? ev.kind.slice(4) : null;
  const state = KINDS[kind];
  if (!state) return null;
  const p = eventPayload(ev);
  return { id: ev.subject ?? null, state, key: typeof p.key === 'string' && p.key ? p.key : null, exit: Number.isFinite(p.exit) ? p.exit : null };
}

// Records (parseRecord rows) -> map job id -> { key, state, exit, description }.
export function fromRecords(records) {
  const m = new Map();
  for (const r of records ?? []) m.set(r.id, { key: r.key ?? null, state: r.state, exit: r.exit ?? null, description: r.description ?? null });
  return m;
}

// Fold the job events after `after` (an event id) into the map from the records. The records are the truth when they arrive; the events bridge the moment
// between a job starting and the next read of the records, and give the key where the record has none yet.
export function applyEvents(base, events, after = 0) {
  const out = new Map(base);
  for (const ev of events ?? []) {
    if ((ev.id ?? 0) <= after) continue;
    const s = jobEventState(ev);
    if (!s || !s.id) continue;
    const old = out.get(s.id);
    out.set(s.id, { key: s.key ?? old?.key ?? null, state: s.state, exit: s.exit ?? old?.exit ?? null, description: old?.description ?? null });
  }
  return out;
}

// Is a job of this row active? `jobs` = the map above; `tasks` = the tasks started from this browser ({ key, state }); `args` left out = any job of the area.
export function isPending(jobs, tasks, area, args) {
  for (const j of jobs.values()) if (ACTIVE.includes(j.state) && jobMatches(j.key, area, args)) return true;
  return (tasks ?? []).some((t) => t.state === 'running' && jobMatches(t.key, area, args));
}

// The failure to show on a row: the newest job of the row, when it failed and was not dismissed (a later active or ok job of the same key replaces it).
// Job ids start with their time, so the newest is the greatest id.
export function failureOf(jobs, dismissed, area, args) {
  let newest = null;
  for (const [id, j] of jobs) {
    if (!jobMatches(j.key, area, args)) continue;
    if (newest === null || id > newest.id) newest = { id, ...j };
  }
  if (!newest || !FAILED.includes(newest.state) || dismissed?.has(newest.id)) return null;
  const what = newest.description ? `${newest.description} failed` : 'The job failed';
  return {
    id: newest.id,
    error: { code: newest.state === 'interrupted' ? 'job.interrupted' : 'job.failed', what: newest.exit !== null ? `${what} (exit ${newest.exit})` : what, why: '', next: '', guide: '' },
  };
}

// The same by the LEADING arguments only (a pool or disk row: any job whose arguments start with the pool or disk name, whatever else follows).
// activeKeys lists the keys of the running jobs, so a page can name what is happening ("pool bulk replace --member ..." -> Replacing).
export function activeKeys(jobs, tasks, area, lead) {
  const out = [];
  for (const j of jobs.values()) if (ACTIVE.includes(j.state) && jobMatchesLead(j.key, area, lead)) out.push(j.key);
  for (const t of tasks ?? []) if (t.state === 'running' && jobMatchesLead(t.key, area, lead)) out.push(t.key);
  return out;
}

export function failureOfLead(jobs, dismissed, area, lead) {
  const sub = new Map();   // the matching jobs, keyed so that failureOf's exact match (area, no args) takes them
  for (const [id, j] of jobs) if (jobMatchesLead(j.key, area, lead)) sub.set(id, { ...j, key: area });
  return failureOf(sub, dismissed, area, []);
}
