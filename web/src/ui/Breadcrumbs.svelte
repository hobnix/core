<script>
  // The trail above a page title: the PARENTS of the page (the title under it names the page itself). Every part is a real link (middle click,
  // copy address work); a plain click navigates inside the app. Nothing is drawn for an empty trail. The first part is the server's name and is
  // never translated. The shell derives the items (shell/PageTrail.svelte).
  //   <Breadcrumbs items={[{ label: 'homeserver', path: '/' }, { label: 'Storage', path: '/storage' }]} />
  import { go, url } from '../route.svelte.js';
  import { tr } from '../i18n.js';
  let { items = [] } = $props();

  function click(e, path) {
    if (e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;   // let the browser open it in a tab
    e.preventDefault();
    go(path);
  }
</script>

{#if items.length}
  <nav class="bc" aria-label="Breadcrumb">
    <ol>
      {#each items as c, i (c.path)}
        <li>
          {#if i}<span class="sep" aria-hidden="true">›</span>{/if}
          <a href={url(c.path)} onclick={(e) => click(e, c.path)}>{i ? tr(c.label) : c.label}</a>
        </li>
      {/each}
    </ol>
  </nav>
{/if}

<style>
  .bc { margin-bottom: 6px; }
  ol { display: flex; flex-wrap: wrap; align-items: center; gap: 2px 6px; margin: 0; padding: 0; list-style: none; font: 12px var(--mono); color: var(--fg-3); }
  li { display: flex; align-items: center; gap: 6px; min-width: 0; }
  a { color: var(--fg-3); text-decoration: none; overflow-wrap: anywhere; }
  a:hover { color: var(--fg); text-decoration: underline; }
  @media (max-width: 860px) { a { padding: 6px 2px; margin: -6px -2px; } }
</style>
