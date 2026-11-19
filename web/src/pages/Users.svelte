<script>
  import { tip } from '../ui/tooltip.svelte.js';
  // Users of the domain: the list on the left, the drawer on the right (facts, groups, the shares the user can reach). The share access matrix is READ
  // ONLY here: permissions are edited on the share itself (decision 4 of ); a row links to the share.
  import { poll, rows } from '../data.svelte.js';
  import { go } from '../route.svelte.js';
  import { sharesPath } from '../pools.svelte.js';
  import { takeSelection, setSelection } from '../select.svelte.js';
  import { openPlan, openCreate } from '../ui.svelte.js';
  import { rowstate } from '../rowstate.svelte.js';
  import ErrorNote from '../ui/ErrorNote.svelte';
  import { userPending, userFailed } from './rows.js';
  import NewUser from '../forms/users/NewUser.svelte';
  import SetPassword from '../forms/users/SetPassword.svelte';
  import EditUser from '../forms/users/EditUser.svelte';
  import Membership from '../forms/users/Membership.svelte';
  import SshKeys from '../forms/ssh/SshKeys.svelte';
  import Table from '../shell/Table.svelte';
  import PageHeader from '../shell/PageHeader.svelte';
  import PageState from '../shell/PageState.svelte';
  import Button from '../ui/Button.svelte';
  import Split from '../ui/Split.svelte';
  import Drawer from '../ui/Drawer.svelte';
  import Kv from '../ui/Kv.svelte';
  import Chip from '../ui/Chip.svelte';
  import { Card, Muted, StatusDot, Row } from '../ui/index.js';

  const list = poll('/api/sys/users/list', 30000);
  const glist = poll('/api/sys/users/groups', 30000);
  const groupNames = $derived(rows(glist).map((r) => r[0]));
  let selName = $state('');
  let tab = $state('info');
  $effect(() => { const n = takeSelection('users'); if (n) selName = n; });

  // name, full name, enabled|disabled, groups (comma separated)
  const users = $derived(rows(list).map((r) => ({
    name: r[0], full: r[1] && r[1] !== '-' ? r[1] : '', enabled: r[2] === 'enabled',
    groups: (r[3] ?? '').split(',').map((g) => g.trim()).filter(Boolean),
  })));
  const doing = (u) => userPending(u.name, rowstate.pending);
  const failure = (u) => (doing(u) ? null : userFailed(u.name, rowstate.failed));
  const sel = $derived(users.find((u) => u.name === selName));

  // share, level, via (reads every share ACL: only for the opened user)
  const acc = poll(() => (sel ? `/api/sys/users/access/${encodeURIComponent(sel.name)}` : ''), 30000, 'shares-overview');
  const reach = $derived(rows(acc).map((r) => ({ share: r[0], level: r[1], via: r[2] })));
  // full, mail, description of the opened user ("-" = empty)
  const det = poll(() => (sel ? `/api/sys/users/details/${encodeURIComponent(sel.name)}` : ''), 30000, 'users-list');
  const detail = (k) => { const v = rows(det).find((r) => r[0] === k)?.[1]; return v && v !== '-' ? v : ''; };
  const isAdmin =$derived(sel?.name.toLowerCase() === 'administrator' && !!sel?.enabled);
  const reachColumns = [{ key: 'share', label: 'Share' }, { key: 'level', label: 'Level' }, { key: 'via', label: 'Through' }];
  const stateOf = (u) => (u.enabled ? 'active' : 'locked');
  const toShare = (s) => { setSelection('shares', s); go(sharesPath()); };

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
  <Split open={!!sel}>
    {#snippet list()}
      <Card style="padding:0">
        <Table id="users" {columns} rows={users} key="name" selected={sel?.name} onrow={(u) => { selName = u.name; tab = 'info'; }}>
          {#snippet cell(u, col)}
            {#if col.key === 'name'}<b>{u.name}</b>
            {:else if col.key === 'full'}<Muted>{u.full}</Muted>
            {:else if col.key === 'groups'}<Row gap="1" wrap>{#each u.groups as g}<Chip>{g}</Chip>{/each}</Row>
            {:else}{#if doing(u)}<Muted><i class="ph ph-circle-notch spin"></i> {doing(u)}…</Muted>{:else}<StatusDot state={u.enabled ? 'ok' : 'off'} label={stateOf(u)} />{/if}{#if failure(u)}<Chip tone="bad">failed</Chip>{/if}{/if}
          {/snippet}
        </Table>
      </Card>
    {/snippet}
    {#snippet side()}
      {#if sel}
        <Drawer title={sel.name} chip={sel.full} state={sel.enabled ? 'ok' : 'off'} stateLabel={stateOf(sel)} bind:tab onclose={() => (selName = '')}
                tabs={[{ id: 'info', label: 'Info' }, { id: 'access', label: 'Can reach' }]}>
          {#snippet children(t)}
            {#if failure(sel)}<ErrorNote error={failure(sel).error} ondismiss={() => rowstate.dismiss(failure(sel).id)} />{/if}
            {#if t === 'access'}
              <Table id="reach" columns={reachColumns} rows={reach} key="share" loading={!acc.loaded} empty={acc.loaded ? (acc.error ? 'The access could not be read.' : 'No share is reachable.') : 'Loading…'}>
                {#snippet cell(r, col)}
                  {#if col.key === 'share'}<button class="link-btn" use:tip={'Permissions are edited on the share'} onclick={() => toShare(r.share)}>{r.share}</button>
                  {:else if col.key === 'level'}<Chip>{r.level}</Chip>
                  {:else}<Muted>{r.via}</Muted>{/if}
                {/snippet}
              </Table>
              <Muted as="p" style="padding:10px 16px">Read only. Change who may reach a share on the share itself (its Permissions tab).</Muted>
            {:else}
              <Kv items={[{ k: 'Account', v: sel.name }, { k: 'Full name', v: sel.full }, { k: 'State', v: stateOf(sel) }, { k: 'Groups', v: sel.groups.join(', ') },
                         { k: 'Email', v: detail('mail') }, { k: 'Description', v: detail('description') }]} />
            {/if}
          {/snippet}
          {#snippet actions()}
            <Button tooltip={'Change the full name, email and description'} onclick={() => openCreate(EditUser, { user: sel.name })}><i class="ph ph-pencil-simple"></i>Edit</Button>
            <Button tooltip={'Set a new password for this user'} onclick={() => openCreate(SetPassword, { user: sel.name })}><i class="ph ph-password"></i>Password</Button>
            <Button tooltip={'Choose the groups of this user'} onclick={() => openCreate(Membership, { subject: 'user', name: sel.name, have: sel.groups, options: groupNames })}><i class="ph ph-users-three"></i>Groups</Button>
            <Button variant="ghost" icon={sel.enabled ? 'lock' : 'lock-open'} disabled={isAdmin} busy={(rowstate.pending('users', [sel.name, 'lock']) || rowstate.pending('users', [sel.name, 'unlock']))} busyLabel={sel.enabled ? 'Locking…' : 'Unlocking…'} tooltip={isAdmin ? 'Administrator cannot be locked' : sel.enabled ? 'Lock the account (shows the plan first)' : 'Unlock the account (shows the plan first)'}
              onclick={() => openPlan('users', [sel.name, sel.enabled ? 'lock' : 'unlock'], `${sel.enabled ? 'Lock' : 'Unlock'} ${sel.name}`)}>{sel.enabled ? 'Lock' : 'Unlock'}</Button>
            <Button variant="danger" icon="trash" disabled={isAdmin} busy={rowstate.pending('users', [sel.name, 'user-delete'])} busyLabel="Deleting…" tooltip={isAdmin ? 'Administrator cannot be deleted' : 'Delete the user (cannot be undone; you type the name)'}
              onclick={() => openPlan('users', [sel.name, 'user-delete'], `Delete ${sel.name}`)}>Delete</Button>
          {/snippet}
        </Drawer>
      {/if}
    {/snippet}
  </Split>
</PageState>
