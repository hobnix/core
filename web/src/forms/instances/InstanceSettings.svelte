<script>
  // Settings of one instance: `ct <name> set [--ram .. --cpu .. --disk .. --autostart on|off --docker yes|no]` or `ct <name> ip --address <ip>`.
  // Only what differs from today's value is sent.
  import { Checkbox, Field, TextInput, Segmented } from '../../ui/index.js';
  import CreateDialog from '../../shell/CreateDialog.svelte';

  let { ct, ondone = () => {} } = $props();
  const num = (v) => { const m = /^(\d+)/.exec(v ?? ''); return m ? m[1] : ''; };
  const yes = (v) => /^(yes|true|on)$/i.test((v ?? '').trim());

  const start = { ram: num(ct.ram), cpu: num(ct.cpu), disk: num(ct.disk), autostart: yes(ct.autostart), docker: yes(ct.docker), address: /^\d+\./.test(ct.address) ? ct.address : '' };
  let mode = $state('resources');
  let ram = $state(start.ram);
  let cpu = $state(start.cpu);
  let disk = $state(start.disk);
  let autostart = $state(start.autostart);
  let docker = $state(start.docker);
  let address = $state(start.address);

  const args = () => {
    if (mode === 'address') return address.trim() && address.trim() !== start.address ? [ct.name, 'ip', '--address', address.trim()] : null;
    const a = [ct.name, 'set'];
    if (ram.trim() && ram.trim() !== start.ram) a.push('--ram', ram.trim());
    if (cpu.trim() && cpu.trim() !== start.cpu) a.push('--cpu', cpu.trim());
    if (disk.trim() && disk.trim() !== start.disk) a.push('--disk', disk.trim());
    if (autostart !== start.autostart) a.push('--autostart', autostart ? 'on' : 'off');
    if (docker !== start.docker) a.push('--docker', docker ? 'yes' : 'no');
    return a.length > 2 ? a : null;
  };
</script>

<CreateDialog kicker="Settings" title={`Settings of ${ct.name}`} area="ct" {args} {ondone}>
  {#snippet form()}
    <Segmented bind:value={mode} label="What to change" options={[{ value: 'resources', label: 'Resources' }, { value: 'address', label: 'Fixed address' }]} />
    {#if mode === 'resources'}
      <div class="two">
        <Field label={'RAM limit (MiB, "none" removes it)'}><TextInput bind:value={ram} autocomplete="off" /></Field>
        <Field label="CPU limit"><TextInput bind:value={cpu} autocomplete="off" /></Field>
      </div>
      <Field label="Disk size (GiB, can only grow)"><TextInput bind:value={disk} autocomplete="off" /></Field>
      <Checkbox bind:checked={autostart} label="Start at boot" hint="off = keep it off: it stays as it is" />
      <Checkbox bind:checked={docker} label="Docker support (restart the instance afterwards)" />
    {:else}
      <Field label="Fixed address" help="The instance restarts when the address changes.">
        <TextInput bind:value={address} placeholder="10.10.95.25" autocomplete="off" spellcheck={false} />
      </Field>
    {/if}
  {/snippet}
</CreateDialog>

<style>
  .two { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }
</style>
