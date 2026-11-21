# Hobnix 0.10.0 release notes

Draft release notes of the release "0.10 Live Interface", built from the changelog entries of `docs/changelog/` that are on `0.10` but not in `v0.9.0` and
from the plan `docs/PLAN-live-interface.md`. Written 2026-11-20 for `v0.10.0-beta.1`.

**Read this first.** This is a beta. Nothing in 0.10 has been run on a real server yet. Every item below is built and covered by the tests of the
repository, and none of it was seen on hardware. The first real measurement of the write load of the state database happens on this beta
(`hs live measure`). The tracker issue [#990](https://github.com/hobnix/server/issues/990) "Hardware test: 0.10 — Live Interface" lists every box to check
on a server. A box that is not ticked is postponed, it never blocks the release.

## What 0.10 is
The web interface follows events and no longer polls. One collector keeps the data of every page in the state database, the server announces changes, and
an open page shows a change within a few seconds, also a change made in a terminal.

## Live state
- **Always on, one store.** Live state has no setting any more. The collector `hs-live` keeps every page's data in the state database. Redis is gone (no
  service, no socket), and so are the timer `hs-reads-collect`, `hs sys reads status` and `hs sys reads collect`. Upgrade: nothing to do. A `liveState`
  line left in `machine.toml` is ignored, and `hs config check` shows a note for this release; you can delete the line (ADR 0026).
- **`/api/events`** is the stream the open page listens to. A named event says which topic changed and the page reads that topic again.
- **The Data page** shows the heartbeat age of the collector (`hs sys live status` has it as the last column; a warning shows when there is none) and,
  per topic, the last and the worst delay from the request to the new data, on the server and as seen in the page. Health says so when the worst of the
  last 20 delays of a topic is over 10 seconds. Only numbers are kept.
- **`hs live measure`** measures the write load of the state database and the latency of changed topics.
- **Rows follow their jobs.** A row on Apps, Marketplace, Services, Instances, Docker, Pools, Disks, Shares, Users, Groups, Backup and Vault shows
  Installing, Updating, Starting, Stopping, Removing, Snapshotting and so on as soon as its job runs, also when the job was started in a terminal. A job
  record carries a key such as `apps remove nextcloud`, and `job.running`, `job.ok` and `job.failed` carry it too. A failed job puts the row back to its
  last real state and shows its error until you dismiss it.
- **Backup checks, restores and pool changes show "step n of m"**, and a backup writes one `backup.ok` or `backup.failed` event per part and a `lock.done`
  event when the vault is closed.
- **Unit watcher and disk events.** A small service, `hs-unit-watch`, watches systemd, so Health, Services, Pools, Shares, Instances, Docker and the
  gateway show a unit that stops, starts or fails at once. Plugging or pulling a disk updates the Disks page.
- **The Events page** shows a new entry the moment it is written; "Show more" loads older ones (`hs event list --before <id>`).

## 66 timed reads down to 26
The ratchet counted 66 reads that asked the server on a timer. The count at the start of the step was 47 call sites; 26 are left. The Docker status,
health, registry logins, container lists, parts and rebuilds that wait, `machine.toml` changes that wait and the preset list got a collector topic. Snapshot
lists, free-disk pickers, SMART history and service forms read again when their topic changes, and the detail panels of a user, group, share, container or
node read again when their list changes. The 26 that stay timed have a reason each in `scripts/lib/read-reasons.tsv`: reads with a free argument (logs,
per-disk or per-node answers), reads named by a page or capability declaration, node reads over ssh, the VPS probe, `release show`, `incident state` and
`testlab results`. Without the live connection the old intervals still apply.

## Health and notifications
- **Acknowledge a health problem** with an expiry and a note: `hs health ack --for 7d --note ...`, `hs health list-acks`. The Acknowledge button on the
  Health page and in the bell opens a form (until it clears, a day, a week, 30 days; optional note). Admins only. An acknowledged problem ends by itself
  when it clears or the time is over.
- **Browser notifications** are opt-in: a switch in Settings > General, off by default and kept in this browser only. A new problem, warning or error
  raises a notification while the page is open in the background. They need HTTPS or localhost and may not work over plain HTTP; the switch says why.

## Jobs and the interface
- **Docker start, stop and restart are jobs.** The dialog no longer stays open; the row shows it is busy and a toast says how it went.
- **Job toasts and the install wizard fix.** The step list of the install dialog follows the job (it stayed on step 1), a job that waits for an answer
  raises a toast with a link, and Start in a plan dialog closes it at once.
- **Role-gated buttons.** 114 change buttons are greyed for a role the server would refuse and say which role they need, from the same role table the
  server uses.
- **The Events timeline** sits on a panel per day, readable in light and dark and on a phone.
- **Jobs: list and record side by side.** The record opens beside the list; on a phone it opens full screen with a close button.

## SnapRAID per-share limits
The parity sync no longer stops the whole pool for 100 removed files. The limit is per share (default: the higher of 100 files and 1 % of the share), and
the sync stops only for shares over it, with a table of share, folder, removed files and limit. `hs share <share> parity skip <folder>` leaves a folder
out of the parity (you type the folder name; its files lose their protection), `limit` sets the number by hand. The share drawer has a Parity section and
the pool page has a button to sync anyway.

## For developers
- **End-to-end browser test** in test-lab stage 6: an action from a second session updates the open page without a reload within the limit (5 s with a
  hook, 20 s timed); it fails when the limit is set to 0. Built; the real run waits for the nested VM.
- **ADR 0028 (error codes) is accepted.** Nothing is built yet; the build is issue #488 in milestone 0.12.

## Not tested on hardware yet
The whole release. The boxes are in [#990](https://github.com/hobnix/server/issues/990). Not tested on hardware yet:
- `hs live measure` with all topics (write load, latency): the first real numbers.
- A terminal change shows in the open page within seconds; stopping the collector marks the data as old.
- A fresh install, and an upgrade with an old `liveState` line.
- The Data page and `hs sys live status` with the heartbeat age.
- Apps from a terminal with the Apps page open, and a failing install.
- The unit watcher and plugging or pulling a USB or SATA disk.
- Acknowledge a failing SMART with a day and a note, and the push when it fails again.
- Installing a recipe (for example bazarr): the Stepper and the question toast.
- SnapRAID skip and limit (`hs share media parity skip downloads`, a sync, limit 10 with 20 deleted files).
- The browser stage of the test-lab in the nested VM.
- Browser notifications on a real browser, and over plain HTTP.

## Known issues
- **#899**: the apply of a Docker app fails with "exit 127" when its images are not downloaded yet.
- **#850**: the install dialog warns that the server is rebuilt for an app that does not rebuild (ntfy).
- The issues of milestone 0.10 (#480 and its steps) are still open on the board because their hardware boxes in #990 are not ticked.
