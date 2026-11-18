<script>
  // Step "Name and kind" of the instance wizard (CreateInstance.svelte). The same step for a container, Docker and a virtual machine.
  import { Field, TextInput, Segmented, Muted } from '../../../ui/index.js';
  let { name = $bindable(''), type = $bindable('container') } = $props();
  const kinds = [{ value: 'container', label: 'Empty container' }, { value: 'docker', label: 'Docker' }, { value: 'vm', label: 'Virtual machine' }];
</script>

<Field label="Name">
  <TextInput bind:value={name} placeholder="e.g. jellyfin" autocomplete="off" spellcheck={false} />
</Field>
<Field label="Kind">
  <Segmented bind:value={type} label="Kind" options={kinds} />
</Field>
{#if type === 'vm'}<Muted as="div">A virtual machine reserves its memory and disk. Without sizes it gets 2048 MiB, 2 cores and 20 GiB.</Muted>{/if}
