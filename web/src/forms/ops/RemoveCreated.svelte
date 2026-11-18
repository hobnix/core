<script>
  // Remove what a failed install created: hs sys apps plan|start cleanup <job>. The plan lists what the run made (each line checked again), the
  // data question is its own checkbox (kept by default), the typed name of the app is the dialog's confirmation. Runs as a background job.
  import CreateDialog from '../../shell/CreateDialog.svelte';
  import Checkbox from '../../ui/Checkbox.svelte';
  import { tr } from '../../i18n.js';

  let { job, app = '', onclose, ondone } = $props();
  let deleteData = $state(false);
  const args = () => (job ? ['cleanup', job, ...(deleteData ? ['--delete-data'] : [])] : null);
</script>

<CreateDialog title={tr('Remove what was created')} kicker={tr('Remove')} area="apps" {args} {onclose} {ondone}>
  {#snippet form()}
    <div style="font-size:12px;color:var(--fg-3);margin:6px 0">{tr('Only what the install itself created is removed. What was there before stays.')}</div>
    <Checkbox bind:checked={deleteData} label={tr('Also delete the data it created')} hint={tr('Off: the data is kept (the default).')} />
    {#if app}<div style="font-size:12px;color:var(--fg-3);margin:6px 0">{tr('Type the name of the app to confirm:')} <b>{app}</b></div>{/if}
  {/snippet}
</CreateDialog>
