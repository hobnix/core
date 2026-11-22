// Fixture graphs for the network map (gallery entry NetMap, ADR 0029; the demo page of #877 can reuse them). Rows as `hs sys netmap` prints them.
const row = (id, kind, parent, label, state = '-') => ({ id, kind, parent, label, state, rx_bytes: '-', tx_bytes: '-' });

// The small server: way out, gateway, host, one bridge, three instances, two services.
export const SMALL = [
  row('wan', 'wan', '-', 'Provider', 'up'),
  row('gw', 'gateway', 'wan', 'Gateway 192.168.1.1', 'up'),
  row('host', 'host', 'gw', 'hobnix', 'up'),
  row('br0', 'bridge', 'host', 'br0', 'up'),
  row('nextcloud', 'instance', 'br0', 'nextcloud', 'running'),
  row('media', 'instance', 'br0', 'media', 'running'),
  row('old', 'instance', 'br0', 'old-vm', 'stopped'),
  row('nc-web', 'service', 'nextcloud', 'cloud.example.org', 'ok'),
  row('jf-web', 'service', 'media', 'Jellyfin', 'ok'),
  row('mystery', 'sensor', 'host', 'Unknown kind', 'failed'),
];
export const SMALL_RATES = { wan: { rx: 3.2e6, tx: 4e5 }, gw: { rx: 3.2e6, tx: 4e5 }, host: { rx: 3e6, tx: 4e5 }, br0: { rx: 2.9e6, tx: 3.5e5 }, nextcloud: { rx: 2.4e6, tx: 9e4 }, media: { rx: 4e5, tx: 2.5e5 }, 'nc-web': { rx: 1.2e6, tx: 3e4 }, 'jf-web': { rx: 150, tx: 2e5 } };

// 100 nodes: the same chain, three bridges, 80 instances and services (the stutter test and the wrapped tier).
export function big(n = 100) {
  const g = [row('wan', 'wan', '-', 'Provider', 'up'), row('gw', 'gateway', 'wan', 'Gateway', 'up'), row('host', 'host', 'gw', 'hobnix', 'up')];
  const rates = {};
  const bridges = ['br0', 'br-10', 'br-20'];
  for (const b of bridges) g.push(row(b, 'bridge', 'host', b, 'up'));
  let i = 0;
  while (g.length < n) {
    i++;
    const parent = g.length % 5 === 0 && i > 1 ? `c${i - 1}` : bridges[i % 3];
    const kind = parent.startsWith('c') ? 'service' : 'instance';
    const id = `c${i}`;
    g.push(row(id, kind, parent, `${kind === 'service' ? 'svc' : 'ct'}-${i}`, i % 7 === 0 ? 'stopped' : 'running'));
    if (i % 7 !== 0) rates[id] = { rx: 1024 * 2 ** (i % 14), tx: 1024 * 2 ** ((i * 3) % 12) };
  }
  for (const id of ['wan', 'gw', 'host', ...bridges]) rates[id] = { rx: 5e6, tx: 8e5 };
  return { graph: g, rates };
}
