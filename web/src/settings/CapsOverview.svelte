<script>
  import { onMount } from 'svelte';
  import { P, capabilityPath } from '../paths.js';
  // Settings > Capabilities (/settings/capabilities): every optional part of this server with its switch, on the shared list. A part with a
  // settings page of its own links to it. The extensions have their own page (Settings > Extensions).
  import { Stack } from '../ui/index.js';
  import PageHeader from '../shell/PageHeader.svelte';
  import PartsTable from './PartsTable.svelte';
  import { useLayout } from './layoutstate.svelte.js';
  import Fields from './Fields.svelte';
  import { fieldsFor } from './layout.js';
  import { useConfig } from './config.svelte.js';
  import { useParts } from './parts.svelte.js';
  import { url } from '../route.svelte.js';

  // the old address of the extensions card, /settings/capabilities#extensions, is replaced by the new page (Back keeps working)
  onMount(() => {
    if (location.hash === '#extensions') {
      history.replaceState({}, '', url(P.settingsExtensions));
      dispatchEvent(new PopStateEvent('popstate'));
    }
  });

  const { partList, parts: getParts } = useParts();
  const plainParts = $derived(getParts().filter((p) => p.kind !== 'extension' && !p.name.startsWith('edge-')));
  const getLayout = useLayout();
  const layout = $derived(getLayout());
  const { opts: getOpts } = useConfig();
  const fields = $derived(fieldsFor(layout, 'capabilities', getOpts()));
  const pathOf = (p) => (layout.caps[p.name]?.entry ? capabilityPath(p.name) : '');
</script>

<Stack gap="4">
  <PageHeader title="Capabilities" crumb="Settings" sub="Optional parts of this server. Off means its pages and commands are not there. A part with a NixOS module changes at the next hs rebuild." />
  <PartsTable id="capabilities" items={plainParts} loaded={partList.loaded} error={!!partList.error} empty="No optional parts." {pathOf} />
  {#if fields.length}<Fields opts={fields} />{/if}
</Stack>
