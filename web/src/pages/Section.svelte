<script>
  // The overview of a group that has no state page of its own (Instances, Apps, Network, People, Settings, Developer): one card per child page with the
  // note the tree shows (a count or a problem chip). Storage, Backup and System have pages/GroupPage.svelte. Nothing is read here that the tree does not read.
  import { route, go } from '../route.svelte.js';
  import { lockedWhy } from '../roles.js';
  import { ui } from '../ui.svelte.js';
  import { tip } from "../ui/tooltip.svelte.js";
  import { tree } from '../nav.js';
  import Icon from '../ui/Icon.svelte';
  import PageTrail from '../shell/PageTrail.svelte';

  let { deck, meta = {} } = $props();

  const find = (items, path) => {
    for (const it of items) {
      if (it.path === path) return it;
      const r = it.children && find(it.children, path);
      if (r) return r;
    }
    return null;
  };
  const node = $derived(find(tree, route.path));
  const locked = $derived(!!deck?.data?.locked);

  const cards = $derived((node?.children ?? []).map((c) => ({ ...c, needs: lockedWhy(ui.role, c.path), kids: c.children ?? [] })));
  const dim = (c) => locked && c.storage;
  const note = (it) => (dim(it) ? { text: 'locked', warn: true } : meta[it.path] ?? null);
  const shown = (n) => n.text ?? '●';
</script>

<div class="page">
  <PageTrail />
  <h3>{node?.label ?? 'Overview'}</h3>

  <div class="grid">
    {#each cards as c}
      {@const n = note(c)}
      <div class="card elev-sm item" class:dim={dim(c) || !!c.needs}>
        <button class="head" use:tip={c.needs || ""} aria-label={c.needs ? `${c.label}. ${c.needs}` : undefined} onclick={() => c.path && go(c.path)}>
          <Icon name={c.icon} /><span class="nm">{c.label}</span>
          {#if n}<span class="meta" class:warn={n.warn}>{shown(n)}</span>{/if}
          {#if dim(c) || c.needs}<Icon name="lock-simple" class="lock" />{/if}
        </button>
        {#each c.kids as k}
          {@const kn = note(k)}
          {@const kneeds = lockedWhy(ui.role, k.path)}
          <button class="kid" class:grey={!!kneeds} use:tip={kneeds || ""} aria-label={kneeds ? `${k.label}. ${kneeds}` : undefined} onclick={() => go(k.path)}>
            <Icon name={k.icon} /><span>{k.label}</span>
            {#if kn}<span class="meta" class:warn={kn.warn}>{shown(kn)}</span>{/if}
          </button>
        {/each}
      </div>
    {/each}
  </div>
</div>

<style>
  .page { display: flex; flex-direction: column; gap: 14px; }
  h3 { font-size: 20px; margin: 0; }
  .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(260px, 1fr)); gap: 12px; }
  .item { padding: 6px; gap: 0; }
  .item.dim { opacity: 0.6; }
  .kid.grey { opacity: 0.6; }
  .head, .kid { display: flex; align-items: center; gap: 8px; width: 100%; padding: 8px 10px; border: 0; background: none; color: inherit; font: inherit; text-align: left; border-radius: var(--r); cursor: pointer; }
  .head:hover, .kid:hover { background: var(--color-neutral-900); }
  .head :global(i), .kid :global(i) { font-size: 16px; color: var(--color-neutral-400); }
  .head :global(i.lock) { color: var(--color-neutral-600); }
  .kid { padding-left: 30px; font-size: 13px; color: var(--color-neutral-300); }
  .nm { font-size: 14px; font-weight: 500; }
  .meta { margin-left: auto; font-size: 11px; color: var(--color-neutral-500); }
  .meta.warn { color: var(--st-warn); }
</style>
