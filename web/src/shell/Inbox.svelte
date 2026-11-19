<script>
  // The bell in the top bar (design 4.5, 4.11): the count is the unacknowledged problems plus the unread notifications. The list shows both, each
  // linking to its object; an acknowledged problem stays in it, dimmed, and is not counted. It follows the event stream: a health event reads the
  // problem list again, a warn or error event is a new notification. The slow timer runs only while the stream is down.
  // Notifications are the warn/error rows of live.events (what arrived since this page opened); "read" is remembered in this browser only.
  import { tip } from '../ui/tooltip.svelte.js';
  import { get } from '../api.js';
  import { live } from '../live.svelte.js';
  import { lang } from '../lang.svelte.js';
  import { go } from '../route.svelte.js';
  import { agoShort } from '../format.js';
  import StatusDot from '../ui/StatusDot.svelte';
  import Button from '../ui/Button.svelte';
  import { openPlan } from '../ui.svelte.js';
  import { problemItems, notificationItems, bellCount, newestId } from './inbox.js';

  const KEY = 'hs.inbox.read';
  const FALLBACK = 60000;
  let open = $state(false);
  let rows = $state([]);
  let failed = $state(false);
  let readUpTo = $state(0);
  try { readUpTo = Number(localStorage.getItem(KEY)) || 0; } catch { /* storage may be blocked */ }

  // health events seen so far: a new one reads the list again
  const healthSeen = $derived(live.events.filter((e) => e.source === 'health' || String(e.kind).startsWith('health.')).length + live.resyncs);
  async function load() {
    try { rows = (await get('/api/sys/health/list')).rows ?? []; failed = false; } catch { failed = true; }
  }
  $effect(() => {
    healthSeen;
    load();
    if (live.open) return;
    const t = setTimeout(load, FALLBACK);
    return () => clearTimeout(t);
  });

  const problems = $derived(problemItems(rows));
  const notes = $derived(notificationItems(live.events, lang.code));
  const count = $derived(bellCount(problems, notes, readUpTo));
  const label = $derived(count ? `Inbox, ${count} new` : 'Inbox');

  function toggle(e) {
    e.stopPropagation();
    open = !open;
    if (!open) markRead();
  }
  function markRead() {
    readUpTo = Math.max(readUpTo, newestId(notes));
    try { localStorage.setItem(KEY, String(readUpTo)); } catch { /* per-viewer convenience only */ }
  }
  function visit(e, href) {
    e.preventDefault();
    markRead();
    open = false;
    go(href);
  }
</script>

<svelte:window onclick={() => { if (open) { open = false; markRead(); } }} onkeydown={(e) => { if (e.key === 'Escape' && open) { open = false; markRead(); } }} />

<span class="inbox">
  <button class="inbox-bell" aria-label={label} aria-haspopup="true" aria-expanded={open} use:tip={{ text: label, side: 'bottom' }} onclick={toggle}>
    <i class="ph ph-bell" style="font-size:16px"></i>{#if count > 0}<span class="inbox-count">{count}</span>{/if}
  </button>
  {#if open}
    <div class="inbox-pop" role="dialog" aria-label="Inbox" tabindex="-1" onclick={(e) => e.stopPropagation()} onkeydown={() => {}}>
      <div class="inbox-head">Problems</div>
      <div class="inbox-list">
        {#each problems as p (p.id)}
          <a href={p.href} class:acked={p.acked} onclick={(e) => visit(e, p.href)}>
            <StatusDot bare state={p.acked ? 'off' : 'warn'} label={p.acked ? 'acknowledged' : 'problem'} />
            <span class="tx">{p.text}<span class="sub">{#if p.acked} · acknowledged{/if}{#if p.since} · {agoShort(p.since)}{/if}</span></span>
          </a>
          {#if !p.acked}<Button need="admin" size="sm" variant="ghost" tooltip="Silent until the problem is gone" onclick={() => { open = false; openPlan('health', ['ack', p.id], 'Acknowledge'); }}>Acknowledge</Button>{/if}
        {:else}
          <div class="inbox-empty">{failed ? 'The problem list could not be read.' : 'No open problems.'}</div>
        {/each}
      </div>
      <div class="inbox-head">Notifications</div>
      <div class="inbox-list">
        {#each notes as n (n.id)}
          <a href={n.href} class:unread={n.id > readUpTo} onclick={(e) => visit(e, n.href)}>
            <StatusDot bare state={n.level === 'error' ? 'bad' : 'warn'} label={n.level === 'error' ? 'error' : 'warning'} />
            <span class="tx">{n.text}<span class="sub"> · {agoShort(n.time)}</span></span>
          </a>
        {:else}
          <div class="inbox-empty">Nothing new since this page opened.</div>
        {/each}
      </div>
    </div>
  {/if}
</span>
