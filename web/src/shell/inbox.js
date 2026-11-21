// The Inbox behind the bell in the top bar (#783, design 4.5 and 4.11), as plain functions (tests/web-inbox.mjs runs them with node).
// Problems: the rows of `hs sys health list` (id, text, acked|-, since, told). Notifications: the warn and error rows of the domain event stream
// (live.events, the same row shape as pages/events.js). The count is the unacknowledged problems plus the unread notifications; an acknowledged
// problem stays in the list, dimmed, and is not counted. Everything is plain text: nothing here becomes HTML.
import { parseRow, eventText } from '../pages/events.js';

const empty = (v) => (v == null || v === '-' ? '' : String(v));

// The page of the object a problem text is about (a few words of the texts of scripts/health-check.sh); anything else goes to the Health page.
const PROBLEM_OBJECT = [
  [/backup|restore drill|off-site/i, '/protection/backup'],
  [/disk|SMART|self-test|scrub|parity|snapraid|zfs|pool/i, '/storage/disks'],
];
const HEALTH = '/operations/health';

// rows of health/list -> [{ kind: 'problem', id, text, acked, since, href }], acknowledged ones last
export function problemItems(rows) {
  const out = (rows ?? [])
    .filter((r) => Array.isArray(r) && r[0] && r[0] !== '-' && !String(r[0]).startsWith('mitigation:'))
    .map((r) => {
      const text = empty(r[1]) || empty(r[0]);
      return { kind: 'problem', id: String(r[0]), text, acked: r[2] === 'acked', since: Number(r[3]) || 0, until: /^\d+$/.test(r[5] ?? '') ? Number(r[5]) : 0, href: (PROBLEM_OBJECT.find(([re]) => re.test(text)) ?? [null, HEALTH])[1] };
    });
  return [...out.filter((p) => !p.acked), ...out.filter((p) => p.acked)];
}

// the page of the object an event is about, from its source and subject
export function eventHref(e) {
  const s = encodeURIComponent(e.subject);
  if (e.source === 'job') return '/operations/jobs';
  if (e.source === 'disk') return '/storage/disks';
  if (e.source === 'storage') return e.subject ? `/storage/pools/${s}` : '/storage/pools';
  if (e.source === 'ct') return '/instances';
  return '/operations/events';
}

// rows of the event stream -> notifications, newest first. Health rows are the problems above and audit rows are the log, so both are left out.
export function notificationItems(events, lang = 'en') {
  return (events ?? []).map(parseRow)
    .filter((e) => e.id && e.level !== 'info' && e.source !== 'health' && e.source !== 'audit')
    .map((e) => ({ kind: 'notification', id: e.id, level: e.level, text: eventText(e, lang), time: e.time, href: eventHref(e) }))
    .sort((a, b) => b.id - a.id);
}

// the bell: unacknowledged problems plus notifications newer than `readUpTo` (the id of the newest one seen when the list was opened)
export function bellCount(problems, notifications, readUpTo = 0) {
  return problems.filter((p) => !p.acked).length + notifications.filter((n) => n.id > readUpTo).length;
}

export const newestId = (notifications) => notifications.reduce((m, n) => Math.max(m, n.id), 0);
