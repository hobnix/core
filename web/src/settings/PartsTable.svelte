<script>
  // The list of Settings > Capabilities and Settings > Extensions: the shared Table, one row per part with its state tag, what it is and its switch
  // (the plan dialog first, as before). No quick look (like Instances, Shares, Disks): the name and the button at the end of a row open the page of the part.
  import { go, url } from '../route.svelte.js';
  import Table from '../shell/Table.svelte';
  import PartTag from './PartTag.svelte';
  import { flip } from './parts.svelte.js';
  import { jobRunning } from '../ui.svelte.js';
  import { Card, Row, Muted } from '../ui/index.js';
  import Button from '../ui/Button.svelte';

  // items: the parts; pathOf(part): the address of its page, '' when it has none; id keeps the sort
  let { id, items, loaded = false, error = false, empty = 'Nothing here.', pathOf = () => '' } = $props();

  const columns = [
    { key: 'name', label: 'Name', cls: 'name' },
    { key: 'state', label: 'State', value: (p) => (p.on || p.pending ? 'on' : 'off') },
    { key: 'title', label: 'What it is', optional: true },
    { key: 'act', label: '', sort: false, align: 'right' },
  ];
  const link = (e, p) => { e.stopPropagation(); if (!(e.metaKey || e.ctrlKey || e.shiftKey || e.button)) { e.preventDefault(); go(pathOf(p)); } };
</script>

<Card style="padding:4px 8px;overflow-x:auto">
  <Table {id} {columns} rows={items} key="name" compact loading={!loaded} empty={error ? 'The list could not be read.' : empty}>
    {#snippet cell(p, col)}
      {#if col.key === 'name'}{#if pathOf(p)}<a href={url(pathOf(p))} onclick={(e) => link(e, p)}><code>{p.name}</code></a>{:else}<code>{p.name}</code>{/if}
      {:else if col.key === 'state'}<PartTag part={p} />
      {:else if col.key === 'title'}<Muted>{p.title}</Muted>
      {:else}<Row gap="1" justify="end" style="flex-wrap:nowrap">
        {#if pathOf(p)}<Button variant="ghost" size="sm" class="btn-icon" icon="arrow-square-out" label="Open page" tooltip={'Open the page of this part'} onclick={() => go(pathOf(p))} />{/if}
        <Button size="sm" busy={(jobRunning('parts', ['disable', p.name]) || jobRunning('parts', ['enable', p.name]))} busyLabel="Switching…" disabled={!p.canSwitch} tooltip={!p.canSwitch ? 'This part cannot be switched here' : p.on || p.pending ? 'Switch this part off (shows the plan)' : 'Switch this part on (shows the plan)'} onclick={() => flip(p)}>{p.on || p.pending ? 'Switch off…' : 'Switch on…'}</Button>
      </Row>{/if}
    {/snippet}
  </Table>
</Card>
