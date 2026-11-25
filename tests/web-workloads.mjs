// The rows of the list Apps & VMs (web/src/pages/workloads.js): building and nesting, the App column, the filters of the address, the context row of a
// match under it, open and shut rows, and the sorting of the two levels (web/src/shell/sort.js treeRows). Plain node, no Svelte.
import { readFileSync } from 'node:fs';
import { buildRows, recipesOf, recipeOfApp, filtersOf, isFiltered, filterRows, isOpen, shownKids, appsHidden, portsOf } from '../web/src/pages/workloads.js';
import { treeRows } from '../web/src/shell/sort.js';

let ok = 0, bad = 0;
const eq = (name, got, want) => { if (JSON.stringify(got) === JSON.stringify(want)) { ok++; console.log(`  ok    ${name}`); } else { bad++; console.log(`  FAIL  ${name}: got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`); } };

const ct = (name, type = 'container', state = 'running', address = '10.0.0.1') => ({ name, type, state, address, owner: name === 'docker' ? 'docker' : '' });
const app = (name, extra = {}) => ({ name, parent: 'docker', project: name, state: 'running', running: '1/1', ports: '-', address: '-', images: `img/${name}:1`, managed: 'web', update: 'no', files: 'same', ...extra });
const cts = [ct('win', 'virtual-machine', 'stopped', '-'), ct('docker', 'container', 'running', '192.168.1.24 (eth0)'), ct('jellyfin'), ct('pelican-wings')];
const apps = [app('vaultwarden', { ports: '8081,8443', address: '192.168.1.24', images: 'vaultwarden/server:1' }), app('radarr', { managed: 'recipe' }), app('radarr2', { managed: 'recipe' }), app('docker', { images: 'x/dockhand' })];
const recipes = [
  { name: 'docker', cts: ['docker'], state: 'installed' }, { name: 'radarr', cts: ['docker'], state: 'installed' }, { name: 'jellyfin', cts: ['jellyfin'], state: 'installed' },
  { name: 'pelican', cts: ['pelican-panel', 'pelican-wings'], state: 'partly' }, { name: 'windows', cts: ['win'], state: 'not installed' },
];
const rows = buildRows({ cts, apps, recipes });
const names = (list) => list.map((r) => r.name);
const of = (list, name) => list.find((r) => r.name === name);

console.log('-- rows and nesting');
eq('the instances are the top rows, in the order they came', names(rows), ['win', 'docker', 'jellyfin', 'pelican-wings']);
eq('every Docker app is under the container docker, one level', [names(of(rows, 'docker').kids), of(rows, 'docker').total, rows.flatMap((r) => r.kids).flatMap((k) => k.kids)], [['vaultwarden', 'radarr', 'radarr2', 'docker'], 4, []]);
const ids = [...rows, ...rows.flatMap((r) => r.kids)].map((r) => r.id);
eq('an id is unique although an app and the instance are both called docker', new Set(ids).size, ids.length);
eq('provider and type', [rows.map((r) => `${r.provider}/${r.type}`), [...new Set(of(rows, 'docker').kids.map((r) => `${r.provider}/${r.type}`))]], [['incus/vm', 'incus/container', 'incus/container', 'incus/container'], ['docker/container']]);
eq('a "-" address and ports are empty', [of(rows, 'win').address, of(rows, 'docker').kids[1].address, of(rows, 'docker').kids[1].ports, portsOf({ ports: '80,443' })], ['', '', [], ['80', '443']]);
eq('an app whose container is not listed stays at the top', names(buildRows({ cts: [], apps: [app('lost')] })), ['lost']);

console.log('-- the App column');
eq('an instance: the recipes that set it up', [of(rows, 'jellyfin').apps, of(rows, 'pelican-wings').apps, of(rows, 'win').apps], [['jellyfin'], ['pelican'], []]);
eq('the container docker: only its own recipe, the apps in Docker report it too', of(rows, 'docker').apps, ['docker']);
eq('a recipe that is not installed set nothing up', recipesOf('win', recipes), []);
eq('a Docker app: the recipe of the same name when a recipe manages it', of(rows, 'docker').kids.map((r) => r.apps), [[], ['radarr'], [], []]);
eq('a web app with the name of a recipe is not that recipe', recipeOfApp(app('radarr'), recipes), '');

console.log('-- filters in the address');
eq('the values of the address', filtersOf({ provider: 'docker', type: 'vm', q: 'photo', sel: 'x' }), { provider: 'docker', type: 'vm', q: 'photo' });
eq('an unknown value is all', filtersOf({ provider: 'lxd', type: 'toString' }), { provider: '', type: '', q: '' });
eq('without the capability docker there is no provider filter', filtersOf({ provider: 'docker', q: 'a' }, { docker: false }), { provider: '', type: '', q: 'a' });
eq('filtered or not', [isFiltered(filtersOf({})), isFiltered(filtersOf({ q: '  ' })), isFiltered(filtersOf({ type: 'vm' }))], [false, false, true]);
const run = (query) => filterRows(rows, filtersOf(query));
eq('no filter: every row and child, no context row', [names(run({})), names(of(run({}), 'docker').kids).length, run({}).some((r) => r.context)], [['win', 'docker', 'jellyfin', 'pelican-wings'], 4, false]);
eq('provider docker: the container stays as the context of its apps', [names(run({ provider: 'docker' })), run({ provider: 'docker' })[0].context, run({ provider: 'docker' })[0].kids.length], [['docker'], true, 4]);
eq('provider incus: no Docker app, no context', [names(run({ provider: 'incus' })), of(run({ provider: 'incus' }), 'docker').kids, of(run({ provider: 'incus' }), 'docker').context], [['win', 'docker', 'jellyfin', 'pelican-wings'], [], false]);
eq('type vm', names(run({ type: 'vm' })), ['win']);
eq('type container: a Docker app is a container', [names(run({ type: 'container' })), of(run({ type: 'container' }), 'docker').kids.length], [['docker', 'jellyfin', 'pelican-wings'], 4]);
eq('search by name, case ignored', [names(run({ q: 'VAULT' })), names(run({ q: 'VAULT' })[0].kids), run({ q: 'VAULT' })[0].context], [['docker'], ['vaultwarden'], true]);
eq('search by app', names(run({ q: 'pelican' })), ['pelican-wings']);
eq('search by address, and by address with port', [names(run({ q: '10.0.0.1' })), names(run({ q: '192.168.1.24:8443' })[0].kids)], [['jellyfin', 'pelican-wings'], ['vaultwarden']]);
eq('search by image', names(run({ q: 'x/dockhand' })[0].kids), ['docker']);
eq('a row that matches itself is no context row', [run({ q: 'docker' })[0].context, names(run({ q: 'docker' })[0].kids)], [false, ['docker']]);
eq('the filters combine', [names(run({ provider: 'docker', type: 'vm' })), names(run({ provider: 'docker', q: 'radarr' })[0].kids)], [[], ['radarr', 'radarr2']]);
eq('the count of apps does not follow the filter', run({ q: 'vault' })[0].total, 4);
eq('the rows given in are not changed', [of(rows, 'docker').kids.length, of(rows, 'docker').context], [4, false]);

console.log('-- open and shut');
const host = of(rows, 'docker');
eq('open at first, shut when the session says so', [isOpen(host, new Set()), isOpen(host, new Set(['docker'])), shownKids(host, new Set(['docker'])).length, shownKids(host, new Set()).length], [true, false, 0, 4]);
eq('a context row opens although it was shut', shownKids(run({ q: 'vault' })[0], new Set(['docker'])).length, 1);
eq('the hint: only the stopped container docker, and only with Docker', [appsHidden(host), appsHidden({ ...host, ct: ct('docker', 'container', 'stopped') }), appsHidden({ ...host, ct: ct('docker', 'container', 'stopped') }, false), appsHidden({ ...of(rows, 'win') })], [false, true, false, false]);

console.log('-- sorting two levels');
const cols = [{ key: 'name' }];
const drawn = (order, closed = new Set()) => treeRows(rows, cols, order, null, (r) => shownKids(r, closed)).map((x) => `${'  '.repeat(x.depth)}${x.row.name}`);
eq('the data order without a sort, the apps right under their container', drawn(null), ['win', 'docker', '  vaultwarden', '  radarr', '  radarr2', '  docker', 'jellyfin', 'pelican-wings']);
eq('a sort orders the top rows and the apps separately', drawn({ key: 'name', dir: 'desc' }), ['win', 'pelican-wings', 'jellyfin', 'docker', '  vaultwarden', '  radarr2', '  radarr', '  docker']);
eq('a shut row draws no child', drawn({ key: 'name', dir: 'asc' }, new Set(['docker'])), ['docker', 'jellyfin', 'pelican-wings', 'win']);
eq('without kids it is the plain list', treeRows(rows, cols, null).map((x) => x.depth), [0, 0, 0, 0]);

console.log('-- the page and the table');
const src = (f) => readFileSync(new URL(`../web/src/${f}`, import.meta.url), 'utf8');
const page = src('pages/Workloads.svelte'), table = src('shell/Table.svelte');
eq('the table draws the child rows as rows of their own', [/treeRows\(rows, columns, order, first, kids\)/.test(table), /class:child=\{depth > 0\}/.test(table), /kids=\{\(r\) => shownKids\(r, closed\)\}/.test(page)], [true, true, true]);
eq('the open and shut rows are kept for the session', /sessionStorage\.setItem\('apps:closed'/.test(page), true);
eq('the filters are written into the address, replacing the entry', /setQuery\(patch, \{ replace: true \}\)/.test(page), true);

console.log(`  -> ${ok} ok, ${bad} failed`);
process.exit(bad ? 1 : 0);
