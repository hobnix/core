# Live state for the web interface

The web interface shows its pages from a store that a collector fills (the state database on the server) and updates the page when something changes,
without polling. There is nothing to switch on: it runs on every server that runs the web interface.

## Before you start
- The web interface is on: `webUi = true` in `machine.toml` (see [Web interface](../../docs/web-interface.md)).
- This guide is not tested on hardware yet.

## What runs
The collector `hs-live` reads each topic on its own interval and keeps the result in `/var/lib/hs/state.db`. It writes a topic only when its output changed,
and one heartbeat row every few seconds. The web interface reads from there and tells the browser over `/api/events` which topic changed. A change made
in a terminal (`hs share`, `hs ct`, `hs disk`, `hs pool`, `hs vault`, `hs unlock`) asks the collector to read the affected topics again; the open page
shows it within a few seconds. Not tested on hardware yet.

There is no setting and no extra service (Redis is not used any more). A `liveState` line left in `machine.toml` from an older version is ignored;
`hs config check` says so in a note, and you can delete the line.

## Check that it worked
Not tested on hardware yet.

```bash
hs sys live status
```

Every topic shows an age of a few seconds (the age is `-1` when nothing has been collected yet) and an empty error (`-`). The age counts from the last
time the collector looked, not from the last change of the data.

```bash
hs sys live check
```

prints nothing when all is well, and a line per problem otherwise (the collector is not running, or a topic could not be read).

The Diagnostics page shows the live topics. It follows the live stream (`/api/events`) and falls back to polling every 5 seconds when the stream is
lost. If the collector stops, the pages keep showing the last data and mark it as old; they never wait for it.

## See how fast a change shows
Not tested on hardware yet.

```bash
hs sys live status
```

Columns 11 to 14 are the delay in milliseconds (`-` = no sample yet): the last and the worst time from the request to read a topic again (a change from
a terminal, a container event) to its new generation in the database, then the last and the worst time a browser page needed from the `changed`
message to showing the new data. The server numbers come from the collector; the browser numbers only while the Live state page is open and only
for topics whose request the collector saw. Only numbers and the topic name are kept, nothing about who looked. The same two pairs are columns on
the Live state page (Delay, Worst, Seen in page, Page worst).

`hs sys live check` adds a line `live:slow:<topic>` (or `live:slowweb:<topic>` for the page numbers) when the worst of the last 20 samples of a topic is
over 10 seconds. The limits (5 s for a topic with a hook, 20 s for a timed one, 10 s for the note) are in `scripts/lib/live-limits.tsv`.
A server in a virtual machine shows numbers that say little about real hardware; do not tune from them.

## Measure the write load
```bash
sudo hs live measure --minutes 30
```

writes a result file with the writes per minute, the growth of the database and the time a change needs to reach the page (see the
[operations guide](../../docs/operations.md)). Not tested on hardware yet.

## If something goes wrong
| Symptom | Cause | Fix |
| --- | --- | --- |
| The Health page says the live state collector is not running | `hs-live` stopped | `systemctl status hs-live`, then `sudo systemctl restart hs-live` |
| The page says "refreshing" for a few seconds | The first value is not collected yet | Wait; the page retries by itself |
| `hs sys live status` shows a growing age | The collector is stuck or the read fails | `journalctl -u hs-live` |

## Next
- [Web interface](../../docs/web-interface.md)
