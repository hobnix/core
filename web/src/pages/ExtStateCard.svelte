<script>
  // The card of one package page that declares a `state` ({ read, dot, line }): one dot and one line from the first row of its declared read,
  // a link to the page. Used by ExtCards on the Group page and the Apps list.
  import StateCard from '../ui/StateCard.svelte';
  import { poll, rows } from '../data.svelte.js';
  import { extReadPath, stateOfRow } from '../shell/generic.js';
  import { extensionPath } from '../paths.js';
  import { live } from '../live.svelte.js';

  let { ext } = $props();
  const path = extReadPath(ext.name, ext.state.read);
  // follows the read's live topic when the package declares `live` on it (the session's topic map); a timer only while there is none or the stream is down
  const st = poll(path, 15000, () => live.topics[path]);
  const now = $derived(st.data ? stateOfRow(ext.state, rows(st)[0]) : { state: 'off', line: st.error ? 'Not available' : '' });
</script>

<StateCard title={ext.title} state={now.state} line={now.line} href={extensionPath(ext.name)} />
