<script>
  // Tab "Console" of the page of one instance: a shell inside it (every instance) and the screen of a virtual machine, both in the existing windows over the page
  // (shell/Terminal.svelte, shell/VmConsole.svelte keep their own terminal frame; this tab only opens them), then the journal of the instance.
  import { openCreate, ui } from '../../ui.svelte.js';
  import { Card, Muted, Row } from '../../ui/index.js';
  import Button from '../../ui/Button.svelte';
  import Terminal from '../../shell/Terminal.svelte';
  import VmConsole from '../../shell/VmConsole.svelte';
  import LogsTab from './LogsTab.svelte';
  import { isVm, isRunning } from './ct.js';

  let { m } = $props();
  const ct = $derived(m.ct);
  const why = $derived(!ui.features.terminal ? 'Switch on webTerminal in machine.toml' : !isRunning(ct) ? 'The instance is not running' : '');
</script>

<Card title="Console">
  <Row gap="3" wrap align="center">
    <Button need="admin" icon="terminal-window" disabled={!!why} tooltip={why || 'A shell inside the instance'} onclick={() => openCreate(Terminal, { target: ct.name, title: ct.name })}>Terminal</Button>
    {#if isVm(ct)}<Button need="admin" icon="monitor" disabled={!!why} tooltip={why || 'The screen of the virtual machine'} onclick={() => openCreate(VmConsole, { target: ct.name, title: ct.name })}>Screen</Button>{/if}
  </Row>
  <Muted as="p">{isVm(ct) ? 'The terminal is a shell inside the virtual machine; the screen is its graphical console.' : 'A shell inside the container.'} Both open in a window and close without stopping anything.</Muted>
</Card>

<Card title="Logs">
  {#key ct.name}<LogsTab ct={ct.name} />{/key}
</Card>
