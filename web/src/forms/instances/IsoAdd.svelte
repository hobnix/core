<script>
  // Add an image: hs sys iso plan|start add <file-or-url> [--name <name.iso>] (--checksum <hex> | --no-checksum). The plan answers "needs checksum"
  // until one of the two is given; the download or copy is a background job (its progress is in the task list).
  import CreateDialog from '../../shell/CreateDialog.svelte';
  import { Field, TextInput, Segmented, Checkbox } from '../../ui/index.js';

  let { onclose, ondone } = $props();
  let kind = $state('url');
  let src = $state('');
  let name = $state('');
  let sum = $state('');
  let none = $state(false);

  const args = () => {
    const s = src.trim();
    if (!s) return null;
    const a = ['add', s];
    if (name.trim()) a.push('--name', name.trim());
    if (none) a.push('--no-checksum');
    else if (sum.trim()) a.push('--checksum', sum.trim());
    return a;
  };
  const plain = $derived(kind === 'url' && /^http:\/\//i.test(src.trim()));
</script>

<CreateDialog title="Add an ISO image" kicker="Add" area="iso" {args} {onclose} {ondone}>
  {#snippet form()}
    <Field label="Where is it">
      <Segmented bind:value={kind} label="Where is it" options={[{ value: 'url', label: 'From a URL' }, { value: 'path', label: 'A file on this server' }]} />
    </Field>
    <Field label={kind === 'url' ? 'URL' : 'Path of the file'} error={plain ? 'This is a plain HTTP address: the download can be changed on the way. Prefer HTTPS and check the checksum.' : ''}>
      <TextInput bind:value={src} placeholder={kind === 'url' ? 'https://cdimage.debian.org/.../debian-13-netinst.iso' : '/bulk/shares/isos/debian-13-netinst.iso'} autocomplete="off" spellcheck={false} />
    </Field>
    <Field label="Checksum (SHA-256 or SHA-512)" help="A wrong checksum deletes the file and fails the job, with both checksums shown. Without one nothing is verified.">
      <TextInput bind:value={sum} disabled={none} placeholder="from the download page" autocomplete="off" spellcheck={false} />
    </Field>
    <Checkbox bind:checked={none} label="There is no checksum: show me the computed one instead" />
    <Field label="Name in the library (optional)">
      <TextInput bind:value={name} placeholder="taken from the file name" autocomplete="off" spellcheck={false} />
    </Field>
  {/snippet}
</CreateDialog>
