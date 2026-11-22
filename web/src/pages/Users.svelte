<script>
  // Users of the domain: the list, and the quick look over it (?sel=<name>: selection.svelte.js). "Open page" goes to the page of the user (pages/identity/User.svelte),
  // where the groups, the shares the user can reach and the actions are. The quick look keeps the facts and the two everyday actions; Lock and Delete are on the page.
  import { poll, rows } from '../data.svelte.js';
  import { selected, select, close } from '../selection.svelte.js';
  import { takeSelection } from '../select.svelte.js';
  import { openCreate } from '../ui.svelte.js';
  import { rowstate } from '../rowstate.svelte.js';
  import { go, url } from '../route.svelte.js';
  import { userPending, userFailed } from './rows.js';
  import { userPath, userOf, stateOf, builtInUser } from './identity/user.js';
  import NewUser from '../forms/users/NewUser.svelte';
  import SetPassword from '../forms/users/SetPassword.svelte';
  import EditUser from '../forms/users/EditUser.svelte';
  import SshKeys from '../forms/ssh/SshKeys.svelte';
  import ErrorNote from '../ui/ErrorNote.svelte';
  import Table from '../shell/Table.svelte';
  import PageHeader from '../shell/PageHeader.svelte';
  import PageState from '../shell/PageState.svelte';
  import Button from '../ui/Button.svelte';
  import QuickLook from '../ui/QuickLook.svelte';
  import Kv from '../ui/Kv.svelte';
  import Chip from '../ui/Chip.svelte';
  import { Card, Muted, StatusDot, Row } from '../ui/index.js';

  const list = poll('/api/sys/users/list', 30000);
  const selName = $derived(selected());
  // a search result asks for a user with setSelection (select.svelte.js): it becomes ?sel= here
  $effect(() => { const n = takeSelection('users'); if (n) select(n); });

  const users = $derived(rows(list).map(userOf));
  const doing = (u) => userPending(u.name, rowstate.pending);
  const failure = (u) => (doing(u) ? null : userFailed(u.name, rowstate.failed));
  const sel = $derived(users.find((u) => u.name === selName));
  // mail and description of the opened user ("-" = empty)
  const det = poll(() => (sel ? `/api/sys/users/details/${encodeURIComponent(sel.name)}` : ''), 30000, 'users-list');
  const detail = (k) => { const v = rows(det).find((r) => r[0] === k)?.[1]; return v && v !== '-' ? v : ''; };
  const link = (e, name) => { e.stopPropagation(); if (!(e.metaKey || e.ctrlKey || e.shiftKey || e.button)) { e.preventDefault(); go(userPath(name)); } };

  const columns = [
    { key: 'name', label: 'User' }, { key: 'full', label: 'Name', optional: true }, { key: 'groups', label: 'Groups', optional: true, value: (u) => u.groups.join(', ') },
    { key: 'state', label: 'State', value: (u) => stateOf(u) },
  ];
</script>

<PageHeader title="Users" crumb="Identity" sub="The accounts of the domain. Locking or deleting shows a plan first.">
  {#snippet actions()}
    <Button tooltip={'The SSH keys that may log in as adminuser'} onclick={() => openCreate(SshKeys)}><i class="ph ph-key"></i>SSH keys</Button>
    <Button variant="primary" tooltip={'Create a user'} onclick={() => openCreate(NewUser)}><i class="ph ph-plus"></i>New user</Button>
  {/snippet}
</PageHeader>

<PageState loading={!list.loaded} error={list.error?.message} hasData={list.data != null} empty={list.loaded && !users.length}
           emptyIcon="user" emptyTitle="No users" emptyText="The domain controller (dc1) may be down, or the storage is locked. Otherwise add the first user.">
  {#snippet emptyAction()}<Button variant="primary" tooltip={'Create a user'} onclick={() => openCreate(NewUser)}><i class="ph ph-plus"></i>New user</Button>{/snippet}
  <div style="position:relative">
    <Card style="padding:0">
      <Table id="users" {columns} rows={users} key="name" selected={sel?.name} onrow={(u) => select(u.name)}>
        {#snippet cell(u, col)}
          {#if col.key === 'name'}<a href={url(userPath(u.name))} onclick={(e) => link(e, u.name)}><b>{u.name}</b></a>{#if builtInUser(u.name)} <Chip>built in</Chip>{/if}
          {:else if col.key === 'full'}<Muted>{u.full}</Muted>
          {:else if col.key === 'groups'}<Row gap="1" wrap>{#each u.groups as g}<Chip>{g}</Chip>{/each}</Row>
          {:else}{#if doing(u)}<Muted><i class="ph ph-circle-notch spin"></i> {doing(u)}…</Muted>{:else}<StatusDot state={u.enabled ? 'ok' : 'off'} label={stateOf(u)} />{/if}{#if failure(u)}<Chip tone="bad">failed</Chip>{/if}{/if}
        {/snippet}
      </Table>
    </Card>
    {#if sel}
      <QuickLook title={sel.name} chip={builtInUser(sel.name) ? 'built in' : sel.full} state={sel.enabled ? 'ok' : 'off'} stateLabel={stateOf(sel)} rowKey={sel.name} href={userPath(sel.name)} onclose={close}>
        {#if failure(sel)}<ErrorNote error={failure(sel).error} ondismiss={() => rowstate.dismiss(failure(sel).id)} />{/if}
        <Kv items={[{ k: 'Account', v: sel.name }, { k: 'Full name', v: sel.full }, { k: 'State', v: stateOf(sel) }, { k: 'Groups', v: sel.groups.join(', ') },
                   { k: 'Email', v: detail('mail') }, { k: 'Description', v: detail('description') }]} />
        {#snippet actions()}
          <Button need="admin" variant="primary" icon="pencil-simple" tooltip={'Change the full name, email and description'} onclick={() => openCreate(EditUser, { user: sel.name })}>Edit</Button>
          <Button need="admin" icon="password" tooltip={'Set a new password for this user'} onclick={() => openCreate(SetPassword, { user: sel.name })}>Password</Button>
        {/snippet}
      </QuickLook>
    {:else if selName && list.loaded}
      <QuickLook title={selName} onclose={close}><Muted as="p" style="padding:12px 16px;margin:0">No user called “{selName}” exists. It may have been deleted or renamed.</Muted></QuickLook>
    {/if}
  </div>
</PageState>
