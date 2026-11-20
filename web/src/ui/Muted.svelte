<script>
  // The one style for secondary text (replaces the classes `mute` and `muted`): 12 px, the third text colour. `as`: span (default) | p | div.
  //   <Muted as="p">No CA yet.</Muted>
  let { as = 'span', children, ...rest } = $props();
</script>

<svelte:element this={as} class="ui-muted" {...rest}>{@render children?.()}</svelte:element>

<style>
  .ui-muted { font-size: 12px; color: var(--fg-3); }
  p.ui-muted { margin: 0; }
</style>
