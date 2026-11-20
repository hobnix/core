<script>
  import { tip } from './tooltip.svelte.js';
  import Combobox from './Combobox.svelte';
  import StatusDot from './StatusDot.svelte';
  import Button from './Button.svelte';
  import EmptyState from './EmptyState.svelte';
  import { agoShort } from '../format.js';
  import { tr } from '../i18n.js';
  import { groupByDay, severityDot } from './timeline.js';
  // Timeline: the body of a Feed page (Events, Notifications, Jobs, Health problems): entries newest first, cut into days, with filters above.
  // It knows nothing about the server; the page filters the data and passes the result, and follows events (no polling here).
  //   entries   [{ id, time (epoch seconds), severity, title, text, kind, object, ackable, acked }]
  //             severity: ok | info | warn | bad (error, critical) | anything else is neutral; the word is always written
  //             object = { label, href } links to what the entry is about; kind = a small code ("job.failed") after the title
  //   filters   [{ key, label, options }] one Combobox each; values = { key: value } (bindable); onfilter(key, value) after a pick
  //   toolbar   snippet after the filters (a text field, a button)
  //   onack(entry), onundo(entry)   the acknowledge button of an entry with `ackable` (and Undo once it is `acked`); without a handler no button
  //   more, onmore                  "Show older" button while `more` is true
  //   empty, emptyTitle             what is shown when there are no entries (filters stay visible)
  //   <Timeline {entries} filters={[{ key: 'level', label: 'Level', options: ['', 'info', 'warn'] }]} bind:values onack={ack} />
  let { entries = [], filters = [], values = $bindable({}), onfilter = null, toolbar, onack = null, onundo = null, more = false, onmore = null, emptyTitle = 'Nothing here', empty = '' } = $props();
  const days = $derived(groupByDay(entries));
  const WORD = { ok: 'ok', info: 'info', warn: 'warning', bad: 'failed' };
  const dayLabel = (d) => (d === 'today' ? tr('Today') : d === 'yesterday' ? tr('Yesterday') : d || tr('Unknown time'));
  const dotOf = (s) => severityDot(s);
  const word = (e) => tr(WORD[dotOf(e.severity)] ?? e.severity ?? 'off');
  const time = (t) => new Date(t * 1000).toLocaleString();
  const clock = (t) => (t > 0 ? new Date(t * 1000).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) : '');
</script>

<div class="tl">
  {#if filters.length || toolbar}
    <div class="bar">
      {#each filters as f (f.key)}
        <Combobox options={f.options} label={f.label} bind:value={values[f.key]} onchange={(v) => onfilter?.(f.key, v)} />
      {/each}
      {@render toolbar?.()}
    </div>
  {/if}
  {#if !entries.length}
    <EmptyState icon="list-bullets" title={tr(emptyTitle)} text={empty} />
  {:else}
    {#each days as g (g.day)}
      <h3 class="day">{dayLabel(g.day)}</h3>
      <ol class="list">
        {#each g.entries as e, i (e.id ?? `${g.day}-${i}`)}
          <li class="e" class:acked={e.acked}>
            <span class="when" use:tip={e.time > 0 ? time(e.time) : undefined}>{e.time > 0 ? (g.day === 'today' ? agoShort(e.time) : clock(e.time)) : '-'}</span>
            <StatusDot state={dotOf(e.severity)} label={word(e)} />
            <span class="body">
              <span class="head">
                {#if e.title}<b>{e.title}</b>{/if}
                {#if e.kind}<code>{e.kind}</code>{/if}
              </span>
              {#if e.text}<span class="txt">{e.text}</span>{/if}
              {#if e.object}<a class="obj" href={e.object.href}>{e.object.label}</a>{/if}
            </span>
            {#if e.ackable && (onack || onundo)}
              <span class="act">
                {#if e.acked}
                  <span class="ackd">{tr('Acknowledged')}</span>
                  {#if onundo}<Button size="sm" onclick={() => onundo(e)}>{tr('Undo')}</Button>{/if}
                {:else if onack}
                  <Button size="sm" onclick={() => onack(e)}>{tr('Acknowledge')}</Button>
                {/if}
              </span>
            {/if}
          </li>
        {/each}
      </ol>
    {/each}
    {#if more && onmore}<div class="more"><Button onclick={onmore}>{tr('Show older')}</Button></div>{/if}
  {/if}
</div>

<style>
  .bar { display: flex; flex-wrap: wrap; gap: 8px; margin: 12px 0; align-items: center; }
  .day { margin: 16px 0 4px; font-size: 12px; font-weight: 600; color: var(--fg-3); text-transform: uppercase; letter-spacing: 0.04em; }
  .list { list-style: none; margin: 0; padding: 0; border-top: 1px solid var(--line); }
  .e { display: grid; grid-template-columns: 84px 110px minmax(0, 1fr) auto; gap: 12px; align-items: start; padding: 8px 0; border-bottom: 1px solid var(--line); }
  .e.acked { opacity: 0.7; }
  .when { font-size: 12px; color: var(--fg-3); white-space: nowrap; padding-top: 1px; }
  .body { display: flex; flex-direction: column; gap: 2px; min-width: 0; }
  .head { display: flex; gap: 8px; flex-wrap: wrap; align-items: baseline; }
  .txt { color: var(--fg-2); overflow-wrap: anywhere; }
  .obj { font-size: 12px; align-self: flex-start; }
  .act { display: flex; gap: 8px; align-items: center; }
  .ackd { font-size: 12px; color: var(--fg-3); }
  .more { margin-top: 12px; }
  @media (max-width: 860px) {
    .e { grid-template-columns: minmax(0, 1fr) auto; }
    .when, .body, .act { grid-column: 1 / -1; }
  }
</style>
