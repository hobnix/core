<script>
  // Children side by side. `gap` is a step of the spacing tokens (1 2 3 4 6 8), `align`: center (default) | start | end | stretch | baseline,
  // `wrap` lets them flow to the next line, `justify`: start | between | end. Put <span class="grow"></span> between to push the rest right.
  //   <Row gap="3"><b>Name</b><Muted>12 GB</Muted></Row>
  let { gap = '3', align = 'center', justify = 'start', wrap = false, children, ...rest } = $props();
  const j = { start: 'flex-start', between: 'space-between', end: 'flex-end' };
</script>

<div class="row" style:gap="var(--space-{gap})" style:align-items={align === 'start' || align === 'end' ? `flex-${align}` : align} style:justify-content={j[justify] ?? 'flex-start'} class:wrap {...rest}>{@render children?.()}</div>

<style>
  .row { display: flex; min-width: 0; }
  .wrap { flex-wrap: wrap; }
</style>
