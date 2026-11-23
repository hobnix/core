<script>
  // The card of one package page that declares a `state` ({ read, dot, line }): one dot and one line from the first row of its declared read,
  // a link to the page. Used by ExtCards on the Group page and the Apps list.
  import StateCard from '../ui/StateCard.svelte';
  import { poll, rows } from '../data.svelte.js';
  import { extReadPath, stateOfRow } from '../shell/generic.js';
  import { extensionPath } from '../paths.js';

  let { ext } = $props();
  const st = poll(extReadPath(ext.name, ext.state.read), 15000);
  const now = $derived(st.data ? stateOfRow(ext.state, rows(st)[0]) : { state: 'off', line: st.error ? 'Not available' : '' });
</script>

<StateCard title={ext.title} state={now.state} line={now.line} href={extensionPath(ext.name)} />
