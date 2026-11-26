<script>
  // Identity > Users > one user: /identity/users/<name>[/<tab>] (D6). The Object template (shell/ObjectPage.svelte) with the tabs Overview, Groups and Access (D3 a):
  //   Overview  account, full name, state, email, description; the groups and shares it is linked to are listed under the tabs
  //   Groups    the groups of the user, each a link to the group, and the button that changes them
  //   Access    the shares the user can reach, the level and through what (read only: permissions are edited on the share)
  // Actions (D4): Edit (primary) and Password (secondary) in the header; Groups and Lock/Unlock in the More menu; Delete only in the danger section.
  // The built-in accounts (Administrator, Guest, krbtgt) carry the read-only marker: no lock, no delete.
  import { P, withQuery } from '../../paths.js';
  import { route, go } from '../../route.svelte.js';
  import { objectOf, objects } from '../../objects.js';
  import { poll, rows } from '../../data.svelte.js';
  import { sharesPath } from '../../pools.svelte.js';
  import { setSelection } from '../../select.svelte.js';
  import { rowstate } from '../../rowstate.svelte.js';
  import { openPlan, openCreate } from '../../ui.svelte.js';
  import { tip } from '../../ui/tooltip.svelte.js';
  import { userPending, userFailed } from '../rows.js';
  import ObjectPage from '../../shell/ObjectPage.svelte';
  import Table from '../../shell/Table.svelte';
  import { Banner, Button, Card, Chip, Kv, Muted, Row } from '../../ui/index.js';
  import ErrorNote from '../../ui/ErrorNote.svelte';
  import EditUser from '../../forms/users/EditUser.svelte';
  import SetPassword from '../../forms/users/SetPassword.svelte';
  import Membership from '../../forms/users/Membership.svelte';
  import { userPath, userOf, stateOf, builtInUser } from './user.js';

  const at = $derived(objectOf(route.path));
  const name = $derived(at?.kind === 'user' ? at.id : '');
  const list = poll('/api/sys/users/list', 30000);
  const glist = poll('/api/sys/users/groups', 30000);
  const groupNames = $derived(rows(glist).map((r) => r[0]));
  const u = $derived(rows(list).map(userOf).find((x) => x.name.toLowerCase() === name.toLowerCase()));

  // share, level, via (reads every share ACL: only for this user); mail, description
  const acc = poll(() => (u ? `/api/sys/users/access/${encodeURIComponent(u.name)}` : ''), 30000, 'shares-overview');
  const reach = $derived(rows(acc).map((r) => ({ share: r[0], level: r[1], via: r[2] })));
  const det = poll(() => (u ? `/api/sys/users/details/${encodeURIComponent(u.name)}` : ''), 30000, 'users-list');
  const detail = (k) => { const v = rows(det).find((r) => r[0] === k)?.[1]; return v && v !== '-' ? v : ''; };
  const reachColumns = [{ key: 'share', label: 'Share' }, { key: 'level', label: 'Level' }, { key: 'via', label: 'Through' }];
  const toShare = (s) => { setSelection('shares', s); go(sharesPath()); };

  const fixed = $derived(!!u && builtInUser(u.name));
  const doing = $derived(u ? userPending(u.name, rowstate.pending) : '');
  const failure = $derived(u && !doing ? userFailed(u.name, rowstate.failed) : null);
  const lockWord = $derived(u?.enabled ? 'Lock' : 'Unlock');
  const lockBusy = $derived(!!u && !!(rowstate.pending('users', [u.name, 'lock']) || rowstate.pending('users', [u.name, 'unlock'])));
  const edit = () => openCreate(EditUser, { user: u.name });
  const password = () => openCreate(SetPassword, { user: u.name });
  const groups = () => openCreate(Membership, { subject: 'user', name: u.name, have: u.groups, options: groupNames });
  const groupLink = (e, g) => { if (!(e.metaKey || e.ctrlKey || e.shiftKey || e.button)) { e.preventDefault(); go(withQuery(P.groups, { sel: g })); } };

  const menu = $derived(u ? [
    { label: 'Groups…', icon: 'users-three', need: 'admin', onclick: groups },
    { label: `${lockWord}…`, icon: u.enabled ? 'lock' : 'lock-open', need: 'admin', disabled: fixed || lockBusy, reason: fixed ? `${u.name} is a built-in account and cannot be locked` : '', onclick: () => openPlan('users', [u.name, u.enabled ? 'lock' : 'unlock'], `${lockWord} ${u.name}`) },
  ] : []);
  const danger = $derived(u ? [{
    label: 'Delete…', text: 'Removes the account for good. It cannot be undone; the plan comes first and you type the name.', need: 'admin', disabled: fixed, reason: fixed ? `${u.name} is a built-in account and cannot be deleted` : '',
    onclick: () => openPlan('users', [u.name, 'user-delete'], `Delete ${u.name}`),
  }] : []);
  const links = $derived(u ? [
    ...u.groups.map((g) => ({ kind: 'Groups', name: g, href: withQuery(P.groups, { sel: g }) })),
    ...reach.map((r) => ({ kind: 'Shares', name: r.share, href: withQuery(sharesPath(), { sel: r.share }), note: `${r.level}, ${r.via}` })),
  ] : []);
  const jobs = $derived((r) => !!u && (r.description ?? '').split(/[\s"']+/).includes(u.name));
</script>

<ObjectPage title={name} chip={u?.full ?? ''} state={u ? (u.enabled ? 'ok' : 'off') : ''} stateLabel={u ? stateOf(u) : ''}
            tabs={objects.user.tabs} tab={at?.tab ?? ''} onpick={(id) => go(userPath(name, id))} {menu} {danger} {links} {jobs} need="admin"
            loading={!list.loaded} error={list.error && !list.data ? list.error.message : ''} notFound={list.loaded && !!list.data && !u} notFoundTitle="No such user" backTo={P.users} backLabel="All users"
            notFoundText={`No user called “${name}” exists in the domain. It may have been deleted or renamed.`}>
  {#snippet primary()}
    {#if u}
      <Button need="admin" variant="primary" icon="pencil-simple" tooltip={'Change the full name, email and description'} onclick={edit}>Edit</Button>
      <Button need="admin" icon="password" tooltip={'Set a new password for this user'} onclick={password}>Password</Button>
    {/if}
  {/snippet}
  {#snippet banners()}
    {#if u}
      {#if fixed}<Banner tone="info">{u.name} is a built-in account of the domain: it can be edited, but not locked or deleted.</Banner>{/if}
      {#if doing}<Banner tone="info">{doing}… a job is running on this account; this page follows it.</Banner>
      {:else if failure}<ErrorNote error={failure.error} ondismiss={() => rowstate.dismiss(failure.id)} />{/if}
    {/if}
  {/snippet}
  {#snippet children(t)}
    {#if u}
      {#if t === 'overview'}
        <Card title="Overview">
          <Kv items={[{ k: 'Account', v: u.name }, { k: 'Full name', v: u.full }, { k: 'State', v: stateOf(u) }, { k: 'Email', v: detail('mail') }, { k: 'Description', v: detail('description') },
                      { k: 'Groups', v: u.groups.join(', ') }]} />
        </Card>
      {:else if t === 'groups'}
        <Card title="Groups">
          {#if u.groups.length}
            <Row gap="2" wrap>{#each u.groups as g}<Chip><a href={withQuery(P.groups, { sel: g })} onclick={(e) => groupLink(e, g)}>{g}</a></Chip>{/each}</Row>
          {:else}
            <Muted as="p">{u.name} is in no group.</Muted>
          {/if}
          <Row gap="2" style="margin-top:12px"><Button need="admin" tooltip={'Choose the groups of this user'} onclick={groups}><i class="ph ph-users-three"></i>Change groups…</Button></Row>
        </Card>
      {:else}
        <Card title="Can reach">
          <Table id="reach" columns={reachColumns} rows={reach} key="share" loading={!acc.loaded} empty={acc.loaded ? (acc.error ? 'The access could not be read.' : 'No share is reachable.') : 'Loading…'}>
            {#snippet cell(r, col)}
              {#if col.key === 'share'}<button class="link-btn" use:tip={'Permissions are edited on the share'} onclick={() => toShare(r.share)}>{r.share}</button>
              {:else if col.key === 'level'}<Chip>{r.level}</Chip>
              {:else}<Muted>{r.via}</Muted>{/if}
            {/snippet}
          </Table>
          <Muted as="p" style="margin-top:10px">Read only. Change who may reach a share on the share itself (its Permissions tab).</Muted>
        </Card>
      {/if}
    {/if}
  {/snippet}
</ObjectPage>
