<script>
  // Edit a user: `hs sys users plan|start <user> user-edit [--full <name>] [--mail <address>] [--description <text>]`. Only the fields that differ from what
  // the domain holds are sent; "-" clears a field. The login name cannot be changed here.
  import CreateDialog from '../../shell/CreateDialog.svelte';
  import { poll, rows } from '../../data.svelte.js';
  import { Field, TextInput, Muted } from '../../ui';

  let { user, ondone = () => {} } = $props();
  const det = poll(`/api/sys/users/details/${encodeURIComponent(user)}`, 30000);
  const have = $derived(Object.fromEntries(rows(det).map((r) => [r[0], r[1] === '-' ? '' : (r[1] ?? '')])));
  let edited = $state({});
  const val = (k) => (k in edited ? edited[k] : (have[k] ?? ''));

  const fullOk = $derived(val('full') === '' || /^\w[\w .'-]{0,63}$/.test(val('full')));
  const mailOk = $derived(val('mail') === '' || /^[A-Za-z0-9._%+-]{1,64}@[A-Za-z0-9.-]{1,190}$/.test(val('mail')));
  const descOk = $derived(val('description').length <= 255 && !/[\x00-\x1f\x7f]/.test(val('description')));
  const changed = $derived(['full', 'mail', 'description'].filter((k) => det.loaded && val(k) !== (have[k] ?? '')));
  const flag = { full: '--full', mail: '--mail', description: '--description' };
  const args = () => (det.loaded && changed.length && fullOk && mailOk && descOk
    ? [user, 'user-edit', ...changed.flatMap((k) => [flag[k], val(k) === '' ? '-' : val(k)])] : null);
</script>

<CreateDialog title="Edit user" kicker={user} area="users" {args} {ondone}>
  {#snippet form()}
    <Field label="Full name" id="eu-full" error={!fullOk ? 'Letters, digits, spaces, dot, dash and apostrophe only.' : ''}>
      <TextInput value={val('full')} oninput={(e) => (edited.full = e.currentTarget.value)} placeholder="Anna Muster" autocomplete="off" disabled={!det.loaded} />
    </Field>
    <Field label="Email" id="eu-mail" error={!mailOk ? 'This is not an email address.' : ''}>
      <TextInput type="email" value={val('mail')} oninput={(e) => (edited.mail = e.currentTarget.value)} placeholder="anna@example.org" autocomplete="off" disabled={!det.loaded} />
    </Field>
    <Field label="Description" id="eu-desc" error={!descOk ? 'One line, up to 255 characters.' : ''}>
      <TextInput value={val('description')} oninput={(e) => (edited.description = e.currentTarget.value)} autocomplete="off" disabled={!det.loaded} />
    </Field>
    <Muted as="p">The login name stays as it is. Leave a field empty to clear it.</Muted>
  {/snippet}
</CreateDialog>
