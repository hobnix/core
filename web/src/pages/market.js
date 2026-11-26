// The Marketplace as a store (#474): the rows of the package reads turned into cards, tabs, filters and the package page. Pure, no Svelte:
// tests/web-market.mjs runs it in plain node.
//
// Everything a repository says about a package is NOT trusted: names are checked against the patterns of the server, an icon is a Phosphor
// name or the address of the asset endpoint (which checks again), text is only ever rendered as text, a link is only http or https.

// the fixed category list (config/package-categories.toml `ids`); an id the list does not know is "Other"
export const CATEGORIES = [
  ['media', 'Media'], ['files', 'Files'], ['network', 'Network'], ['home', 'Home'], ['games', 'Games'], ['tools', 'Tools'], ['dev', 'Development'],
  ['admin', 'Administration'],
];
const CATEGORY = new Map(CATEGORIES);
export const categoryLabel = (id) => CATEGORY.get(id) ?? 'Other';

export const NAME = /^[a-z][a-z0-9-]{0,40}$/;        // a package and a repository (scripts/lib/pkg_index.py)
const ICON_NAME = /^ph:([a-z0-9]+(-[a-z0-9]+)*)$/;     // scripts/lib/pkg_app.py ICON_NAME
const ICON_FILE = /^[A-Za-z0-9_-][A-Za-z0-9._-]{0,79}\.svg$/;
const SHOT = /^[A-Za-z0-9_-][A-Za-z0-9._-]{0,79}(\/[A-Za-z0-9_-][A-Za-z0-9._-]{0,79}){0,3}\.(png|webp)$/;
const DATE = /^\d{4}-\d\d-\d\d$/;
const dash = (v) => (v === undefined || v === null || v === '-' ? '' : String(v));

// hs sys pkg market: name, kind, repo, available, installed (- = none), state (new|current|update|waits|orphan), core, audience, title
export function parseMarket(rows) {
  return (rows ?? []).map((r) => ({
    name: r[0], kind: r[1], repo: r[2], avail: dash(r[3]), inst: dash(r[4]), state: r[5], core: r[6] === 'yes', title: dash(r[8]),
  }));
}

// hs sys pkg repos: name, address, signed|unsigned, default|added
export function parseRepos(rows) {
  return (rows ?? []).map((r) => ({ name: r[0], url: r[1], signed: r[2] === 'signed', from: r[3] }));
}

// hs sys pkg cards: name, repo, category, icon, verified -> Map `<repo>/<name>` -> { category, icon, verified }
export function parseCards(rows) {
  return new Map((rows ?? []).map((r) => [`${r[1]}/${r[0]}`, {
    category: dash(r[2]), icon: dash(r[3]), verified: DATE.test(r[4] ?? '') ? r[4] : '',
  }]));
}

// Who vouches for a package (#477), the `level` of the trust chip: official only for the official repository as the core configures it
// (`official`, a default row of config/package-repos.toml) AND signed; any repository added on this server is never official, whatever its name
// (the server refuses a second `official` anyway); an unsigned one says so. '' while the repository is not known (the chip is left out).
export const OFFICIAL_REPO = 'official';
export function trustOf(repo, repos) {
  const r = (repos ?? []).find((x) => x.name === repo);
  if (!r) return '';
  if (!r.signed) return 'unsigned';
  return r.name === OFFICIAL_REPO && r.from === 'default' ? 'official' : 'community';
}

// the tested line of a card and the page. Only the official signed repository has test days (the server passes no other on, hs sys pkg
// cards): there it is the day or "not tested"; any other repository has no Hobnix test date, which says nothing either way.
export const testedText = (verified, trust = 'official') => (trust !== 'official' ? 'No Hobnix test date'
  : verified ? `Tested on a real server on ${verified}` : 'Not tested on a real server');

// the address of a package picture (/api/pkg/asset/<repo>/<name>/<file>), '' for anything the server would refuse anyway
export function assetUrl(repo, name, file) {
  if (!NAME.test(repo ?? '') || !NAME.test(name ?? '') || !(ICON_FILE.test(file ?? '') || SHOT.test(file ?? ''))) return '';
  return `/api/pkg/asset/${repo}/${name}/${file.split('/').map(encodeURIComponent).join('/')}`;
}

// what the icon tile draws: { icon } a Phosphor name, { src } a picture of the package; the kind's own icon when there is neither
export function iconOf(p, icon) {
  const own = p.kind === 'extension' ? 'puzzle-piece' : p.kind === 'capability' ? 'plug' : p.kind === 'blueprint' ? 'stack' : 'package';
  const m = ICON_NAME.exec(icon ?? '');
  if (m) return { icon: m[1], src: '' };
  const src = ICON_FILE.test(icon ?? '') ? assetUrl(p.repo, p.name, icon) : '';
  return { icon: own, src };
}

// the store rows: market rows with their card data. A package with two rows (two repositories) keeps both: the repository is in its address.
export function storeRows(market, cards) {
  return parseMarket(market).filter((p) => NAME.test(p.name) && NAME.test(p.repo)).map((p) => {
    const c = cards.get(`${p.repo}/${p.name}`) ?? { category: '', icon: '', verified: '' };
    return { ...p, ...c, ...iconOf(p, c.icon), installed: p.state !== 'new' && p.state !== 'waits' };
  });
}

// the tabs of the page and which rows each one shows. Apps first; extensions, capabilities and blueprints are Add-ons.
export const isApp = (p) => p.kind === 'recipe';
export const TABS = ['apps', 'addons', 'installed', 'updates', 'advanced'];
export function rowsOf(tab, rows) {
  if (tab === 'apps') return rows.filter(isApp);
  if (tab === 'addons') return rows.filter((p) => !isApp(p));
  if (tab === 'installed') return rows.filter((p) => p.installed);
  if (tab === 'updates') return rows.filter((p) => p.state === 'update');
  return [];
}
export function tabsOf(rows) {
  const n = (t) => rowsOf(t, rows).length;
  return [
    { id: 'apps', label: 'Apps' }, { id: 'addons', label: 'Add-ons' },
    { id: 'installed', label: `Installed (${n('installed')})` }, { id: 'updates', label: `Updates (${n('updates')})` },
    { id: 'advanced', label: 'Advanced' },
  ];
}

// the categories that have a row, in the order of the list, Other last: [{ value, label, count }] with All first
export function categoriesOf(rows) {
  const count = new Map();
  for (const p of rows) { const id = CATEGORY.has(p.category) ? p.category : 'other'; count.set(id, (count.get(id) ?? 0) + 1); }
  const out = [{ value: 'all', label: 'All', count: rows.length }];
  for (const [id, label] of CATEGORIES) if (count.has(id)) out.push({ value: id, label, count: count.get(id) });
  if (count.has('other')) out.push({ value: 'other', label: 'Other', count: count.get('other') });
  return out;
}

// ═══ fits this server (#793) ═══
// hs sys pkg fit: name, repo, verdict, check, level, need, have, total (memory and disk in bytes, - = not known), only for apps that are not
// installed -> Map `<repo>/<name>` -> { verdict, checks: [{ check, level, need, have, total }] }. A word this page does not know is "unknown".
const VERDICTS = ['fits', 'note', 'no', 'unstated', 'unknown'];
const LEVELS = ['ok', 'note', 'no', 'unstated', 'unknown'];
export function parseFit(rows) {
  const out = new Map();
  for (const r of rows ?? []) {
    const key = `${r[1]}/${r[0]}`;
    const f = out.get(key) ?? { verdict: VERDICTS.includes(r[2]) ? r[2] : 'unknown', checks: [] };
    f.checks.push({ check: dash(r[3]), level: LEVELS.includes(r[4]) ? r[4] : 'unknown', need: dash(r[5]), have: dash(r[6]), total: dash(r[7]) });
    out.set(key, f);
  }
  return out;
}

const bytesOf = (v) => (/^\d{1,18}$/.test(v) ? Number(v) : null);
// bytes the way "What it needs and uses" counts them (1 GB = 1024 MB, like the memory limit of a container)
export function binSize(v) {
  if (v >= 1024 ** 4) return `${+(v / 1024 ** 4).toFixed(1)} TB`;
  if (v >= 1024 ** 3) return `${+(v / 1024 ** 3).toFixed(1)} GB`;
  return `${Math.round(v / 1024 ** 2)} MB`;
}

// the verdict in words. With memory or disk not stated, "fits" says that it is only about what the package states.
export function fitLabel(f) {
  const part = f.checks.some((c) => (c.check === 'memory' || c.check === 'disk') && c.level === 'unstated');
  if (f.verdict === 'fits') return part ? 'Fits what it states' : 'Fits this server';
  if (f.verdict === 'note') return part ? 'Fits what it states, with a note' : 'Fits, with a note';
  if (f.verdict === 'no') return 'Does not fit this server';
  if (f.verdict === 'unstated') return 'Needs not stated';
  return 'Fit could not be checked';
}

// one check as a sentence: what the package says of itself, next to this server now
export function fitText(c) {
  const need = bytesOf(c.need), have = bytesOf(c.have), total = bytesOf(c.total);
  if (c.check === 'core') return 'This release needs a newer Hobnix: update the server first.';
  if (c.check === 'memory') {
    if (c.level === 'unstated') return 'Memory: the package does not state how much it uses.';
    if (c.level === 'unknown' || need === null || have === null || total === null) return 'Memory: could not be checked.';
    if (c.level === 'no') return `Memory: it says it uses ${binSize(need)}, more than this server has in total (${binSize(total)}).`;
    if (c.level === 'note') return `Memory: it says it uses ${binSize(need)}, more than the ${binSize(have)} free right now (${binSize(total)} in total). It may be slow or not start. With ZFS, part of the used memory is a file cache that is given back when needed.`;
    return `Memory: it says it uses ${binSize(need)}; ${binSize(have)} of ${binSize(total)} is free right now.`;
  }
  if (c.check === 'disk') {
    if (c.level === 'unstated') return 'Disk: the package does not state how much it uses.';
    if (c.level === 'unknown' || need === null || have === null) return 'Disk: could not be checked.';
    if (c.level === 'no') return `Disk: it says it uses ${binSize(need)}; only ${binSize(have)} is free where the disk of a new container goes.`;
    return `Disk: it says it uses ${binSize(need)}; ${binSize(have)} is free where the disk of a new container goes.`;
  }
  if (c.check === 'gpu') {
    if (c.level === 'ok') return 'Graphics card: it can use one, and this server has an NVIDIA card.';
    if (c.have === 'other') return 'Graphics card: it can use one. This server has one that is not from NVIDIA; the package does not say whether it can use that one.';
    if (c.have === 'none') return 'Graphics card: it can use one, and none was found on this server.';
    return 'Graphics card: it can use one; whether this server has one could not be checked.';
  }
  if (c.check === 'share') return 'Share: it works with a share. It uses an existing one or makes its own; the package does not name one.';
  if (c.check === 'docker' || c.check === 'tailscale') {
    const name = c.check === 'docker' ? 'Docker' : 'Tailscale';
    if (c.level === 'ok') return `${name}: it needs it, and it is set up.`;
    if (c.have !== 'missing') return `${name}: it needs it; whether it is set up could not be checked.`;
    return c.check === 'docker' ? 'Docker: not set up yet. The install sets it up first.' : 'Tailscale: off. The install switches it on and rebuilds the server.';
  }
  return `It needs "${c.need}", which this server does not know how to provide.`;
}

// the few words under the chip of a card: the first thing that is in the way, or the first note
const SHORT = {
  core: () => 'needs a newer Hobnix', memory: (c) => (c.level === 'no' ? 'more memory than the server has' : 'more memory than is free now'),
  disk: () => 'not enough free disk space',
  gpu: (c) => (c.have === 'none' ? 'no graphics card found' : c.have === 'other' ? 'graphics card may not be usable' : 'graphics card not checked'),
  docker: (c) => (c.have === 'missing' ? 'sets up Docker first' : 'Docker not checked'),
  tailscale: (c) => (c.have === 'missing' ? 'switches on Tailscale and rebuilds' : 'Tailscale not checked'),
};
export function fitReason(f) {
  const want = f.verdict === 'no' ? ['no'] : f.verdict === 'note' ? ['note', 'unknown'] : [];
  const c = f.checks.find((x) => want.includes(x.level));
  if (!c) return '';
  return Object.hasOwn(SHORT, c.check) ? SHORT[c.check](c) : `needs "${c.need}"`;
}

// the filter "Fits this server": fits and fits with a note. Not stated and not checked never count as fitting.
export const fitsServer = (f) => f?.verdict === 'fits' || f?.verdict === 'note';

// what the filter leaves out of `rows`, in words ('' when nothing)
export function hiddenByFit(rows, fit) {
  const n = { no: 0, unstated: 0, unknown: 0, installed: 0 };
  for (const p of rows) {
    const f = fit.get(`${p.repo}/${p.name}`);
    if (!fitsServer(f)) n[f ? f.verdict : p.installed ? 'installed' : 'unknown']++;
  }
  const words = [
    [n.no, 'does not fit', 'do not fit'], [n.unstated, 'does not state its needs', 'do not state their needs'],
    [n.unknown, 'could not be checked', 'could not be checked'], [n.installed, 'is installed', 'are installed'],
  ].filter(([c]) => c).map(([c, one, many]) => `${c} ${c === 1 ? one : many}`);
  return words.length ? `Hidden: ${words.join(', ')}.` : '';
}

// search over name, title and category; `category` is an id, 'other' or 'all'; `fit` (the Map of parseFit) keeps what fits. Apps sort by name.
export function filterRows(rows, { q = '', category = 'all', fit = null } = {}) {
  const words = q.trim().toLowerCase().split(/\s+/).filter(Boolean);
  return rows.filter((p) => (category === 'all' || (category === 'other' ? !CATEGORY.has(p.category) : p.category === category))
    && (!fit || fitsServer(fit.get(`${p.repo}/${p.name}`)))
    && words.every((w) => `${p.name} ${p.title} ${categoryLabel(p.category)}`.toLowerCase().includes(w)))
    .sort((a, b) => a.name.localeCompare(b.name) || a.repo.localeCompare(b.repo));
}

// the one word for a kind
export const kindLabel = (k) => (k === 'recipe' ? 'App' : k === 'extension' ? 'Extension' : k === 'capability' ? 'Capability' : k === 'blueprint' ? 'Blueprint' : 'Package');

// the state line of a card: installed version, the update, or what keeps it from being installed
export function stateLine(p) {
  if (p.state === 'new') return `Version ${p.avail}`;
  if (p.state === 'current') return `Installed, version ${p.inst}`;
  if (p.state === 'update') return `Installed ${p.inst}, ${p.avail} is out`;
  if (p.state === 'waits') return `Version ${p.avail} needs a newer Hobnix: update the server first`;
  return 'Installed, its repository is gone';
}

// The buttons of a card and of the package page, at most two: [{ id, label, primary, icon, reason }]. An installed app shows Open and Manage
// instead of Install; Open is off (with its reason) while no address of the app is known. `open`: where Open goes, '' = nowhere.
export function cardActions(p, open = '') {
  if (p.state === 'new') return [{ id: 'install', label: 'Install', primary: true, icon: 'download-simple' }];
  if (p.state === 'waits') return [{ id: 'install', label: 'Install', primary: true, icon: 'download-simple', reason: 'This release needs a newer Hobnix: update the server first' }];
  const manage = { id: 'manage', label: 'Manage', primary: false, icon: 'gear-six' };
  if (p.state === 'update') return [{ id: 'update', label: 'Update', primary: true, icon: 'arrows-clockwise' }, manage];
  if (isApp(p)) return [{ id: 'open', label: 'Open', primary: true, icon: 'arrow-square-out', reason: open ? '' : 'No address of this app is known yet (Network > Services)' }, manage];
  return [manage];
}

// only an http or https address is a link; anything else (javascript:, data:, a bare word) is shown as text or not at all
export function safeLink(url) {
  const s = String(url ?? '').trim();
  if (!/^https?:\/\/[^\s"'<>\\]+$/i.test(s)) return '';
  try { const u = new URL(s); return u.protocol === 'http:' || u.protocol === 'https:' ? u.href : ''; } catch { return ''; }
}

// Where Open goes for an installed app: the dashboard link of a service in one of its instances (sys services app: name, container, ...;
// sys services tiles: group, title, link, description, icon, name), else '' (the page of the app in this interface is the caller's choice).
export function openHref(instances, svcRows, tileRows) {
  const inst = new Set(instances ?? []);
  const names = new Set((svcRows ?? []).filter((r) => inst.has(r[1])).map((r) => r[0]));
  for (const t of tileRows ?? []) if (names.has(t[5])) { const l = safeLink(t[2]); if (l) return l; }
  return '';
}

// hs sys pkg show: key TAB value lines -> one object; repeated keys (screenshot, route, step, ask) are lists. status refused carries the reason.
export function parseShow(rows) {
  const o = { screenshots: [], routes: [], steps: [], asks: 0 };
  for (const r of rows ?? []) {
    const [k, ...v] = r;
    if (k === 'screenshot') { if (SHOT.test(v[0] ?? '')) o.screenshots.push(v[0]); }
    else if (k === 'route') o.routes.push({ name: v[0], port: dash(v[1]), scheme: dash(v[2]), exposure: dash(v[3]), main: v[4] === 'yes' });
    else if (k === 'step') o.steps.push({ id: v[0], text: dash(v[1]) });
    else if (k === 'ask') o.asks++;
    else if (k !== 'slot_off') o[k] = dash(v[0]);
  }
  const list = (s) => (s ? s.split(',').filter(Boolean) : []);
  return { ...o, needs: list(o.needs), ports: list(o.ports), upstream: safeLink(o.upstream), refused: o.status === 'refused' };
}

// hs sys pkg history: `history TAB index|none`, then `version` TAB version, date, current|older, withdrawn, reason, changes ->
// { source: 'index' | 'none' | '' (not read), versions: [{ version, date, current, withdrawn, reason, changes }] }. The texts come from a
// repository: they are drawn as text, without the invisible format characters that reorder a line. `date` keeps the day only.
const SEMVER = /^\d{1,9}\.\d{1,9}\.\d{1,9}$/;
const plain = (v) => dash(v).replace(/\p{Cf}/gu, '');
export function parseHistory(rows) {
  const o = { source: '', versions: [] };
  for (const r of rows ?? []) {
    if (r[0] === 'history' && (r[1] === 'index' || r[1] === 'none')) o.source = r[1];
    else if (r[0] === 'version' && SEMVER.test(r[1] ?? '')) {
      const day = /^(\d{4}-\d\d-\d\d)(T|$)/.exec(r[2] ?? '');
      o.versions.push({ version: r[1], date: day ? day[1] : '', current: r[3] === 'current', withdrawn: r[4] === 'yes', reason: plain(r[5]), changes: plain(r[6]) });
    }
  }
  return o;
}

// what the page lists under "What it needs and uses": [{ k, v }] without the empty ones
export function usesOf(s) {
  const out = [];
  if (s.needs?.length) out.push({ k: 'Needs', v: s.needs.join(', ') });
  if (s.ram_mb && /^\d+$/.test(s.ram_mb)) out.push({ k: 'Memory', v: Number(s.ram_mb) >= 1024 ? `${+(Number(s.ram_mb) / 1024).toFixed(1)} GB` : `${s.ram_mb} MB` });
  if (s.disk_gb && /^\d+$/.test(s.disk_gb)) out.push({ k: 'Disk', v: `${s.disk_gb} GB` });
  if (s.ports?.length) out.push({ k: 'Ports', v: s.ports.join(', ') });
  if (s.gpu === 'yes') out.push({ k: 'Graphics card', v: 'used when there is one' });
  if (s.instances) out.push({ k: 'Containers', v: s.instances });
  if (s.input === 'form' || s.asks) out.push({ k: 'Questions', v: 'asks a few questions before it installs' });
  else if (s.input === 'terminal') out.push({ k: 'Questions', v: 'asks its questions in a terminal' });
  return out;
}
