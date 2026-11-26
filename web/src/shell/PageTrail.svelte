<script>
  // The breadcrumb of the page on screen, derived from the tree (nav.js trailOf): no page passes its own. PageFrame says which node is on screen
  // (a remote node has its own name and tree); without it, it is this server.
  import { getContext } from 'svelte';
  import Breadcrumbs from '../ui/Breadcrumbs.svelte';
  import { route } from '../route.svelte.js';
  import { nodeTrail } from '../nav.js';
  import { ui } from '../ui.svelte.js';

  const node = getContext('hs-node');
  const items = $derived(nodeTrail(route.path, node?.(), route.node || ui.host, ui.features.extensions));
</script>

<Breadcrumbs {items} />
