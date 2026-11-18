<script>
  // New user: `hs sys users plan|start <name> user-add [--full <name>] [--group <group> ...]`, the password on stdin. The user starts in Domain Users;
  // every chosen group is joined by the job once the account exists (the plan lists one step per group).
  import CreateDialog from '../../shell/CreateDialog.svelte';
  import PasswordFields from './PasswordFields.svelte';
  import { poll, rows } from '../../data.svelte.js';
  import { Field, TextInput, Row, Muted, Banner } from '../../ui';

  let { ondone = () => {} } = $props();
  let name = $state('');
  let full = $state('');
  let pw = $state('');
  let pw2 = $state('');
  let chosen = $state([]);

  const gl = poll('/api/sys/users/groups', 30000);
  // everyone is in Domain Users already; the script refuses it
  const groups = $derived(rows(gl).map((r) => r[0]).filter((n) => n.toLowerCase() !== 'domain users'));
  const toggle = (g) => { chosen = chosen.includes(g) ? chosen.filter((x) => x !== g) : [...chosen, g]; };

  const nameOk = $derived(/^[A-Za-z][A-Za-z0-9._-]{0,31}$/.test(name));
  const fullOk = $derived(full === '' || /^\w[\w .'-]{0,63}$/.test(full));
  const pwOk = $derived(pw.length >= 8 && pw === pw2 && pw.length <= 256 && !/[\r\n\0]/.test(pw));
  const args = () => (nameOk && fullOk && pwOk ? [name, 'user-add', ...(full ? ['--full', full] : []), ...chosen.flatMap((g) => ['--group', g])] : null);
  const adminWarn = $derived(chosen.some((g) => g.toLowerCase() === 'domain admins'));
</script>

<CreateDialog title="New user" area="users" {args} stdin={() => (pwOk ? pw : undefined)} {ondone}>
  {#snippet form()}
    <Field label="User name" id="nu-name" error={name && !nameOk ? 'Starts with a letter; letters, digits, dot, dash and underscore, up to 32.' : ''}>
      <Row gap="2"><Muted>HOME\</Muted><TextInput bind:value={name} placeholder="anna" autocomplete="off" spellcheck={false} /></Row>
    </Field>
    <Field label="Full name (optional)" id="nu-full" error={full && !fullOk ? 'Letters, digits, spaces, dot, dash and apostrophe only.' : ''}>
      <TextInput bind:value={full} placeholder="Anna Muster" autocomplete="off" />
    </Field>
    <PasswordFields bind:pw bind:pw2 />
    <div class="field">
      <span class="lbl">Groups (optional)</span>
      <div class="chips">
        {#each groups as g (g)}
          <button type="button" class="chip" class:on={chosen.includes(g)} aria-pressed={chosen.includes(g)} onclick={() => toggle(g)}>
            <i class="ph {chosen.includes(g) ? 'ph-check' : 'ph-plus'}"></i>{g}
          </button>
        {:else}
          <Muted>{gl.loaded ? 'No other groups yet.' : 'Loading…'}</Muted>
        {/each}
      </div>
    </div>
    {#if adminWarn}
      <Banner tone="warn">Domain Admins can sign in to this interface and change everything on the server.</Banner>
    {/if}
    <Muted as="p">The new user is in Domain Users. What the chosen groups may open is set in Shares.</Muted>
  {/snippet}
</CreateDialog>

<style>
  .lbl { display: block; font-size: 12px; margin-bottom: 5px; color: var(--fg-2); }
  .chips { display: flex; flex-wrap: wrap; gap: 6px; }
  .chip { display: inline-flex; align-items: center; gap: 5px; font: inherit; font-size: 12.5px; padding: 4px 11px; border-radius: 999px; cursor: pointer;
    color: var(--fg-2); background: transparent; border: 1px solid var(--line-2); }
  .chip:hover { border-color: var(--accent); }
  .chip.on { background: var(--panel-3); color: var(--fg); border-color: transparent; }
</style>
