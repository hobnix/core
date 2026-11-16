<script>
  // The error screen of the Install dialog (docs/PLAN-app-lifecycle.md Q3, step 9, #466): a failed Install job names its step, says why, shows the
  // last lines of its log and offers Retry (the job again from that step) and Remove what was created. `job` is the failed record: its `result` holds
  // failed_step, reason, tail (written by scripts/apps-change.sh). The dialog (step 8b) renders this where it shows the job's end.
  import Banner from '../../ui/Banner.svelte';
  import Button from '../../ui/Button.svelte';
  import { openPlan, openCreate } from '../../ui.svelte.js';
  import { tr } from '../../i18n.js';
  import RemoveCreated from './RemoveCreated.svelte';

  let { job, onclose = () => {} } = $props();

  const r = $derived(job?.result ?? {});
  const step = $derived(r.failed_step ?? '');
  const lines = $derived((r.tail ?? '').split(' | ').filter((l) => l.trim() !== ''));
  const retry = () => { onclose(); openPlan('apps', ['retry', job.id], tr('Retry the install')); };
  const remove = () => { onclose(); openCreate(RemoveCreated, { job: job.id, app: r.instance ?? '' }); };
</script>

<Banner tone="bad">
  {tr('The install stopped')}{#if step}: {tr('failed at')} <code>{step}</code>{/if}.
  {r.reason ?? ''}
</Banner>
{#if lines.length}
  <pre style="font:12px var(--mono);color:var(--fg-2);background:var(--bg-2);padding:8px 10px;border-radius:6px;white-space:pre-wrap">{lines.join('\n')}</pre>
{/if}
<div style="display:flex;gap:8px;margin-top:12px">
  <Button variant="primary" icon="arrow-clockwise" onclick={retry} disabled={!step}>{tr('Retry')}</Button>
  <Button variant="danger" icon="trash" onclick={remove} disabled={!r.instance}>{tr('Remove what was created')}</Button>
</div>
