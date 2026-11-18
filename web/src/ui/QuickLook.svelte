<script>
  // The quick look of a list page: the Drawer as an overlay above the list, so selecting a row never narrows or moves the list (design 3.3).
  // The same props and snippets as <Drawer>; the list stays usable behind it (it is not modal), so another row replaces the content.
  //   <QuickLook title={row.name} chip="zfs" state="ok" stateLabel="online" onclose={() => (sel = null)} {openPage}> ...Kv, linked objects... {#snippet actions()}...{/snippet} </QuickLook>
  // `href`: the "Open page" link to the object's own page. Escape closes it when the focus is inside it. Full screen on a phone (up to 860 px).
  // Put it inside the page's relative container, next to the list, not in a <Split>.
  import Drawer from './Drawer.svelte';
  let { href = '', openLabel = 'Open page', tab = $bindable(''), children: body, actions: acts, ...rest } = $props();
</script>

<div class="ql">
  <Drawer {...rest} bind:tab>
    {#snippet children(active)}{@render body?.(active)}{/snippet}
    {#snippet actions()}
      {#if href}<a class="btn sm" {href}>{openLabel}<i class="ph ph-arrow-right"></i></a>{/if}
      {@render acts?.()}
    {/snippet}
  </Drawer>
</div>

<style>
  .ql { position: absolute; top: 0; right: 0; bottom: 0; z-index: 12; display: flex; pointer-events: none; }
  .ql :global(.arow:empty) { display: none; }
  .ql :global(.sdr) { pointer-events: auto; position: static; width: 400px; max-height: 100%; height: 100%; }
  @media (max-width: 860px) { .ql { position: fixed; inset: 52px 0 0 0; z-index: 13; } .ql :global(.sdr) { width: 100vw; } }
</style>
