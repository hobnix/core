<script>
  // Remove an app instance: hs sys apps plan|start remove <instance> (docs/PLAN-app-lifecycle.md Q3, step 11). The plan lists what goes and what stays,
  // the data question is its own checkbox (kept by default; deleting asks for the name a second time), the typed name of the instance is the dialog's
  // confirmation. Runs as a background job.
  import CreateDialog from '../../shell/CreateDialog.svelte';
  import Checkbox from '../../ui/Checkbox.svelte';
  import TextInput from '../../ui/TextInput.svelte';
  import { tr } from '../../i18n.js';

  let { app, onclose, ondone } = $props();   // app = the instance
  let deleteData = $state(false);
  let again = $state('');
  const args = () => (app ? ['remove', app, ...(deleteData ? ['--delete-data', ...(again === app ? ['--confirm-data', app] : [])] : [])] : null);
</script>

<CreateDialog title={tr('Remove') + ' ' + app} kicker={tr('Remove')} area="apps" {args} {onclose} {ondone}>
  {#snippet form()}
    <div style="font-size:12px;color:var(--fg-3);margin:6px 0">{tr('Removes the instance, its route and its fixed address. Shares and volumes with data stay unless you delete the data.')}</div>
    <Checkbox bind:checked={deleteData} label={tr('Also delete the data')} hint={tr('Off: the data is kept and a later install finds it again (the default).')} />
    {#if deleteData}
      <div style="font-size:12px;color:var(--fg-3);margin:6px 0">{tr('Type the name of the app a second time to delete its data:')} <b>{app}</b></div>
      <TextInput bind:value={again} placeholder={app} autocomplete="off" spellcheck={false} ariaLabel={tr('The name of the app, again')} />
    {/if}
  {/snippet}
</CreateDialog>
