<script>
  // Give a user or group access: `hs sys shares plan|start <share> perm --set <sid>=<level>`; the principals come from /api/sys/shares/principals.
  import CreateDialog from '../../shell/CreateDialog.svelte';
  import { poll, rows } from '../../data.svelte.js';
  import { Field, Select, Segmented, Muted } from '../../ui';

  // taken: the SIDs that already have an entry
  let { share, taken = [], onclose, ondone = () => {} } = $props();

  const pr = poll('/api/sys/shares/principals', 60000, 'shares-principals');
  // sid, name, user|group
  const people = $derived(rows(pr).map((r) => ({ sid: r[0], name: r[1], type: r[2] })).filter((p) => !taken.includes(p.sid)));

  let sid = $state('');
  let level = $state('read');
  const args = () => (/^S-1-[0-9]+(-[0-9]+)+$/.test(sid) ? [share, 'perm', '--set', `${sid}=${level}`] : null);
</script>

<CreateDialog title="Add access to {share}" kicker="Permissions" area="shares" {args} {onclose} {ondone}>
  {#snippet form()}
    <Field label="User or group" help={pr.loaded && !people.length ? (pr.error ? 'The users could not be read.' : 'Everyone already has an entry.') : ''}>
      <Select bind:value={sid}>
        <option value="">{pr.loaded ? 'Choose…' : 'Loading…'}</option>
        {#each people as p}<option value={p.sid}>{p.name} ({p.type})</option>{/each}
      </Select>
    </Field>
    <Field label="Access" id="aa-level">
      <Segmented bind:value={level} label="Access" options={['none', 'read', 'write', 'full']} />
    </Field>
    <Muted as="p">Permissions apply at the next connection.</Muted>
  {/snippet}
</CreateDialog>
