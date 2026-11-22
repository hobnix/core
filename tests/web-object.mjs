// The Object frame and the quick look (docs/PLAN-navigation.md step 1): the tabs of an object page from its address, the tab limit, the order of the frame (the
// danger section last), the three roles on an object page opened by address, the disk object in the registry, and the quick look's rules (Escape, press outside, focus
// return) with a fake document. Run with node; the components themselves are not run here (source checks stand in for them).
import { readFileSync } from 'node:fs';
import { P, diskPath } from '../web/src/paths.js';
import { objectOf, objects } from '../web/src/objects.js';
import { itemOf, titleOf } from '../web/src/nav.js';
import { ROLES, lockedWhy, canSee, roleOk } from '../web/src/roles.js';
import { MAX_TABS, ORDER, frameTabs, activeTab, tabSegment, menuFor, readOnlyNote } from '../web/src/shell/objectpage.js';
import { OVERLAY, closesOnKey, closesOnPress, returnTarget } from '../web/src/ui/quicklook.js';

let ok = 0, bad = 0;
const eq = (name, got, want) => { if (JSON.stringify(got) === JSON.stringify(want)) { ok++; console.log(`  ok    ${name}`); } else { bad++; console.log(`  FAIL  ${name}: got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`); } };
const src = (p) => readFileSync(new URL(`../web/src/${p}`, import.meta.url), 'utf8').replace(/\r\n/g, '\n');

// ── tabs from the address, at most four
const t5 = ['a', 'b', 'c', 'd', 'e'].map((id) => ({ id, label: id.toUpperCase() }));
eq('at most four tabs', frameTabs(t5).length, MAX_TABS);
eq('the first tab is Overview', frameTabs(t5)[0].id, 'overview');
eq('a duplicate id is dropped', frameTabs([{ id: 'overview', label: 'Overview' }, { id: 'overview', label: 'Again' }, { id: 'x', label: 'X' }]).map((t) => t.id), ['overview', 'x']);
eq('no tabs, no tab row', frameTabs(undefined), []);
const dt = frameTabs(objects.disk.tabs);
eq('the tab named by the address is the active one', activeTab(dt, 'smart'), 'smart');
eq('no tab in the address is Overview', activeTab(dt, ''), 'overview');
eq('an unknown tab is Overview, not an error', activeTab(dt, 'nonsense'), 'overview');
eq('Overview has no address segment', [tabSegment(''), tabSegment('overview'), tabSegment('smart')], ['', '', '/smart']);
eq('the disk registry has Overview and at most three own tabs', [objects.disk.tabs.length <= MAX_TABS, objects.disk.tabs[0].id, objects.disk.tabs.map((t) => t.id)], [true, 'overview', ['overview', 'smart', 'tests', 'files']]);

// ── the disk object: its address and the tree item it belongs to
eq('a disk page address', diskPath('sda'), '/storage/disks/sda');
eq('a tab after the name', diskPath('sda', 'smart'), '/storage/disks/sda/smart');
eq('Overview is the short address', diskPath('sda', 'overview'), '/storage/disks/sda');
eq('a name with a space and a slash is encoded', diskPath('a b/c'), '/storage/disks/a%20b%2Fc');
for (const name of ['sda', 'a b/c', 'nvme0n1', 'ata-WDC_WD40-1']) for (const tab of ['', 'tests'])
  eq(`${name}/${tab || 'overview'}: the address reads back`, objectOf(diskPath(name, tab)), { kind: 'disk', id: name, tab });
eq('the list is not a disk object', objectOf(P.disks), null);
eq('a disk page is a page of the Disks item', itemOf(diskPath('sda'))?.path, P.disks);
eq('a disk page title ends with the disk', titleOf(diskPath('sda', 'smart')).slice(-2), ['Disks', 'sda']);
eq('the pool objects still work', objectOf('/storage/pools/tank'), { kind: 'pool', id: 'tank', tab: '' });

// ── the three roles on an object page opened by address: read-only for viewer and app-manager, never an error
eq('the roles', ROLES, ['viewer', 'app-manager', 'admin']);
eq('every role may open a disk page by address (no lock, no refusal)', ROLES.map((r) => [lockedWhy(r, diskPath('sda')), canSee(r, diskPath('sda', 'smart'))]), [['', true], ['', true], ['', true]]);
eq('the read-only note: viewer and app-manager see it, admin does not', ROLES.map((r) => readOnlyNote(r, 'admin') !== ''), [true, true, false]);
eq('the note names the role and what changing needs', readOnlyNote('viewer', 'admin'), 'Read-only: your role (viewer) may look at this page but not change anything on it. Changing needs the admin role.');
eq('an object that an app manager may change is not read-only for it', ROLES.map((r) => readOnlyNote(r, 'app-manager') !== ''), [true, false, false]);
{
  const items = [{ label: 'Long test', need: 'admin' }, { label: 'Browse files' }];
  const by = (r) => menuFor(items, r).map((i) => !!i.disabled);
  eq('menu: a viewer and an app manager have the admin item greyed, the free one open', [by('viewer'), by('app-manager')], [[true, false], [true, false]]);
  eq('menu: an admin has nothing greyed', by('admin'), [false, false]);
  eq('a greyed item says why', menuFor(items, 'viewer')[0].reason, 'Your role (viewer) may not do this. It needs admin.');
  eq('nothing is removed from the menu for a role', ROLES.map((r) => menuFor(items, r).length), [2, 2, 2]);
  eq('the role order is the one of roleOk', [roleOk('admin', 'admin'), roleOk('viewer', 'admin')], [true, false]);
}

// ── the frame, read from its source: the order, and what a disk page shows
const frame = src('shell/ObjectPage.svelte');
const at = (s) => frame.indexOf(s);
const idx = ['<PageHeader', '{#if note}', '@render banners', '<JobStrip', '<PageTabs', '@render children', '<LinkedObjects', '<DangerZone'].map(at);
eq('the frame draws in the order of ORDER (header, note, banners, jobs, tabs, body, links, danger)', [ORDER.length, idx.every((v, i) => v > -1 && (i === 0 || v > idx[i - 1]))], [8, true]);
eq('the danger section is the last thing the frame draws', frame.slice(at('<DangerZone')).includes('<LinkedObjects') || frame.slice(at('<DangerZone')).includes('<PageTabs') || frame.slice(at('<DangerZone')).includes('@render children'), false);
eq('the frame limits its tabs through frameTabs', /frameTabs\(tabs\)/.test(frame), true);
const disk = src('pages/disks/Disk.svelte');
const primary = disk.slice(disk.indexOf('{#snippet primary()}'), disk.indexOf('{/snippet}', disk.indexOf('{#snippet primary()}')));
const branches = primary.split(/\{:else\}|\{\/if\}/);
eq('the disk page shows at most two actions in its header (one primary, one secondary)', branches.map((b) => (b.match(/<Button\b/g) ?? []).length).every((n) => n <= 2), true);
eq('no visible action of the disk page is destructive', /variant="danger"/.test(disk), false);
eq('Format sits in the danger section', /danger = \$derived\(loose/.test(disk) && /label: 'Format…'/.test(disk), true);
eq('the disk page passes the roles through the frame (need=admin)', /need="admin"/.test(disk.slice(disk.indexOf('<ObjectPage'))), true);
eq('an unknown disk is a sentence and a way back', /notFound=\{/.test(disk) && /backTo=\{P\.disks\}/.test(disk), true);

// ── the list: no quick look (owner decision 2026-11-22); a row has an "Open disk" button at its end
const list = src('pages/Disks.svelte');
eq('Disks has no QuickLook, selection helper, Split or Drawer', [/<QuickLook|QuickLook\.svelte/.test(list), /selection\.svelte\.js/.test(list), /<Split|<Drawer|takeSelection/.test(list)], [false, false, false]);
eq('a row ends with an "Open disk" icon button that goes to the disk page', [/label="Open disk"/.test(list), /icon="arrow-square-out"/.test(list), /go\(diskPath\(d\.name\)\)/.test(list), /<Table id="disks"[^>]*onrow/.test(list)], [true, true, true, false]);
eq('the list does not read the SMART history or the self-tests (the page does)', [/detail: true/.test(disk), /detail/.test(list)], [true, false]);
eq('QuickLook restores focus and listens for Escape and presses', /returnTarget/.test(src('ui/QuickLook.svelte')) && /closesOnKey/.test(src('ui/QuickLook.svelte')) && /closesOnPress/.test(src('ui/QuickLook.svelte')), true);
eq('QuickLook is a non-modal dialog (role dialog, no aria-modal, no scroll lock)', [/role="dialog"/.test(src('ui/QuickLook.svelte')), /aria-modal/.test(src('ui/QuickLook.svelte')), /overflow\s*:\s*hidden/.test(src('ui/QuickLook.svelte'))], [true, false, false]);

// ── the quick look's rules with a fake document
const el = (attrs = {}, parent = null) => {
  const self = { attrs, parent, isConnected: true, focused: false,
    closest(sel) { const want = sel.split(',').map((s) => s.trim()); for (let n = self; n; n = n.parent) if (want.some((w) => w === '[data-k]' ? n.attrs['data-k'] != null : w === '[aria-modal="true"]' ? n.attrs['aria-modal'] === 'true' : w === '[role="menu"]' ? n.attrs.role === 'menu' : false)) return n; return null; },
    contains(n) { for (let x = n; x; x = x.parent) if (x === self) return true; return false; },
    focus() { self.focused = true; } };
  return self;
};
const doc = (overlay = false, rows = {}) => ({ querySelector: (s) => (s === OVERLAY ? (overlay ? {} : null) : (rows[/data-k="(.*)"/.exec(s)?.[1].replace(/\\(.)/g, '$1')] ?? null)) });
eq('Escape closes when nothing else is open', closesOnKey({ key: 'Escape' }, doc()), true);
eq('Escape does not close it while a dialog or a menu is open', closesOnKey({ key: 'Escape' }, doc(true)), false);
eq('Escape that somebody used already does not close it', closesOnKey({ key: 'Escape', defaultPrevented: true }, doc()), false);
eq('another key does not close it', closesOnKey({ key: 'a' }, doc()), false);
{
  const root = el(); const inside = el({}, root); const row = el({ 'data-k': 'sdb' }); const cell = el({}, row); const outside = el(); const dlg = el({ 'aria-modal': 'true' }); const inDlg = el({}, dlg);
  eq('a press inside does not close it', closesOnPress(inside, root, '[data-k]', doc()), false);
  eq('a press on another row does not close it (that row replaces it)', closesOnPress(cell, root, '[data-k]', doc()), false);
  eq('a press outside closes it', closesOnPress(outside, root, '[data-k]', doc()), true);
  eq('a press in a dialog it opened does not close it', closesOnPress(inDlg, root, '[data-k]', doc()), false);
  eq('a press while a dialog is open does not close it', closesOnPress(outside, root, '[data-k]', doc(true)), false);
}
{
  const row = el({ 'data-k': 'sda' }); const opener = el();
  eq('focus goes back to the row of the object', returnTarget(doc(false, { sda: row }), 'sda', opener), row);
  eq('a row that is gone falls back to the element that had the focus', returnTarget(doc(), 'sda', opener), opener);
  opener.isConnected = false;
  eq('nothing to focus when both are gone', returnTarget(doc(), 'sda', opener), null);
  eq('a key with a quote is escaped in the selector', returnTarget(doc(false, { 'a"b': row }), 'a"b', null), row);
}

// ── the user object (step 5): address, tabs, the read-only marker, and the pages
{
  const { userPath, builtInUser, userOf } = await import('../web/src/pages/identity/user.js');
  eq('a user page address', [userPath('alice'), userPath('alice', 'groups'), userPath('a b', 'overview')], ['/people/users/alice', '/people/users/alice/groups', '/people/users/a%20b']);
  eq('a user address reads back', objectOf(userPath('a b', 'access')), { kind: 'user', id: 'a b', tab: 'access' });
  eq('the users list is not a user object', objectOf(P.users), null);
  eq('the user tabs are Overview, Groups, Access', objects.user.tabs.map((t) => t.id), ['overview', 'groups', 'access']);
  eq('the built-in accounts are marked, others not', [builtInUser('Administrator'), builtInUser('krbtgt'), builtInUser('alice')], [true, true, false]);
  eq('a users row is parsed, "-" is empty', userOf(['bob', '-', 'disabled', 'Domain Users, staff']), { name: 'bob', full: '', enabled: false, groups: ['Domain Users', 'staff'] });
  const page = src('pages/identity/User.svelte'), ul = src('pages/Users.svelte');
  eq('the user page has no visible destructive button, Delete is in the danger section', [/variant="danger"/.test(page), /label: 'Delete…'/.test(page)], [false, true]);
  eq('the users list uses QuickLook and ?sel=, not Split or Drawer', [/<QuickLook/.test(ul), /selection\.svelte\.js/.test(ul), /<Split|<Drawer/.test(ul)], [true, true, false]);
}

// ── the instance object (step 4): address (own kind segment, an instance may be called docker), tabs, the pages
{
  const { instancePath } = await import('../web/src/pages/instances/path.js');
  eq('an instance page address', [instancePath('docker'), instancePath('jellyfin', 'config'), instancePath('a b', 'overview')], ['/instances/ct/docker', '/instances/ct/jellyfin/config', '/instances/ct/a%20b']);
  eq('an instance address reads back', objectOf(instancePath('a b', 'console')), { kind: 'instance', id: 'a b', tab: 'console' });
  eq('the instance named docker is not the Docker page', [objectOf(instancePath('docker'))?.kind, objectOf(P.docker)], ['instance', null]);
  eq('the other pages under /instances are no instance objects', [P.apps, P.iso, P.services, P.registries].map((p) => objectOf(p)), [null, null, null, null]);
  eq('the instances list is not an instance object', objectOf(P.instances), null);
  eq('the instance tabs are Overview, Config, Network, Console', objects.instance.tabs.map((t) => t.id), ['overview', 'config', 'network', 'console']);
  eq('an instance page is a page of the Instances item', itemOf(instancePath('x'))?.path, P.instances);
  const page = src('pages/instances/Instance.svelte'), il = src('pages/Instances.svelte');
  eq('the instance page has no visible destructive button, Delete is in the danger section', [/variant="danger"/.test(page), /label: 'Delete…'/.test(page)], [false, true]);
  eq('the instances list uses QuickLook and ?sel=, not Split or Drawer', [/<QuickLook/.test(il), /selection\.svelte\.js/.test(il), /<Split|<Drawer/.test(il)], [true, true, false]);
  eq('the console tab opens the existing terminal and VM console windows', [/Terminal\.svelte/.test(src('pages/instances/ConsoleTab.svelte')), /VmConsole\.svelte/.test(src('pages/instances/ConsoleTab.svelte'))], [true, true]);
}

// ── Shares list: no quick look (owner decision 2026-11-23); a row ends with Browse and "Open share" buttons
const shl = src('pages/Shares.svelte');
eq('Shares has no QuickLook, selection helper, Split or Drawer', [/<QuickLook|QuickLook\.svelte/.test(shl), /selection\.svelte\.js/.test(shl), /<Split|<Drawer/.test(shl)], [false, false, false]);
eq('a share row ends with an "Open share" icon button that goes to the share page', [/label="Open share"/.test(shl), /icon="arrow-square-out"/.test(shl), /go\(sharePath\(s\.name\)\)/.test(shl), /<Table id="shares"[^>]*onrow/.test(shl)], [true, true, true, false]);

console.log(`  -> ${ok} ok, ${bad} failed`);
process.exit(bad ? 1 : 0);
