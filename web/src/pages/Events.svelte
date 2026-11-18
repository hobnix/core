<script>
  // Events: the event log (hs sys event list, ADR 0005), newest first. Filters: source (asked of the server), level, kind and time (in the browser).
  // New rows arrive through the live stream (`domain` items of /api/events, no polling while it is open); a resync, or a closed stream, reads again.
  import { poll, rows, refresh } from '../data.svelte.js';
  import { live } from '../live.svelte.js';
  import { lang } from '../lang.svelte.js';
  import { ui } from '../ui.svelte.js';
  import { tr } from '../i18n.js';
  import PageHeader from '../shell/PageHeader.svelte';
  import PageState from '../shell/PageState.svelte';
  import Timeline from '../ui/Timeline.svelte';
  import { parseRow, eventText, merge, filterRows, SINCE, sinceFrom } from './events.js';

  const STEP = 100;
  let limit = $state(STEP);
  let values = $state({ source: '', level: '', since: '' });   // the filters of the Timeline
  let kind = $state('');
  const source = $derived(values.source), level = $derived(values.level), since = $derived(values.since);

  const path = $derived(`/api/sys/event/list?n=${limit}${source ? `&source=${encodeURIComponent(source)}` : ''}`);
  // an open stream carries the news: the timer is long then
  const list = poll(() => path, 30000, undefined);   // the stream brings new rows at once; this slow read is the safety net while it is closed
  // a resync says rows may be lost: read again (the poll follows live.resyncs only with a topic, so ask for it here)
  let seenResync = live.resyncs;
  $effect(() => { if (live.resyncs !== seenResync) { seenResync = live.resyncs; refresh([path]); } });

  const read = $derived(rows(list).map(parseRow));
  // rows from the stream that the read does not hold yet (only those that match the source filter)
  const news = $derived(live.events.map(parseRow).filter((e) => !source || e.source === source));
  const all = $derived(merge(read, news, 1000));
  const shown = $derived(filterRows(all, { level, kind, since: sinceFrom(since) }));
  const sources = $derived([...new Set(all.map((e) => e.source))].sort());
  const sourceOptions = $derived([{ value: '', label: tr('All sources') }, ...(source && !sources.includes(source) ? [source] : []), ...sources]);
  const levelOptions = [{ value: '', label: 'All levels' }, 'info', 'warn', 'error'];
  const sinceOptions = SINCE.map(([v, l]) => ({ value: v, label: l }));
  const filters = $derived([
    { key: 'source', label: 'Source', options: sourceOptions },
    { key: 'level', label: 'Level', options: levelOptions },
    { key: 'since', label: 'Time', options: sinceOptions },
  ]);
  const entries = $derived(shown.map((e) => ({ id: String(e.id), time: e.time, severity: e.level, title: eventText(e, lang.code), text: e.subject, kind: `${e.source}.${e.kind}` })));
  const more = $derived(read.length >= limit && limit < 1000);
</script>

<div class="page">
  <PageHeader title="Events" crumb="{ui.host} / Operations" sub="What happened on this server, newest first." />

  <PageState loading={!list.loaded} error={list.error?.message ?? ''} hasData={list.data != null} empty={false}>
    <Timeline {entries} {filters} bind:values onfilter={(k) => { if (k === 'source') limit = STEP; }} {more} onmore={() => { limit += STEP; }}
              emptyTitle="No events" empty="Nothing matches. Events are written as things happen on the server.">
      {#snippet toolbar()}
        <input class="input" bind:value={kind} placeholder="Kind, e.g. job.failed" aria-label="Kind" maxlength="60" autocomplete="off" spellcheck="false" />
      {/snippet}
    </Timeline>
  </PageState>
</div>

