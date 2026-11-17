<script>
  // Where the off-site copy goes (hs sys backup plan|start offsite-config --kind s3|rest|sftp|folder|typed ...). The fields are arguments;
  // the secrets (S3 access key id and secret key, the REST password) are lines on standard input and never reach an argument or a log.
  // A new repository gets its own password: the answer carries it once (secret password), the Backup page shows it with "write it down".
  import CreateDialog from '../../shell/CreateDialog.svelte';
  import Field from '../../ui/Field.svelte';
  import TextInput from '../../ui/TextInput.svelte';
  import Select from '../../ui/Select.svelte';
  import { ui } from '../../ui.svelte.js';
  import { refresh } from '../../data.svelte.js';

  let { onclose, ondone = () => {} } = $props();

  let kind = $state('s3');
  let endpoint = $state(''), bucket = $state(''), prefix = $state('');
  let accessKey = $state(''), secretKey = $state('');
  let url = $state(''), restUser = $state(''), restPass = $state('');
  let host = $state(''), sshUser = $state(''), port = $state(''), path = $state('');
  let typed = $state('');

  const WORD = /^[A-Za-z0-9/@:._+=,~%-]+$/;
  const ok = (v) => WORD.test(v.trim()) && !v.includes('..');
  const args = () => {
    const a = ['offsite-config', '--kind', kind];
    if (kind === 's3') {
      if (!ok(endpoint) || !ok(bucket) || !accessKey.trim() || !secretKey.trim()) return null;
      a.push('--endpoint', endpoint.trim(), '--bucket', bucket.trim());
      if (prefix.trim()) { if (!ok(prefix)) return null; a.push('--prefix', prefix.trim()); }
    } else if (kind === 'rest') {
      if (!ok(url)) return null;
      a.push('--url', url.trim());
      if (restUser.trim()) { if (!ok(restUser) || !restPass) return null; a.push('--user', restUser.trim()); }
    } else if (kind === 'sftp') {
      if (!ok(host) || !ok(sshUser) || !ok(path)) return null;
      a.push('--host', host.trim(), '--user', sshUser.trim(), '--path', path.trim());
      if (port.trim()) { if (!/^[0-9]{1,5}$/.test(port.trim())) return null; a.push('--port', port.trim()); }
    } else if (kind === 'folder') {
      if (!ok(path)) return null;
      a.push('--path', path.trim());
    } else {
      if (!ok(typed)) return null;
      a.push('--repo', typed.trim());
    }
    return a;
  };
  // one line per secret, in the order backup.sh reads them
  const stdin = () => (kind === 's3' ? `${accessKey.trim()}\n${secretKey.trim()}` : kind === 'rest' && restUser.trim() ? restPass : undefined);
  const done = (r) => {
    if (r?.secret?.password) ui.offsitePass = r.secret.password;
    refresh(['/api/sys/backup/state']);
    ondone(r);
  };
</script>

<CreateDialog title="Off-site copy" kicker="Backup" area="backup" {args} {stdin} {onclose} ondone={done}>
  {#snippet form()}
    <Field label="Kind of target">
      <Select bind:value={kind} options={[
        { value: 's3', label: 'S3-compatible (Backblaze, Wasabi, MinIO, AWS ...)' },
        { value: 'rest', label: 'restic REST server' },
        { value: 'sftp', label: 'SFTP (another computer you can ssh to)' },
        { value: 'folder', label: 'A folder (a mounted disk)' },
        { value: 'typed', label: 'Another restic address (b2:, azure: ...)' }]} />
    </Field>
    {#if kind === 's3'}
      <Field label="Endpoint" help="Host of the service, for example s3.eu-central-1.amazonaws.com"><TextInput bind:value={endpoint} autocomplete="off" spellcheck={false} /></Field>
      <Field label="Bucket"><TextInput bind:value={bucket} autocomplete="off" spellcheck={false} /></Field>
      <Field label="Folder in the bucket (optional)"><TextInput bind:value={prefix} placeholder="hobnix" autocomplete="off" spellcheck={false} /></Field>
      <Field label="Access key id"><TextInput bind:value={accessKey} autocomplete="off" spellcheck={false} /></Field>
      <Field label="Secret key"><TextInput type="password" bind:value={secretKey} autocomplete="new-password" spellcheck={false} /></Field>
    {:else if kind === 'rest'}
      <Field label="Address" help="https://host:8000/path. Run the server as rest-server --append-only: then this server cannot delete there."><TextInput bind:value={url} autocomplete="off" spellcheck={false} /></Field>
      <Field label="User (optional)"><TextInput bind:value={restUser} autocomplete="off" spellcheck={false} /></Field>
      <Field label="Password"><TextInput type="password" bind:value={restPass} autocomplete="new-password" spellcheck={false} /></Field>
    {:else if kind === 'sftp'}
      <Field label="Host"><TextInput bind:value={host} autocomplete="off" spellcheck={false} /></Field>
      <Field label="User"><TextInput bind:value={sshUser} autocomplete="off" spellcheck={false} /></Field>
      <Field label="Port (optional)"><TextInput bind:value={port} inputmode="numeric" autocomplete="off" /></Field>
      <Field label="Folder on the host" help="Absolute path. Login uses the ssh key of root on this server, no password."><TextInput bind:value={path} autocomplete="off" spellcheck={false} /></Field>
    {:else if kind === 'folder'}
      <Field label="Folder" help="Absolute path, for example the mounted off-site disk."><TextInput bind:value={path} autocomplete="off" spellcheck={false} /></Field>
    {:else}
      <Field label="Address" help="Credentials of these kinds are not asked here: put them in /var/lib/hs/backup-offsite.env (KEY=VALUE lines)."><TextInput bind:value={typed} autocomplete="off" spellcheck={false} /></Field>
    {/if}
  {/snippet}
</CreateDialog>
