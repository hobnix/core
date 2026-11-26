<script>
  // A pool of this server, picked from a searchable list. Reads the pool store (`pool list`, loaded once per page, kept by pools.svelte.js). The submitted
  // value is the pool name, unchanged.
  //   <PoolField bind:value={pool} role="data" />
  // props: value (bindable), role ('data' | 'apps'), kind ('zfs' | 'snapraid'), free, wide, label, id, placeholder, disabled, onchange,
  //   data / loaded / error (parsed pool rows instead of the store: the Gallery and tests)
  import { onMount } from 'svelte';
  import ServerField from './ServerField.svelte';
  import { pools, loadPools } from '../pools.svelte.js';
  import { P } from '../paths.js';
  import { poolOptions } from './serverfields.js';

  let { value = $bindable(''), role = '', kind = '', free = false, wide = true, label = '', id = undefined, placeholder = 'Choose a pool', disabled = false,
        onchange = null, data = undefined, loaded = undefined, error = undefined } = $props();

  onMount(() => { if (!data) loadPools(); });
  const options = $derived(poolOptions(data ?? pools.rows, { role, kind }));
</script>

<ServerField {options} loaded={loaded ?? (data ? true : pools.loaded)} {error} noun="pools" createHref={P.pools} createLabel="Open the pools" {free} {wide} {label} {id} {placeholder}
             {disabled} {onchange} bind:value />
