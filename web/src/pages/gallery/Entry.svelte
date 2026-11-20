<script>
  // One component of the gallery: its name (the coverage test tests/web-gallery.mjs looks for `<Entry name="X"` in pages/Gallery.svelte), where it lives,
  // one line of what it is, and the states in the default snippet. Each state is a `.cell` with a small caption: <div class="cell"><small>busy</small>...</div>.
  let { name, from = 'ui', text = '', children } = $props();
</script>

<section class="gal-entry" id="c-{name}" data-entry={name}>
  <h2>{name} <small>{from}/{name}.svelte</small></h2>
  {#if text}<p class="gal-what">{text}</p>{/if}
  <div class="gal-states">{@render children?.()}</div>
</section>
