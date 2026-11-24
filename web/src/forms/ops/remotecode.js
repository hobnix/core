// Helpers of the remote share code forms (RemoteAdd, RemoteGive, RemoteCode). Plain functions, tested by tests/web-remote-code.mjs.

// the servers Add remote share offers by name: nodes of kind peer whose key works (rows of `hs sys node list`: name, kind, host, port, source, key)
export function serverOptions(nodeRows) {
  return (nodeRows ?? []).filter((r) => r[1] === 'peer' && r[5] === 'ok').map((r) => ({ value: r[0], label: r[0], detail: r[2] }));
}

// the code field takes CODE or CODE@host; the first part is what is checked here (16 characters of the code alphabet, dashes and spaces ignored)
export function splitCode(text) {
  const t = String(text ?? '').trim();
  const at = t.indexOf('@');
  const code = (at < 0 ? t : t.slice(0, at)).replace(/[\s-]/g, '').toUpperCase();
  return { code, host: at < 0 ? '' : t.slice(at + 1).trim(), ok: /^[A-HJ-NP-Z2-9]{16}$/.test(code) };
}

// the answer of `peers start code`: { code, address, seconds } from the `secret` lines. null when it holds no code.
export function codeAnswer(r) {
  const s = r?.secret;
  if (!s?.code) return null;
  return { code: s.code, address: s.address ?? '', seconds: Math.max(0, Number(s.expires_in) || 0) };
}
export const shown = (a) => (a.address ? `${a.code}@${a.address}` : a.code);   // the code as the other server types it

export function countdown(sec) {
  const n = Math.max(0, Math.floor(sec));
  return `${Math.floor(n / 60)}:${String(n % 60).padStart(2, '0')}`;
}

// The events `remote.claimed` that can be the use of THIS code: after the dialog opened (id > fromId), not after the code ran out (time <= until, epoch
// seconds; an event without a time is kept), about this share, about the server named when the code was bound, and WITH a fingerprint (the giving side;
// a share another server pushes here has a host and no fingerprint, it is no use of this code). Rows of the stream: { id, time, source, kind, subject,
// payload } (payload an object or JSON text). The code itself is never in an event.
export function claimsOf(events, { fromId = 0, until = Infinity, share = '', server = '' } = {}) {
  const out = [];
  for (const e of events ?? []) {
    if (!e || e.id <= fromId || e.source !== 'remote' || e.kind !== 'claimed') continue;
    if (e.time && Number(e.time) > until) continue;
    let p = e.payload;
    if (typeof p === 'string') { try { p = JSON.parse(p); } catch { p = null; } }
    if (!p || !p.fingerprint) continue;
    if (share && p.share && p.share !== '-' && p.share !== share) continue;
    if (server && p.server !== server) continue;
    const fp = String(p.fingerprint);
    out.push({ server: p.server ?? e.subject ?? '', fingerprint: fp.startsWith('SHA256:') ? fp : `SHA256:${fp}` });
  }
  return out;
}

// What the dialog says: nothing yet, one server (named: "<server> connected"), or an ambiguous claim (no name was given and several claims could be
// this code: show it neutrally, never as "connected"). A proper match needs a code id in the start answer (follow-up, PR #1167).
export function claimState(claims, bound) {
  if (!claims.length) return null;
  if (bound || claims.length === 1) return { kind: 'connected', ...claims[0] };
  return { kind: 'ambiguous', claims };
}
