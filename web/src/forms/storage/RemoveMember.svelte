<script>
  import { Field, Segmented, Banner, Button, Stack, Row, Muted, Chip } from '../../ui/index.js';
  // Remove a member (SnapRAID: a single disk) or detach one from a ZFS mirror (hs sys pool plan|start <pool> remove --member <name> [--mode detach|vdev|move|nomove]).
  // The plan is red and the server names the word to type (the disk).
  import CreateDialog from '../../shell/CreateDialog.svelte';
  import ReplaceMember from './ReplaceMember.svelte';
  import { poll, rows } from '../../data.svelte.js';
  import { poolTopic } from '../../pages/storage/pool.js';
  import { live } from '../../live.svelte.js';
  import { openCreate } from '../../ui.svelte.js';

  let { pool, member, snap = false } = $props();

  // Remove only works on a disk the server can read now (it moves its files, or leaves them on the disk). A disk that is MISSING or not mounted
  // cannot be removed: replacing it restores its files from the parity. Say so here instead of letting the plan refuse after a choice.
  const mem = poll(() => `/api/sys/pool/members?pool=${pool}`, 30000, () => poolTopic('members', pool, live.topics));
  // members: name, bytes, state (ONLINE|UNMOUNTED|MISSING ...), group, ...
  const state = $derived(rows(mem).find((r) => r[0] === member)?.[2] ?? '');
  const gone = $derived(snap && mem.loaded && state !== '' && state !== 'ONLINE');

  const snapData = $derived(snap && !member.startsWith('parity'));
  let mode = $state(snap ? 'move' : 'detach');

  const args = () => (gone ? null : [pool, 'remove', '--member', member, ...(snap && !snapData ? [] : ['--mode', mode])]);
</script>

<CreateDialog title={snap ? 'Remove a disk' : 'Detach a disk'} kicker="Pool" area="pool" {args}>
  {#snippet form()}
    <Field label="Member" id="rm-member"><Row gap="2" id="rm-member"><code>{member}</code><Chip>{pool}</Chip></Row></Field>
    {#if gone}
      <Banner tone="warn">
        <Stack gap="2">
          <div><strong>{member} is {state}.</strong> {state === 'MISSING' ? 'The server cannot see the disk at all.' : 'The disk is there but not mounted.'}</div>
          <div>A disk cannot be removed while the server cannot read it: its files would be dropped from the array although the parity still holds them.
            <strong>Replace it</strong> with a new disk instead: its files are rebuilt from the parity (hours).</div>
          <Muted as="div">Before you replace it, look for a simple cause: the cable, the port and the power; an encrypted disk that is still locked (<code>hs unlock</code>);
            <code>hs disk list</code> and <code>lsblk -o NAME,LABEL,SIZE</code> show whether the disk is there at all. Replacing needs the parity to be in good order and no more
            disks missing than there are parity disks.</Muted>
        </Stack>
        {#snippet action()}<Button variant="primary" tooltip={'Replace the disk instead of removing it'} onclick={() => openCreate(ReplaceMember, { pool, member, snap })}><i class="ph ph-swap"></i>Replace {member}…</Button>{/snippet}
      </Banner>
    {:else if !snap}
      <Field label="What happens to the mirror" help={mode === 'detach' ? 'The other disk of the mirror stays alone; nothing moves.' : 'The data moves to the other mirrors first; both disks leave the pool.'}>
        <Segmented bind:value={mode} label="Mode" options={[{ value: 'detach', label: 'Detach this disk' }, { value: 'vdev', label: 'Remove the whole mirror' }]} />
      </Field>
    {:else if snapData}
      <Field label="What happens to the files on this disk" help={mode === 'move' ? 'The files move to the other disks first. That can take hours; it runs as a background job.' : `Nothing moves. Files still on the disk are no longer in /${pool} (the disk is not erased); use this for a disk you emptied already.`}>
        <Segmented bind:value={mode} label="Mode" options={[{ value: 'move', label: 'Move them to the other disks' }, { value: 'nomove', label: 'Leave them on the disk' }]} />
      </Field>
    {:else}
      <Muted as="p">The parity disk is unlabelled and leaves the array; nothing is erased.</Muted>
    {/if}
  {/snippet}
</CreateDialog>
