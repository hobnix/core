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

// the tested line of a card and the page: the day from the index, or the plain "not tested"
export const testedText = (verified) => (verified ? `Tested on a real server on ${verified}` : 'Not tested on a real server');

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

// search over name, title and category; `category` is an id, 'other' or 'all'. Apps sort by name.
export function filterRows(rows, { q = '', category = 'all' } = {}) {
  const words = q.trim().toLowerCase().split(/\s+/).filter(Boolean);
  return rows.filter((p) => (category === 'all' || (category === 'other' ? !CATEGORY.has(p.category) : p.category === category))
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
