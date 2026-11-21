// The data of the disks, shared by the list with its quick look (pages/Disks.svelte) and the page of one disk (pages/disks/Disk.svelte): the same reads, the same words.
// Call it while a component is initialised (it makes polls and deriveds). `filter()` is the list filter (all | <pool> | none | missing); `sel()` is the device name of
// the disk the page or the quick look is about; `detail: true` also reads the SMART history and the self-test results of that disk (the page does, the quick look does not).
import { poll, rows } from '../../data.svelte.js';
import { live } from '../../live.svelte.js';
import { pools } from '../../pools.svelte.js';
import { healthDot } from '../../format.js';
import { sleepOf, parsePower } from '../../disk-sleep.js';
import { rowstate } from '../../rowstate.svelte.js';
import { diskPending, failedOf } from '../storage/pending.js';
import { diskPool, poolTopic, hoursTxt, roleLabel, serialIn } from '../storage/pool.js';

export function diskModel({ filter = () => 'all', sel = () => '', detail = false } = {}) {
  // the one SnapRAID pool (its disks are labelled "bulk data-01" by monitor disks, an internal prefix)
  const snapName = $derived(pools.rows.find((p) => p.kind !== 'zfs')?.name ?? '');

  const mon = poll('/api/sys/monitor/disks', 30000, 'monitor-disks');
  const health = poll('/api/sys/disk-health/list', 60000, 'disk-health');
  const inv = poll('/api/sys/state/disks', 30000, 'disk-inventory');
  // sleep since / wakes today per disk and the measured power numbers (each with its source)
  const powerPoll = poll('/api/sys/disk/power', 60000, 'monitor-disks');
  const pw = $derived(parsePower(rows(powerPoll)));
  // data disks that are out of the pool by hand: member, detached | recovering, since (epoch)
  const marks = poll('/api/sys/disk/marks', 15000, 'disk-marks');
  const markOf = $derived(Object.fromEntries(rows(marks).map((r) => [r[0], r[1]])));
  const poolInfo = poll(() => (snapName ? `/api/sys/pool/info?pool=${snapName}` : ''), 60000, () => poolTopic('info', snapName, live.topics));
  const snapPool = $derived(rows(poolInfo).some((r) => /SnapRAID/i.test(r[0] ?? '')));

  // monitor disks: name, bytes, SSD/HDD, role, temp, health, hours, reallocated, pending, crc, model+serial, free, power, filesystem (xfs, ext4, zfs, ... / none / -)
  const all = $derived(rows(mon).map((r) => ({
    name: r[0], size: Number(r[1]), kind: r[2], role: r[3], temp: r[4], smart: r[5], hours: r[6], realloc: r[7], pending: r[8], crc: r[9], model: r[10], free: r[11], sleep: sleepOf(r), fs: r[13],
  })));
  // disk-health list: name, size, kind, model, verdict, hours, first reason
  const verdicts = $derived(Object.fromEntries(rows(health).map((r) => [r[0], { verdict: r[4], reason: r[6] }])));
  // state disks: serial, model, size, dev, state, role, pool, first_seen, last_seen, worse, note
  const known = $derived(rows(inv).map((r) => ({ serial: r[0], model: r[1], size: Number(r[2]), dev: r[3], state: r[4], role: r[5], first: r[7], lastSeen: Number(r[8]), note: r[10] })));
  const missing = $derived(known.filter((k) => k.state === 'missing'));

  const isLoose = (d) => d.role === 'free' || d.role === 'mounted';
  // the pool a disk belongs to ("bulk ..." labels are the SnapRAID pool, whatever its name)
  const poolOf = (d) => { const p = diskPool(d.role); return p === 'bulk' && snapName ? snapName : p; };
  const disk = $derived(filter() === 'missing' ? null : all.find((d) => d.name === sel()) ?? null);
  const gone = $derived(filter() === 'missing' ? missing.find((m) => m.serial === sel()) ?? null : null);

  // members: the SnapRAID pool and the pool the page is looking at (the filter, else the pool of the selected disk)
  const zName = $derived(pools.rows.some((p) => p.name === filter() && p.name !== snapName) ? filter() : disk && poolOf(disk) !== snapName ? poolOf(disk) : '');
  const membSnap = poll(() => (snapName ? `/api/sys/pool/members?pool=${snapName}` : ''), 30000, () => poolTopic('members', snapName, live.topics));
  const membZ = poll(() => (zName ? `/api/sys/pool/members?pool=${zName}` : ''), 30000, () => poolTopic('members', zName, live.topics));

  const counts = $derived({
    all: all.length, ...Object.fromEntries(pools.rows.map((p) => [p.name, all.filter((d) => poolOf(d) === p.name).length])),
    none: all.filter(isLoose).length, missing: missing.length,
  });
  const visible = $derived(all.filter((d) => (filter() === 'all' ? true : filter() === 'none' ? isLoose(d) : filter() === 'missing' ? false : poolOf(d) === filter())));

  const verdictOf = (d) => {
    const v = verdicts[d.name]?.verdict;
    return v && v !== '-' ? v : d.smart && d.smart !== '-' ? d.smart : 'idle';
  };
  // the pool member a disk is (SnapRAID: "bulk data-01" -> data-01; ZFS: the by-id name of the members list) and its group (data | parity | mirror-0 ...)
  const membRows = (p) => (p === snapName ? rows(membSnap) : p === zName ? rows(membZ) : []);
  const snapRole = (d) => /^bulk (data|parity)-\d+$/.test(d?.role ?? '');
  const memberOf = (d) => {
    if (!d || !poolOf(d)) return '';
    if (snapRole(d)) return d.role.replace(/^bulk /, '');
    return membRows(poolOf(d)).map((r) => r[0]).find((n) => serialIn(d.model, n)) ?? '';
  };
  const stateOf = (d) => (markOf[memberOf(d)] ? 'info' : healthDot(verdictOf(d) === 'idle' ? '' : verdictOf(d)));
  const wordOf = (d) => (markOf[memberOf(d)] ? markOf[memberOf(d)] : verdictOf(d));
  // the model column holds "model serial": split off the last word
  const modelOf = (d) => (d.model ?? '').trim().replace(/\s+\S+$/, '');
  const serialOf = (d) => (d.model ?? '').trim().split(/\s+/).pop();
  const roleText = (d) => {
    if (snapRole(d)) return roleLabel(d.role);
    const g = membRows(poolOf(d)).find((r) => r[0] === memberOf(d))?.[3];
    return g && g !== '-' ? g : roleLabel(d.role);
  };
  // what a disk is doing (format, test, detach, recover, move, forget): any job that names the device, its pool member or its serial; also one started in a terminal
  const namesOf = (d) => [d.name, memberOf(d), serialOf(d)];
  const doingOf = (d) => diskPending(namesOf(d), rowstate.active);
  const failureOfDisk = (d) => failedOf('disk', namesOf(d), rowstate.failedLead);
  const poolText = (d) => poolOf(d) || (isLoose(d) ? 'free' : d.role);
  const dataMembers = (p) => membRows(p).filter((r) => r[3] === 'data' && r[2] === 'ONLINE').map((r) => r[0]);
  // the pane next to a disk in the file manager: another data disk (a pool disk and its own pool never meet there)
  const otherDisk = (member) => { const o = dataMembers(snapName).find((n) => n !== member); return o ? `disk:${o}` : ''; };

  // ── the page of one disk: SMART history and self-tests (read only when `detail`)
  const rec = $derived(known.find((k) => k.dev === disk?.name && k.state !== 'missing'));
  const serial = $derived(rec?.serial ?? '');
  const hist = poll(() => (detail && serial ? `/api/sys/state/smart/${encodeURIComponent(serial)}` : ''), 60000, 'disk-health');
  const results = poll(() => (detail && disk ? `/api/sys/disk/results/${encodeURIComponent(disk.name)}` : ''), 60000);
  // state smart: time, realloc, pending, crc, temp, hours (newest first)
  const readings = $derived(rows(hist).map((r) => ({ t: Number(r[0]), pending: Number(r[2]), temp: Number(r[4]) })).filter((x) => !isNaN(x.t)).reverse());
  const spanTxt = $derived.by(() => {
    if (readings.length < 2) return '';
    const h = (readings[readings.length - 1].t - readings[0].t) / 3600;
    return h <= 48 ? `last ${Math.max(1, Math.round(h))} hours` : `last ${Math.round(h / 24)} days`;
  });
  const pts = (vals, w, y) => vals.map((v, i) => `${((i / Math.max(1, vals.length - 1)) * w).toFixed(1)},${y(v).toFixed(1)}`).join(' ');
  const pend = $derived(readings.filter((x) => !isNaN(x.pending)).map((x) => x.pending));
  const pendMax = $derived(Math.max(10, ...pend));
  const linePts = $derived(pts(pend, 400, (v) => 56 - (v / pendMax) * 50));
  const temps = $derived(readings.filter((x) => !isNaN(x.temp)).map((x) => x.temp));
  const tempPts = $derived(pts(temps, 400, (v) => 40 - Math.max(0.05, Math.min(0.95, (v - 20) / 35)) * 40));
  // `disk results` lines: "Short offline Completed without error at 21400 h"
  const tests = $derived(rows(results).map((r) => r.join(' ').trim()).filter((l) => l && !/^none yet/i.test(l) && !/^A test is running/i.test(l)).map((l) => {
    const m = /^(\S+)\s+(?:\S+\s+)?(.*?)\s*(?:at (\d+) h)?$/.exec(l);
    return { kind: /^ext/i.test(m?.[1] ?? '') ? 'long' : (m?.[1] ?? l).toLowerCase(), result: m?.[2] ?? '', when: m?.[3] ? `at ${hoursTxt(m[3])}` : '' };
  }));
  const running = $derived(rows(results).map((r) => r.join(' ')).find((l) => /^A test is running/i.test(l)));

  return {
    mon, health, inv, hist, results, marks,
    get snapName() { return snapName; }, get snapPool() { return snapPool; }, get pw() { return pw; }, get markOf() { return markOf; },
    get all() { return all; }, get known() { return known; }, get missing() { return missing; }, get verdicts() { return verdicts; },
    get counts() { return counts; }, get visible() { return visible; }, get disk() { return disk; }, get gone() { return gone; },
    get rec() { return rec; }, get serial() { return serial; }, get readings() { return readings; }, get spanTxt() { return spanTxt; },
    get linePts() { return linePts; }, get tempPts() { return tempPts; }, get temps() { return temps; }, get tests() { return tests; }, get running() { return running; },
    isLoose, namesOf, poolOf, verdictOf, stateOf, wordOf, modelOf, serialOf, roleText, memberOf, snapRole, doingOf, failureOfDisk, poolText, dataMembers, otherDisk,
  };
}
