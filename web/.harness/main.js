// Throwaway harness (not committed): mounts the Jobs panel's JobRecords with a stubbed backend and lets the page push domain events.
import { mount } from 'svelte';
import { live } from '../src/live.svelte.js';
import JobRecords from '../src/shell/JobRecords.svelte';

window.__live = live;
window.__fetches = [];
window.__rows = [];
window.fetch = async (url) => {
  window.__fetches.push(String(url));
  if (String(url).includes('/api/sys/jobs/records')) {
    return new Response(JSON.stringify({ rows: window.__rows }), { status: 200, headers: { 'Content-Type': 'application/json' } });
  }
  return new Response('{}', { status: 200, headers: { 'Content-Type': 'application/json' } });
};
window.__count = null;
mount(JobRecords, { target: document.getElementById('app'), props: { onload: (n) => { window.__count = n; } } });
// the real shape of a row of the event log: source and kind apart ("job.queued" is source job, kind queued)
window.__push = (name) => {
  const [source, kind] = name.split('.');
  const id = (live.lastId || 0) + 1;
  live.lastId = id;
  live.events = [...live.events, { id, time: Date.now(), source, kind, subject: 'x', level: 'info', text: '', payload: null }];
};
