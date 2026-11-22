// The group pages (docs/PLAN-navigation.md step 9): the state lines of Storage, Backup and System as plain functions with fixtures (locked storage, an
// offline pool, no data), and the source rules of the pages (reads only what the places read, one action at most, no own icons or colours). Run with node.
import { readFileSync } from 'node:fs';
import { P } from '../web/src/paths.js';
import { readsFor } from '../web/src/readsfor.js';
import { storageState, backupState, systemState, headOf } from '../web/src/pages/groups/state.js';

let ok = 0, bad = 0;
const eq = (name, got, want) => { if (JSON.stringify(got) === JSON.stringify(want)) { ok++; console.log(`  ok    ${name}`); } else { bad++; console.log(`  FAIL  ${name}: got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`); } };
const src = (p) => readFileSync(new URL(`../web/src/${p}`, import.meta.url), 'utf8').replace(/\r\n/g, '\n');
const by = (s, key) => s.cards.find((c) => c.key === key);

// ── Storage
const pool = (name, state = 'online') => ({ name, role: 'data', kind: 'zfs', state });
const sizes = { tank: { used: 500e9, size: 1000e9 } };
const disks = [['sda', '1T', 'hdd', 'data', '30', 'PASSED', '100', '0', '0'], ['sdb', '1T', 'hdd', 'data', '31', 'PASSED', '100', '0', '0']];
const fine = storageState({ pools: [pool('tank')], sizes, disks, shares: [['media']] });
eq('Storage: a healthy server says healthy', [fine.head.state, by(fine, 'pools').state, by(fine, 'disks').state, by(fine, 'shares').state], ['ok', 'ok', 'ok', 'ok']);
eq('Storage: one card per place, each with an address', fine.cards.map((c) => [c.key, c.href]), [['pools', P.pools], ['disks', P.disks], ['shares', P.shares], ['encryption', P.encryption]]);
const locked = storageState({ locked: true, pools: [pool('tank')], sizes, disks, shares: [['media']] });
eq('Storage: locked storage shows locked on pools, disks and shares, never numbers', ['pools', 'disks', 'shares'].map((k) => [by(locked, k).state, by(locked, k).label]), [['off', 'locked'], ['off', 'locked'], ['off', 'locked']]);
eq('Storage: locked storage is a warning on top', [locked.head.state, by(locked, 'encryption').label], ['warn', 'locked']);
const off = storageState({ pools: [pool('tank', 'faulted')], sizes, disks, shares: [] });
eq('Storage: an offline pool is a problem and is named', [off.head.state, by(off, 'pools').state, by(off, 'pools').label], ['bad', 'bad', 'tank faulted']);
eq('Storage: a degraded pool is a warning', by(storageState({ pools: [pool('tank', 'degraded')], sizes }), 'pools').state, 'warn');
eq('Storage: a pool over 90 % is a warning', by(storageState({ pools: [pool('tank')], sizes: { tank: { used: 950e9, size: 1000e9 } } }), 'pools').state, 'warn');
eq('Storage: a disk with pending sectors needs attention', by(storageState({ pools: [pool('tank')], sizes, disks: [['sda', '1T', 'hdd', 'data', '30', 'PASSED', '1', '0', '8']] }), 'disks').state, 'warn');
const none = storageState({});
eq('Storage: no data is off on pools, disks and shares, never ok', none.cards.slice(0, 3).map((c) => c.state), ['off', 'off', 'off']);

// ── Backup
const NOW = 1_800_000_000;
const kv = (o) => Object.entries(o);
const bk = (o) => backupState({ backup: kv({ configured: 'yes', ...o }), expiry: [], now: NOW });
eq('Backup: a recent backup is ok', by(bk({ last_ok: NOW - 3600, next: NOW + 7200 }), 'backup').state, 'ok');
eq('Backup: a backup older than a day and a half is a warning', by(bk({ last_ok: NOW - 40 * 3600 }), 'backup').state, 'warn');
eq('Backup: a failed backup is a problem and says when the last good one was', [by(bk({ status: 'failed', last_ok: NOW - 7200 }), 'backup').state, by(bk({ status: 'failed', last_ok: NOW - 7200 }), 'backup').line], ['bad', 'Last good one 2 h ago.']);
eq('Backup: not configured is off', by(backupState({ backup: kv({ configured: 'no' }), expiry: [] }), 'backup').label, 'not set up');
eq('Backup: an expiry date that is due is a problem, one that is soon a warning', [by(backupState({ backup: null, expiry: [['cert', '-', '-', 'due']] }), 'expiry').state, by(backupState({ backup: null, expiry: [['cert', '-', '-', 'soon']] }), 'expiry').state], ['bad', 'warn']);
const nb = backupState({});
eq('Backup: no data is off on every card and on top', [nb.head.state, nb.cards.map((c) => c.state)], ['off', ['off', 'off']]);
eq('Backup: cards point at Backup and Expiry', nb.cards.map((c) => c.href), [P.backup, P.expiry]);

// ── System
const sys = systemState({ problems: [['a', 'Pool tank is DEGRADED', ''], ['b', 'Backup is old', 'acked']], updates: kv({ behind: '3' }), certs: kv({ ca: 'yes', days_left: '20' }), ups: kv({ configured: 'no' }), events: [['x', 'x', 'x', 'x', 'x', 'error']] });
eq('System: a serious open problem is a problem; an acknowledged one does not count', [by(sys, 'health').state, by(sys, 'health').line], ['bad', '1 open problem, 1 serious.']);
eq('System: updates behind are information, not an alarm', [by(sys, 'updates').state, by(sys, 'updates').label], ['info', '3 behind']);
eq('System: a certificate that runs out soon is a warning', by(sys, 'certificates').state, 'warn');
eq('System: no UPS is off', by(sys, 'hardware').state, 'off');
eq('System: the worst card is the line on top', [sys.head.state, sys.head.label], ['bad', '1 problem']);
const ns = systemState({});
eq('System: no data is off on all five cards and on top', [ns.head.state, ns.cards.map((c) => c.state)], ['off', ['off', 'off', 'off', 'off', 'off']]);
eq('System: Hardware, Updates and Certificates sit inside it', ns.cards.map((c) => c.href), [P.health, P.updates, P.certificates, P.hardware, P.events]);
eq('headOf: nothing known says no data', headOf([{ state: 'off' }], 'x').label, 'no data');

// ── the pages (source checks stand in for the components)
const pages = { Storage: 'pages/groups/Storage.svelte', Backup: 'pages/groups/Backup.svelte', System: 'pages/groups/System.svelte' };
const ofGroup = { Storage: P.storage, Backup: P.backupGroup, System: P.system };
for (const [n, f] of Object.entries(pages)) {
  const s = src(f);
  const polled = [...s.matchAll(/poll\('([^']+)'/g)].map((m) => m[1]);
  eq(`${n}: every read of the page is in the reads of the group (prefetch)`, polled.length > 0 && polled.every((p) => readsFor(ofGroup[n]).includes(p)), true);
  eq(`${n}: at most one visible button`, (s.match(/<Button\b/g) ?? []).length <= 1, true);
  eq(`${n}: no own icon class, no hex colour, no raw button`, [/\bph-/.test(s), /#[0-9a-f]{3,8}\b/i.test(s), /<button\b/.test(s)], [false, false, false]);
}
const gp = src('pages/GroupPage.svelte');
eq('GroupPage: state line first, then the cards; no raw button, no own icon', [gp.indexOf('state.head') < gp.indexOf('state.cards'), /<button\b/.test(gp), /\bph-/.test(gp)], [true, false, false]);
const sec = src('pages/Section.svelte');
eq('Section: no pool bars any more, no ph- class, no inline style', [/poolStore|bytes\(/.test(sec), /\bph-/.test(sec), /style="/.test(sec)], [false, false, false]);

console.log(`  -> ${ok} ok, ${bad} failed`);
process.exit(bad ? 1 : 0);
