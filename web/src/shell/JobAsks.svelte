<script>
  // Raises a Toast for every job that waits for an answer (state `waiting`), on any page and also when the dialog that started the job is closed
  // (hobnix/server#972, #447). Reads the job records once, then again on a job.* event or a records generation bump (no polling while the event
  // stream is up; a slow timer only while it is down). The toast links to the record and goes away when the question is answered. Draws nothing.
  import { onDestroy } from 'svelte';
  import { get } from '../api.js';
  import { live } from '../live.svelte.js';
  import { url } from '../route.svelte.js';
  import { tr } from '../i18n.js';
  import { toast, dismissToast } from '../ui/toast.svelte.js';
  import { parseRecord, latestOnly, jobChanged, askDiff } from '../jobrecords.js';

  const shown = new Set();
  const key = (id) => `ask:${id}`;
  const readList = latestOnly(() => get('/api/sys/jobs/records?n=100'), (d) => {
    const { raise, dismiss } = askDiff((d.rows ?? []).map(parseRecord), shown);
    for (const r of raise) {
      shown.add(r.id);
      toast({ key: key(r.id), kind: 'ask', title: `${r.description} ${tr('needs an answer')}`, href: url(`/health/jobs?job=${encodeURIComponent(r.id)}`), linkLabel: tr('Open the job') });
    }
    for (const id of dismiss) { shown.delete(id); dismissToast(key(id)); }
  });
  const load = () => readList().catch(() => {});

  let seen = jobChanged(live.events, live.gen['reads:jobs-records'], { ev: -1, gen: -1 }).seen;
  load();
  $effect(() => {
    const c = jobChanged(live.events, live.gen['reads:jobs-records'], seen);
    if (!c.changed) return;
    seen = c.seen;
    load();
  });
  $effect(() => { if (live.open) return; const t = setInterval(load, 15000); return () => clearInterval(t); });
  onDestroy(() => { for (const id of shown) dismissToast(key(id)); });
</script>
