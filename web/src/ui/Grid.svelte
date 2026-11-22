<script>
  // Children in a grid of equal columns that wrap: as many as fit at `min` px each (the cards of a group page). `gap` is a step of the spacing tokens.
  //   <Grid min="260"><StateCard/><StateCard/></Grid>
  let { min = '260', gap = '4', children, ...rest } = $props();
</script>

<div class="grid" style:grid-template-columns="repeat(auto-fill, minmax({min}px, 1fr))" style:gap="var(--space-{gap})" {...rest}>{@render children?.()}</div>

<style>
  .grid { display: grid; min-width: 0; }
</style>
