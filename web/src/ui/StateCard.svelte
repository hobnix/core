<script>
  // The card of a Group page: the state of one place, not a description of it. A status dot with its word, one line of state, a link to the place.
  //   <StateCard title="Pools" state="warn" label="1 degraded" line="3 pools, 12.4 TB used" href="/storage/pools" />
  // `href` adds the link at the foot (`linkText` is its text); `actions` takes one or two Buttons beside it; children go under the line.
  import Card from './Card.svelte';
  import StatusDot from './StatusDot.svelte';
  import { url } from '../route.svelte.js';
  let { title, state = 'off', label = '', line = '', href = '', linkText = 'Open', actions, children, ...rest } = $props();
</script>

<Card {...rest}>
  {#snippet header()}
    <span class="t">{title}</span>
    <span class="grow"></span>
    <StatusDot {state} {label} />
  {/snippet}
  {#if line}<p class="line">{line}</p>{/if}
  {@render children?.()}
  {#if href || actions}
    <div class="foot">
      {#if href}<a class="more" href={url(href)}>{linkText} <i class="ph ph-arrow-right" aria-hidden="true"></i></a>{/if}
      {#if actions}<div class="grow"></div>{@render actions()}{/if}
    </div>
  {/if}
</Card>

<style>
  .t { font-weight: 500; font-size: 14px; }
  .line { margin: 0; color: var(--fg-2); font-size: 13px; }
  .foot { display: flex; align-items: center; gap: var(--space-3); margin-top: auto; }
  .grow { flex: 1; }
  .more { font-size: 13px; color: var(--accent); text-decoration: none; }
  .more:hover { text-decoration: underline; }
</style>
