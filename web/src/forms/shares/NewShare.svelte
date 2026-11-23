<script>
  // New share: `hs sys shares plan|start <name> add --kind shares|sensitive --pool <pool> [--ct <instance> --path <inside> [--as <uid>:<gid>]]`.
  // The command has no switches for backup, cache or snapshots at creation: those are separate changes on the share afterwards.
  import CreateDialog from '../../shell/CreateDialog.svelte';
  import { Field, TextInput, Checkbox, Banner, Segmented, Row, InstanceField } from '../../ui';
  import { onMount } from 'svelte';
  import { pools, loadPools, poolsOfRole, poolOfRole, poolRow } from '../../pools.svelte.js';

  let { onclose, ondone = () => {} } = $props();


  let name = $state('');
  let kind = $state('shares');
  onMount(() => { loadPools(); });
  const choices = $derived([...poolsOfRole('data'), ...poolsOfRole('apps')]);
  let chosen = $state('');
  const pool = $derived(chosen || poolOfRole('data'));
  const isApps = $derived(poolRow(pool)?.role === 'apps');
  let bind = $state(false);
  let ct = $state('');
  let path = $state('');
  let mapUser = $state(false);
  let asUid = $state('1000');
  let asGid = $state('1000');

  const nameOk = $derived(/^[a-z0-9][a-z0-9-]{0,40}$/.test(name));
  const args = () => {
    if (!nameOk || !pool) return null;
    const a = [name, 'add', '--kind', kind, '--pool', pool];
    if (bind) {
      if (!ct) return null;
      a.push('--ct', ct);
      if (path) a.push('--path', path);
      else return null;
      if (mapUser && /^[0-9]{1,7}$/.test(asUid) && /^[0-9]{1,7}$/.test(asGid)) a.push('--as', `${asUid}:${asGid}`);
    }
    return a;
  };
</script>

<CreateDialog title="New share" area="shares" {args} {onclose} {ondone}>
  {#snippet form()}
    <Field label="Name" error={name && !nameOk ? 'Lowercase letters, digits and “-”, starting with a letter or digit.' : ''}>
      <TextInput bind:value={name} placeholder="photos" autocomplete="off" spellcheck={false} />
    </Field>

    <Field label="Kind" id="ns-kind" help={kind === 'sensitive' ? 'Container-owned data: read-only for the Samba users.' : 'Read and write; everyone acts as adminuser. Only Domain Admins may use it until you set permissions.'}>
      <Segmented bind:value={kind} label="Kind" options={[{ value: 'shares', label: 'Shared folder', icon: 'folder' }, { value: 'sensitive', label: 'Sensitive', icon: 'folder-lock' }]} />
    </Field>

    {#if pools.loaded && !choices.length}
      <Banner tone="info">Shares wait for a pool: this server has none yet. Add one on Storage > Pools first.</Banner>
    {:else}
      <Field label="Where" id="ns-tier" help={isApps ? 'Fast and small: for app data and files used often.' : 'The big pool of disks: for media, photos and backups.'}>
        <Segmented value={pool} label="Where" options={choices.map((c) => ({ value: c, label: c, icon: poolRow(c)?.role === 'apps' ? 'lightning' : 'hard-drives' }))} onchange={(v) => (chosen = v)} />
      </Field>
    {/if}

    <div class="field">
      <Checkbox bind:checked={bind} label="Mount it into an instance" />
    </div>

    {#if bind}
      <Field label="Instance">
        <InstanceField bind:value={ct} />
      </Field>
      <Field label="Path inside the instance">
        <TextInput bind:value={path} placeholder="/mnt/photos" autocomplete="off" spellcheck={false} />
      </Field>
      <div class="field">
        <Checkbox bind:checked={mapUser} label="Write as an app user (uid:gid)" hint={mapUser ? 'One such user per instance; the instance restarts when the mapping changes.' : ''} />
        {#if mapUser}
          <Row gap="2" style="margin-top:8px;max-width:220px">
            <TextInput bind:value={asUid} ariaLabel="uid" inputmode="numeric" />
            <span>:</span>
            <TextInput bind:value={asGid} ariaLabel="gid" inputmode="numeric" />
          </Row>
        {/if}
      </div>
    {/if}
  {/snippet}
</CreateDialog>
