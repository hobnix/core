<script>
  // A share of this server (and later of other servers), picked from a searchable list instead of typed. Reads `shares overview` through the live state
  // (no timer of its own). The submitted value is the share name, unchanged.
  //   <ShareField bind:value={share} kind="shares" />                                   value: 'media'
  //   <ShareField bind:value={pick} groups={['local', 'remote']} />                     value: { scope: 'local'|'remote', peer, share }
  //   <ShareField bind:value={name} free />                                              a name that is not on the server yet may be typed
  // props: value (bindable), groups (['local'] default; with 'remote' the value is the object above, two servers can hold the same share name),
  //   kind ('shares' | 'sensitive' | a list), exclude (names), remote ([{ peer, share, state }]: the remote group is a STUB until issue 1149 decides how remote
  //   shares are named and read; the field says "server", never "peer", to the user), free, wide, label, id, placeholder, disabled, onchange,
  //   more (names that are not shares of the server but may be picked, e.g. deleted ones that a backup still holds), data / loaded / error (rows instead of the live read: the Gallery and tests)
  import ServerField from './ServerField.svelte';
  import { poll, rows } from '../data.svelte.js';
  import { P } from '../paths.js';
  import { shareOptions, shareGroups, encodeShare, decodeShare, LOCAL, REMOTE } from './serverfields.js';

  let { value = $bindable(''), groups = [LOCAL], kind = undefined, exclude = undefined, remote = [], more = [], free = false, wide = true, label = '', id = undefined,
        placeholder = 'Choose a share', disabled = false, onchange = null, data = undefined, loaded = undefined, error = undefined } = $props();

  const st = poll(() => (data ? '' : '/api/sys/shares/overview'), 60000, 'shares-overview');
  const withRemote = $derived(groups.includes(REMOTE));
  const base = $derived(shareOptions(data ?? rows(st), { kind, exclude }));
  const local = $derived([...base, ...more.filter((n) => !base.some((o) => o.value === n)).map((n) => ({ value: n, label: n, detail: 'only in the backup' }))]);
  const options = $derived(shareGroups(local, remote, groups));

  // the Combobox holds one string; with the remote group the field's value is the { scope, peer, share } object
  const picked = $derived(withRemote ? encodeShare(value) : value);
  function change(v) {
    value = withRemote ? decodeShare(v) : v;
    onchange?.(value);
  }
</script>

<ServerField {options} loaded={loaded ?? (data ? true : st.loaded)} error={error ?? (data ? '' : st.error)} noun="shares" createHref={P.shares} createLabel="Create a share"
             {free} {wide} {label} {id} {placeholder} {disabled} onchange={change} value={picked} />
