<script>
  // The number of removed files that stops the parity sync for one share: `hs sys shares plan|start <share> parity-limit --to <N>|off|default`.
  import CreateDialog from '../../shell/CreateDialog.svelte';
  import { Field, TextInput, Muted } from '../../ui';

  let { share, current = '', onclose, ondone = () => {} } = $props();
  let to = $state(current && current !== 'default' ? current : '');
  const ok = $derived(/^([0-9]{1,9}|off|default)$/.test(to));
  const args = () => (ok ? [share, 'parity-limit', '--to', to] : null);
</script>

<CreateDialog title="Limit of removed files for {share}" kicker="Change" area="shares" {args} {onclose} {ondone}>
  {#snippet form()}
    <Field label="Limit (a number, off or default)" error={to && !ok ? 'A whole number, “off” or “default”.' : ''}>
      <TextInput bind:value={to} placeholder="default" autocomplete="off" spellcheck={false} />
    </Field>
    <Muted as="p">The parity sync stops for this share when more files than this were removed since the last sync, so a mistake or malware is not made permanent. “default” is the higher of 100 files and 1 % of the share. “off” never stops.</Muted>
  {/snippet}
</CreateDialog>
