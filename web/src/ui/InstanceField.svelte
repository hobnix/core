<script>
  // An instance (container or VM) of this server, picked from a searchable list with its state. Reads `ct list` through the live state, no timer of its
  // own. The submitted value is the instance name, unchanged.
  //   <InstanceField bind:value={ct} running />
  // props: value (bindable), running (only running ones), type ('ct' | 'vm'), exclude (names), free, wide, label, id, placeholder, disabled, onchange,
  //   data / loaded / error (rows instead of the live read: the Gallery and tests)
  import ServerField from './ServerField.svelte';
  import { poll, rows } from '../data.svelte.js';
  import { P } from '../paths.js';
  import { instanceOptions } from './serverfields.js';

  let { value = $bindable(''), running = false, type = '', exclude = undefined, free = false, wide = true, label = '', id = undefined, placeholder = 'Choose an instance',
        disabled = false, onchange = null, data = undefined, loaded = undefined, error = undefined } = $props();

  const st = poll(() => (data ? '' : '/api/sys/ct/list'), 15000);
  const options = $derived(instanceOptions(data ?? rows(st), { running, type, exclude }));
</script>

<ServerField {options} loaded={loaded ?? (data ? true : st.loaded)} error={error ?? (data ? '' : st.error)} noun={running ? 'running instances' : 'instances'} createHref={P.appsGroup}
             createLabel="Open the instances" {free} {wide} {label} {id} {placeholder} {disabled} {onchange} bind:value />
