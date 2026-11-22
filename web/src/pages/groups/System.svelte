<script>
  // The System group page (the former Health): problems, updates, certificates, hardware and events as state cards. It reads what those places
  // read (readsfor.js, P.operations).
  import { poll, rows } from '../../data.svelte.js';
  import { openPlan, jobRunning } from '../../ui.svelte.js';
  import GroupPage from '../GroupPage.svelte';
  import Button from '../../ui/Button.svelte';
  import { systemState } from './state.js';

  const hlist = poll('/api/sys/health/list', 15000);
  const updates = poll('/api/sys/system/updates', 60000, 'system-updates');
  const dc = poll('/api/sys/dc/state', 30000);
  const ups = poll('/api/sys/ups/status', 20000);
  const ev = poll('/api/sys/event/list?n=100', 30000, 'event-log');
  const answer = (st) => (st.data && !st.error ? rows(st) : null);
  const state = $derived(systemState({ problems: answer(hlist), updates: answer(updates), certs: answer(dc), ups: answer(ups), events: answer(ev) }));
</script>

<GroupPage title="System" {state} sub="Problems, updates, certificates, hardware and events of this server.">
  {#snippet actions()}
    <Button need="admin" variant="primary" icon="shield-check" busy={jobRunning('jobs', ['run', 'hs-health-check.service'])} busyLabel="Checking…" tooltip={'Check everything now and list the problems'} onclick={() => openPlan('jobs', ['run', 'hs-health-check.service'], 'Health check')}>Run health check</Button>
  {/snippet}
</GroupPage>
