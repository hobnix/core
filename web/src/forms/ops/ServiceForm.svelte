<script>
  // Describe a service (hs sys routes plan|start add <name> --port N --container C | --host H ...). Only the description is written; the route on the
  // reverse proxy is made by "Apply" on the Services page. public-ok is red: the typed word is the service name.
  // With `edit` (the name of a described service) the same form changes it: `hs sys routes plan|start edit <name> ...` sends every field, a field
  // left empty is cleared (--clear), what the form does not show (fqdn, scheme, health, other wants) stays in the file.
  import CreateDialog from '../../shell/CreateDialog.svelte';
  import { Field, TextInput, Select, Textarea, Checkbox } from '../../ui/index.js';
  import { poll, rows } from '../../data.svelte.js';

  let { onclose, ondone = () => {}, edit = '' } = $props();

  const cts = poll('/api/sys/ct/list', 15000);
  const instances = $derived(rows(cts).map((r) => r[0]));

  let name = $state('');
  let where = $state('container');
  let ct = $state('');
  let host = $state('');
  let port = $state('');
  let title = $state('');
  let names = $state('');
  let exposure = $state('private-ok');
  let paths = $state('');
  let blocked = $state('');
  let auth = $state(false);     // forward auth (authentik) in front of the service
  let wasAuth = false;
  let skip = $state('');        // paths that stay open without login
  let reqHeaders = $state('');  // one header per line, "Name: value"
  let resHeaders = $state('');
  let dashboard = $state(true);
  let proxied = $state(true);   // want reverse-proxy of the file, kept as it is

  // the facts of the service being edited: key, value rows (a dash is empty)
  const cur = poll(() => (edit ? `/api/sys/services/show/${encodeURIComponent(edit)}` : ''), 600000, 'services-list');
  let filled = false;
  $effect(() => {
    if (!edit || filled || !cur.loaded) return;
    const v = Object.fromEntries(rows(cur).map((r) => [r[0], r[1] === '-' ? '' : (r[1] ?? '')]));
    if (!v.name) return;
    filled = true;
    name = v.name; where = v.where || 'container';
    if (where === 'container') ct = v.machine; else host = v.machine;
    port = v.port; title = v.title; names = v.names === v.name ? '' : v.names;
    exposure = v.exposure || 'private-ok'; paths = v.public_paths.split(',').join(' ');
    blocked = v.blocked_paths.split(',').join(' '); skip = v.auth_skip.split(',').join(' ');
    auth = wasAuth = v.auth === 'authentik';
    reqHeaders = v.request_headers.split(' | ').join('\n'); resHeaders = v.response_headers.split(' | ').join('\n');
    const want = v.want.split(',');
    dashboard = want.includes('dashboard'); proxied = want.includes('reverse-proxy');
  });

  const args = () => {
    if (!/^[a-z0-9][a-z0-9-]{0,40}$/.test(name)) return null;
    if (edit && !filled) return null;
    if (!/^[0-9]{1,5}$/.test(port) || +port < 1 || +port > 65535) return null;
    const a = [edit ? 'edit' : 'add', name, '--port', port];
    if (where === 'container') { if (!ct) return null; a.push('--container', ct); }
    else { if (!/^[A-Za-z0-9][A-Za-z0-9._:-]{0,100}$/.test(host.trim())) return null; a.push('--host', host.trim()); }
    if (title.trim()) a.push('--title', title.trim());
    else if (edit) a.push('--clear', 'title');
    const n = names.replace(/\s+/g, '');
    if (n) { if (!/^[a-z0-9][a-z0-9,-]{0,100}$/.test(n)) return null; a.push('--names', n); }
    else if (edit) a.push('--clear', 'names');
    a.push('--exposure', exposure);
    const ps = paths.split(/[\s,]+/).filter(Boolean);
    for (const p of ps) {
      if (!/^\/[A-Za-z0-9._/-]{0,100}$/.test(p)) return null;
      a.push('--public-path', p);
    }
    if (!ps.length && edit) a.push('--clear', 'public-path');
    const list = (text, opt, clear, re, sep) => {
      const items = text.split(sep).map((x) => x.trim()).filter(Boolean);
      for (const x of items) { if (!re.test(x)) return false; a.push(opt, x); }
      if (!items.length && clear) a.push('--clear', clear);
      return true;
    };
    const pathRe = /^\/[A-Za-z0-9._/-]{0,100}$/, headRe = /^[A-Za-z0-9-]{1,64}: [ -~]{1,200}$/;
    if (!list(blocked, '--blocked-path', edit && 'blocked-path', pathRe, /[\s,]+/)) return null;
    if (auth) a.push('--auth', 'authentik');
    else if (edit && wasAuth) a.push('--auth', 'none');
    if (auth) { if (!list(skip, '--auth-skip', edit && 'auth-skip', pathRe, /[\s,]+/)) return null; }
    else if (edit) a.push('--clear', 'auth-skip');
    if (!list(reqHeaders, '--request-header', edit && 'request-header', headRe, '\n')) return null;
    if (!list(resHeaders, '--response-header', edit && 'response-header', headRe, '\n')) return null;
    if (edit) a.push('--want', [proxied && 'reverse-proxy', dashboard && 'dashboard'].filter(Boolean).join(',') || 'none');
    else a.push('--want', dashboard ? 'reverse-proxy,dashboard' : 'reverse-proxy');
    return a;
  };
</script>

<CreateDialog title={edit ? 'Change ' + edit : 'Describe a service'} kicker="Services" area="routes" {args} {onclose} {ondone}>
  {#snippet form()}
    <Field label="Name" id="sv-name">
      <TextInput bind:value={name} readonly={!!edit} placeholder="wiki" maxlength={41} autocomplete="off" />
    </Field>
    <Field label="Runs on" id="sv-where">
      <Select bind:value={where}>
        <option value="container">An instance of this server</option>
        <option value="host">Another machine (name or address)</option>
      </Select>
    </Field>
    {#if where === 'container'}
      <Field label="Instance" id="sv-ct">
        <Select bind:value={ct}>
          <option value="">Choose…</option>
          {#each instances as i}<option value={i}>{i}</option>{/each}
        </Select>
      </Field>
    {:else}
      <Field label="Host" id="sv-host">
        <TextInput bind:value={host} placeholder="10.10.95.40" autocomplete="off" />
      </Field>
    {/if}
    <Field label="Port" id="sv-port">
      <TextInput bind:value={port} placeholder="3000" inputmode="numeric" maxlength={5} autocomplete="off" />
    </Field>
    <Field label="Title (optional)" id="sv-title">
      <TextInput bind:value={title} placeholder="Wiki" maxlength={160} autocomplete="off" />
    </Field>
    <Field label="Host names (optional)" id="sv-names">
      <TextInput bind:value={names} placeholder="wiki,notes: the name of the service when empty" autocomplete="off" />
    </Field>
    <Field label="Exposure" id="sv-exp">
      <Select bind:value={exposure}>
        <option value="private-ok">private-ok: only inside (the default)</option>
        <option value="never-public">never-public: refused on a public proxy</option>
        <option value="public-ok">public-ok: may be put on the internet</option>
      </Select>
    </Field>
    <Field label="Public paths (optional)" id="sv-paths">
      <TextInput bind:value={paths} placeholder="/hook /api/public" autocomplete="off" />
    </Field>
    <Field label="Blocked paths (optional)" id="sv-blocked">
      <TextInput bind:value={blocked} placeholder="/admin /metrics" autocomplete="off" />
    </Field>
    <Checkbox bind:checked={auth} label="Login first (forward auth with authentik)" />
    {#if auth}
      <Field label="Paths without login (optional)" id="sv-skip">
        <TextInput bind:value={skip} placeholder="/hook /api/public" autocomplete="off" />
      </Field>
    {/if}
    <Field label="Request headers (optional, one per line)" id="sv-reqh">
      <Textarea rows={2} bind:value={reqHeaders} placeholder="X-Forwarded-Prefix: /wiki" />
    </Field>
    <Field label="Response headers (optional, one per line)" id="sv-resh">
      <Textarea rows={2} bind:value={resHeaders} placeholder="X-Frame-Options: SAMEORIGIN" />
    </Field>
    <Checkbox bind:checked={dashboard} label="Show a tile on the dashboard" />
  {/snippet}
</CreateDialog>

<style>
</style>
