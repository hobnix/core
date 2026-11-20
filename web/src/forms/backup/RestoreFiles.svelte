<script>
  // Restore files from the backup: `hs sys shares plan|start <share> restore --snapshot <id|latest> [--path <inside>]` (scripts/share-change.sh,
  // which runs `hs backup restore`). The files land in the share `restored` below their full original path; the original is never touched and
  // nothing but the restored subtree changes owner. A share that was deleted can still be typed in: that is what a restore is for.
  import CreateDialog from '../../shell/CreateDialog.svelte';
  import { poll, rows } from '../../data.svelte.js';
  import { Field, TextInput, Select, Muted } from '../../ui';

  let { share: first = '', onclose, ondone = () => {} } = $props();

  const ov = poll('/api/sys/backup/overview', 60000);
  const snaps = poll('/api/sys/backup/snapshots?tag=shares', 60000);
  // kind, name, on|off, bytes
  const names = $derived(rows(ov).filter((r) => r[0] === 'shares' || r[0] === 'sensitive').map((r) => r[1]));
  // id, time, tags; newest first
  const list = $derived(rows(snaps).map((r) => ({ id: r[0], time: r[1] })).reverse());

  let share = $state(first);
  let snapshot = $state('latest');
  let path = $state('');
  const shareOk = $derived(/^[a-z0-9][a-z0-9-]{0,40}$/.test(share));
  const pathOk = $derived(path === '' || (/^\/?[A-Za-z0-9_][A-Za-z0-9._\/ -]*$/.test(path) && !path.includes('..')));
  const args = () => {
    if (!shareOk || !pathOk || !/^(latest|[A-Za-z0-9]{1,64})$/.test(snapshot)) return null;
    const a = [share, 'restore', '--snapshot', snapshot];
    if (path) a.push('--path', path);
    return a;
  };
</script>

<CreateDialog title="Restore files from the backup" kicker="Restore" area="shares" {args} {onclose} {ondone}>
  {#snippet form()}
    <Field label="Share" error={share && !shareOk ? 'A share name: lower-case letters, digits and hyphens.' : ''}>
      <TextInput bind:value={share} list="rf-shares" placeholder="photos" autocomplete="off" spellcheck={false} />
      <datalist id="rf-shares">{#each names as n}<option value={n}></option>{/each}</datalist>
    </Field>
    <Field label="Restore point">
      <Select bind:value={snapshot}>
        <option value="latest">latest</option>
        {#each list as s}<option value={s.id}>{s.id} · {s.time}</option>{/each}
      </Select>
    </Field>
    <Field label="Folder or file inside the share (optional)" error={!pathOk ? 'A path inside the share, without “..”.' : ''}>
      <TextInput bind:value={path} placeholder="whole share" autocomplete="off" spellcheck={false} />
    </Field>
    <Muted as="p">The files are restored into the share <code>restored</code> (created when it does not exist), below their full original path. The original is not touched: copy back what you need.</Muted>
  {/snippet}
</CreateDialog>
