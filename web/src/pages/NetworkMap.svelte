<script>
  // Monitoring > Network map (#877, docs/PLAN-network-map.md part 6): the way out, gateway, host, bridges, instances and services, with the traffic
  // as moving dots. The graph follows the live topic `netmap` (a change of the topology, not of the counters); the traffic comes from the counters
  // stream (netmap/counters.svelte.js), which falls back to a timed read only while the stream is down. The page is loaded lazily (ADR 0030, condition 3).
  import PageHeader from '../shell/PageHeader.svelte';
  import PageState from '../shell/PageState.svelte';
  import NetMap from '../ui/NetMap.svelte';
  import Banner from '../ui/Banner.svelte';
  import Muted from '../ui/Muted.svelte';
  import { poll, rows, refresh } from '../data.svelte.js';
  import { ui } from '../ui.svelte.js';
  import { netmapCounters } from '../netmap/counters.svelte.js';
  import { graphOf, hrefOf } from '../netmap/rates.js';

  const topo = poll('/api/sys/netmap/topology', 30000, 'netmap');
  const counters = netmapCounters();
  const graph = $derived(graphOf(rows(topo)));
  const status = $derived(
    counters.mode === 'stream' ? 'Live: the traffic is read about every 2 seconds while this page is open.'
    : counters.mode === 'poll' ? 'The live stream is not available, so the traffic is read every 5 seconds until it is back.'
    : 'Connecting to the live stream.');
</script>

<PageHeader title="Network map" crumb="{ui.host} › Monitoring" sub="How this server reaches the network: the way out, the host, its bridges, the instances and their services." />

<PageState loading={!topo.loaded} error={topo.error?.message} hasData={topo.data != null} empty={topo.loaded && !topo.error && !graph.length}
  emptyIcon="network" emptyTitle="Nothing to draw yet" emptyText="The server did not list any network node. Check the page again in a moment."
  retry={() => refresh(['/api/sys/netmap/topology'])}>
  {#if counters.mode === 'poll'}<Banner tone="info">{status}</Banner>{/if}
  <div class="card">
    <NetMap {graph} rates={counters.rates} label="Network map of {ui.host}" hrefFor={hrefOf} />
  </div>
  {#if counters.mode !== 'poll'}<Muted>{status}</Muted>{/if}
</PageState>
