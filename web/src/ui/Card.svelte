<script>
  // The one card. A header line (title, optional kicker) with actions on the right, then the body. No separate Section: a card without a header is a plain block.
  //   <Card title="The CA">{#snippet actions()}<Button>Make</Button>{/snippet} ...body... </Card>
  // `dither`: 'top-right' | 'top-left' | 'bottom-right' | 'bottom-left' fades the halftone from that corner (the node card on Summary); the body then sits above it.
  // `pad`: 'md' (default, the card padding of the tokens) | 'lg'. `header` replaces the title line when the header needs more than text.
  import Halftone from '../shell/Halftone.svelte';
  let { title = '', kicker = '', dither = '', pad = 'md', header, actions, children, ...rest } = $props();
  const corners = { 'top-right': [1, 0], 'top-left': [0, 0], 'bottom-right': [1, 1], 'bottom-left': [0, 1] };
</script>

<section class="card ui-card {pad}" class:dither={!!dither} {...rest}>
  {#if dither && corners[dither]}<Halftone focus={corners[dither]} />{/if}
  {#if header}
    <div class="head">{@render header()}{#if actions}<div class="grow"></div><div class="act">{@render actions()}</div>{/if}</div>
  {:else if title || kicker || actions}
    <div class="head">
      <div class="tt">{#if kicker}<div class="card-kicker">{kicker}</div>{/if}{#if title}<h3>{title}</h3>{/if}</div>
      {#if actions}<div class="grow"></div><div class="act">{@render actions()}</div>{/if}
    </div>
  {/if}
  {@render children?.()}
</section>

<style>
  .ui-card { gap: var(--space-3); padding: var(--space-6); min-width: 0; }
  .ui-card.lg { padding: var(--space-8); }
  .dither { overflow: hidden; }
  .dither > :global(:not(.ht)) { position: relative; z-index: 1; }
  .head { display: flex; align-items: center; gap: var(--space-4); min-width: 0; }
  .tt { min-width: 0; }
  h3 { margin: 0; font-size: 14px; font-weight: 500; line-height: 1.3; }
  .grow { flex: 1; }
  .act { display: flex; align-items: center; gap: var(--space-3); flex: none; }
</style>
