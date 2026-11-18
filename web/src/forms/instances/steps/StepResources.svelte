<script>
  // Step "Resources": memory, CPU and disk size. Empty = the default of the kind (hs sys ct plan shows what that is).
  import { Field, TextInput, Muted } from '../../../ui/index.js';
  let { ram = $bindable(''), cpu = $bindable(''), disk = $bindable(''), type = 'container' } = $props();
  const num = (v) => v.trim() === '' || /^[0-9]{1,7}$/.test(v.trim());
  const bad = $derived(!num(ram) || !num(cpu) || !num(disk));
</script>

<div class="row3">
  <Field label="RAM limit (MiB)"><TextInput bind:value={ram} placeholder={type === 'vm' ? '2048' : 'default'} inputmode="numeric" autocomplete="off" /></Field>
  <Field label="CPU limit"><TextInput bind:value={cpu} placeholder={type === 'vm' ? '2' : 'default'} inputmode="numeric" autocomplete="off" /></Field>
  <Field label="Disk (GiB)"><TextInput bind:value={disk} placeholder={type === 'vm' ? '20' : 'default'} inputmode="numeric" autocomplete="off" /></Field>
</div>
{#if bad}<div class="bad">Use whole numbers.</div>{/if}
<Muted as="div">{type === 'vm' ? 'The memory and the disk of a virtual machine are reserved for it.' : 'The memory limit is a ceiling, not reserved memory.'}</Muted>

<style>
  .row3 { display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px; }
  .bad { font-size: 12px; color: var(--bad); }
</style>
