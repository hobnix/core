<script>
  // The Parity section of a SnapRAID share (Storage > Shares): the folders the parity leaves out and the limit of removed files that stops the
  // sync for this share. Reads `hs sys share parity state <share>`; changes go through `hs sys shares plan|start` (parity-skip, parity-keep, parity-limit).
  import { poll, rows } from '../../data.svelte.js';
  import { openPlan, openCreate } from '../../ui.svelte.js';
  import { rowstate } from '../../rowstate.svelte.js';
  import { Row, Muted, Chip } from '../../ui/index.js';
  import Button from '../../ui/Button.svelte';
  import ParitySkip from '../../forms/shares/ParitySkip.svelte';
  import ParityLimit from '../../forms/shares/ParityLimit.svelte';

  let { share, locked = false } = $props();

  const state = poll(() => `/api/sys/share/parity/state/${encodeURIComponent(share)}`, 30000, 'shares-overview');
  // limit<TAB>default|custom|off<TAB>N|-, default<TAB>floor<TAB>percent, skip<TAB>folder
  const lines = $derived(rows(state));
  const limit = $derived(lines.find((r) => r[0] === 'limit') ?? []);
  const def = $derived(lines.find((r) => r[0] === 'default') ?? []);
  const skipped = $derived(lines.filter((r) => r[0] === 'skip').map((r) => r[1]));
  const mode = $derived(limit[1] ?? 'default');
  const limitText = $derived(mode === 'off' ? 'off: a sync never stops for this share' : mode === 'custom' ? `${limit[2]} removed files` : `the higher of ${def[1] ?? 100} files and ${def[2] ?? 1} % of the share`);
</script>

<div style="padding: 12px 16px">
  <Row align="baseline" gap="3" style="margin-bottom:8px"><b>Parity</b><Muted>folders left out and the stop limit of the sync</Muted></Row>
  <Row gap="3" wrap style="padding: 7px 0; border-bottom: 1px solid var(--line)">
    <span>Sync stops after</span>
    <span style="flex: 1"><Chip>{limitText}</Chip></span>
    <Button size="sm" disabled={locked || !state.loaded} tooltip={locked ? 'Storage is locked' : 'Change how many removed files stop the sync for this share'} onclick={() => openCreate(ParityLimit, { share, current: mode === 'custom' ? limit[2] : mode })}>Change limit</Button>
  </Row>
  {#each skipped as f}
    <Row gap="3" wrap style="padding: 7px 0; border-bottom: 1px solid var(--line)">
      <code>{f}</code>
      <span style="flex: 1"><Muted>left out of the parity, not protected</Muted></span>
      <Button size="sm" busy={rowstate.pending('shares', [share, 'parity-keep', '--folder', f])} disabled={locked} tooltip={'Protect this folder again from the next sync'} onclick={() => openPlan('shares', [share, 'parity-keep', '--folder', f], `Protect ${f} of ${share} again`)}>Protect again</Button>
    </Row>
  {:else}
    <Muted as="p">No folder is left out of the parity.</Muted>
  {/each}
  <div style="margin-top:8px">
    <Button size="sm" icon="eye-slash" disabled={locked} tooltip={locked ? 'Storage is locked' : 'Leave a folder out of the parity (shows the plan and asks for the folder name)'} onclick={() => openCreate(ParitySkip, { share })}>Leave a folder out…</Button>
  </div>
</div>
