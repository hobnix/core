<script>
  // Bind storage to an instance: `ct <name> add-storage --kind fast|shares|sensitive --name <storage> --path <inside> [--readonly] [--as uid:gid]`
  import CreateDialog from '../../shell/CreateDialog.svelte';
  import { Field, TextInput, Segmented, Checkbox } from '../../ui/index.js';

  let { ct, ondone = () => {} } = $props();
  let kind = $state('shares');
  let sname = $state('');
  let path = $state('');
  let readonly = $state(false);
  let as = $state('');

  const kinds = [{ value: 'shares', label: 'Share' }, { value: 'sensitive', label: 'Sensitive share' }, { value: 'fast', label: 'Fast volume' }];
  const args = () => {
    if (!sname.trim() || !path.trim()) return null;
    const a = [ct, 'add-storage', '--kind', kind, '--name', sname.trim(), '--path', path.trim()];
    if (readonly) a.push('--readonly');
    if (as.trim()) a.push('--as', as.trim());
    return a;
  };
</script>

<CreateDialog kicker="Storage" title={`Bind storage to ${ct}`} area="ct" {args} {ondone}>
  {#snippet form()}
    <Field label="Kind"><Segmented bind:value={kind} label="Kind" options={kinds} /></Field>
    <Field label={kind === 'fast' ? 'Volume name' : 'Share name'}><TextInput bind:value={sname} placeholder="media" autocomplete="off" spellcheck={false} /></Field>
    <Field label="Path inside the instance"><TextInput bind:value={path} placeholder="/media" autocomplete="off" spellcheck={false} /></Field>
    <Checkbox bind:checked={readonly} label="Read only" />
    <Field label="App user inside (uid:gid, optional)"><TextInput bind:value={as} placeholder="1000:1000" autocomplete="off" spellcheck={false} /></Field>
  {/snippet}
</CreateDialog>
