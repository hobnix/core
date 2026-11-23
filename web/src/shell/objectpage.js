// The rules of the Object page frame (shell/ObjectPage.svelte) that need no DOM; tests/web-object.mjs runs them in node.
import { roleOk, refusal } from '../roles.js';

export const MAX_TABS = 4;   // Overview plus up to three of the object's own (docs/PLAN-web-design.md 3.6); History is the job strip, not a tab

// The tabs a page may show: at most MAX_TABS, the first one is Overview (id 'overview'), ids are unique.
export function frameTabs(tabs) {
  const seen = new Set();
  const list = (tabs ?? []).filter((t) => t && t.id && !seen.has(t.id) && seen.add(t.id)).slice(0, MAX_TABS);
  if (list.length && list[0].id !== 'overview') list[0] = { ...list[0], id: 'overview' };
  return list;
}

// The tab named by the address (`/<kind>/<id>/<tab>`): that one when the object has it, else the first (an unknown tab is Overview, not an error).
export const activeTab = (tabs, tab) => (tabs.some((t) => t.id === tab) ? tab : (tabs[0]?.id ?? ''));

// The address segment of a tab: Overview has none, so the object's own address stays the short one.
export const tabSegment = (tab) => (!tab || tab === 'overview' ? '' : `/${encodeURIComponent(tab)}`);

// Menu items for a role: an item with `need` the role does not have stays in the list, disabled, with the refusal sentence as its reason (design 4.9).
export function menuFor(items, role) {
  return (items ?? []).map((it) => (it.need && !roleOk(role, it.need) ? { ...it, disabled: true, reason: refusal(role, it.need) } : it));
}

// A viewer opening an object page by address sees it read-only, not an error: the note says so. '' when the role may change the object.
export function readOnlyNote(role, need = 'admin') {
  return roleOk(role, need) ? '' : `Read-only: your role (${role}) may look at this page but not change anything on it. Changing needs the ${need} role.`;
}

// The vertical order of the frame; the component renders exactly this and the node test reads its source against it. The danger section is last.
export const ORDER = ['header', 'note', 'banners', 'jobs', 'tabs', 'body', 'links', 'danger'];
