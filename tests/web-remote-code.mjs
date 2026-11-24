// The remote share code forms (web/src/forms/ops/Remote*.svelte, remotecode.js): unit tests of the helpers and a static contract per form source
// (no svelte in this checkout). Run with node, no dependencies.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { serverOptions, splitCode, codeAnswer, shown, countdown, claimsOf, claimState } from '../web/src/forms/ops/remotecode.js';

const src = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'web', 'src');
let failed = 0;
const bad = (m) => { failed++; console.log('FAIL  ' + m); };
const eq = (name, got, want) => { if (JSON.stringify(got) !== JSON.stringify(want)) bad(`${name}: got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`); };
const must = (name, cond) => { if (!cond) bad(name); };
const read = (p) => fs.readFileSync(path.join(src, p), 'utf8');

// the known servers: kind peer with a working key only
eq('servers', serverOptions([['alpha', 'peer', 'alpha.local', '22', 'file', 'ok'], ['vps', 'vps', 'v', '22', 'file', 'ok'], ['beta', 'peer', 'b', '22', 'file', 'missing']]),
  [{ value: 'alpha', label: 'alpha', detail: 'alpha.local' }]);
eq('servers: none', serverOptions(undefined), []);

// the code field
eq('code: with address', splitCode('k7qx-9m2d t4pw-3hnc@alpha.local:8480'), { code: 'K7QX9M2DT4PW3HNC', host: 'alpha.local:8480', ok: true });
eq('code: alone', splitCode('K7QX-9M2D-T4PW-3HNC').ok, true);
eq('code: short', splitCode('K7QX-9M2D').ok, false);
eq('code: letters outside the alphabet (0 O 1 I)', splitCode('K7QX-9M2D-T4PW-3HN0').ok, false);

// the answer and what is shown
const a = codeAnswer({ secret: { code: 'K7QX9M2DT4PW3HNC', address: 'alpha.local:8480', expires_in: '600' } });
eq('answer', a, { code: 'K7QX9M2DT4PW3HNC', address: 'alpha.local:8480', seconds: 600 });
eq('shown', shown(a), 'K7QX9M2DT4PW3HNC@alpha.local:8480');
eq('no code', codeAnswer({ secret: { password: 'x' } }), null);
eq('countdown', [countdown(600), countdown(59), countdown(-3)], ['10:00', '0:59', '0:00']);

// the event that turns the dialog into "connected"
const ev = (o) => ({ id: 5, time: 1000, source: 'remote', kind: 'claimed', subject: 'beta', payload: { server: 'beta', share: 'media', fingerprint: 'abc' }, ...o });
const q = (o) => ({ fromId: 0, until: 2000, share: 'media', server: '', ...o });
eq('claimed', claimsOf([ev({})], q({ server: 'beta' })), [{ server: 'beta', fingerprint: 'SHA256:abc' }]);
eq('claimed: json text payload, key already named', claimsOf([ev({ payload: '{"server":"beta","share":"media","fingerprint":"SHA256:xyz"}' })], q()), [{ server: 'beta', fingerprint: 'SHA256:xyz' }]);
eq('push event ignored (host, no fingerprint)', claimsOf([ev({ payload: { server: 'beta', share: 'media', host: 'beta.local' } })], q()), []);
eq('claim before the dialog opened ignored', claimsOf([ev({})], q({ fromId: 5 })), []);
eq('wrong server name ignored', claimsOf([ev({})], q({ server: 'gamma' })), []);
eq('expired ignored', claimsOf([ev({ time: 2001 })], q()), []);
eq('another share ignored', claimsOf([ev({})], q({ share: 'photos' })), []);
eq('another kind ignored', claimsOf([ev({ kind: 'code.made' })], q()), []);
const one = claimsOf([ev({})], q());
const two = claimsOf([ev({}), ev({ id: 6, payload: { server: 'gamma', share: 'media', fingerprint: 'def' } })], q());
eq('state: none', claimState([], false), null);
eq('state: bound name connects', claimState(two.slice(0, 1), true)?.kind, 'connected');
eq('state: one unbound claim connects', claimState(one, false)?.server, 'beta');
eq('state: several unbound claims are ambiguous, not connected', claimState(two, false)?.kind, 'ambiguous');

// static contracts
const add = read('forms/ops/RemoteAdd.svelte'), give = read('forms/ops/RemoteGive.svelte'), code = read('forms/ops/RemoteCode.svelte'), rs = read('pages/shares/RemoteShares.svelte');
must('add: the code goes on stdin, not in the arguments', /const stdin = \(\) =>/.test(add) && !/a\.push\([^)]*code/.test(add) && /area="peers" \{args\} \{stdin\}/.test(add));
must('add: add-code with --server and --reconnect', add.includes("'add-code'") && add.includes("'--server'") && add.includes("'--reconnect'"));
must('add: the fallback by hand is the old form', add.includes('Enter a login by hand') && add.includes('RemoteMount'));
must('add: a server field, not a text input', add.includes('<ServerField') && !/<TextInput[^>]*bind:value=\{server\}/.test(add));
must('give: ShareField and the code action', give.includes('<ShareField') && give.includes("['code', share]") && give.includes("'--peer'"));
must('code: panel with padding', code.includes('panel="dialog"'));
must('add: server label follows args in reconnect mode', add.includes('optional') && add.includes('!!reconnect'));
must('code: waits for the event, keeps nothing', code.includes('claimsOf(live.events') && !/localStorage|sessionStorage/.test(code));
must('rows: Reconnect and New code', rs.includes('Reconnect…') && rs.includes('New code…') && !rs.includes('New password') && rs.includes('reconnect: r.peer'));
for (const f of ['forms/ops/RemoteAdd.svelte', 'forms/ops/RemoteGive.svelte', 'forms/ops/RemoteCode.svelte', 'pages/shares/RemoteShares.svelte']) {
  const t = read(f).replace(/<script>[\s\S]*?<\/script>/, '');      // the markup only: what the user reads
  const words = [...t.matchAll(/>([^<>{}]+)</g)].map((m) => m[1]).join(' ') + [...t.matchAll(/(?:label|title|placeholder|tooltip|help)=["`]([^"`]*)["`]/g)].map((m) => m[1]).join(' ');
  must(`${f}: the words server and remote share, never peer, on screen`, !/peers?/i.test(words));
}
must('no Peer*.svelte left', !fs.readdirSync(path.join(src, 'forms/ops')).some((f) => /^Peer/.test(f)));

if (failed) { console.log(`${failed} failed`); process.exit(1); }
console.log('ok');
