// Shares page views (issue #1151, docs/PLAN-remote-shares.md D1): Local, Remote, Kept folders; the Remote view holds what the Network tab held;
// the Network tab is gone. Source checks, runs in plain node (no Svelte).
import { readFileSync } from 'node:fs';
let ok = 0, bad = 0;
const t = (name, cond) => { if (cond) { ok++; console.log(`  ok    ${name}`); } else { bad++; console.log(`  FAIL  ${name}`); } };
const src = (f) => readFileSync(new URL(`../web/src/${f}`, import.meta.url), 'utf8');
const shares = src('pages/Shares.svelte'), remote = src('pages/shares/RemoteShares.svelte'), net = src('pages/Network.svelte');

t('the view switch has Local, Remote and Kept folders', /label: 'Local'/.test(shares) && /label: `Remote/.test(shares) && /Kept folders/.test(shares));
t('the view is read from the address (?view=remote)', /route\.query\.view === 'remote'/.test(shares));
t('the Remote view has the two buttons', /Add remote share/.test(shares) && /Give access/.test(shares));
t('the Local view points to the Remote view', /see Remote/.test(shares));
t('the Remote view has both blocks', /Shares I use from other servers/.test(remote) && /Shares I give to other servers/.test(remote));
t('the Remote view keeps the actions of a row', ['Instance…', 'Reconnect…', 'Stop using…', 'New code…', 'Take back…'].every((w) => remote.includes(w)));
t('the Network page has no Remote tab and no peer forms', !/id: 'remote'/.test(net) && !/(Peer|Remote)(Mount|Offer|Attach|Add|Give)/.test(net) && !/remote\/list/.test(net));
t('the interface does not say peer to the user', !/>Peer</.test(remote) && !/label: 'Peer'/.test(remote));
console.log(`  -> ${ok} ok, ${bad} failed`);
process.exit(bad ? 1 : 0);
