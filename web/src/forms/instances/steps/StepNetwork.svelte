<script>
  // Step "Network and storage": fixed address, network (VLAN profile) and storage bindings; the same for every kind (a VM takes fast volumes only).
  import { Button, Field, TextInput, Select, Checkbox, Muted } from '../../../ui/index.js';
  import { poll, rows } from '../../../data.svelte.js';

  let { address = $bindable(''), profile = $bindable(''), binds = $bindable([]), type = 'container' } = $props();
  let nextId = 1;
  const pf = poll('/api/sys/ct/profiles', 60000);
  // name, network, description
  const profiles = $derived(rows(pf).map((r) => ({ name: r[0], net: r[1], desc: r[2] })));
  const sh = poll('/api/sys/shares/overview', 60000, 'shares-overview');
  const shareNames = $derived(rows(sh).filter((r) => r[1] !== 'other').map((r) => r[0]));
  const bindKinds = [{ value: 'shares', label: 'Share' }, { value: 'sensitive', label: 'Sensitive share' }, { value: 'fast', label: 'Fast volume' }];
  const addBind = () => { binds = [...binds, { id: nextId++, kind: 'shares', name: '', path: '', ro: false }]; };
  const dropBind = (id) => { binds = binds.filter((b) => b.id !== id); };
  const bindOk = (b) => /^[A-Za-z0-9][A-Za-z0-9._-]{0,60}$/.test(b.name.trim()) && /^\/(?!.*\.\.)[A-Za-z0-9._/-]{0,200}$/.test(b.path.trim());
  const bindsOk = $derived(binds.every(bindOk) && new Set(binds.map((b) => b.name.trim())).size === binds.length);
  const vmBulk = $derived(type === 'vm' && binds.some((b) => b.kind !== 'fast'));
</script>

<Field label="Fixed address (optional)">
  <TextInput bind:value={address} placeholder="10.10.95.25" autocomplete="off" spellcheck={false} />
</Field>
<Field label="Network">
  <Select bind:value={profile}>
    <option value="">Default network</option>
    {#each profiles as p}<option value={p.name}>{p.name} ({p.net}{p.desc && p.desc !== '-' ? ', ' + p.desc : ''})</option>{/each}
  </Select>
  {#if pf.loaded && pf.error}<Muted as="div">The networks could not be read; the default one is used.</Muted>{/if}
</Field>
<div class="grp">
  <span class="lbl">Storage bindings <span class="opt">(optional)</span></span>
  {#each binds as b (b.id)}
    <div class="brow">
      <Select bind:value={b.kind} ariaLabel="Kind" options={bindKinds} />
      <TextInput ariaLabel="Name" list="ci-shares" bind:value={b.name} placeholder={b.kind === 'fast' ? 'volume' : 'share'} autocomplete="off" spellcheck={false} />
      <TextInput ariaLabel="Path inside" bind:value={b.path} placeholder="/media" autocomplete="off" spellcheck={false} />
      <Checkbox bind:checked={b.ro} label="ro" />
      <Button variant="ghost" class="btn-icon" tooltip={'Remove this binding'} type="button" aria-label="Remove this binding" onclick={() => dropBind(b.id)}><i class="ph ph-x"></i></Button>
    </div>
  {/each}
  <datalist id="ci-shares">{#each shareNames as n}<option value={n}></option>{/each}</datalist>
  <div><Button variant="ghost" size="sm" class="createinstance-sm" type="button" onclick={addBind}><i class="ph ph-plus"></i>Bind storage</Button></div>
  {#if binds.length && !bindsOk}<div class="bad">Each binding needs a different name and an absolute path without "..".</div>{/if}
  {#if vmBulk}<div class="bad">Share folders cannot go into a virtual machine; use a fast volume, or mount the Samba share inside it.</div>{/if}
</div>
<Muted as="div">A share that does not exist yet is created when it is bound. The same storage can be bound later from the instance page.</Muted>

<style>
  .grp { display: flex; flex-direction: column; gap: 6px; }
  .bad { font-size: 12px; color: var(--bad); }
  .lbl { display: block; font-size: 12px; color: var(--fg-2); }
  .opt { color: var(--fg-3); }
  .brow { display: grid; grid-template-columns: 120px minmax(0, 1fr) minmax(0, 1fr) auto auto; gap: 6px; align-items: center; }
  :global(.btn.createinstance-sm) { font-size: 12px; }
</style>
