<script>
  import { extensionPath } from '../paths.js';
  // Settings > Extensions (/settings/extensions): the packages that add pages and commands (hs ext), on the shared list. Off by default; one
  // without a NixOS module is on at once. A row of an extension that is on opens its page.
  import { Stack } from '../ui/index.js';
  import PageHeader from '../shell/PageHeader.svelte';
  import PartsTable from './PartsTable.svelte';
  import { useParts } from './parts.svelte.js';

  const { partList, parts: getParts } = useParts();
  const extensions = $derived(getParts().filter((p) => p.kind === 'extension'));
  const pathOf = (p) => (p.on ? extensionPath(p.name) : '');
</script>

<Stack gap="4">
  <PageHeader title="Extensions" sub="Packages that add pages and commands (hs ext). Off by default; one without a NixOS module is on at once." />
  <PartsTable id="extensions" items={extensions} loaded={partList.loaded} error={!!partList.error} empty="No extensions on this server." {pathOf} />
</Stack>
