<script>
  // A user of the domain, picked from a searchable list. Reads `users list` through the live state, no timer of its own. The submitted value is the user
  // name, unchanged. `principals` lists users AND groups the way the permission forms need them (`shares principals`): the value is then the SID.
  //   <UserField bind:value={user} enabled />            <UserField principals taken={sids} bind:value={sid} label="User or group" />
  // props: value (bindable), enabled (leave out locked accounts), principals, taken (SIDs to leave out, `principals` only), exclude (names), free, wide, label, id,
  //   placeholder, disabled, onchange, data / loaded / error (rows instead of the live read: the Gallery and tests)
  import ServerField from './ServerField.svelte';
  import { poll, rows } from '../data.svelte.js';
  import { P } from '../paths.js';
  import { userOptions, principalOptions } from './serverfields.js';

  let { value = $bindable(''), enabled = false, principals = false, taken = [], exclude = undefined, free = false, wide = true, label = '', id = undefined,
        placeholder = undefined, disabled = false, onchange = null, data = undefined, loaded = undefined, error = undefined } = $props();

  const st = poll(() => (data ? '' : principals ? '/api/sys/shares/principals' : '/api/sys/users/list'), 60000, () => (principals ? 'shares-principals' : undefined));
  const list = $derived(data ?? rows(st));
  const options = $derived(principals ? principalOptions(list, { taken }) : userOptions(list, { enabled, exclude }));
</script>

<ServerField {options} loaded={loaded ?? (data ? true : st.loaded)} error={error ?? (data ? '' : st.error)} noun={principals ? 'users and groups' : 'users'} createHref={P.users}
             createLabel="Open the users" {free} {wide} {label} {id} placeholder={placeholder ?? (principals ? 'Choose a user or group' : 'Choose a user')} {disabled} {onchange} bind:value />
