<script>
  // Users of the domain: the list. No quick look (owner decision 2026-11-23, as on Disks): each row ends with Edit, Change password and Open user; the name opens the
  // page of the user (pages/identity/User.svelte) too, where the groups, the shares the user can reach, Lock and Delete are. Built-in accounts have the read-only marker: no Edit, no password here.
  import { poll, rows } from '../data.svelte.js';
  import { openCreate } from '../ui.svelte.js';
  import { rowstate } from '../rowstate.svelte.js';
  import { go, url } from '../route.svelte.js';
  import { userPending, userFailed } from './rows.js';
  import { userPath, userOf, stateOf, builtInUser } from './identity/user.js';
  import NewUser from '../forms/users/NewUser.svelte';
  import SetPassword from '../forms/users/SetPassword.svelte';
  import EditUser from '../forms/users/EditUser.svelte';
  import SshKeys from '../forms/ssh/SshKeys.svelte';
  import Table from '../shell/Table.svelte';
  import PageHeader from '../shell/PageHeader.svelte';
  import PageState from '../shell/PageState.svelte';
  import Button from '../ui/Button.svelte';
  import Chip from '../ui/Chip.svelte';
  import { Card, Muted, StatusDot, Row } from '../ui/index.js';

  const list = poll('/api/sys/users/list', 30000);
  const users = $derived(rows(list).map(userOf));
  const doing = (u) => userPending(u.name, rowstate.pending);
  const failure = (u) => (doing(u) ? null : userFailed(u.name, rowstate.failed));
  const link = (e, name) => { e.stopPropagation(); if (!(e.metaKey || e.ctrlKey || e.shiftKey || e.button)) { e.preventDefault(); go(userPath(name)); } };

  const columns = [
    { key: 'name', label: 'User' }, { key: 'full', label: 'Name', optional: true }, { key: 'groups', label: 'Groups', optional: true, value: (u) => u.groups.join(', ') },
    { key: 'state', label: 'State', value: (u) => stateOf(u) },
    { key: 'act', label: '', sort: false, align: 'right', width: '1%' },
  ];
</script>

<PageHeader title="Users" sub="The accounts of the domain. Locking or deleting shows a plan first.">
  {#snippet actions()}
    <Button tooltip={'The SSH keys that may log in as adminuser'} onclick={() => openCreate(SshKeys)}><i class="ph ph-key"></i>SSH keys</Button>
    <Button variant="primary" tooltip={'Create a user'} onclick={() => openCreate(NewUser)}><i class="ph ph-plus"></i>New user</Button>
  {/snippet}
</PageHeader>

<PageState loading={!list.loaded} error={list.error?.message} hasData={list.data != null} empty={list.loaded && !users.length}
           emptyIcon="user" emptyTitle="No users" emptyText="The domain controller (dc1) may be down, or the storage is locked. Otherwise add the first user.">
  {#snippet emptyAction()}<Button variant="primary" tooltip={'Create a user'} onclick={() => openCreate(NewUser)}><i class="ph ph-plus"></i>New user</Button>{/snippet}
  <div>
    <Card style="padding:0">
      <Table id="users" {columns} rows={users} key="name">
        {#snippet cell(u, col)}
          {#if col.key === 'name'}<a href={url(userPath(u.name))} onclick={(e) => link(e, u.name)}><b>{u.name}</b></a>{#if builtInUser(u.name)} <Chip>built in</Chip>{/if}
          {:else if col.key === 'full'}<Muted>{u.full}</Muted>
          {:else if col.key === 'groups'}<Row gap="1" wrap>{#each u.groups as g}<Chip>{g}</Chip>{/each}</Row>
          {:else if col.key === 'act'}<Row gap="1" style="justify-content:flex-end;flex-wrap:nowrap">
              <Button need="admin" variant="ghost" size="sm" class="btn-icon" icon="pencil-simple" label="Edit {u.name}" disabled={builtInUser(u.name)} tooltip={builtInUser(u.name) ? 'A built-in account is read-only' : 'Change the full name, email and description'} onclick={() => openCreate(EditUser, { user: u.name })} />
              <Button need="admin" variant="ghost" size="sm" class="btn-icon" icon="password" label="Change password of {u.name}" disabled={builtInUser(u.name)} tooltip={builtInUser(u.name) ? 'A built-in account is read-only' : 'Set a new password for this user'} onclick={() => openCreate(SetPassword, { user: u.name })} />
              <Button variant="ghost" size="sm" class="btn-icon" icon="arrow-square-out" label="Open user" tooltip={'Open user'} onclick={() => go(userPath(u.name))} />
            </Row>
          {:else}{#if doing(u)}<Muted><i class="ph ph-circle-notch spin"></i> {doing(u)}…</Muted>{:else}<StatusDot state={u.enabled ? 'ok' : 'off'} label={stateOf(u)} />{/if}{#if failure(u)}<Chip tone="bad">failed</Chip>{/if}{/if}
        {/snippet}
      </Table>
    </Card>
  </div>
</PageState>
