<script>
  import { P, nodePath } from '../paths.js';
  import { route, setLocalNode, go } from '../route.svelte.js';
  import { poll, rows, prefetch, refresh, touch, clearPollCache, cacheSession } from '../data.svelte.js';
  import TopBar from './TopBar.svelte';
  import Tree from './Tree.svelte';
  import BottomPanel from './BottomPanel.svelte';
  import PageFrame from './PageFrame.svelte';
  import NodeProbe from './NodeProbe.svelte';
  import PlanDialog from './PlanDialog.svelte';
  import Toast from '../ui/Toast.svelte';
  import JobAsks from './JobAsks.svelte';
  import Skeleton from '../ui/Skeleton.svelte';
  import { readsFor, fieldReads } from '../readsfor.js';
  import { lockGate } from '../lockgate.js';
  import { ui } from '../ui.svelte.js';
  import { canSee } from '../roles.js';
  import { pools, loadPools, poolOfRole } from '../pools.svelte.js';
  import { changes, startChanges } from '../changes.svelte.js';
  import { treeMeta } from '../pages/proxy/status.js';
  import { treeMeta as dockerTree, dockerChildren } from '../pages/docker/health.js';
  import { tree } from '../nav.js';
  import Banner from '../ui/Banner.svelte';
  import { indexWarning } from '../pages/pkgindex.js';
  import { VPS_NODE } from '../redirects.js';

  let { user, onsignout } = $props();

  // below 860 px the tree column is a slide-in drawer; the menu button in the top bar opens it, and a page change closes it again
  let navOpen = $state(false);
  $effect(() => { route.full; navOpen = false; });

  // the one document every page header shares (also read by the Summary: the backend answers both from one cached call)
  const deck = poll('/api/sys/deck', 5000);
  const locked = $derived(!!deck.data?.locked);
  // this node's name: the session answer says it (features.host), the status document too once it arrived
  const host = $derived(ui.features.host ?? deck.data?.host ?? '');
  $effect(() => { if (host) { ui.host = host; setLocalNode(host); } });

  // entries of the changelog this user has not seen (the badge of What's new; the Summary shows a banner); looked at again every five minutes
  startChanges();

  // the session already names a domain account as HOMEnna
  const who = $derived(user.user);

  // The right-hand notes of the tree rows. Each is read only where the answer exists; storage rows stay quiet while it is locked.
  const status = poll('/api/sys/status', 30000);
  const disks = poll(() => (locked ? '' : '/api/sys/monitor/disks'), 30000, 'monitor-disks');
  const shares = poll(() => (locked ? '' : '/api/sys/shares/overview'), 30000, 'shares-overview');
  const cts = poll(() => (locked ? '' : '/api/sys/ct/list'), 30000);
  // the rows of the identity and vault pages are admin rows: a lower role does not ask (the server would answer 403); its pages are greyed in the tree and never opened
  const admin = $derived(ui.role === 'admin');
  const users = poll(() => (locked || !admin ? '' : '/api/sys/users/list'), 60000);
  const groups = poll(() => (locked || !admin ? '' : '/api/sys/users/groups'), 60000);
  const vault = poll(() => (locked || !admin ? '' : '/api/sys/vault/list'), 60000, 'vault-list');
  // Docker is on but something it needs is missing (the share apps, its mount): a dot on Apps & VMs, the rows that need Docker dimmed
  const dockerOn = $derived(Array.isArray(ui.features.capabilities) && ui.features.capabilities.includes('docker'));
  const dockerHealth = poll(() => (locked || !dockerOn ? '' : '/api/sys/docker/health'), 30000);

  // each time the deck says the storage is open: read what the main pages show first, while the browser is idle (the answers land in poll()'s cache).
  // A lock drops that cache, so the next unlock reads anew
  const gate = lockGate(clearPollCache, () => {
    // first, all at once: what the pickers of the dialogs list (who wants one of these while it runs joins it, api.js)
    touch(fieldReads(ui.role, ui.features.capabilities));
    // what the pages read first, one after the other while the browser is idle: the first click on any of them finds its data (the pools first: the data pool is one of them).
    // loadPools(true): the pool store would else keep the rows from before a lock (the read of touch() is joined)
    const asked = cacheSession();
    loadPools(true).then(() => {
      if (asked !== cacheSession()) return;   // locked or signed out meanwhile
      const pages = [P.appsGroup, '/storage/shares', poolOfRole('data') ? `/storage/pools/${poolOfRole('data')}` : '/storage/pools', '/storage/disks', P.health, P.backup, '/network', P.users,
        P.apps, P.services, '/storage/vault', '/storage/encryption', P.hardware, P.expiry];
      prefetch([...new Set([...pages.filter((pg) => canSee(ui.role, pg)).flatMap((p) => readsFor(p, ui.features.extensions, ui.features.live, pools.loaded ? pools.rows : undefined, ui.features.capabilities)),
        '/api/sys/jobs/running', '/api/sys/unifi/networks', '/api/sys/unifi/clients'])]);
    });
  });
  $effect(() => { gate(!!deck.data, locked); });   // no answer yet = the lock state is not known

  // the proxyserver node: the VPS status document (404 = proxyStatusUrl not set, 502 = not reachable); it drives the dots of its tree rows
  const prox = poll('/api/proxy/status', 15000);
  const proxState = $derived(prox.data ? 'ok' : !prox.loaded ? 'loading' : prox.error?.status === 404 ? 'off' : 'down');
  // new commits upstream (refs fetched earlier by hs update; the read never fetches): the count tag of the Update button
  const upd = poll(() => (locked || !admin ? '' : '/api/sys/system/updates'), 60000, 'system-updates');
  const pending = $derived(Number(rows(upd).find((r) => r[0] === 'behind')?.[1]) || 0);

  // the package index could not be fetched for days, or it expired (hs sys pkg index, kept by the timer hs-pkg-refresh); follows the event index.changed|failed
  const pkgIndex = poll(() => (locked || !admin ? '' : '/api/sys/pkg/index'), 300000, 'pkg-index');
  const indexWarn = $derived(indexWarning(rows(pkgIndex)));

  // ── the servers: this one first, then the rows of `hs node list` (name kind host port source key), plus the implicit proxyserver of the old vps part
  const nodeList = poll(() => (admin ? '/api/sys/node/list' : ''), 30000);
  const reports = $state({});                              // name -> { dot, state } from the NodeProbe of a remote node
  const report = (name, dot, state, extra = {}) => {
    const r = reports[name];
    if (!r || r.dot.state !== dot.state || r.dot.title !== dot.title || r.state !== state || r.doc?.time !== extra.doc?.time || r.why !== (extra.why ?? '')) reports[name] = { dot, state, caps: extra.caps ?? null, doc: extra.doc ?? null, why: extra.why ?? '' };
  };
  const vpsOn = $derived(Array.isArray(ui.features.capabilities) ? ui.features.capabilities.includes('vps') : !!ui.features.vps);
  const remotes = $derived.by(() => {
    const out = rows(nodeList).map((r) => ({ name: r[0], kind: r[1], host: r[2], key: r[5] ?? 'ok' }));
    if (vpsOn && !out.some((n) => n.name === VPS_NODE)) out.push({ name: VPS_NODE, kind: 'vps', host: '', key: 'ok' });
    return out.filter((n) => n.name !== host);
  });
  const nodes = $derived.by(() => {
    const list = [{ name: host || '…', kind: 'main', local: true, state: 'ok', dot: locked ? { state: 'warn', title: 'storage locked' } : deck.data ? { state: 'ok', title: 'online' } : { state: 'off', title: deck.error ? 'not reachable' : 'loading' } }];
    for (const n of remotes) {
      let dot, state = 'loading';
      if (n.key === 'missing' || n.key === 'locked') { dot = { state: 'off', title: n.key === 'locked' ? 'key locked (vault closed)' : 'no key yet' }; state = 'off'; }
      else if (n.name === VPS_NODE) {
        const d = treeMeta(proxState, prox.data)['/']?.dot;
        state = proxState === 'down' ? 'down' : proxState;
        dot = proxState === 'down' ? { state: 'bad', title: 'does not answer' } : proxState === 'off' ? { state: 'off', title: 'not set up' } : d ? { state: d, title: d === 'ok' ? 'online' : 'needs a look' } : { state: 'off', title: 'reading' };
      } else { const r = reports[n.name]; dot = r?.dot ?? { state: 'off', title: 'reading' }; state = r?.state ?? 'loading'; }
      const rep = n.name === VPS_NODE ? null : reports[n.name];
      list.push({ name: n.name, kind: n.kind, host: n.host, local: false, state, dot, caps: rep?.caps ?? null, why: rep?.why ?? (n.name === VPS_NODE && proxState === 'down' ? 'The status document of the proxyserver is not reachable over Tailscale.' : ''),
        retry: () => refresh([n.name === VPS_NODE ? '/api/proxy/status' : `/api/sys/node/status/${encodeURIComponent(n.name)}`]) });
    }
    return list;
  });
  const current = $derived(nodes.find((n) => n.name === route.node) ?? { name: route.node, kind: 'peer', local: false, state: 'loading', dot: { state: 'off', title: 'unknown' } });
  const known = $derived(!route.node || nodes.some((n) => n.name === route.node));

  const meta = $derived.by(() => {
    const m = {};
    const d = deck.data;
    for (const p of pools.rows.map((r) => r.name)) {
      const pl = d?.pools?.[p];
      if (pl?.size > 0) m[`/storage/pools/${p}`] = { text: `${Math.round((pl.used / pl.size) * 100)} %` };
    }
    // monitor disks: name, bytes, SSD/HDD, role, temp, health, ...; the role of a pool member starts with the pool name ("bulk data-01" for SnapRAID)
    const dl = rows(disks);
    if (disks.loaded && dl.length) {
      let watchAll = 0;
      for (const p of pools.rows.map((r) => r.name)) {
        const mine = dl.filter((r) => String(r[3]).split(' ')[0] === p);
        watchAll += mine.filter((r) => /WATCH|WARN|BAD|FAIL/i.test(r[5])).length;
      }
      m['/storage/disks'] = watchAll ? { text: `${watchAll} watch`, warn: true } : { text: String(dl.length) };
    }
    if (changes.count) m[P.whatsNew] = { text: `${changes.count} new` };
    const sl = rows(shares).filter((r) => r[1] !== 'other');
    if (sl.length) m['/storage/shares'] = { text: String(sl.length) };
    const cl = rows(cts);
    if (cl.length) m[P.appsGroup] = { text: `${cl.filter((r) => /^running$/i.test(r[2])).length}/${cl.length}` };
    if (rows(groups).length) m[P.groups] = { text: String(rows(groups).length) };
    if (rows(users).length) m[P.users] = { text: String(rows(users).length) };
    if (d) m['/storage/encryption'] = locked ? { text: 'locked', warn: true } : d.encryption && d.encryption !== 'none' ? { text: 'open' } : null;
    if (locked) m['/storage/vault'] = { text: 'locked', warn: true };
    else if (vault.loaded && rows(vault).length) m['/storage/vault'] = { text: `${rows(vault).length} items` };
    // status: backup <ok|failed|...> <age in seconds or ->
    const b = rows(status).find((r) => r[0] === 'backup');
    if (b && /^[0-9]+$/.test(b[2] ?? '')) {
      const h = Math.floor(Number(b[2]) / 3600);
      m[P.backup] = { text: h < 1 ? '< 1 h' : h < 48 ? `${h} h` : `${Math.floor(h / 24)} d`, warn: b[1] !== 'ok' };
    }
    if (dockerHealth.loaded && dockerOn) for (const [p, v] of Object.entries(dockerTree(rows(dockerHealth), dockerChildren(tree)))) m[p] = { ...m[p], ...v };   // Apps & VMs keeps its count
    if (d?.problems > 0) m[P.health] = { text: String(d.problems), warn: true };
    // a remote node's rows are keyed "<node>:<inner path>"
    for (const [p, v] of Object.entries(treeMeta(proxState, prox.data))) m[`${VPS_NODE}:${p}`] = v;
    for (const [nm, r] of Object.entries(reports)) {
      if (nm === VPS_NODE || !r.doc || remotes.find((x) => x.name === nm)?.kind !== 'edge') continue;
      for (const [p, v] of Object.entries(treeMeta('ok', r.doc))) m[`${nm}:${p}`] = v;
    }
    return m;
  });
</script>

<TopBar host={host || '…'} node={route.node || host} {nodes} {pending} {locked} user={who} {onsignout} menuOpen={navOpen} onmenu={() => (navOpen = !navOpen)} />
<svelte:window onkeydown={(e) => e.key === 'Escape' && (navOpen = false)} />
{#each remotes.filter((n) => n.name !== VPS_NODE && n.key === 'ok') as n (n.name)}<NodeProbe name={n.name} onstate={report} />{/each}
<div class="body">
  <nav class="side" class:open={navOpen} aria-label="Servers and pages"><Tree {nodes} {locked} {meta} /></nav>
  {#if navOpen}<button class="treescrim" aria-label="Close the resource tree" onclick={() => (navOpen = false)}></button>{/if}
  <main class="main gridbg">
    <div class="wrap">
      {#if indexWarn}<Banner tone={indexWarn.tone}>{indexWarn.text}</Banner>{/if}
      {#if !host || !route.node}
        <Skeleton lines={5} height={16} gap={16} />
      {:else if !known && nodeList.loaded}
        <div class="card"><b>There is no server called {route.node}.</b>
          <span class="text-muted">The addresses of a server are /node/&lt;name&gt;/... Go to <button class="link-btn" onclick={() => go(nodePath(host))}>{host}</button>.</span></div>
      {:else}
        <PageFrame {deck} {meta} node={current} {locked} />
      {/if}
    </div>
  </main>
</div>
<BottomPanel user={who} />
{#if ui.dialog}<PlanDialog dialog={ui.dialog} />{/if}
{#if ui.create}{@const Form = ui.create.component}<Form {...ui.create.props} />{/if}
<Toast />
<JobAsks />

<style>
  .body { position: relative; flex: 1; min-height: 0; display: flex; }
  .side { width: 276px; flex: none; display: flex; flex-direction: column; min-height: 0; background: var(--panel); border-right: 1px solid var(--line); }
  .main { --sticky-top: -26px; position: relative; flex: 1; min-width: 0; overflow: auto; scrollbar-gutter: stable; padding: 26px 28px 36px; }
  .wrap { max-width: 1900px; margin: 0 auto; display: flex; flex-direction: column; gap: 14px; min-width: 0; }
  .treescrim { display: none; }
  @media (max-width: 860px) {
    .side { position: absolute; z-index: 15; top: 0; bottom: 0; left: 0; width: min(300px, 86vw); transform: translateX(-105%); transition: transform 0.2s; box-shadow: var(--shadow); }
    .side.open { transform: none; }
    .treescrim { display: block; position: absolute; inset: 0; z-index: 14; border: 0; background: var(--scrim); }
    .main { padding: 18px 14px 28px; --sticky-top: -18px; overflow-x: hidden; }
    .main :global(> *) { min-width: 0; max-width: 100%; }
  }
  @media (prefers-reduced-motion: reduce) { .side { transition: none; } }
</style>
