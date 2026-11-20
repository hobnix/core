<script>
  // Add a server to the list: hs sys node plan|start add <name> <host> [--kind peer|vps|edge] [--port N]. Changes nothing on the other server;
  // the key and the line its owner has to allow come next (Nodes page, drawer of the new node).
  import CreateDialog from '../../shell/CreateDialog.svelte';
  import { Field, TextInput, Select, Muted } from '../../ui/index.js';

  let { onclose, ondone } = $props();

  let name = $state('');
  let host = $state('');
  let kind = $state('peer');
  let port = $state('');

  const args = () => {
    const n = name.trim();
    const h = host.trim();
    if (!n || !h) return null;
    const a = ['add', n, h, '--kind', kind];
    if (port.trim()) a.push('--port', port.trim());
    return a;
  };
  const kinds = [
    { id: 'peer', label: 'Another home server', hint: 'for example a relative\'s server; SSH user adminuser, port 22' },
    { id: 'edge', label: 'Edge node', hint: 'a public server of this repo (role edge); SSH user root, port 2222' },
    { id: 'vps', label: 'Proxyserver (old)', hint: 'the proxyserver of the old repo; SSH user root, port 2222' },
  ];
</script>

<CreateDialog title="Add a server" kicker="Add" area="node" {args} {onclose} {ondone}>
  {#snippet form()}
    <Field label="Name" help="Lower case letters, digits and dashes. It is the name in the address bar: /node/<name>.">
      <TextInput bind:value={name} placeholder="cousin" maxlength={31} autocomplete="off" spellcheck={false} />
    </Field>
    <Field label="Host name or address">
      <TextInput bind:value={host} placeholder="cousin-server.tail.ts.net" autocomplete="off" spellcheck={false} />
    </Field>
    <Field label="What it is" help={kinds.find((k) => k.id === kind)?.hint}>
      <Select bind:value={kind} options={kinds.map((k) => ({ value: k.id, label: k.label }))} />
    </Field>
    <Field label="SSH port (optional)">
      <TextInput bind:value={port} placeholder={kind === 'peer' ? '22' : '2222'} inputmode="numeric" maxlength={5} autocomplete="off" />
    </Field>
    <Muted as="div">Nothing changes on the other server. Next you make the key and give its owner one line to allow.</Muted>
  {/snippet}
</CreateDialog>
