// The Marketplace as a store (web/src/pages/market.js, #474): cards from the package reads, tabs and their counts, categories, search, the
// buttons of a card, and that nothing a repository says becomes markup, a script address or a path outside the asset endpoint.
import { parseCards, storeRows, rowsOf, tabsOf, categoriesOf, filterRows, cardActions, iconOf, assetUrl, safeLink, openHref, parseShow, usesOf,
  stateLine, categoryLabel, trustOf, testedText } from '../web/src/pages/market.js';

let ok = 0, bad = 0;
const check = (name, cond, extra = '') => { if (cond) { ok++; console.log(`  ok    ${name}`); } else { bad++; console.log(`  FAIL  ${name} ${extra}`); } };

// hs sys pkg market: name, kind, repo, available, installed, state, core, audience, title
const market = [
  ['jellyfin', 'recipe', 'official', '1.1.0', '1.0.2', 'update', 'no', 'generic', 'watch your films'],
  ['immich', 'recipe', 'official', '1.0.0', '-', 'new', 'no', 'generic', 'photos'],
  ['ntfy', 'recipe', 'official', '1.0.0', '1.0.0', 'current', 'no', 'generic', 'push messages'],
  ['navidrome', 'recipe', 'family', '1.1.0', '-', 'new', 'no', 'generic', 'music'],
  ['posters', 'extension', 'official', '1.1.0', '1.0.0', 'current', 'no', 'generic', 'posters'],
  ['gateway', 'capability', 'official', '1.0.0', '-', 'waits', 'no', 'generic', 'gateway proxy'],
  ['Bad', 'recipe', 'official', '1.0.0', '-', 'new', 'no', 'generic', 'a name the server never sends'],
];
// hs sys pkg cards: name, repo, category, icon, verified
const cards = parseCards([
  ['jellyfin', 'official', 'media', 'ph:film-strip', '2026-11-18'],
  ['immich', 'official', 'media', 'icon.svg', '-'],
  ['ntfy', 'official', 'tools', 'ph:<script>', 'yesterday'],
  ['navidrome', 'family', 'secret-stuff', '../../etc/passwd.svg', '-'],
]);
const rows = storeRows(market, cards);
check('a row with a bad name is left out', !rows.some((p) => p.name === 'Bad') && rows.length === 6);
const jf = rows.find((p) => p.name === 'jellyfin');
check('card data joins by repo and name', jf.category === 'media' && jf.icon === 'film-strip' && jf.src === '' && jf.verified === '2026-11-18');
const im = rows.find((p) => p.name === 'immich');
check('an svg icon of the package is the asset address', im.src === '/api/pkg/asset/official/immich/icon.svg' && im.icon === 'package');
const nt = rows.find((p) => p.name === 'ntfy');
check('an icon that is not a plain Phosphor name is the package icon', nt.icon === 'package' && nt.src === '');
check('a verified value that is not a date is no date', nt.verified === '');
const nd = rows.find((p) => p.name === 'navidrome');
check('an icon path that leaves the package is never an address', nd.src === '' && nd.icon === 'package');
check('an unknown category is Other', categoryLabel(nd.category) === 'Other');
check('installed: current and update yes, new and waits no', jf.installed && nt.installed && !im.installed && !rows.find((p) => p.name === 'gateway').installed);
check('an add-on without card data gets its kind icon', rows.find((p) => p.name === 'posters').icon === 'puzzle-piece' && rows.find((p) => p.name === 'gateway').icon === 'plug');

// tabs
check('Apps are the recipes', rowsOf('apps', rows).map((p) => p.name).sort().join() === 'immich,jellyfin,navidrome,ntfy');
check('Add-ons are the rest', rowsOf('addons', rows).map((p) => p.name).sort().join() === 'gateway,posters');
check('Installed and Updates', rowsOf('installed', rows).length === 3 && rowsOf('updates', rows).map((p) => p.name).join() === 'jellyfin');
const tabs = tabsOf(rows);
check('tabs: Apps first, counts on Installed and Updates, Advanced last', tabs.map((t) => t.label).join('|') === 'Apps|Add-ons|Installed (3)|Updates (1)|Advanced');

// categories and search
const cats = categoriesOf(rowsOf('apps', rows));
check('categories: All first, only those with a row, in list order, Other last', cats.map((c) => `${c.value}:${c.count}`).join() === 'all:4,media:2,tools:1,other:1');
check('filter by category', filterRows(rows, { category: 'media' }).map((p) => p.name).join() === 'immich,jellyfin');
check('filter Other', filterRows(rows, { category: 'other' }).map((p) => p.name).sort().join() === 'gateway,navidrome,posters');
check('search over name and title, all words', filterRows(rows, { q: 'watch films' }).map((p) => p.name).join() === 'jellyfin' && !filterRows(rows, { q: 'watch nothing' }).length);
check('search finds a category word', filterRows(rows, { q: 'tools' }).map((p) => p.name).join() === 'ntfy');

// buttons
const ids = (p, open) => cardActions(p, open).map((a) => a.id + (a.reason ? '!' : '')).join();
check('new: Install', ids(im) === 'install');
check('waits: Install, off with the reason', ids(rows.find((p) => p.name === 'gateway')) === 'install!');
check('update: Update and Manage', ids(jf) === 'update,manage');
check('installed app: Open and Manage instead of Install', ids(nt, 'http://x:1') === 'open,manage');
check('installed app without an address: Open is off', ids(nt, '') === 'open!,manage');
check('installed add-on: Manage', ids(rows.find((p) => p.name === 'posters')) === 'manage');
check('never more than two buttons', rows.every((p) => cardActions(p, 'x').length <= 2));
check('state line', stateLine(jf) === 'Installed 1.0.2, 1.1.0 is out' && stateLine(im) === 'Version 1.0.0');

// untrusted strings
check('asset address: only the patterns of the server', assetUrl('official', 'a', 'shots/one.webp') === '/api/pkg/asset/official/a/shots/one.webp'
  && assetUrl('official', 'a', '../x.png') === '' && assetUrl('official', 'a', '.hidden.png') === '' && assetUrl('off/icial', 'a', 'i.svg') === ''
  && assetUrl('official', 'a', 'a.gif') === '' && assetUrl('official', 'a', 'shots/.x/a.png') === '');
check('a link is http or https only', safeLink('https://jellyfin.org') === 'https://jellyfin.org/' && safeLink('javascript:alert(1)') === ''
  && safeLink('data:text/html,x') === '' && safeLink('//evil.example') === '' && safeLink('https://a.example/"><script>') === '' && safeLink('') === '');
check('icon: a Phosphor name keeps its name only', iconOf({ kind: 'recipe', repo: 'r', name: 'n' }, 'ph:film-strip').icon === 'film-strip'
  && iconOf({ kind: 'recipe', repo: 'r', name: 'n' }, 'ph:x y').icon === 'package');

// Open
const svc = [['jellyfin', 'jellyfin', 'Jellyfin', 'yes', 'no', '-', 'private-ok', 'no'], ['evil', 'ntfy', 'x', 'yes', 'no', '-', 'private-ok', 'no']];
const tiles = [['Media', 'Jellyfin', 'http://192.168.1.22:8096', 'Movies', 'mdi', 'jellyfin'], ['X', 'x', 'javascript:alert(1)', '-', '-', 'evil']];
check('Open: the dashboard link of a service in the instances', openHref(['jellyfin'], svc, tiles) === 'http://192.168.1.22:8096/');
check('Open: a script address is no link', openHref(['ntfy'], svc, tiles) === '' && openHref([], svc, tiles) === '');

// the package page
const s = parseShow([['status', 'ok'], ['name', 'jellyfin'], ['description', '<img src=x onerror=alert(1)>'], ['upstream', 'javascript:alert(1)'], ['needs', 'a,b'],
  ['ram_mb', '2048'], ['disk_gb', '8'], ['ports', '8096'], ['gpu', 'yes'], ['input', 'none'], ['screenshot', 'shots/a.webp'], ['screenshot', '../../x.png'],
  ['route', 'web', '8096', 'http', 'private-ok', 'yes'], ['step', 'read', 'Fetch'], ['slot_off', 'page', 'docs']]);
check('show: the description stays the text it was', s.description === '<img src=x onerror=alert(1)>');
check('show: a script upstream is no link', s.upstream === '');
check('show: a screenshot outside the package is left out', s.screenshots.join() === 'shots/a.webp');
check('show: lists and routes', s.needs.join() === 'a,b' && s.routes[0].port === '8096' && s.steps[0].id === 'read' && !s.refused);
check('uses: memory in GB, disk, ports, graphics card', usesOf(s).map((x) => `${x.k}=${x.v}`).join('|') === 'Needs=a, b|Memory=2 GB|Disk=8 GB|Ports=8096|Graphics card=used when there is one');
const r = parseShow([['status', 'refused'], ['reason', 'no package x']]);
check('show refused: the reason', r.refused && r.reason === 'no package x');

// trust (#477): official only for the official repository the core configures, and signed
const repos = [{ name: 'official', signed: true, from: 'default' }, { name: 'friends', signed: true, from: 'added' }, { name: 'family', signed: false, from: 'added' }];
check('the configured official repository, signed: Official', trustOf('official', repos) === 'official');
check('an added signed repository: Community', trustOf('friends', repos) === 'community');
check('an unsigned repository: Community, unsigned', trustOf('family', repos) === 'unsigned');
check('an added repository called official is never Official', trustOf('official', [{ name: 'official', signed: true, from: 'added' }]) === 'community');
check('the official repository without signatures is not Official', trustOf('official', [{ name: 'official', signed: false, from: 'default' }]) === 'unsigned');
check('another default repository is not Official', trustOf('recipes', [{ name: 'recipes', signed: true, from: 'default' }]) === 'community');
check('an unknown repository: no label yet', trustOf('x', repos) === '' && trustOf('x', null) === '');
check('tested: the day or not tested (official)', testedText('2026-01-02', 'official') === 'Tested on a real server on 2026-01-02' && testedText('', 'official') === 'Not tested on a real server');
check('tested: any other repository claims nothing, even with a day', ['community', 'unsigned', ''].every((t) => testedText('2026-01-02', t) === 'No Hobnix test date' && testedText('', t) === 'No Hobnix test date'));

console.log(`${ok} ok, ${bad} failed`);
process.exit(bad ? 1 : 0);
