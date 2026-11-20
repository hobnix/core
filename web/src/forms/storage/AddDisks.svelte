<script>
  import { Field, TextInput, Select, Checkbox, Segmented, Row } from '../../ui/index.js';
  // Add disks (design: "Create dialog" > "Add disks", three variants):
  //   ZFS pool        : exactly 2 free disks become a new mirror vdev (red, the pool name is typed to confirm)
  //   SnapRAID pool   : "Add empty disks" (role, filesystem, optional LUKS) or "Adopt disks" (one disk that already holds files)
  // The server's plan (hs sys pool plan <pool> add|adopt ...) decides what is allowed and what must be typed; this form only collects the choices.
  import CreateDialog from '../../shell/CreateDialog.svelte';
  import DiskPicker from './DiskPicker.svelte';
  import { poll, rows } from '../../data.svelte.js';
  import { parseInfo, poolTopic } from '../../pages/storage/pool.js';
  import { live } from '../../live.svelte.js';
  import { pools, poolNames, poolOfRole, poolRow } from '../../pools.svelte.js';
  import { freeDisks, FS } from './disks.js';

  let { pool: pool0 = '', variant: variant0 = 'empty', snap: snap0 = undefined } = $props();

  let pool = $state(pool0 || poolOfRole('data') || poolNames()[0] || '');
  let variant = $state(variant0);        // 'empty' | 'adopt' (only SnapRAID)
  let picked = $state([]);
  let role = $state('data');
  let fs = $state('ext4');
  let encrypt = $state(false);
  let pass = $state('');
  let merge = $state(false);
  let chown = $state(false);

  const info = poll(() => `/api/sys/pool/info?pool=${pool}`, 60000, () => poolTopic('info', pool, live.topics));
  // the adopt listing also names encrypted disks (hs sys pool disks --role adopt), the plain one does not
  const free = poll(() => (variant === 'adopt' ? '/api/sys/pool/disks?role=adopt' : '/api/sys/pool/disks'), 15000);

  // does this pool use SnapRAID? the page that opened the form knows (snap0); a pool picked here is read
  const layout = $derived(parseInfo(rows(info)).facts.layout ?? '');
  const snap = $derived(poolRow(pool)?.kind !== 'zfs' && (/SnapRAID/i.test(layout) || (!info.loaded && snap0 === true)));
  const disks = $derived(freeDisks(rows(free)));
  const adopting = $derived(snap && variant === 'adopt');
  const list = $derived(adopting ? disks.filter((d) => d.hasFiles || d.notes.some((n) => /encrypted/.test(n))) : disks);

  function setPool(p) { pool = p; picked = []; if (poolRow(p)?.kind === 'zfs') variant = 'empty'; }
  function setVariant(v) { variant = v; picked = []; }

  const args = () => {
    if (!picked.length || !info.loaded) return null;
    if (adopting) return [pool, 'adopt', '--disks', picked[0], ...(merge ? ['--merge'] : []), ...(chown ? ['--chown'] : [])];
    if (!snap) return picked.length === 2 ? [pool, 'add', '--disks', picked.join(',')] : null;
    if (encrypt && !pass) return null;
    return [pool, 'add', '--disks', picked.join(','), '--role', role, '--fs', fs, ...(encrypt ? ['--encrypt'] : [])];
  };
  const stdin = () => (snap && !adopting && encrypt && pass ? pass : undefined);
  const title = $derived(adopting ? 'Adopt disks' : snap ? 'Add disks' : 'Add mirror pair');
</script>

<CreateDialog {title} kicker="Pool" area="pool" {args} {stdin}>
  {#snippet form()}
    <Field label="Pool" id="ad-pool">
      <Segmented label="Pool" value={pool} options={pools.rows.map((r) => r.name)} onchange={setPool} />
    </Field>

    {#if snap}
      <Field label="What to add" id="ad-var">
        <Segmented label="What to add" value={variant} options={[{ value: 'empty', label: 'Add empty disks' }, { value: 'adopt', label: 'Adopt disks' }]} onchange={setVariant} />
      </Field>
    {/if}

    <Field id="ad-disks" label={adopting ? 'A disk with files on it (it stays as it is, its files are brought into the pool)' : snap ? 'Free disks (they are erased)' : 'Two free disks for the new mirror (they are erased)'}
           help={!snap && !adopting ? `${picked.length} of 2 picked${picked.length > 2 ? ': pick exactly two' : ''}` : ''}>
      <div id="ad-disks">
        <DiskPicker disks={list} loaded={free.loaded} bind:picked single={adopting} empty={adopting ? 'No disk with files on it.' : 'No free disks.'} />
      </div>
    </Field>

    {#if adopting}
      <Checkbox bind:checked={merge} label="Merge its folders into the existing shares" />
      <Checkbox bind:checked={chown} label="Give the files to the file owner of the shares (chown)" />
    {:else if snap}
      <Row gap="3" align="start">
        <div style="flex:1"><Field label="Role"><Select bind:value={role} options={['data', 'parity']} /></Field></div>
        <div style="flex:1.6"><Field label="Filesystem"><Select bind:value={fs} options={FS.map(([value, label]) => ({ value, label }))} /></Field></div>
      </Row>
      <Checkbox bind:checked={encrypt} label="Encrypt with LUKS" />
      {#if encrypt}
        <Field label="Passphrase (the one for all encrypted disks of this server; the first time it sets it)" help="It is sent to the server on its own and never appears in the command.">
          <TextInput type="password" bind:value={pass} autocomplete="new-password" spellcheck={false} />
        </Field>
      {/if}
    {/if}
  {/snippet}
</CreateDialog>
