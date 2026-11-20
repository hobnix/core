<script>
  // The strip of an Object page: the running or last jobs of ONE object, newest first, each a line that links to its record (design 3.4). It reads the
  // job records like the Jobs panel: once, again on a job.* event or a records generation bump, polling only while the event stream is down.
  //   <JobStrip match={(r) => r.description.includes(serial)} />
  // `match(record)` picks the jobs of the object (records are parseRecord rows). `href(record)` is the link to the record (default: Health > Jobs, #385).
  import { get } from '../api.js';
  import { live } from '../live.svelte.js';
  import { url } from '../route.svelte.js';
  import StatusDot from '../ui/StatusDot.svelte';
  import { parseRecord, stateDot, lastJobEvent, latestOnly, percent, clock } from '../jobrecords.js';
  let { match = () => true, href = (r) => `/health/jobs?job=${encodeURIComponent(r.id)}`, limit = 3, title = 'Jobs' } = $props();

  let list = $state(null);
  let failed = $state(false);
  const readList = latestOnly(() => get('/api/sys/jobs/records?n=100'), (d) => { list = (d.rows ?? []).map(parseRecord); failed = false; });
  const load = async () => { try { await readList(); } catch { failed = true; } };
  const mine = $derived((list ?? []).filter((r) => match(r)).slice(0, limit));

  let lastJob = lastJobEvent(live.events)?.id ?? 0;
  $effect(() => { const ev = lastJobEvent(live.events); if (!ev || ev.id === lastJob) return; lastJob = ev.id; load(); });
  let lastGen = live.gen['reads:jobs-records'];
  $effect(() => { const g = live.gen['reads:jobs-records']; if (g === lastGen) return; lastGen = g; load(); });
  $effect(() => { if (list === null) load(); });
  $effect(() => { if (live.open) return; const t = setInterval(load, 15000); return () => clearInterval(t); });
</script>

{#if failed && list === null}
  <p class="none">The jobs could not be read.</p>
{:else if list !== null && mine.length}
  <section class="strip" aria-label={title}>
    <span class="card-kicker">{title}</span>
    <ul>
      {#each mine as r (r.id)}
        <li>
          <StatusDot state={stateDot(r.state)} label={r.state} />
          <a href={url(href(r))}>{r.description}</a>
          {#if r.state === 'running' && percent(r.progress) !== null}<span class="meta">{percent(r.progress)} %</span>{:else if r.state === 'running' && r.step?.text}<span class="meta">{r.step.text}</span>{/if}
          <span class="grow"></span>
          <span class="meta">{clock(r.ended ?? r.started ?? r.queued)}</span>
        </li>
      {/each}
    </ul>
  </section>
{/if}

<style>
  .strip { display: flex; flex-direction: column; gap: var(--space-2); padding: var(--space-4) var(--space-6); border: 1px solid var(--line); border-radius: var(--r); background: var(--panel); }
  ul { list-style: none; margin: 0; padding: 0; }
  li { display: flex; align-items: center; gap: var(--space-4); padding: var(--space-1) 0; font-size: 13px; flex-wrap: wrap; }
  a { color: var(--fg); text-decoration: none; }
  a:hover { text-decoration: underline; color: var(--accent); }
  .meta { font-size: 12px; color: var(--fg-3); }
  .grow { flex: 1; }
  .none { font-size: 12px; color: var(--fg-3); margin: 0; }
</style>
