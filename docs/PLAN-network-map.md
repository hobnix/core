# Plan: network map (2026-11-18)

Status: plan; nothing built. Epic hobnix/server#870, milestone 0.10.1 "Network Map". Issues: Storybook setup #879 (milestone 0.9),
UI SDK spike #871, graph document #872, counters stream #873, layout #874, drawing #875, access #876, page and demo data #877, test and docs #878.

A page that draws the server as a map: the way out (WAN, gateway), the host, its bridges, the instances and the services on them, with
the traffic that reaches each node shown as moving dots and a rate. Model: the topology view of a UniFi console. First version: **this
server only**. Peer nodes belong to multi-node management (#203, "Later — after 1.0") and join the same graph later.

It is also the pilot for UI SDK (`@ui-sdk/svelte`, beta): the library gives behaviour (keyboard, focus, popover), not the drawing.

## Decisions taken

- **Nothing is hardcoded.** The page draws whatever graph the backend describes. A new instance, a new bridge, a service without an
  instance all appear without a change in `web/`.
- **UI SDK is used early, pinned, and every part has a story.** One exact beta in `web/package.json` (all web dependencies are pinned); an
  upgrade is its own pull request. A beta break shows up in Storybook before it reaches a page. UI SDK carries behaviour only; our design
  tokens (`web/design/`) stay the visual layer.
- **Counters, not rates, on the wire.** Same rule as `hs sys deck`: the server sends totals, the client takes two readings and divides.
- **Server only.** No peer nodes, no router integration.

## What the map shows

| Tier | Node kinds | Source (to verify per issue) |
| --- | --- | --- |
| 0 | `wan` (provider, link state) | default route and the physical port, as `scripts/deck-status.sh` finds it |
| 1 | `gateway` (the next hop of the default route) | `ip route`; name and address only. Its own traffic is unknown without a router integration: the map shows what the server's port sees. |
| 2 | `host` (this server), `bridge` (br0, br-<vlan>) | `/sys/class/net`, the bridges under the physical port |
| 3 | `instance` (container or VM, with state) | Incus: `/1.0/instances?recursion=1`, `state.network.<nic>.counters` |
| 4 | `service` (a route or port that belongs to an instance) | the service registry (`scripts/services.py`) |

Admin pages stay off the map as public routes (`ADMIN_TARGETS` guard): a service is drawn, its admin page is not offered as an
address. The map shows what the Instances and Services pages already show, no more.

## Parts

1. **Graph document** (backend). A new read-only `hs sys netmap` (a registry row, `docs/api/sys.toml`, regenerated `openapi.json` and
   `sys.gen.d.ts`): tab-separated rows `id  kind  parent  label  state  rx_bytes  tx_bytes`, an empty field is `-`, a source that cannot be
   read leaves the counters `-`, never an old value. Topology changes (an instance starts or stops) go through the live-state topic
   `netmap` and the event stream, as everything else.
2. **Counters stream.** Counters change all the time, so an invalidation event per change would flood the stream.
   **Decision (#873, 2026-11-22):** a stream of its own, `GET /api/netmap/stream` (server-sent events, session needed, role of the read
   `sys netmap counters`), not the `/api/events` stream and not a live topic: a topic would be sampled by the collector all the time and
   counted as a change on every round.
   - **Frame:** `data: {"t": <epoch ms of the reading>, "rows": [[id, rx_bytes, tx_bytes], ...]}`. Totals, `-` for a counter that cannot be
     read (never an old value). The client divides two readings by their `t`. `: ping` + `event: beat` every 5 s of silence; `event: end`
     after `HS_WEB_STREAM_HOURS`, after sign-out or when storage locks; the page reconnects.
   - **Source:** the new read `hs sys netmap counters` (`scripts/netmap-counters.sh`): `/sys/class/net/<if>/statistics` for `wan` (the
     physical port, as `hs sys deck` finds it), `host`, `bridge:<name>`, and ONE `incus query /1.0/instances?recursion=2` for
     `instance:<name>` (the sum of the NICs without `lo`). The node ids are the contract with the graph document (#872) and must match.
   - **Interval:** 2 s (`HS_WEB_NETMAP_EVERY`). One shared sampler thread for all open streams, not one sample per stream.
   - **Only while a page is open:** the sampler thread starts with the first stream and ends when the last one closes; no stream, no
     process, no old numbers kept.
   - **Limit:** 4 streams at once (`HS_WEB_NETMAP_MAX`); the fifth gets 503 and polls `sys netmap counters` every 5 s as its fallback.
     Polling is allowed only while the stream is down.
   - **Cost:** one `hs sys netmap counters` run per 2 s while somebody looks, whatever the number of pages. Measured on a server with many
     instances: not yet (needs hardware; see "Not tested on hardware yet"). The plan above assumed `recursion=1`; Incus returns the state
     only with `recursion=2`, to confirm on the server.
3. **Layout** (web, pure function, no DOM). Graph in, positions out: tiers from the root, siblings spaced evenly, a wide tier wraps or
   scrolls, an unknown kind falls back to a generic node, an empty graph gives an empty state. Unit-tested without a browser.
4. **Drawing** (web). SVG for nodes and links, a canvas layer for the moving dots (speed and density follow the rate, none at zero).
   `prefers-reduced-motion` turns the dots into a static thickness. Dark and light from the tokens. Budget: 100 nodes without a stutter.
5. **Access without a mouse** (web, UI SDK). Roving focus across the nodes, a popover or drawer with the node's detail (state, rates,
   services, link to its page). A table view with the same facts is the text alternative of the map and is reachable from the page.
6. **Page and demo mode.** A page in the web interface (placement decided in the navigation work, PLAN-web-design.md); fixture graphs
   for Storybook and the demo mode (#461) so the page runs without a server.
7. **Test and documentation.** `tests/commands.sh` row, a `reads` probe in `scripts/smoke.sh`, layout unit tests, an end-to-end test in the
   test-lab (start an instance: a node appears without a reload), a guide following `docs/GUIDE-TEMPLATE.md`, a changelog entry.

## Order and dependencies

```
Storybook set up (#193) ──► UI SDK spike ──► Layout ──► Drawing ──► Access ──► Page + demo
Graph document ───────────────────────────────────────────────────────────────┘      │
Counters stream ─────────────────────────────────────────────────────────────────────┘
                                                                      Test + docs (last)
```

The backend parts (1, 2) and the web parts (3 to 5) can run in parallel; the spike comes first because it decides whether UI SDK
builds, themes and passes our checks. If the spike fails, parts 3 to 6 do not change: only the access part (5) falls back to hand-written
behaviour.

## Risks and open questions

- UI SDK is beta (`0.1.0-beta.11` on 2026-11-18, released almost daily). Mitigation: exact pin, stories, one component first.
- Whether Incus reports per-instance NIC counters for every instance type (container, VM) on our setup: not verified. A VM without the
  agent may show none; the node then shows `-`, not zero.
- The gateway's own throughput (the UniFi figure) cannot be seen. The map labels the figure as "seen by this server".
- Where the page lives in the navigation: open until the navigation plan (0.11) fixes the groups.
- Counters stream: limit of streams and cost of one sample on a server with many instances: to measure in the issue, not assumed.

## Not tested on hardware yet

Nothing in this plan was run on a server. Counters stream (#873), to run on the server: open the stream with a signed-in browser or `curl -N`
and watch rows arrive every 2 s; start an instance with traffic and see its totals rise; close the page and see (`ps`) that no
`hs sys netmap counters` runs; time one `hs sys netmap counters` with 20 or more instances. Every issue carries its "Hardware test" steps when its pull request is opened.
