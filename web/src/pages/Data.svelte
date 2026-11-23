<script>
  import { P } from '../paths.js';
  import PageHeader from '../shell/PageHeader.svelte';
  import { Banner, Card, Stack, Muted } from '../ui/index.js';
  import { poll, rows } from '../data.svelte.js';
  import Table from '../shell/Table.svelte';
  import { live } from '../live.svelte.js';
  import { parseLiveRows } from '../livestatus.js';
  import { go } from '../route.svelte.js';

  // The live-state topics themselves (ADR 0026: always on, kept in the state database).
  const liveSt = poll(() => '/api/sys/live/status', 5000, 'live');
  const liveRows = $derived(parseLiveRows(rows(liveSt)));
  const problemRows = $derived(liveRows.filter((r) => r.state === 'stale' || r.state === 'never' || r.state === 'failing'));
  const liveDown = $derived(liveSt.error?.status === 503 && !liveSt.error?.retryAfter);
  const liveRefreshing = $derived(liveSt.error?.status === 503 && liveSt.error?.retryAfter > 0);

  // the collector heartbeat age is the same on every line
  const beat = $derived(liveRows.length ? liveRows[0].beat : null);

  const secs = (s) => (s === null ? '' : s < 90 ? `${Math.round(s)} s` : s < 5400 ? `${Math.round(s / 60)} min` : `${Math.round(s / 3600)} h`);
  // one status vocabulary (fresh, stale, error, expired, pending, never, failing)
  const tone = (s) => ({ fresh: 'var(--st-ok)', pending: 'var(--fg-2)', stale: 'var(--st-warn)', failing: 'var(--st-warn)', expired: 'var(--st-warn)', error: 'var(--st-bad)', never: 'var(--st-bad)' }[s] || 'var(--fg-2)');
  const liveTone = tone;
  const when = (ts) => (ts ? new Date(ts * 1000).toLocaleString() : '');

  const liveColumns = [
    { key: 'topic', label: 'Topic', value: (r) => r.topic },
    { key: 'state', label: 'Status', value: (r) => r.state },
    { key: 'every', sort: 'num', optional: true, label: 'Every', value: (r) => r.every, align: 'right' },
    { key: 'age', sort: 'num', label: 'Age', value: (r) => r.age, align: 'right' },
    { key: 'gen', sort: 'num', optional: true, label: 'Gen', value: (r) => r.gen, align: 'right' },
    { key: 'rc', sort: 'num', optional: true, label: 'Exit', value: (r) => r.rc, align: 'right' },
    { key: 'err', label: 'Error', value: (r) => r.err },
    { key: 'tsErr', sort: 'num', optional: true, label: 'Error time', value: (r) => r.tsErr, align: 'right' },
  ];
</script>

<Stack gap="4">
  <PageHeader title="Diagnostics" crumb="Monitoring" sub="How fresh the pages are, and what makes them slow." />

    {#if liveDown}
      <Banner tone="bad">The live state data cannot be read. The table shows the last data; polling every 5 s until it comes back. Check <code>systemctl status hs-live</code>.</Banner>
    {:else if liveRefreshing}
      <Banner tone="info" icon="circle-notch">Live state is starting; the first reading should arrive in a few seconds.</Banner>
    {:else if !live.open}
      <Banner tone="info" icon="pause-circle">Live updates are paused; polling every 5 s until the stream reconnects.</Banner>
    {/if}

    {#if liveRows.length && !liveDown}
      {#if beat === null}
        <Banner tone="bad">The live state collector has no heartbeat. Check <code>systemctl status hs-live</code>.</Banner>
      {:else}
        <Muted as="p">Collector heartbeat: last round {secs(beat)} ago.</Muted>
      {/if}
    {/if}

    {#if problemRows.length}
      <Banner tone="bad">{problemRows.length} topic(s) are stale, never read, or failing. See <button class="link-btn" onclick={() => go(P.health)}>Health</button> and <code>hs-live</code> for details.</Banner>
    {:else if liveRows.length}
      <Banner tone="ok">All live topics are fresh.</Banner>
    {/if}

    <Card>
      <Table id="data-live" columns={liveColumns} rows={liveRows} key="topic" compact loading={!liveSt.loaded}
             empty={liveSt.error ? 'The live topics could not be read.' : 'No live topics are configured.'}>
        {#snippet cell(r, col)}
          {#if col.key === 'topic'}<code>{r.topic}</code>
          {:else if col.key === 'state'}<span style="color:{liveTone(r.state)}">{r.state}</span>
          {:else if col.key === 'every'}<span class="c">{secs(r.every)}</span>
          {:else if col.key === 'age'}<span class="c">{secs(r.age)}</span>
          {:else if col.key === 'gen'}<span class="c">{r.gen}</span>
          {:else if col.key === 'rc'}<span class="c">{r.rc === null ? '-' : r.rc}</span>
          {:else if col.key === 'err'}<span class="c" style="color:{r.err ? 'var(--st-bad)' : ''}">{r.err ?? '-'}</span>
          {:else}<span class="c">{when(r.tsErr)}</span>{/if}
        {/snippet}
      </Table>
    </Card>
    <Muted as="p">These are the live-state topics in the state database. The <code>live</code> row describes the previous collection by design. <code>hs sys live status</code> shows the same on the command line. <button class="link-btn" onclick={() => go(P.liveState)}>Live state</button> has the details per topic.</Muted>
</Stack>

<style>
  .c { padding: 6px 8px; color: var(--fg-2); font-variant-numeric: tabular-nums; }
</style>
