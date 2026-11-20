<script>
  // The panel of an Object page and the quick look: the objects this one is related to, each with its status and a link to its page (design 1.2: the
  // link exists in both directions, so the other page lists this object too). `items`: [{ kind, name, href, state?, label?, note? }], grouped by `kind`.
  //   <LinkedObjects items={[{ kind: 'Pool', name: 'tank', href: '/storage/pools/tank', state: 'ok' }]} />
  import { url } from '../route.svelte.js';
  import StatusDot from '../ui/StatusDot.svelte';
  import Card from '../ui/Card.svelte';
  let { items = [], title = 'Linked objects' } = $props();
  const groups = $derived.by(() => {
    const m = new Map();
    for (const it of items) { if (!m.has(it.kind)) m.set(it.kind, []); m.get(it.kind).push(it); }
    return [...m];
  });
</script>

{#if groups.length}
  <Card {title}>
    {#each groups as [kind, list] (kind)}
      <div class="g">
        <div class="card-kicker">{kind}</div>
        <ul>
          {#each list as it (it.href)}
            <li>
              <a href={url(it.href)}>{it.name}</a>
              {#if it.note}<span class="note">{it.note}</span>{/if}
              <span class="grow"></span>
              {#if it.state}<StatusDot state={it.state} label={it.label ?? ''} />{/if}
            </li>
          {/each}
        </ul>
      </div>
    {/each}
  </Card>
{/if}

<style>
  ul { list-style: none; margin: 0; padding: 0; }
  li { display: flex; align-items: center; gap: var(--space-4); padding: var(--space-2) 0; border-bottom: 1px solid var(--line); font-size: 13px; }
  li:last-child { border-bottom: 0; }
  a { color: var(--fg); text-decoration: none; font-weight: 500; }
  a:hover { text-decoration: underline; color: var(--accent); }
  .note { font-size: 12px; color: var(--fg-3); }
  .grow { flex: 1; }
  .g + .g { margin-top: var(--space-3); }
</style>
