<script>
  // The quick look of a list page: the Drawer as an overlay above the list, so selecting a row never narrows or moves the list (design 3.3, D5).
  // The same props and snippets as <Drawer>; the list stays usable behind it (it is not modal), so another row replaces the content.
  //   <QuickLook title={row.name} chip="zfs" state="ok" stateLabel="online" rowKey={row.name} onclose={close} href={diskPath(row.name)}> ...Kv, linked objects... {#snippet actions()}...{/snippet} </QuickLook>
  // `href`: the INNER path of the object's own page ("Open page"); it is followed inside the app. Full screen on a phone (up to 860 px).
  // Behaviour (rules in quicklook.js): Escape closes it wherever the focus is in the page while no dialog or menu is open; a press outside closes it, but not on
  // another row of the list (that replaces it) and not in a dialog it opened; closing gives the focus back to the row (`rowKey` = the row's key, the Table's data-k).
  // It is a non-modal dialog: role="dialog", not marked modal, no scroll lock, no focus trap. Put it inside the page's relative container, next to the list, not in a <Split>.
  import Drawer from './Drawer.svelte';
  import { go, url } from '../route.svelte.js';
  import { closesOnKey, closesOnPress, returnTarget } from './quicklook.js';
  let { href = '', openLabel = 'Open page', rowKey = '', row = '[data-k]', onclose = null, tab = $bindable(''), children: body, actions: acts, ...rest } = $props();

  let root = $state();
  let opener = null;
  let key = rowKey;
  $effect(() => { key = rowKey; });
  $effect(() => {
    opener = document.activeElement;
    const keydown = (e) => { if (onclose && closesOnKey(e, document)) { e.preventDefault(); onclose(); } };
    const press = (e) => { if (onclose && closesOnPress(e.target, root, row, document)) onclose(); };
    document.addEventListener('keydown', keydown);
    document.addEventListener('pointerdown', press, true);
    return () => {
      document.removeEventListener('keydown', keydown);
      document.removeEventListener('pointerdown', press, true);
      returnTarget(document, key, opener)?.focus({ preventScroll: true });
    };
  });
  const open = (e) => { if (e.metaKey || e.ctrlKey || e.shiftKey || e.button) return; e.preventDefault(); go(href); };
</script>

<div class="ql" bind:this={root}>
  <Drawer {...rest} {onclose} role="dialog" bind:tab>
    {#snippet children(active)}{@render body?.(active)}{/snippet}
    {#snippet actions()}
      {#if href}<a class="btn sm" href={url(href)} onclick={open}>{openLabel}<i class="ph ph-arrow-right" aria-hidden="true"></i></a>{/if}
      {@render acts?.()}
    {/snippet}
  </Drawer>
</div>

<style>
  .ql { position: absolute; top: 0; right: 0; bottom: 0; z-index: 12; display: flex; align-items: flex-start; pointer-events: none; }
  .ql :global(.arow:empty) { display: none; }
  .ql :global(.sdr) { pointer-events: auto; position: sticky; top: var(--sticky-top, 0); width: 400px; max-height: calc(100vh - 140px); height: auto; }
  @media (max-width: 860px) { .ql { position: fixed; inset: 52px 0 0 0; z-index: 13; } .ql :global(.sdr) { position: static; width: 100%; height: 100%; max-height: 100%; }
    .ql :global(.sdr .drawer-sq), .ql :global(.sdr .stab), .ql :global(.sdr .arow .btn) { min-height: 44px; }
    .ql :global(.sdr .drawer-sq) { width: 44px; }
    .ql :global(.sdr .arow) { padding-bottom: calc(14px + env(safe-area-inset-bottom, 0px)); }
    .ql :global(.sdr .body) { overscroll-behavior: contain; } }
</style>
