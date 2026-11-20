<script>
  // The package builder, first slice (ADR 0020, issue #268): a form for the manifest of a new package and the server's verdict on it, live.
  // The form makes a package.toml text (builder.js); the page sends it to `hs sys pkg plan check-draft` (the checks of `hs pkg validate`) and shows
  // the findings. Nothing is saved or written: drafts, the code editor and the pull request / archive step are later steps of the ADR.
  import { plan } from '../api.js';
  import { ui } from '../ui.svelte.js';
  import { tr } from '../i18n.js';
  import PageHeader from '../shell/PageHeader.svelte';
  import Banner from '../ui/Banner.svelte';
  import Button from '../ui/Button.svelte';
  import Field from '../ui/Field.svelte';
  import TextInput from '../ui/TextInput.svelte';
  import Select from '../ui/Select.svelte';
  import Textarea from '../ui/Textarea.svelte';
  import { blank, manifestText, findingsOf, fieldOf, withKind, hasStoreFields, CATEGORIES } from './builder.js';

  let f = $state(blank());
  const text = $derived(manifestText(f));
  let found = $state([]);
  let state = $state('idle');               // idle | checking | valid | invalid | error
  let failure = $state('');
  let timer;
  let ctl;

  const check = async (t) => {
    ctl?.abort();
    ctl = new AbortController();
    state = 'checking';
    try {
      const r = await plan('pkg', ['check-draft'], undefined, undefined, ctl.signal, { manifest: t });
      found = findingsOf(r.findings);
      failure = '';
      state = r.status === 'ok' ? 'valid' : r.findings?.length ? 'invalid' : 'error';
      if (state === 'error') failure = r.reason || 'The draft could not be checked.';
    } catch (e) {
      if (e.name === 'AbortError') return;
      state = 'error';
      failure = e.message;
    }
  };
  // live: ask again 400 ms after the last keystroke
  $effect(() => {
    const t = text;
    clearTimeout(timer);
    timer = setTimeout(() => check(t), 400);
    return () => clearTimeout(timer);
  });

  const errors = $derived(found.filter((x) => x.level === 'error'));
  const forField = (name) => errors.filter((x) => fieldOf(x.where) === name);
  const setKind = (e) => { f = withKind(f, e.target.value); };
  const err = (name) => forField(name).map((x) => x.text).join(' ');
  const copy =() => navigator.clipboard?.writeText(text).catch(() => {});
</script>

<PageHeader title="Package builder" crumb={ui.host} sub="Write the manifest of a new app or extension; the server checks it as you type. Nothing is saved yet." />

<div class="grid">
  <form class="card" onsubmit={(e) => e.preventDefault()}>
    <Field label={tr('Kind')}>
      <Select value={f.kind} onchange={setKind} options={[{ value: 'recipe', label: tr('App (recipe)') }, { value: 'extension', label: tr('Extension') }, { value: 'capability', label: tr('Capability') }]} />
    </Field>
    {#each [['name', 'Name', 'my-app'], ['title', 'Title', 'What it is, in a few words'], ['version', 'Version', '0.1.0'], ['requires', 'Needs core', '>=1']] as [k, label, ph]}
      <Field label={tr(label)} error={err(k)}>
        <TextInput bind:value={f[k]} placeholder={ph} autocomplete="off" spellcheck={false} />
      </Field>
    {/each}
    <Field label={tr('For')}>
      <Select bind:value={f.audience} options={[{ value: 'generic', label: tr('Everyone (generic)') }, { value: 'personal', label: tr('One person (personal)') }]} />
    </Field>
    {#if f.kind === 'recipe'}
      <Field label={tr('Script')} error={err('script')}>
        <TextInput bind:value={f.script} autocomplete="off" spellcheck={false} />
      </Field>
    {/if}
    {#if hasStoreFields(f)}
      <Field label={tr('Description')} help={tr('One short paragraph for the store.')} error={err('description')}>
        <TextInput bind:value={f.description} />
      </Field>
      <Field label={tr('Description (German)')} error={err('descriptionDe')}>
        <TextInput bind:value={f.descriptionDe} />
      </Field>
      <Field label={tr('Icon')} help={tr('A Phosphor name such as ph:image. An SVG file is added to the package by hand.')} error={err('icon')}>
        <TextInput bind:value={f.icon} placeholder="ph:package" autocomplete="off" spellcheck={false} />
      </Field>
      <Field label={tr('Category')} error={err('category')}>
        <Select bind:value={f.category} options={CATEGORIES} />
      </Field>
      <Field label={tr('App version')} help={tr('The release of the app this package pins.')} error={err('appVersion')}>
        <TextInput bind:value={f.appVersion} autocomplete="off" spellcheck={false} />
      </Field>
    {/if}
    {#if f.kind === 'recipe'}
      <Field label={tr('Instances')} help={tr('One app, or several side by side under their own names.')}>
        <Select bind:value={f.instances} options={[{ value: 'one', label: tr('One') }, { value: 'many', label: tr('Many') }]} />
      </Field>
    {/if}
    <Field label={tr('Permissions')} help={tr('One per line, for example web.read or net:lan. Declared, not enforced (ADR 0014).')} error={err('permissions')}>
      <Textarea rows={3} bind:value={f.permissions} placeholder={'web.read\nnet:lan'} spellcheck={false} />
    </Field>
  </form>

  <div class="side">
    <div class="verdict" aria-live="polite">
      {#if state === 'checking' && !found.length}<span>{tr('Checking…')}</span>
      {:else if state === 'valid'}<Banner tone="ok">{tr('The manifest passes the checks.')}</Banner>
      {:else if state === 'invalid'}<Banner tone="bad">{errors.length} {tr(errors.length === 1 ? 'problem' : 'problems')}</Banner>
      {:else if state === 'error'}<Banner tone="warn">{failure}</Banner>{/if}
      {#each found.filter((x) => x.level !== 'error') as x}<Banner tone="info">{x.text}</Banner>{/each}
      {#each errors.filter((x) => !fieldOf(x.where)) as x}<Banner tone="bad">{x.text}</Banner>{/each}
    </div>
    <div class="card">
      <div class="head"><b>package.toml</b><Button size="sm" onclick={copy}>Copy</Button></div>
      <pre>{text}</pre>
    </div>
  </div>
</div>

<style>
  .grid { display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); gap: 16px; align-items: start; }
  @media (max-width: 800px) { .grid { grid-template-columns: 1fr; } }
  .card { display: flex; flex-direction: column; gap: 12px; padding: 16px; border: 1px solid var(--line); border-radius: var(--r); background: var(--panel); }
  .side { display: flex; flex-direction: column; gap: 12px; }
  .verdict { display: flex; flex-direction: column; gap: 8px; }
  .head { display: flex; justify-content: space-between; align-items: center; }
  pre { margin: 0; white-space: pre-wrap; word-break: break-word; font-family: var(--mono, monospace); font-size: 13px; }
</style>
