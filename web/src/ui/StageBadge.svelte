<script>
  // The lifecycle stage of a package (ADR 0027) as one word with a dot, and its flags as small chips. Never colour alone.
  //   <StageBadge stage="running" flags={['update']} />
  import StatusDot from './StatusDot.svelte';
  import Chip from './Chip.svelte';
  let { stage = 'available', flags = [] } = $props();
  const dot = $derived(stage === 'running' ? 'ok' : stage === 'on' ? 'info' : 'off');
  const bad = (f) => f === 'failed' || f === 'unhealthy' || f === 'orphan';
</script>

<span style="display:inline-flex;align-items:center;gap:8px;flex-wrap:wrap">
  <StatusDot state={dot} label={stage} />
  {#each flags as f}<Chip tone={bad(f) ? 'bad' : 'warn'}>{f}</Chip>{/each}
</span>
