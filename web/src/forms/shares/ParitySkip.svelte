<script>
  // Leave a folder of a share out of the parity: `hs sys shares plan|start <share> parity-skip --folder <name>`. The plan names the loss of
  // protection and asks to type the FOLDER name (the dialog shows that field, the plan's confirm_name).
  import CreateDialog from '../../shell/CreateDialog.svelte';
  import { Field, TextInput, Muted } from '../../ui';

  let { share, onclose, ondone = () => {} } = $props();
  let folder = $state('');
  const ok = $derived(/^[A-Za-z0-9._ -]{1,80}(\/[A-Za-z0-9._ -]{1,80}){0,6}$/.test(folder) && !folder.split('/').some((p) => p === '.' || p === '..'));
  const args = () => (ok ? [share, 'parity-skip', '--folder', folder] : null);
</script>

<CreateDialog title="Leave a folder out of the parity" kicker="Change" area="shares" {args} {onclose} {ondone}>
  {#snippet form()}
    <Field label="Folder in {share}" error={folder && !ok ? 'A folder inside the share: letters, digits, . _ - and spaces, no “..”.' : ''}>
      <TextInput bind:value={folder} placeholder="downloads" autocomplete="off" spellcheck={false} />
    </Field>
    <Muted as="p">For folders where files appear, change and vanish all the time (downloads, unpacking). SnapRAID skips them, so a sync neither fails on them nor counts their removed files. Their files are not protected by the parity.</Muted>
  {/snippet}
</CreateDialog>
