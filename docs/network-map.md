# Network map

See how this server reaches the network: the way out, the gateway, the server, its bridges, the instances and their services, with the traffic as moving dots.

## Before you start
- A running web interface and a signed-in account: [Web interface](web-interface.md).
- Instances to look at: [Containers and apps](containers-and-apps.md). The map works with none, but then it shows only the way out and the server.

## Open the map
Open Monitoring > Network map in the web interface (the page `/monitoring/network-map`). The map follows the server by itself: an instance that
starts or stops changes the graph without a reload.

The same graph as text, one row per node (id, kind, parent, label, state, received and sent bytes; `-` where a value is unknown):

```bash
sudo hs sys netmap
```

The rows list the way out (`wan`), the gateway, the server (`host`), every bridge, every instance and every service. A service that has an admin
page (Incus, Zoraxy, Arcane) is drawn as a node but never given an address.

## Read the traffic
Each link carries dots. More and faster dots mean more traffic; no dots mean none. A node whose counters are unknown shows `-`, not zero (a VM
without the agent often has none). The figure for the way out is the traffic this server sees; the gateway's own throughput cannot be seen.

If your system is set to reduce motion, the dots become a static line, thicker for more traffic.

One sample of the counters as text, the same totals the page reads:

```bash
sudo hs sys netmap counters
```

## Open the details of a node
Hover over a node, or press Tab to reach the map and the arrow keys to move between nodes. Press Enter or Space to open the details: state, rates, the
services of an instance, and a link to the page of that node where there is one. Press Escape to close them.

The button above the map shows the same facts as a table. It is the text version of the map, for a screen reader or a small screen.

## How the page stays current
The graph follows the live topic `netmap`, which changes only when the topology changes, never because the counters moved. The traffic comes from a
stream of its own (about every 2 seconds, only while the page is open, at most 4 streams in all). When the stream is not available the page says so
and reads the counters every 5 seconds until it is back.

In demo mode (`npm run demo` in `web/`) the page shows a made-up graph with made-up traffic and reads nothing from a server.

Not tested on hardware yet.

## Check that it worked
- Start an instance with the page open: its node and state change within a few seconds, without a reload.
- Download something inside an instance: the dots on its link speed up.
- The rows of `sudo hs sys netmap` match `sudo incus list` and `sudo hs services list`.

## If something goes wrong
| Symptom | Cause | Fix |
| --- | --- | --- |
| "The live stream is not available ..." | the limit of streams is reached, or the server is restarting | close other tabs; the page reads every 5 seconds meanwhile |
| "Nothing to draw yet" | the server listed no node | run `sudo hs sys netmap` in a terminal and read its error |
| An instance shows `-` for traffic | Incus reports no counters for it (a VM without the agent) | install the agent in the VM, or read it as unknown |
| A new instance is missing for a few seconds | the topology is read about every 10 seconds when no `hs` command woke it | wait, or reload once |

## Next
- [Web interface](web-interface.md)
- [Operations](operations.md)
