<script>
  import Chip from '../ui/Chip.svelte';
  // API tokens (Settings > Users and access, ADR 0012 step 17): programs (curl, a dashboard, a script) sign in with `Authorization: Bearer hn_...`.
  // The list is `hs sys token list` (an admin sees all, everybody else their own; never the token), create is `hs sys token start create`
  // (the token comes back ONCE, here, and only its hash is kept), revoke opens the plan dialog and asks for the typed token name.
  import { onMount } from 'svelte';
  import { session, start, get } from '../api.js';
  import { ui, openPlan, jobRunning } from '../ui.svelte.js';
  import Button from '../ui/Button.svelte';
  import Banner from '../ui/Banner.svelte';
  import Field from '../ui/Field.svelte';
  import Select from '../ui/Select.svelte';
  import TextInput from '../ui/TextInput.svelte';
  import Table from '../shell/Table.svelte';

  let role = $state('');
  onMount(async () => { try { role = (await session())?.role ?? ''; } catch { role = ''; } });
  const allowed = $derived(role === 'app-manager' || role === 'admin');

  // read when the page opens, after a create and when a plan dialog closes (a revoke): no timer
  let list = $state({ data: null, error: null, loaded: false });
  async function load() {
    try { list = { data: await get('/api/sys/token/list', true), error: null, loaded: true }; } catch (e) { list = { data: null, error: e, loaded: true }; }
  }
  onMount(load);
  $effect(() => { if (!ui.dialog) load(); });
  // id, name, owner, realm, role, created, expires (epoch seconds), state
  const tokens = $derived((list.data?.rows ?? []).map((r) => ({ id: r[0], name: r[1], owner: r[2], realm: r[3], role: r[4], created: +r[5], expires: +r[6], state: r[7] })));

  const columns = [
    { key: 'name', label: 'Name' },
    { key: 'id', label: 'Id' },
    { key: 'owner', label: 'Owner' },
    { key: 'role', label: 'Role' },
    { key: 'expires', label: 'Expires', sort: 'num' },
    { key: 'act', label: '', sort: false, align: 'right' },
  ];
  const day = (t) => new Date(t * 1000).toLocaleDateString();

  const NAME_RE = /^[A-Za-z0-9][A-Za-z0-9._-]{0,39}$/;
  let name = $state('');
  let newRole = $state('viewer');
  let days = $state('90');
  let error = $state('');
  let made = $state(null);      // { name, token } once, until the person closes it
  let copied = $state(false);
  const roleOptions = $derived(role === 'admin' ? ['viewer', 'app-manager', 'admin'] : ['viewer', 'app-manager']);
  const nameOk = $derived(NAME_RE.test(name.trim()));
  const daysOk = $derived(/^[0-9]{1,3}$/.test(days) && +days >= 1 && +days <= 365);

  async function create() {
    error = ''; copied = false;
    try {
      const r = await start('token', ['create', name.trim(), '--role', newRole, '--days', days]);
      if (r.status === 'refused' || !r.secret?.token) { error = r.reason || 'The token could not be created.'; return; }
      made = { name: name.trim(), token: r.secret.token };
      name = '';
      load();
    } catch (e) { error = e.message; }
  }

  async function copy() {
    try { await navigator.clipboard.writeText(made.token); copied = true; } catch { copied = false; }
  }

  function revoke(t) {
    ui.create = null;
    openPlan('token', ['revoke', t.name], `Revoke the token ${t.name}`);
  }
</script>

<div class="card" id="tokens" style="padding:14px 16px;gap:10px">
  <div style="font-size:14px;font-weight:500">API tokens</div>
  <p style="margin:0;font-size:12.5px;color:var(--fg-3)">A token lets a program use this interface without a password: <code>curl -H "Authorization: Bearer hn_..."</code>. It never has more than its owner's role, it cannot create tokens or use users, secrets or the unlock, and it stops at its expiry or when its owner is disabled (within an hour).</p>
  {#if role && !allowed}
    <p style="margin:0;font-size:12.5px;color:var(--fg-3)">Tokens are made by app managers and admins.</p>
  {:else}
    {#if made}
      <Banner tone="warn">
        <div>Token <b>{made.name}</b>: copy it now, it is shown only once.</div>
        <code style="display:block;word-break:break-all;margin-top:6px;user-select:all">{made.token}</code>
        <div style="display:flex;gap:8px;margin-top:6px"><Button size="sm" icon="copy" onclick={copy}>{copied ? 'Copied' : 'Copy'}</Button><Button size="sm" variant="ghost" onclick={() => (made = null)}>I have copied it</Button></div>
      </Banner>
    {/if}
    {#if error}<Banner tone="bad">{error}</Banner>{/if}
    {#if list.error}<Banner tone="warn">The tokens could not be read.</Banner>{/if}
    <Table id="api-tokens" {columns} rows={tokens} key="id" loading={!list.loaded} empty="No tokens yet.">
      {#snippet cell(r, col)}
        {#if col.key === 'expires'}{day(r.expires)}{#if r.state === 'expired'} <Chip>expired</Chip>{/if}
        {:else if col.key === 'act'}<Button size="sm" variant="ghost" busy={jobRunning('token', ['revoke', r.name])} tooltip={'Revoke this token'} onclick={() => revoke(r)}>Revoke</Button>
        {:else}{r[col.key] || '–'}{/if}
      {/snippet}
    </Table>
    <div style="display:flex;gap:10px;flex-wrap:wrap;align-items:flex-end">
      <Field label="Name" help="Letters, digits, dot, dash, underscore" error={name && !nameOk ? 'Not a valid name.' : ''}><TextInput bind:value={name} placeholder="dashboard" /></Field>
      <Field label="Role"><Select bind:value={newRole} options={roleOptions} /></Field>
      <Field label="Days" help="1 to 365" error={!daysOk ? 'A token lives 1 to 365 days.' : ''}><TextInput bind:value={days} /></Field>
      <Button size="sm" disabled={!nameOk || !daysOk} onclick={create}>Create token</Button>
    </div>
  {/if}
</div>

