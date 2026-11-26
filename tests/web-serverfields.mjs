// The server-aware form fields (web/src/ui ShareField, DiskField, PoolField, InstanceField, UserField on ServerField, and the search of Combobox):
// unit tests of ui/serverfields.js and a static contract per component source (no svelte in this checkout). Run with node, no dependencies.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  shareOptions, shareGroups, encodeShare, decodeShare, shareValue, diskOptions, poolOptions, instanceOptions, userOptions, principalOptions,
} from '../web/src/ui/serverfields.js';

const src = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'web', 'src');
let failed = 0;
const bad = (m) => { failed++; console.log('FAIL  ' + m); };
const eq = (name, got, want) => { if (JSON.stringify(got) !== JSON.stringify(want)) bad(`${name}: got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`); };
const must = (name, cond) => { if (!cond) bad(name); };
const read = (p) => fs.readFileSync(path.join(src, p), 'utf8');

// shares: "other" rows are no shares, kind filter, exclude, detail = kind and size
const SH = [['media', 'shares', '/srv/media', 'off', '1200000000000'], ['photos', 'sensitive', '/srv/photos', 'off', '340000000000'], ['usb', 'other', '/mnt/usb', '-', '0'], ['Bad Name', 'shares', '', '', '']];
eq('shares: all real shares', shareOptions(SH).map((o) => o.value), ['media', 'photos']);
eq('shares: detail', shareOptions(SH)[0].detail, 'share · 1.2 TB');
eq('shares: kind', shareOptions(SH, { kind: 'sensitive' }).map((o) => o.value), ['photos']);
eq('shares: kind list', shareOptions(SH, { kind: ['shares', 'sensitive'] }).map((o) => o.value), ['media', 'photos']);
eq('shares: exclude', shareOptions(SH, { exclude: 'media' }).map((o) => o.value), ['photos']);
eq('shares: none', shareOptions([]), []);

// the group value: { scope, peer, share }, two servers may hold the same share name
eq('encode local', encodeShare(shareValue('local', '', 'media')), 'local:media');
eq('encode remote', encodeShare(shareValue('remote', 'cousin', 'media')), 'remote:cousin/media');
eq('decode remote', decodeShare('remote:cousin/media'), { scope: 'remote', peer: 'cousin', share: 'media' });
eq('decode local', decodeShare('local:media'), { scope: 'local', peer: '', share: 'media' });
eq('decode empty', decodeShare(''), { scope: 'local', peer: '', share: '' });
eq('local and remote differ', encodeShare(shareValue('local', '', 'media')) === encodeShare(shareValue('remote', 'cousin', 'media')), false);
const local = shareOptions(SH);
const both = shareGroups(local, [{ peer: 'cousin', share: 'media', state: 'mounted' }], ['local', 'remote']);
eq('groups: both', both.map((o) => [o.group, o.value]), [['On this server', 'local:media'], ['On this server', 'local:photos'], ['On other servers', 'remote:cousin/media']]);
eq('groups: local only', shareGroups(local, [{ peer: 'x', share: 'y' }], ['local']).map((o) => o.group), ['On this server', 'On this server']);
eq('groups: remote stub is empty', shareGroups(local, [], ['remote']), []);

// disks: free by id (pool disks), or all (monitor disks)
const FREE = [['ata-ST4000_WX1', '4000787030016', 'HDD', ''], ['ata-ST4000_WX2', '4000787030016', 'HDD', '[has ext4 files]']];
eq('disks: free', diskOptions(FREE).map((o) => o.value), ['ata-ST4000_WX1', 'ata-ST4000_WX2']);
must('disks: detail has size and type', /HDD/.test(diskOptions(FREE)[0].detail) && /TB/.test(diskOptions(FREE)[0].detail));
must('disks: detail keeps the note', /has ext4 files/.test(diskOptions(FREE)[1].detail));
eq('disks: exclude', diskOptions(FREE, { exclude: ['ata-ST4000_WX1'] }).length, 1);
eq('disks: all', diskOptions([['sda', '4000000000000', 'HDD', 'data'], ['sdb', '1000000000000', 'SSD', '-']], { scope: 'all' }).map((o) => o.detail), ['4 TB · HDD · data', '1 TB · SSD · free']);

// pools, instances, users
const POOLS = [{ name: 'bulk', role: 'data', kind: 'snapraid', state: 'online' }, { name: 'fast', role: 'apps', kind: 'zfs', state: '-' }];
eq('pools: all', poolOptions(POOLS).map((o) => o.value), ['bulk', 'fast']);
eq('pools: role', poolOptions(POOLS, { role: 'apps' }).map((o) => o.value), ['fast']);
eq('pools: detail', poolOptions(POOLS).map((o) => o.detail), ['data · SnapRAID · online', 'apps · ZFS']);
const CTS = [['jellyfin', 'container', 'RUNNING', '10.10.95.20 (eth0)'], ['immich', 'container', 'STOPPED', '-'], ['win', 'virtual-machine', 'RUNNING', '-']];
eq('instances: all', instanceOptions(CTS).map((o) => o.value), ['jellyfin', 'immich', 'win']);
eq('instances: running', instanceOptions(CTS, { running: true }).map((o) => o.value), ['jellyfin', 'win']);
eq('instances: vm', instanceOptions(CTS, { type: 'vm' }).map((o) => o.value), ['win']);
eq('instances: detail', instanceOptions(CTS)[1].detail, 'CT · stopped');
const USERS = [['anna', 'Anna Example', 'enabled', 'Domain Admins'], ['ben', '-', 'disabled', '-']];
eq('users: all', userOptions(USERS).map((o) => o.value), ['anna', 'ben']);
eq('users: enabled', userOptions(USERS, { enabled: true }).map((o) => o.value), ['anna']);
eq('users: detail', userOptions(USERS).map((o) => o.detail), ['Anna Example', 'locked']);
eq('principals: value is the SID', principalOptions([['S-1-5-21-1-2-3-1105', 'anna', 'user']]), [{ value: 'S-1-5-21-1-2-3-1105', label: 'anna', detail: 'user' }]);
eq('principals: taken', principalOptions([['S-1', 'a', 'user'], ['S-2', 'b', 'group']], { taken: ['S-1'] }).map((o) => o.label), ['b']);

// Combobox search: the box, the aria wiring, the keys, `free`
const cb = read('ui/Combobox.svelte');
must('Combobox: search prop', /search = false/.test(cb));
must('Combobox: filter on label and detail', /o\.label\} \$\{o\.detail/.test(cb) && /\.includes\(q\)/.test(cb));
must('Combobox: filter box is role combobox', /role="combobox"/.test(cb));
must('Combobox: aria-activedescendant on the box', /aria-activedescendant=\{shown\.length/.test(cb));
must('Combobox: aria-controls the listbox', /aria-controls="\{uid\}-opts"/.test(cb) && /id="\{uid\}-opts"/.test(cb));
must('Combobox: result count for a screen reader', /role="status"/.test(cb) && /matches/.test(cb));
must('Combobox: Enter picks, Escape closes in the box', /function onsearchkey/.test(cb) && /e\.key === 'Enter'/.test(cb) && /e\.key === 'Escape'/.test(cb));
must('Combobox: type-ahead stays without search', /typeahead\(e\.key\)/.test(cb));
must('Combobox: groups are role=group', /role=\{g\.name \? 'group'/.test(cb));
must('Combobox: free offers the typed text', /free: true/.test(cb));
must('Combobox: no hex colour', !/#[0-9a-fA-F]{3,8}\b/.test(cb));

// the fields: exported, read the live store (poll, no timer of their own), carry `free`, have the three states through ServerField
const index = read('ui/index.js');
for (const name of ['ServerField', 'ShareField', 'DiskField', 'PoolField', 'InstanceField', 'UserField']) {
  const s = read(`ui/${name}.svelte`);
  must(`${name}: exported from ui/index.js`, new RegExp(`default as ${name} } from './${name}.svelte'`).test(index));
  must(`${name}: no hex colour`, !/#[0-9a-fA-F]{3,8}\b/.test(s));
  must(`${name}: no setInterval or setTimeout`, !/setInterval|setTimeout/.test(s));
  if (name === 'ServerField') {
    must('ServerField: loading, error and empty lines', /Loading \{noun\}/.test(s) && /could not be read/.test(s) && /No \{noun\} yet/.test(s));
    must('ServerField: searchable', /\bsearch\b/.test(s));
    must('ServerField: link to the create page', /createHref/.test(s));
    continue;
  }
  must(`${name}: free prop`, /\bfree\b/.test(s));
  must(`${name}: built on ServerField`, /<ServerField/.test(s) || name === 'DiskField');
  if (name !== 'PoolField') must(`${name}: reads the live state through poll`, /poll\(/.test(s));
}
must('PoolField: reads the pool store', /pools\.svelte\.js/.test(read('ui/PoolField.svelte')));
must('DiskField: reuses DiskPicker and disks.js', /DiskPicker\.svelte/.test(read('ui/DiskField.svelte')) && /disks\.js/.test(read('ui/serverfields.js')));
must('ShareField: groups prop and the scope value', /groups = \[LOCAL\]/.test(read('ui/ShareField.svelte')) && /scope/.test(read('ui/ShareField.svelte')));
must('ShareField: says server, not peer, to the user', !/(label|placeholder|text)[^\n]*"[^"\n]*\bpeer\b/i.test(read('ui/ShareField.svelte')));

// the Gallery shows every field
const gal = read('pages/Gallery.svelte');
for (const name of ['ServerField', 'ShareField', 'DiskField', 'PoolField', 'InstanceField', 'UserField']) must(`Gallery: entry ${name}`, gal.includes(`<Entry name="${name}"`));

// the converted forms use a field, not a TextInput, for the name of an existing server object
for (const [f, field] of [['forms/instances/BindStorage.svelte', 'ShareField'], ['forms/backup/RestoreFiles.svelte', 'ShareField'], ['forms/shares/AddAccess.svelte', 'UserField'],
  ['forms/shares/NewShare.svelte', 'InstanceField'], ['forms/storage/OtherDisk.svelte', 'ShareField']]) {
  must(`${f} uses ${field}`, read(f).includes(`<${field}`));
}
must('BindStorage submits the share name unchanged', /'--name', sname\.trim\(\)/.test(read('forms/instances/BindStorage.svelte')));

// the rule is written down
must('web/CLAUDE.md names the fields', /ShareField/.test(fs.readFileSync(path.join(src, '..', 'CLAUDE.md'), 'utf8')));

if (failed) { console.log(`${failed} failed`); process.exit(1); }
console.log('ok');
