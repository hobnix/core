// Pure helpers of the action slot (docs/PLAN-package-pages.md "Slots"): the [[web.actions]] of a package, as the session answer sends them
// (features.slots: [{ name, title, actions: [{ id, label, plan, role?, main?, danger?, icon? }] }], only packages that are on, only actions whose
// `requires` is on). No Svelte here, so a test can run them.
import { planArgs } from './generic.js';
import { areaRole, maxRole } from '../roles.js';

// the actions of one package split for a row or a header: the main one and the rest (More); with no `main` the first is the main one
export function actionsOf(slots, name) {
  const all = (slots ?? []).find((s) => s.name === name)?.actions ?? [];
  const main = all.find((a) => a.main) ?? all[0] ?? null;
  return { main, more: all.filter((a) => a !== main) };
}

// what the plan dialog is opened with: [area, args, title]
export const planOf = (a) => [a.plan[0], planArgs(a.plan, {}), a.label];

// the least role that may use the action: its own `role` (default admin) or the role of its area, whichever is higher
export const needOf = (a) => maxRole(areaRole(a.plan?.[0]), a.role ?? 'admin');

// a page declaration with the package's actions added to its header (the page's own actions first)
export function withActions(page, slots) {
  const acts = (slots ?? []).find((s) => s.name === page?.name)?.actions ?? [];
  if (!acts.length) return page;
  return { ...page, actions: [...(page.actions ?? []), ...acts.map((a) => ({ label: a.label, plan: a.plan, role: a.role, primary: !!a.main, danger: !!a.danger, icon: a.icon }))] };
}
