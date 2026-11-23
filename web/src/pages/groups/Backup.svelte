<script>
  // The Backup group page: the last backup and the dates that run out, as state cards. It reads what those places read (readsfor.js, P.backupGroup).
  import { poll, rows } from '../../data.svelte.js';
  import { openPlan, jobRunning } from '../../ui.svelte.js';
  import GroupPage from '../GroupPage.svelte';
  import Button from '../../ui/Button.svelte';
  import { backupState } from './state.js';

  const st = poll('/api/sys/backup/state', 15000);
  const ex = poll('/api/sys/expiry/list', 10000);
  const state = $derived(backupState({ backup: st.data ? rows(st) : null, expiry: ex.data ? rows(ex) : null }));
</script>

<GroupPage title="Backup" group="backup" {state} sub="The last backup and the dates that are about to run out.">
  {#snippet actions()}
    <Button need="admin" variant="primary" icon="cloud-arrow-up" busy={jobRunning('backup', ['now'])} busyLabel="Backing up…" tooltip={'Shows the plan first'} onclick={() => openPlan('backup', ['now'], 'Back up now')}>Back up now</Button>
  {/snippet}
</GroupPage>
