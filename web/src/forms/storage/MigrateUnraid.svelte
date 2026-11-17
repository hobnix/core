<script>
  // Take over an Unraid server (hs sys migrate plan|start unraid ...): the disks that hold the files, the old Unraid parity disk(s), an optional spare disk.
  // The server's plan decides what is allowed and which word is typed (the first disk that is erased); this form only collects the choices.
  // Passphrases of encrypted Unraid disks go on standard input as ONE JSON line, never into the arguments.
  import CreateDialog from '../../shell/CreateDialog.svelte';
  import DiskPicker from './DiskPicker.svelte';
  import Checkbox from '../../ui/Checkbox.svelte';
  import TextInput from '../../ui/TextInput.svelte';
  import { get } from '../../api.js';
  import { poolOfRole } from '../../pools.svelte.js';
  import { freeDisks } from './disks.js';

  let { pool = poolOfRole('data') } = $props();

  let data = $state([]);
  let old = $state([]);
  let spare = $state([]);
  let merge = $state(true);
  let chown = $state(false);
  let unraidPass = $state('');
  let serverPass = $state('');

  // read once when the dialog opens (the disks are plugged in before): no timer
  let withFiles = $state({ loaded: false, rows: [] });
  let plain = $state({ loaded: false, rows: [] });
  const load = (path, set) => get(path, true).then((d) => set({ loaded: true, rows: d?.rows ?? [] })).catch(() => set({ loaded: true, rows: [] }));
  $effect(() => { load('/api/sys/pool/disks?role=adopt', (v) => { withFiles = v; }); load('/api/sys/pool/disks', (v) => { plain = v; }); });
  const dataDisks = $derived(freeDisks(withFiles.rows).filter((d) => d.hasFiles || d.notes.some((n) => /encrypted/.test(n))));
  const emptyDisks = $derived(freeDisks(plain.rows).filter((d) => !d.hasFiles && !d.notes.some((n) => /encrypted/.test(n)) && !data.includes(d.id)));
  const encrypted = $derived(dataDisks.some((d) => data.includes(d.id) && d.notes.some((n) => /encrypted/.test(n))));

  const args = () => {
    if (!data.length || (encrypted && !unraidPass)) return null;
    return ['unraid', '--disks', data.join(','), '--pool', pool,
      ...(old.length ? ['--parity', old.join(',')] : []), ...(spare.length ? ['--spare', spare[0]] : []),
      ...(merge ? [] : ['--per-disk']), ...(chown ? ['--chown'] : []), ...(encrypted ? ['--unlock'] : [])];
  };
  const stdin = () => (encrypted && unraidPass ? JSON.stringify({ unraid: unraidPass, server: serverPass }) : undefined);
</script>

<CreateDialog title="Take over an Unraid server" kicker="Pool" area="migrate" {args} {stdin}>
  {#snippet form()}
    <div class="field">
      <label for="mu-data">Disks that hold the files (they stay as they are)</label>
      <div id="mu-data"><DiskPicker disks={dataDisks} loaded={withFiles.loaded} bind:picked={data} empty="No disk with files on it. Plug the Unraid disks in." /></div>
    </div>
    <div class="field">
      <label for="mu-old">The old Unraid parity disk(s) (erased after the first parity is complete, then used as parity)</label>
      <div id="mu-old"><DiskPicker disks={emptyDisks} loaded={plain.loaded} bind:picked={old} empty="No disk without a file system." /></div>
    </div>
    <div class="field">
      <label for="mu-spare">A spare disk, at least as large as the largest data disk (optional: the parity is built on it first and nothing is written to the data disks until it is complete; it is erased)</label>
      <div id="mu-spare"><DiskPicker disks={emptyDisks.filter((d) => !old.includes(d.id))} loaded={plain.loaded} bind:picked={spare} single empty="No other empty disk." /></div>
      {#if !spare.length}<div class="hint" style="font-size:11.5px">Without a spare disk the labels are written and folders move first; the data is not protected until the old parity disk is added and synced.</div>{/if}
    </div>
    <Checkbox bind:checked={merge} label="Merge folders of the same name into one share (like Unraid's user shares)" />
    <Checkbox bind:checked={chown} label="Give the files to the share owner (chown; slow on big disks)" />
    {#if encrypted}
      <div class="field">
        <label for="mu-pass">Passphrase of the encrypted Unraid disks</label>
        <TextInput id="mu-pass" type="password" bind:value={unraidPass} autocomplete="off" spellcheck={false} />
      </div>
      <div class="field">
        <label for="mu-spass">This server's disk passphrase (only when this server has encrypted disks already; it is added as a key slot)</label>
        <TextInput id="mu-spass" type="password" bind:value={serverPass} autocomplete="new-password" spellcheck={false} />
        <div class="hint" style="font-size:11.5px">Both are sent to the server on their own and never appear in the command. A disk that only a key file opens is refused.</div>
      </div>
    {/if}
  {/snippet}
</CreateDialog>

