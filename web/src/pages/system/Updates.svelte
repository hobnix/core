<script>
  // System > Updates: the update page of Settings (settings/SettingsPage.svelte, page `updates`) and its second tab, Releases (settings/Releases.svelte,
  // the channel the server follows). The tab is in the address (`?tab=releases`); the old address /settings/releases ends here (redirects.js).
  import { route, setQuery } from '../../route.svelte.js';
  import PageTabs from '../../ui/PageTabs.svelte';
  import SettingsPage from '../../settings/SettingsPage.svelte';
  import Releases from '../../settings/Releases.svelte';

  let props = $props();
  const tab = $derived(route.query.tab === 'releases' ? 'releases' : 'updates');
  const tabs = [{ id: 'updates', label: 'Updates' }, { id: 'releases', label: 'Releases' }];
</script>

<PageTabs {tabs} {tab} onpick={(id) => setQuery({ tab: id === 'updates' ? null : id }, { replace: true })} />
{#if tab === 'releases'}
  <Releases {...props} />
{:else}
  <SettingsPage {...props} />
{/if}
