<script>
  import { Field, Select, Row, Muted, Chip } from '../../ui/index.js';
  import Button from '../../ui/Button.svelte';
  import { tip } from '../../ui/tooltip.svelte.js';
  // Move a folder (or file) from one SnapRAID data disk to another, disk to disk (hs sys disk plan|start <member> move --path <path> [--to <member>]).
  // The path in /<pool> does not change: the same files are shown at the same paths before, during and after. The disk's own folders are browsed with
  // `hs sys disk ls` (one level at a time); nothing here ever touches /<pool> itself, which is what makes it safe (a copy from a disk into the pool destroys the files).
  import CreateDialog from '../../shell/CreateDialog.svelte';
  import { poolOfRole } from '../../pools.svelte.js';
  import { poll, rows } from '../../data.svelte.js';

  let { pool = poolOfRole('data'), member, targets = [] } = $props();

  let dir = $state('');        // the folder being looked at, relative to the disk ('' = the top)
  let picked = $state('');     // the folder or file chosen to move
  let to = $state('');

  const list = poll(() => `/api/sys/disk/ls/${member}${dir ? `?path=${encodeURIComponent(dir)}` : ''}`, 10000);
  // type d|f, bytes, name
  const entries = $derived(rows(list).map((r) => ({ dirp: r[0] === 'd', bytes: r[1], name: r[2] })));
  const crumbs = $derived(dir ? dir.split('/') : []);
  const others = $derived(targets.filter((n) => n !== member));
  const sizeTxt = (b) => (b === '' ? '' : b > 1e9 ? `${(b / 1e9).toFixed(1)} GB` : b > 1e6 ? `${(b / 1e6).toFixed(1)} MB` : `${Math.ceil(b / 1e3)} kB`);
  const enter = (name) => { dir = dir ? `${dir}/${name}` : name; };
  const up = (n) => { dir = crumbs.slice(0, n).join('/'); };
  const pick = (name) => { picked = dir ? `${dir}/${name}` : name; };
  const args = () => (picked.includes('/') ? [member, 'move', '--path', picked, ...(to ? ['--to', to] : [])] : null);
</script>

<CreateDialog title="Move a folder to another disk" kicker="Pool" area="disk" {args}>
  {#snippet form()}
    <Field label="From data disk" id="mf-from"><Row gap="2" id="mf-from"><code>{member}</code><Chip>{pool}</Chip></Row></Field>
    <Field label="Folder or file" id="mf-pick">
      <div class="crumbs">
        <button type="button" class="lnk" onclick={() => up(0)}>{member}</button>
        {#each crumbs as c, i}<span>/</span><button type="button" class="lnk" onclick={() => up(i + 1)}>{c}</button>{/each}
      </div>
      <ul class="files" aria-label="Contents of the folder">
        {#each entries as e}
          <li class:sel={picked === (dir ? `${dir}/${e.name}` : e.name)}>
            {#if e.dirp}
              <button type="button" class="lnk name" onclick={() => enter(e.name)} use:tip={'Open this folder'}><i class="ph ph-folder"></i> {e.name}</button>
            {:else}
              <span class="name"><i class="ph ph-file"></i> {e.name}</span>
            {/if}
            <span class="sz">{sizeTxt(e.bytes)}</span>
            {#if dir}<Button variant="ghost" class="movefolder-pick" type="button" onclick={() => pick(e.name)}>Choose</Button>{/if}
          </li>
        {:else}
          <li class="sub">{list.loaded ? 'Nothing here.' : 'Loading…'}</li>
        {/each}
      </ul>
      {#if picked}<Muted as="div">Chosen: <code>{picked}</code></Muted>{:else}<Muted as="div">Open shares or sensitive, then choose the folder or file to move.</Muted>{/if}
    </Field>
    <Field label="To data disk">
      <Select bind:value={to}><option value="">The open disk with the most free space</option>{#each others as t}<option value={t}>{t}</option>{/each}</Select>
    </Field>
    <Muted as="p">Disk to disk: /{pool} shows the same files at the same paths the whole time. A file that the target already has is never overwritten. To put the files in another folder or share, rename them inside /{pool} afterwards.</Muted>
  {/snippet}
</CreateDialog>

<style>
  .crumbs { display: flex; flex-wrap: wrap; gap: 4px; align-items: center; font-size: 12.5px; margin-bottom: 6px; }
  .lnk { background: none; border: 0; padding: 0; color: var(--color-accent, inherit); cursor: pointer; font: inherit; text-align: left; }
  .files { list-style: none; margin: 0; padding: 0; max-height: 220px; overflow: auto; border: 1px solid var(--color-border, rgba(128,128,128,.3)); border-radius: var(--r); }
  .files li { display: flex; align-items: center; gap: 8px; padding: 5px 10px; font-size: 12.5px; }
  .files li.sel { background: color-mix(in srgb, var(--color-accent, #9184d9) 18%, transparent); }
  .name { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .sz { color: var(--color-neutral-500); font-size: 11.5px; }
  :global(.btn.movefolder-pick) { padding: 1px 8px; font-size: 12px; }
</style>
