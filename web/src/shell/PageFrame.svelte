<script>
  import Button from '../ui/Button.svelte';
  // Around EVERY page: the states that do not depend on the page's own data, decided here once.
  //   storage locked   a page whose tree item has `storage: true` is NOT rendered (so it reads nothing); an amber banner with the unlock form instead
  //   part switched off the tree item's `capability` is not in the session's capability list: explanation + link to Settings
  //   node unreachable  a remote node that does not answer: red banner with the likely reason and Try again; the page stays visible (its last document), greyed, no actions
  //   no such page      the placeholder (shell/Placeholder.svelte)
  // Everything else (loading, empty, error with stale data) is PageState.svelte inside the page.
  import { route, go } from '../route.svelte.js';
  import { pageFor } from '../routes.js';
  import { itemOf } from '../nav.js';
  import { pageRole, roleOk, refusal } from '../roles.js';
  import { ui } from '../ui.svelte.js';
  import Banner from '../ui/Banner.svelte';
  import EmptyState from '../ui/EmptyState.svelte';
  import Skeleton from '../ui/Skeleton.svelte';
  import UnlockForm from '../forms/unlock/UnlockForm.svelte';
  import Placeholder from './Placeholder.svelte';
  import PendingRebuild from './PendingRebuild.svelte';

  // deck: the shared status document; meta: tree notes; node: { name, kind, local, state: 'ok'|'down'|'off'|'loading', why, retry } of the node on screen
  let { deck, meta, node, locked = false } = $props();

  const inner = $derived(route.path);
  const item = $derived(node.local ? itemOf(inner) : null);
  // a remote node has its own table of pages by kind (routes.js nodeRoutes); they read its status document and offer no change
  const Page = $derived(pageFor(inner, node.local ? 'main' : node.kind));
  const caps = $derived(ui.features.capabilities);
  const off = $derived(node.local && !!item?.capability && Array.isArray(caps) && !caps.includes(item.capability));
  const gate = $derived(node.local && locked && !!item?.storage);
  // a page of a higher role than this session has: said in words (the server answers 403 to its reads too); a remote node's pages only read, never refused here
  const need = $derived(node.local ? pageRole(inner) : 'viewer');
  const refused = $derived(!roleOk(ui.role, need));
  const down = $derived(!node.local && node.state === 'down');
</script>

{#if refused}
  <div class="card"><EmptyState tone="info" icon="prohibit" title="Not for your role"
    text={refusal(ui.role, need) + ` Only the ${need} role may open this page. Ask an administrator if you need it.`}>
    {#snippet action()}<Button tooltip={'Back to the summary'} onclick={() => go('/')}><i class="ph ph-house"></i>Summary</Button>{/snippet}
  </EmptyState></div>
{:else if off}
  <div class="card"><EmptyState tone="info" icon="power" title="This part is switched off"
    text="It is not part of this server's configuration, so there is nothing to show. Switch it on in Settings (the line is capabilities in machine.toml).">
    {#snippet action()}<Button tooltip={'Open the settings page'} onclick={() => go('/settings/capabilities')}><i class="ph ph-sliders"></i>Open Settings</Button>{/snippet}
  </EmptyState></div>
{:else if gate}
  <Banner tone="warn" icon="lock">
    <b>Storage is locked.</b> This page reads the encrypted storage, so it stays empty until the passphrase is entered.
    {#snippet action()}<div class="unl"><UnlockForm /></div>{/snippet}
  </Banner>
{:else}
  {#if down}
    <Banner tone="bad">
      <b>{node.name} does not answer.</b> {node.why || 'The likely reasons: the server is off, the network is down, or its key was changed.'} The data below is the last that was read.
      {#snippet action()}{#if node.retry}<Button size="sm" tooltip={'Read the page again'} onclick={node.retry}><i class="ph ph-arrow-clockwise"></i>Try again</Button>{/if}{/snippet}
    </Banner>
  {/if}
  <div class="pg" class:down inert={down || undefined}>
    {#if node.local}<PendingRebuild />{/if}
    {#if Page?.lazy}
      {#await Page.lazy()}
        <Skeleton />
      {:then m}
        {@const Loaded = m.default}<Loaded {deck} {meta} {node} />
      {:catch}
        <Banner tone="bad">This page could not be loaded. Reload the browser tab and try again.</Banner>
      {/await}
    {:else if Page}<Page {deck} {meta} {node} />{:else}<Placeholder />{/if}
  </div>
{/if}

<style>
  .pg { display: flex; flex-direction: column; gap: 14px; min-width: 0; }
  .pg.down { opacity: 0.45; filter: grayscale(1); }
  .unl { width: min(380px, 100%); }
</style>
