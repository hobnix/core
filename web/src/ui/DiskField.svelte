<script>
  // A disk of this server, picked from a searchable list. By default the free disks (`pool disks`, by-id names: what the pool forms take); `scope="all"`
  // lists every disk (`monitor disks`, with its role). `multiple` shows the checkbox list of forms/storage/DiskPicker.svelte (`picked` = list of names)
  // instead of a dropdown. Read through the live state, no timer of its own. The submitted value is the disk name, unchanged.
  //   <DiskField bind:value={disk} />            <DiskField multiple bind:picked={ids} />            <DiskField scope="all" exclude={['sda']} />
  // props: value (bindable), picked (bindable, `multiple`), scope ('free' | 'all'), exclude (names), free, wide, label, id, placeholder, disabled, onchange,
  //   data / loaded / error (rows instead of the live read: the Gallery and tests)
  import ServerField from './ServerField.svelte';
  import DiskPicker from '../forms/storage/DiskPicker.svelte';
  import { poll, rows } from '../data.svelte.js';
  import { P } from '../paths.js';
  import { diskOptions } from './serverfields.js';
  import { freeDisks } from '../forms/storage/disks.js';

  let { value = $bindable(''), picked = $bindable([]), multiple = false, scope = 'free', exclude = undefined, free = false, wide = true, label = '', id = undefined,
        placeholder = 'Choose a disk', disabled = false, onchange = null, data = undefined, loaded = undefined, error = undefined } = $props();

  const st = poll(() => (data ? '' : scope === 'all' ? '/api/sys/monitor/disks' : '/api/sys/pool/disks'), 15000, () => (scope === 'all' ? 'monitor-disks' : 'pool-disks'));
  const list = $derived(data ?? rows(st));
  const options = $derived(diskOptions(list, { scope, exclude }));
  const isLoaded = $derived(loaded ?? (data ? true : st.loaded));
  const failed = $derived(error ?? (data ? '' : st.error));
  const pickable = $derived(freeDisks(list).filter((d) => !(Array.isArray(exclude) ? exclude : [exclude]).includes(d.id)));
</script>

{#if multiple}
  <DiskPicker disks={pickable} loaded={isLoaded} bind:picked />
{:else}
  <ServerField {options} loaded={isLoaded} error={failed} noun="disks" createHref={P.disks} createLabel="Open the disks" {free} {wide} {label} {id} {placeholder} {disabled} {onchange} bind:value />
{/if}
