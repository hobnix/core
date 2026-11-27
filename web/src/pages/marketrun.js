// What the buttons of a store card and of a package page do (market.js cardActions names them). Install is the one install dialog with its plan
// and typed confirmation (forms/ops/InstallDialog.svelte, unchanged); Update, Turn on/off and Remove are the plans of today; Manage goes to the
// place that manages an installed package (an app: its row in Apps > App catalog).
import { openCreate, openPlan } from '../ui.svelte.js';
import { rowstate } from '../rowstate.svelte.js';
import { go } from '../route.svelte.js';
import { setSelection } from '../select.svelte.js';
import { P, capabilityPath } from '../paths.js';
import InstallDialog from '../forms/ops/InstallDialog.svelte';

export function runAction(id, p, open = '') {
  if (id === 'install') return openCreate(InstallDialog, { pkg: p.name, repo: p.repo });
  if (id === 'update') return openPlan('pkg', ['update', p.name], `Update ${p.name}`);
  if (id === 'open') {
    if (open.startsWith('/')) return go(open);
    if (open) window.open(open, '_blank', 'noopener,noreferrer');
    return;
  }
  if (id === 'manage') {
    if (p.kind === 'recipe') { setSelection('recipes', p.name); return go(P.apps); }
    if (p.kind === 'capability') return go(capabilityPath(p.name));
    return go(P.settingsExtensions);
  }
  if (id === 'enable' || id === 'disable') return openPlan('parts', [id, p.name], `${id === 'enable' ? 'Turn on' : 'Turn off'} ${p.name}`);
  if (id === 'remove') return openPlan('pkg', ['remove', p.name], `Remove ${p.name}`);
}

// the job of a button, while it runs (the button shows it busy)
export function busyOf(id, p) {
  if (id === 'install') return rowstate.pending('apps', ['install', p.name]);
  if (id === 'update') return rowstate.pending('pkg', ['update', p.name]);
  if (id === 'enable' || id === 'disable') return rowstate.pending('parts', [id, p.name]);
  if (id === 'remove') return rowstate.pending('pkg', ['remove', p.name]);
  return false;
}

// the newest failed job of a package ({ id, error }) or null
export const failureOf = (p) => rowstate.failed('apps', ['install', p.name]) ?? rowstate.failed('pkg', ['update', p.name]) ?? rowstate.failed('pkg', ['remove', p.name])
  ?? rowstate.failed('parts', ['enable', p.name]) ?? rowstate.failed('parts', ['disable', p.name]);

// the least role of a button (the server checks again)
export const needOf = (id) => (id === 'install' ? 'app-manager' : id === 'open' || id === 'manage' ? '' : 'admin');
