// The package builder (ADR 0020): the form model and the package.toml text it makes. Pure, no DOM, tested with node (tests/web-builder.mjs).
// The text is only a draft: the server checks it (`hs sys pkg plan check-draft`, the checks of `hs pkg validate`); this file adds no rule of its own.

// The category ids of config/package-categories.toml (tests/web-builder.mjs compares this list with that file).
export const CATEGORIES = ['media', 'files', 'network', 'home', 'games', 'tools', 'dev', 'admin'];
// the lowest API level that knows the store fields and the [app] tables (docs/Package-API.md); a capability package has neither
export const STORE_LEVEL = '>=9';
export const CAPABILITY_LEVEL = '>=1';

export const blank = () => ({ kind: 'recipe', name: '', title: '', version: '0.1.0', requires: STORE_LEVEL, audience: 'generic', script: 'run.sh', permissions: '',
  description: '', descriptionDe: '', icon: 'ph:package', category: 'tools', appVersion: '0.1.0', instances: 'one' });

const q = (s) => JSON.stringify(String(s));      // a TOML basic string: JSON escapes are valid TOML escapes
export const permissionList = (text) => String(text || '').split(/[\n,]+/).map((x) => x.trim()).filter(Boolean);
export const hasStoreFields = (f) => f.kind === 'recipe' || f.kind === 'extension';

// the form after the kind changed: the level follows the kind while it still holds the default of the old one
export function withKind(f, kind) {
  const was = f.kind === 'capability' ? CAPABILITY_LEVEL : STORE_LEVEL;
  const now = kind === 'capability' ? CAPABILITY_LEVEL : STORE_LEVEL;
  return { ...f, kind, requires: f.requires.trim() === was ? now : f.requires };
}

// the package.toml text of the form (the order of `hs pkg new`): top-level keys, then the [app] table (a recipe only)
export function manifestText(f) {
  const out = [`name = ${q(f.name.trim())}`, `version = ${q(f.version.trim())}`, `kind = ${q(f.kind)}`, `title = ${q(f.title.trim())}`,
    `requires_core = ${q(f.requires.trim())}`, `audience = ${q(f.audience)}`];
  if (f.kind === 'capability') out.push('type = "feature"');
  if (f.kind === 'recipe') out.push(`script = ${q(f.script.trim())}`);
  const perms = permissionList(f.permissions);
  if (perms.length) out.push(`permissions = [${perms.map(q).join(', ')}]`);
  if (hasStoreFields(f)) {
    for (const [key, v] of [['description', f.description], ['description_de', f.descriptionDe], ['icon', f.icon], ['category', f.category], ['app_version', f.appVersion]]) {
      if (String(v ?? '').trim()) out.push(`${key} = ${q(String(v).trim())}`);   // an empty field is left out: the server warns about missing store fields
    }
  }
  let text = out.join('\n') + '\n';
  if (f.kind === 'recipe') text += `\n[app]\ninstances = ${q(f.instances === 'many' ? 'many' : 'one')}\n`;
  return text;
}

// `finding` lines of the plan -> [{ level, where, text }] (errors first); the plan's own lines are [level, where, text]
export function findingsOf(list) {
  const f = (list || []).map(([level, where, text]) => ({ level, where: where === '-' ? '' : where, text }));
  return [...f.filter((x) => x.level === 'error'), ...f.filter((x) => x.level !== 'error')];
}

// the form field a finding belongs to (name, version, kind, title, requires_core -> requires, script, permissions, the store fields), '' for none
const FIELD_OF = { requires_core: 'requires', description_de: 'descriptionDe', app_version: 'appVersion' };
export const fieldOf = (where) => FIELD_OF[where] || (['name', 'version', 'kind', 'title', 'audience', 'script', 'permissions', 'description', 'icon', 'category'].includes(where) ? where : '');
