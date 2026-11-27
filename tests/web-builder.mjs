// The form model of the package builder (web/src/pages/builder.js, pure), run with node.
import { readFileSync } from 'node:fs';
import { blank, manifestText, permissionList, findingsOf, fieldOf, withKind, CATEGORIES } from '../web/src/pages/builder.js';

let ok = 0, bad = 0;
const eq = (name, got, want) => { if (JSON.stringify(got) === JSON.stringify(want)) { ok++; console.log(`  ok    ${name}`); } else { bad++; console.log(`  FAIL  ${name}: got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`); } };

const f = { ...blank(), name: ' demo ', title: 'A "quoted" title' };
eq('a recipe draft', manifestText(f), 'name = "demo"\nversion = "0.1.0"\nkind = "recipe"\ntitle = "A \\"quoted\\" title"\nrequires_core = ">=9"\naudience = "generic"\nscript = "run.sh"\nicon = "ph:package"\ncategory = "tools"\napp_version = "0.1.0"\n\n[app]\ninstances = "one"\n');
eq('an extension has no script', manifestText({ ...f, kind: 'extension' }).includes('script'), false);
eq('permissions by line or comma', permissionList('web.read\n net:lan, host:incus\n\n'), ['web.read', 'net:lan', 'host:incus']);
eq('permissions are written as a list', manifestText({ ...f, permissions: 'web.read\nnet:lan' }).includes('permissions = ["web.read", "net:lan"]\n'), true);
eq('no permissions, no line', manifestText(f).includes('permissions'), false);
eq('a newline in a title stays one TOML line', manifestText({ ...f, title: 'a\nb' }).split('\n').filter((l) => l.startsWith('title')).length, 1);
eq('findings: errors first, - means no place', findingsOf([['warn', '-', 'w'], ['error', 'name', 'e']]), [{ level: 'error', where: 'name', text: 'e' }, { level: 'warn', where: '', text: 'w' }]);
eq('nothing found', findingsOf(undefined), []);
eq('requires_core belongs to the requires field', [fieldOf('requires_core'), fieldOf('requires_core_max'), fieldOf('title'), fieldOf('-'), fieldOf('')], ['requires', 'requires', 'title', '', '']);

const toml = readFileSync(new URL('../config/package-categories.toml', import.meta.url), 'utf8');
eq('the category list is the one of config/package-categories.toml', CATEGORIES, [...toml.match(/^ids\s*=\s*\[(.*)\]/m)[1].matchAll(/"([^"]+)"/g)].map((m) => m[1]));
const full = { ...f, description: 'Photos.', descriptionDe: 'Fotos.', category: 'media', appVersion: '1.2.3', instances: 'many' };
eq('store fields and instances are written', manifestText(full).includes('description = "Photos."\ndescription_de = "Fotos."\nicon = "ph:package"\ncategory = "media"\napp_version = "1.2.3"\n\n[app]\ninstances = "many"\n'), true);
eq('an empty store field is left out', manifestText({ ...f, icon: '' }).includes('icon'), false);
eq('an extension has store fields but no [app]', [manifestText({ ...f, kind: 'extension' }).includes('category = "tools"'), manifestText({ ...f, kind: 'extension' }).includes('[app]')], [true, false]);
const cap = manifestText({ ...f, kind: 'capability', requires: '>=1' });
eq('a capability has its type and no store fields', [cap.includes('type = "feature"'), cap.includes('category'), cap.includes('[app]'), cap.includes('script')], [true, false, false, false]);
eq('the level follows the kind while it is the default', [withKind(f, 'capability').requires, withKind(withKind(f, 'capability'), 'recipe').requires, withKind({ ...f, requires: '>=5' }, 'capability').requires], ['>=1', '>=9', '>=5']);
eq('store findings belong to their fields', [fieldOf('app_version'), fieldOf('description_de'), fieldOf('category')], ['appVersion', 'descriptionDe', 'category']);

console.log(`${ok} passed, ${bad} failed`);
process.exit(bad ? 1 : 0);
