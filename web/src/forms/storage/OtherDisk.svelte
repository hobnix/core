<script>
  import { Field, TextInput, Select, Segmented, Muted, ShareField } from '../../ui/index.js';
  // Another disk (USB, hot-plug) with data on it: `hs sys disk plan|start <partition> temp-mount [--name <n>]` mounts it read-only and shares it
  // (only Domain Admins at first), `<name> temp-copy --to <share>` copies everything on it into a share (a background job), `<name> temp-eject`
  // removes the share and unmounts. The disk itself is never formatted or written. The list is `hs sys temp-disk raw`:
  // device|fs|label|bytes|mountpoints per partition (system, pool, swap and backup disks are never offered).
  import CreateDialog from '../../shell/CreateDialog.svelte';
  import { poll, rows } from '../../data.svelte.js';
  import { sizeTxt } from '../../pages/storage/pool.js';

  let { onclose, ondone = () => {} } = $props();

  const raw = poll('/api/sys/temp-disk/raw', 10000, 'temp-disks');

  const TEMP = /^\/mnt\/temp\/([a-z0-9][a-z0-9-]{0,31})$/;
  // the list has one cell per row (fields joined by |)
  const parts = $derived(rows(raw).map((r) => r.join('\t').split('|')).filter((p) => p.length >= 5).map((p) => {
    const mp = p[4].split(',').map((m) => TEMP.exec(m)).find(Boolean);
    return { dev: p[0].replace(/^\/dev\//, ''), fs: p[1], label: p[2], bytes: Number(p[3]), mounted: !!p[4], temp: mp ? mp[1] : '' };
  }));

  let dev = $state('');
  let action = $state('mount');
  let name = $state('');
  let to = $state('');
  const sel = $derived(parts.find((p) => p.dev === dev) ?? parts[0]);
  // a free partition can only be mounted; a mounted one is copied or ejected (one that is mounted elsewhere is left alone)
  const act = $derived(!sel ? '' : !sel.mounted ? 'mount' : sel.temp ? (action === 'copy' ? 'copy' : 'eject') : '');
  const nameOk = $derived(name === '' || /^[a-z0-9][a-z0-9-]{0,31}$/.test(name));
  const args = () => {
    if (!sel || !act) return null;
    if (act === 'mount') return nameOk ? [sel.dev, 'temp-mount', ...(name ? ['--name', name] : [])] : null;
    if (act === 'eject') return [sel.temp, 'temp-eject'];
    return to ? [sel.temp, 'temp-copy', '--to', to] : null;
  };
  const label = (p) => `${p.dev} · ${p.fs}${p.label ? ` “${p.label}”` : ''} · ${sizeTxt(p.bytes)}${p.mounted ? (p.temp ? ' · mounted here' : ' · mounted elsewhere') : ''}`;
</script>

<CreateDialog title="Other disk" kicker="Disk" area="disk" {args} {onclose} {ondone}>
  {#snippet form()}
    {#if parts.length}
      <Field label="Disk">
        <Select value={sel?.dev} options={parts.map((p) => ({ value: p.dev, label: label(p) }))} onchange={(e) => { dev = e.currentTarget.value; action = 'copy'; }} />
      </Field>
    {:else}
      <Field label="Disk" id="od-none"><Muted as="div" id="od-none">{raw.loaded ? (raw.error ? 'The disks could not be read.' : 'No other disk found: plug it in, this list updates by itself.') : 'Loading…'}</Muted></Field>
    {/if}
    {#if sel && !sel.mounted}
      <Field label="Name of the share (optional)" error={nameOk ? '' : 'Lower-case letters, digits and hyphens.'}>
        <TextInput bind:value={name} placeholder={sel.label || sel.dev} autocomplete="off" spellcheck={false} />
      </Field>
      <Muted as="p">Mounted read-only and shared as <code>temp-name</code> for Domain Admins. Nothing on the disk is changed.</Muted>
    {:else if sel?.temp}
      <Field label="What to do">
        <Segmented value={act} label="Action" options={[{ value: 'copy', label: 'Copy into a share' }, { value: 'eject', label: 'Eject' }]} onchange={(v) => (action = v)} />
      </Field>
      {#if act === 'copy'}
        <Field label="Copy everything into the share" help="Runs as a background job; it checks first that there is room.">
          <ShareField bind:value={to} />
        </Field>
      {:else}
        <Muted as="p">The share is removed and the disk unmounted. Afterwards it is safe to unplug.</Muted>
      {/if}
    {:else if sel}
      <Muted as="p">This partition is mounted somewhere this page does not manage.</Muted>
    {/if}
  {/snippet}
</CreateDialog>
