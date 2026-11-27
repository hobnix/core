<script>
  // The card of one app or package in a store grid: icon, name (a real link to its page, middle click works), one line, then `meta` (chips:
  // category, trust) and a foot with `status` text on the left and `actions` (one or two Buttons) on the right. Equal height in a Grid.
  //   <AppTile title="jellyfin" line="Watch your films" href="/apps/marketplace/official/jellyfin" icon="film-strip">
  //     {#snippet meta()}<Chip>Media</Chip>{/snippet} {#snippet actions()}<Button size="sm">Install</Button>{/snippet}</AppTile>
  // All text is data and is drawn as text. `kicker` is a small word over the name (the kind of an add-on).
  import Card from './Card.svelte';
  import AppIcon from './AppIcon.svelte';
  import { url, go } from '../route.svelte.js';
  // a plain click stays in the app (go); a middle or modified click opens the address like any link
  const visit = (e) => { if (e.metaKey || e.ctrlKey || e.shiftKey || e.button) return; e.preventDefault(); go(href); };
  let { title, line = '', href = '', icon = 'package', src = '', on = false, kicker = '', status = '', meta, actions, ...rest } = $props();
</script>

<Card style="height:100%" {...rest}>
  <div class="top">
    <AppIcon {icon} {src} {on} />
    <div class="tt">
      {#if kicker}<div class="card-kicker">{kicker}</div>{/if}
      {#if href}<a class="nm" href={url(href)} onclick={visit}>{title}</a>{:else}<span class="nm">{title}</span>{/if}
    </div>
  </div>
  {#if line}<p class="line">{line}</p>{/if}
  {#if meta}<div class="meta">{@render meta()}</div>{/if}
  {#if status || actions}
    <div class="foot">
      {#if status}<span class="st">{status}</span>{/if}
      {#if actions}<div class="btns">{@render actions()}</div>{/if}
    </div>
  {/if}
</Card>

<style>
  .top { display: flex; align-items: center; gap: var(--space-3); min-width: 0; }
  .tt { min-width: 0; }
  .nm { display: block; font-weight: 600; font-size: 14.5px; color: var(--fg); text-decoration: none; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  a.nm:hover { text-decoration: underline; }
  .line { margin: 0; color: var(--fg-2); font-size: 13px; line-height: 1.45; flex: 1; display: -webkit-box; -webkit-line-clamp: 3; line-clamp: 3; -webkit-box-orient: vertical; overflow: hidden; overflow-wrap: anywhere; }
  .meta { display: flex; flex-wrap: wrap; gap: var(--space-2); }
  .foot { display: flex; flex-direction: column; gap: var(--space-2); margin-top: auto; padding-top: var(--space-2); border-top: 1px solid var(--line); }
  .st { font-size: 12px; color: var(--fg-3); min-width: 0; }
  .btns { display: flex; flex-wrap: wrap; gap: var(--space-2); }
</style>
