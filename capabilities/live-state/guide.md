# Live state for the web interface

The web interface shows its pages from the state database, which a collector keeps filled, and the open page follows changes without polling. This
guide is for the owner of a server with the web interface: what runs, what you see, how to check it and what to do when it stops.

## Before you start
- The web interface is on: `webUi = true` in `machine.toml` (see [Web interface](../../docs/web-interface.md)). There is nothing else to switch on.
- Not tested on hardware yet.

## What live state is
- **The collector** `hs-live` (a systemd service) runs the read commands (`hs sys ...`) of every page on its own interval and keeps the answer in
  `/var/lib/hs/state.db`. It writes a topic only when its answer changed.
- **Three tables** hold it: `live` (one document per topic), `heartbeat` (one row the collector refreshes every few seconds) and `topics` (a change
  counter per topic).
- **The refresh hook** `live_refresh` is called by commands that change something (`hs share`, `hs ct`, `hs disk`, `hs pool`, `hs vault`, `hs unlock`).
  It counts the affected topics up; the collector sees the counter move within about a second and reads the topic again. This also covers a change made
  in a terminal or by a timer.
- **The stream** `/api/events` tells the open page what happened: `changed` (a topic has new data), `domain` (a new row in the event log),
  `down` and `up` (the collector stopped or came back), `resync` (the page missed events and reads everything again).
- Nothing is configured: there is no setting, no extra service and no Redis. Not tested on hardware yet.

## What you see
- **The page updates by itself** within a few seconds after a change, also when the change was made with `hs` in a terminal.
- **The top bar** shows how old the data of the page is and has a refresh button. The refresh button reads from the system now instead of from the
  state database.
- **When the collector stops**, the pages keep their last data and mark it as old. They never wait for it, and the stream says `down`.
- **The Diagnostics page** (Monitoring) lists every live topic with its status, interval, age, generation, exit code and error. Above the table it says
  when the collector made its last round ("Collector heartbeat: last round 4 s ago") and warns when there is no heartbeat. While the stream is lost the
  page polls every 5 seconds.
- **Lists with an argument** (snapshots of a backup tag or of one instance, the free disks of a pool dialog, the SMART history of one disk, the facts
  of one service) have no topic of their own. The page reads them again when the topic of its list changes (`backup-state`, `ct-list`, `pool-disks`,
  `disk-health`, `services-list`) and keeps no timer while the stream is open.

Not tested on hardware yet.

## Check the live state
```bash
sudo hs sys live status
```

One line per topic: topic, interval, age in seconds (`-1` = nothing collected yet), generation, exit code, error, error time, needs, status
(`fresh`, `stale`, `error` or `expired`) and, as the last field, the age in seconds of the collector's heartbeat (the same on every line, `-` = no heartbeat).

```bash
sudo hs sys live check
```

Prints nothing when all is well and one line per problem otherwise (the key `live:down`, `live:never:<topic>` or `live:stale:<topic>`, then a text).
A fresh install whose collector has not started yet prints nothing.

```bash
sudo hs sys live raw <topic>
```

Shows the stored document of one topic as JSON (the output is cut at 64 KiB). `hs sys live inspect` lists all topics as JSON, the form the web
interface uses. Not tested on hardware yet.

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

Writes a result file with the writes per minute, the growth of the database and the time a change needs to reach the stream; see the
[operations guide](../../docs/operations.md#measure-the-live-state-on-the-state-database). Not tested on hardware yet.

## After an upgrade
Nothing to do. The next rebuild removes Redis and the old timer `hs-reads-collect` if the server had them. A `liveState` line in `machine.toml` is ignored:
`hs config check` shows a note for this release, and you can delete the line. The commands `hs sys reads status` and `hs sys reads collect` are gone.
Not tested on hardware yet.

## If something goes wrong
| Symptom | Cause | Fix |
| --- | --- | --- |
| `hs sys live check` says `live:down`, the Diagnostics page says there is no heartbeat | The collector `hs-live` is not running | `systemctl status hs-live`, then `sudo systemctl restart hs-live` |
| Pages show old data and say so | The collector stopped, or the topic fails | `hs sys live status` (status and error per topic), then `journalctl -u hs-live` |
| A page says "refreshing" for a few seconds | The collector runs but has not read this topic yet | Wait; the page retries by itself |
| A topic stays `stale` or shows an error | The command behind it fails or is slow | `sudo hs sys live raw <topic>` shows the last answer and the error |
| The page does not update by itself | The stream is lost (proxy, network) | The page polls every 5 seconds meanwhile; reload the page |

## Next
- [Web interface](../../docs/web-interface.md)
- [Operations](../../docs/operations.md)
