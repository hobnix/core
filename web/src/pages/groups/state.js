// The state lines of the group pages (Storage, Backup, System) as plain functions: tests/web-groups.mjs runs them with node and fixtures.
// Each takes the answers the group's places already read (rows of a tsv answer; `null` = no answer yet or the read failed) and returns
// { head, cards }: `head` is the one line at the top, a card is { key, title, state, label, line, href, linkText } for a <StateCard>.
// state: ok | warn | bad | info | off. Nothing here reads anything: a group page adds no read that its places do not have (tests/web-prefetch.mjs).
import { P } from '../../paths.js';
import { bytes } from '../../format.js';

const none = { state: 'off', label: 'no data', line: 'Nothing was read yet.' };
const plural = (n, one, many = `${one}s`) => `${n} ${n === 1 ? one : many}`;
const kv = (r) => Object.fromEntries((r ?? []).map((x) => [x[0], x[1] ?? '']));
const num = (v) => (v === undefined || v === '' || v === '-' || isNaN(v) ? null : Number(v));
const card = (key, title, href, linkText, s) => ({ key, title, href, linkText, ...s });

// the worst state of the cards, as the one line on top
export function headOf(cards, what) {
  const by = (s) => cards.filter((c) => c.state === s);
  if (by('bad').length) return { state: 'bad', label: plural(by('bad').length, 'problem'), line: `${by('bad').map((c) => c.title).join(', ')} ${by('bad').length === 1 ? 'needs' : 'need'} you.` };
  if (by('warn').length) return { state: 'warn', label: plural(by('warn').length, 'warning'), line: `${by('warn').map((c) => c.title).join(', ')}: look at ${by('warn').length === 1 ? 'it' : 'them'}.` };
  if (cards.every((c) => c.state === 'off')) return { state: 'off', label: 'no data', line: `Nothing is known about ${what} yet.` };
  return { state: 'ok', label: 'healthy', line: `${what[0].toUpperCase()}${what.slice(1)} looks fine.` };
}

// ── Storage ─────────────────────────────────────────────────────────────────────────────────
// pools: the pool rows ({name, role, kind, state}); sizes: deck.data.pools ({name: {used, size}}); disks: monitor/disks rows; shares: shares/overview rows
export function storageState({ locked = false, pools = [], sizes = {}, disks = null, shares = null } = {}) {
  const lockedCard = { state: 'off', label: 'locked', line: 'Unlock the storage to see this.' };
  let poolS, diskS, shareS;
  if (locked) { poolS = diskS = shareS = lockedCard; } else {
    if (!pools.length) poolS = none;
    else {
      const bad = pools.filter((p) => p.state !== '-' && p.state !== 'online');
      const used = pools.reduce((a, p) => a + (sizes[p.name]?.used || 0), 0);
      const size = pools.reduce((a, p) => a + (sizes[p.name]?.size || 0), 0);
      const line = [plural(pools.length, 'pool'), size > 0 ? `${bytes(used)} of ${bytes(size)} used` : ''].filter(Boolean).join(', ');
      const full = pools.filter((p) => sizes[p.name]?.size > 0 && sizes[p.name].used / sizes[p.name].size >= 0.9);
      const unknown = pools.every((p) => p.state === '-');
      poolS = bad.length
        ? { state: bad.some((p) => !/degraded/i.test(p.state)) ? 'bad' : 'warn', label: bad.map((p) => `${p.name} ${p.state}`).join(', '), line }
        : full.length ? { state: 'warn', label: `${full[0].name} nearly full`, line }
          : { state: unknown ? 'off' : 'ok', label: unknown ? 'unknown' : 'online', line };
    }
    if (!disks) diskS = none;
    else {
      // monitor/disks: name, size, kind, role, temp, smart, hours, realloc, pending, crc ...
      const att = disks.filter((r) => /fail|bad/i.test(r[5] ?? '') || Number(r[8]) > 0 || Number(r[7]) > 0);
      diskS = att.length ? { state: 'warn', label: `${att.length} ${att.length === 1 ? 'needs' : 'need'} attention`, line: `${plural(disks.length, 'disk')}: ${att.map((r) => r[0]).join(', ')}` }
        : { state: disks.length ? 'ok' : 'off', label: disks.length ? 'healthy' : 'none found', line: plural(disks.length, 'disk') };
    }
    shareS = shares ? { state: shares.length ? 'ok' : 'off', label: plural(shares.length, 'share'), line: shares.length ? `${plural(shares.length, 'share')} on this server.` : 'No share yet.' } : none;
  }
  const enc = { state: locked ? 'warn' : 'ok', label: locked ? 'locked' : 'unlocked', line: locked ? 'The encrypted storage is locked: nothing on it is available.' : 'The encrypted storage is open.' };
  const cards = [
    card('pools', 'Pools', P.pools, 'Open pools', poolS), card('disks', 'Disks', P.disks, 'Open disks', diskS),
    card('shares', 'Shares', P.shares, 'Open shares', shareS), card('encryption', 'Encryption', P.encryption, 'Open encryption', enc),
  ];
  return { head: headOf(cards, 'the storage'), cards };
}

// ── Backup ──────────────────────────────────────────────────────────────────────────────────
// backup: backup/state rows (key, value); expiry: expiry/list rows (name, date, days, state, note); now: epoch seconds
export function backupState({ backup = null, expiry = null, now = Math.floor(Date.now() / 1000) } = {}) {
  let b;
  if (!backup) b = none;
  else {
    const s = kv(backup);
    const ok = num(s.last_ok), nxt = num(s.next);
    const ago = ok ? `${Math.max(0, Math.round((now - ok) / 3600))} h ago` : '';
    const off = s.offsite_ok === 'yes' || s.offsite === 'yes' ? 'off-site copy on' : '';
    const old = ok && now - ok > 36 * 3600;
    if (s.configured !== 'yes') b = { state: 'off', label: 'not set up', line: 'No backup is configured yet.' };
    else if (s.status === 'failed') b = { state: 'bad', label: 'last backup failed', line: ok ? `Last good one ${ago}.` : 'No backup has worked yet.' };
    else if (!ok) b = { state: 'warn', label: 'no backup yet', line: 'No backup has finished yet.' };
    else b = { state: old ? 'warn' : 'ok', label: old ? 'old' : 'last ok', line: `${[`Last backup ${ago}`, nxt ? `next in ${Math.max(0, Math.round((nxt - now) / 3600))} h` : '', off].filter(Boolean).join(', ')}.` };
  }
  let e;
  if (!expiry) e = none;
  else {
    const due = expiry.filter((r) => ['due', 'expired', 'invalid'].includes(r[3]));
    const soon = expiry.filter((r) => r[3] === 'soon');
    e = due.length ? { state: 'bad', label: `${due.length} due`, line: due.map((r) => r[0]).join(', ') }
      : soon.length ? { state: 'warn', label: `${soon.length} soon`, line: soon.map((r) => r[0]).join(', ') }
        : { state: expiry.length ? 'ok' : 'off', label: expiry.length ? 'fine' : 'none', line: expiry.length ? `${plural(expiry.length, 'date')} watched, none soon.` : 'Nothing is watched.' };
  }
  const cards = [card('backup', 'Backup', P.backup, 'Open backup', b), card('expiry', 'Expiry dates', P.expiry, 'Open expiry dates', e)];
  return { head: headOf(cards, 'the backup'), cards };
}

// ── System (the former Health) ──────────────────────────────────────────────────────────────
// problems: health/list rows (id, text, acked|..); updates: system/updates rows (key, value); certs: dc/state rows; ups: ups/status rows; events: event/list rows
const SEVERE = /BAD|failed|errors?\b|expired|ran out|not healthy|DEGRADED|FAULTED|is locked|are locked|battery is low|power is out|open to everyone/i;   // as pages/Health.svelte
export function systemState({ problems = null, updates = null, certs = null, ups = null, events = null } = {}) {
  let h;
  if (!problems) h = none;
  else {
    const open = problems.filter((r) => r[2] !== 'acked');
    const severe = open.filter((r) => SEVERE.test(r[1] ?? ''));
    h = severe.length ? { state: 'bad', label: plural(severe.length, 'problem'), line: `${plural(open.length, 'open problem')}, ${severe.length} serious.` }
      : open.length ? { state: 'warn', label: plural(open.length, 'problem'), line: `${plural(open.length, 'open problem')}.` }
        : { state: 'ok', label: 'healthy', line: problems.length ? `${plural(problems.length, 'problem')} acknowledged.` : 'No problem found.' };
  }
  let u;
  if (!updates) u = none;
  else {
    const behind = num(kv(updates).behind);
    u = behind === null ? { state: 'off', label: 'unknown', line: 'It is not known whether updates are waiting.' }
      : behind > 0 ? { state: 'info', label: `${behind} behind`, line: `This server is ${plural(behind, 'commit')} behind.` }
        : { state: 'ok', label: 'up to date', line: 'This server is up to date.' };
  }
  let c;
  if (!certs) c = none;
  else {
    const s = kv(certs);
    const days = num(s.days_left);
    c = s.ca !== 'yes' ? { state: 'off', label: 'none', line: 'No certificate authority on this server.' }
      : days !== null && days < 0 ? { state: 'bad', label: 'expired', line: 'The certificate has run out.' }
        : days !== null && days < 60 ? { state: 'warn', label: `${days} days left`, line: `The certificate runs out in ${plural(days, 'day')}.` }
          : { state: 'ok', label: 'valid', line: days === null ? 'The certificate is valid.' : `${plural(days, 'day')} left.` };
  }
  let hw;
  if (!ups) hw = none;
  else {
    const s = kv(ups);
    hw = s.configured !== 'yes' ? { state: 'off', label: 'no UPS', line: 'No UPS is set up.' }
      : s.reachable !== 'yes' ? { state: 'warn', label: 'UPS unreachable', line: 'The UPS does not answer.' }
        : { state: 'ok', label: 'UPS ok', line: s.charge ? `Battery at ${s.charge} %.` : 'The UPS answers.' };
  }
  let ev;
  if (!events) ev = none;
  else {
    const err = events.filter((r) => r[5] === 'error').length;
    const warn = events.filter((r) => r[5] === 'warn').length;
    ev = err ? { state: 'warn', label: plural(err, 'error'), line: `${plural(events.length, 'recent event')}, ${plural(err, 'error')}.` }
      : { state: events.length ? 'ok' : 'off', label: events.length ? 'quiet' : 'none', line: events.length ? `${plural(events.length, 'recent event')}${warn ? `, ${plural(warn, 'warning')}` : ''}.` : 'No event yet.' };
  }
  const cards = [
    card('health', 'Health', P.health, 'Open health', h), card('updates', 'Updates', P.settingsUpdates, 'Open updates', u),
    card('certificates', 'Certificates', P.certificates, 'Open certificates', c), card('hardware', 'Hardware', P.hardware, 'Open hardware', hw),
    card('events', 'Events', P.events, 'Open events', ev),
  ];
  return { head: headOf(cards, 'the system'), cards };
}
