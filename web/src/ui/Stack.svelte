<script>
  // Children one below the other. `gap` is a step of the spacing tokens (1 2 3 4 6 8), `align`: stretch (default) | start | center | end.
  //   <Stack gap="4"><Card/><Card/></Stack>
  let { gap = '4', align = 'stretch', children, ...rest } = $props();
</script>

<div class="stack" style:gap="var(--space-{gap})" style:align-items={align === 'start' || align === 'end' ? `flex-${align}` : align} {...rest}>{@render children?.()}</div>

<style>
  .stack { display: flex; flex-direction: column; min-width: 0; }
</style>
