# Plan: live interface (milestone 0.10)

Status: plan, written 2026-11-19 on branch `0.10` (cut from `0.9`, head `96380839`). Nothing here is built and nothing was run on a server. Epic #480
("The interface follows events, it does not poll"), plus #617 and #619. Not part of this plan: milestone 0.10.1 "Network Map" (epic #870); where it
shares infrastructure this plan says so (section "Shared with 0.10.1").

Related records: docs/adr/0005-events.md (events are signals), docs/adr/0026-live-state-one-mode-one-store.md (the store), docs/adr/0004-job-record.md,
docs/PLAN-events.md, docs/PLAN-jobs.md, docs/PLAN-web-design.md (4.5 bell, 4.11 behaviours), docs/PLAN-web-cache.md, docs/adr/0007-branches-and-releases.md.

## Goal and non-goals

**Goal.** What the interface shows is the state of the server now. A job ends, a container stops, a disk is plugged in, a health problem appears: the event
reaches the browser and the page changes, with no page waiting for a timer. A button shows its effect at once (the row says "installing" before the
collector has read again). "Snappy" becomes a number that is measured and shown.

**Non-goals.**
- The store decision. ADR 0026 decided it (the state database, no Redis). Building it is the milestone **0.3 Foundations** (#481, sub-issues #559 to #566),
  not this one. See decision D1: the plan only depends on it.
- A push channel from the collector to the web server (ADR 0026 decision 9). Only if the real-server check says 1 s is too slow.
- Events that carry data. An event stays a signal "this topic changed, read again" (ADR 0026 decision 8).
- The Network Map (0.10.1), new pages, a redesign. Components came in 0.9.
- Browser notifications are in scope only as a held last step (D7).

## What exists today (read from the code on `0.10`, 2026-11-19)

| Area | State | Where |
| --- | --- | --- |
| Stream | `/api/events` (SSE: `changed {topic, gen}`, `down`, `up`, `resync`, domain events with replay) is served in every mode; `Events._watch` reads the table `topics` once a second | scripts/web-serve.py, state.db |
| Browser | `live` (`open`, `gen`, `events`, last 100 domain events), `poll(path, ms, topic)` drops its timer while the stream is open, `nextDelay` in polldelay.js | web/src/live.svelte.js, data.svelte.js, polldelay.js |
| Topics | 86 lines in scripts/lib/live-topics.tsv with groups and a dependency graph; hooks call `live_refresh`; 30 scripts use it | scripts/live-collect.py, scripts/lib/live.sh |
| Mode | **`liveState` is still in config/schema.toml and `"off"` by default; the `reads` table and `reads-collect.sh` still exist.** #481 and its sub-issues #559 to #566 are open in milestone 0.3, so 0.10 does not yet contain the one-mode store. `HS_WEB_LIVE=db` (measurement only) and `hs live measure` exist | schema.toml:367, scripts/live-measure.sh, live_measure.py |
| Reads ratchet (#482) | done: `scripts/dev/reads-inventory.py --check`, tests/reads-ratchet.sh, read-reasons.tsv (81 rows). **137 reads, 189 `poll()` calls, 66 timed without a topic** (`scripts/lib/timed-reads.max` = 66) | scripts/dev/reads-inventory.py |
| Pending state | not shared. A button stays busy with `busy={jobRunning(area, args)}` (tasks started in this browser only); a row does not know a job that someone else started | web/src/ui.svelte.js, jobkey.js, Apps/Instances.svelte |
| Job events | `job.*` rows arrive on the stream; `jobrecords.js` parses records for the Jobs panel (step, progress) | web/src/jobrecords.js, ADR 0004 |
| Disks | `hs-disk-event@<action>-<name>` is started by a udev rule (`configuration.nix:516`), writes `disk.plugged`/`disk.removed` and already calls `live.sh refresh monitor-disks disk-inventory temp-disks fm-locations backup-state` | scripts/disk-event.sh:69 |
| Units | no source: Docker, Incus and ZFS faults have event sources, a failing or stopped unit is found by the collector interval | live-collect.py |
| Latency | `hs live measure` measures the server end on the database path only (a probe counter); no per-topic delay, nothing in the browser | scripts/live_measure.py |
| Health ack | `hs health ack [<id>]\|unack <id>\|resume` by id, file /var/lib/hs/health-ack (id, time), the check skips acknowledged ids; the web allowlist has `health ack\|unack\|resume`; the bell (shell/Inbox.svelte, #783, PR #821) lists problems and warn/error events, dims acknowledged ones and does not count them. **No** expiry, note, who, no `health.acked`/`health.unacked` kinds, no Acknowledge button found on the Health page | scripts/health-ack.sh, web/src/shell/inbox.js |
| Events page | polls every 30 s next to the stream (`Events.svelte:23`), a growing limit, no paging by id; `sys event list` has `--after` only | web/src/pages/Events.svelte, scripts/event.sh |
| Browser test | test-lab stage 6 (`browser`, playwright) opens every page; no test acts and then watches a page change | capabilities/testlab, scripts/testlab-change.sh |
| Tests that already guard | tests/web-live.sh (+ .mjs), tests/live-state.sh, tests/change-counters.sh, tests/live-db.sh, tests/live-hook.sh, tests/job-step-live.sh, tests/web-undefined.sh (every svelte name is declared) | tests/ |

Where it polls: the 66 timed call sites. About half carry "no producer for a topic yet" (docker containers and health, ...), the rest "free argument"
(one answer per container, share, user, app, node, disk). Those two groups are the work of step 6.

## Decisions

"Owner" marks a decision that is the owner's to take; the others are recommendations an implementer may follow. "Hard to change later" is what a wrong
choice costs after release.

| Id | Question | Options | Recommendation | Owner | Hard to change later |
| --- | --- | --- | --- | --- | --- |
| D1 | #481 is not in `0.10`; what do the steps wait for? | (a) browser-side steps start now and work in both modes; steps that need the store (5, 9, 11) wait until 0.3 is merged into `0.10` (merge, ADR 0007); (b) wait for #481 before anything; (c) build 0.10 on the Redis path | (a) | **yes** | Low |
| D2 | Role of `sys event list` (#617: roles table says viewer, #391 says admin) | viewer; admin; viewer without the `payload` column | viewer: the bell and the Events page are shown to every signed-in role (design 4.5) and event text carries no secrets by rule; change the row in docs/adr/0012-roles-sys-rows.tsv and `sys.toml` in the same commit. Check the payloads of `job.*` and `ext.*` for paths before accepting | taken: viewer (payloads of `job.*` and `ext.*` checked, no path or secret) | Medium: a role per row is a promise to scripts |
| D3 | Disks: udev or polling | udev (built); polling only | udev for plug and pull, as built. SMART values, free space and temperatures stay timed in the collector: one process polls, not every browser | **yes** (named in the milestone text) | Low |
| D4 | How unit state changes become events | (a) one watcher service on the systemd D-Bus (`busctl monitor`/signals `PropertiesChanged` of `org.freedesktop.systemd1`), filtered to the units the interface shows; (b) hooks in each unit (`OnFailure`, `ExecStartPost`); (c) the collector interval | (a) with (c) kept as the safety net. (b) misses a stop made by hand. Verify first that `busctl monitor --json=short` is stable in the pinned systemd | no | Low |
| D5 | Reads with a free argument | (a) refetch when the topic of the list gen changes; (b) a topic family `<topic>:<arg>`; (c) keep the timer with a reason | (a) first, no new producer; (b) only for a read that is expensive or whose list has no topic; (c) where nothing can tell | no | Low |
| D6 | Where the acknowledgement lives | (a) extend the file /var/lib/hs/health-ack with columns (id, time, until, who, note), additive; (b) a table in state.db | (a): the check, the CLI and their tests already use it (`HS_ACK_FILE`); the key rule (a stable problem key) stays in `health-check.sh`. State.db is runtime state that may be rebuilt (ADR 0002), an acknowledgement is a decision of a person | **yes** | Medium: a stored format |
| D7 | Browser notifications | yes, later, opt-in per browser; no; Web Push with a service worker | yes, later and held: the Notification API, off by default, after the rest of 0.10. Risk: browsers require a secure context, so it may not work on plain HTTP over the LAN (works on localhost and where Tailscale serves HTTPS); the guide must say so. No Web Push (needs an external push service and keys) | **yes** | Low |
| D8 | How the delay is measured | server side only; plus a browser sample | both: the collector records, per topic, the time from trigger to new gen (last, worst, count). The browser reports a sample (`topic`, `gen`, time seen) only while the Live state page is open, so there is no per-user tracking and no load on other pages | no | Low |
| D9 | The limits | fixed numbers | e2e test: 5 s for a topic with a hook, 20 s for a timed one; health note when the worst of the last 20 samples of a topic is over 10 s. Numbers live in one file so the owner can change them without code | **yes** (numbers) | Low |
| D10 | A failed job and the row | revert and say why; keep "failed" until read | revert to the last real state and show the job's error in the row (shared `ErrorNote`, merged in 0.9), clear on the next topic change or by hand | no | Low |

## Steps

Sizes: S up to a day, M two to three days. Every step adds its tests, `bash -n` for touched scripts, `scripts/dev/t quick <names>`, German texts for
new help, a changelog entry when users see it, `python3 scripts/openapi-gen.py write` and `python3 scripts/openapi-ts-gen.py write` in the same commit
as a new or changed `sys` row (sys.toml), a smoke probe for each new read, `python3 scripts/events-doc-gen.py write` for a new event kind. Output only
through scripts/lib/ui.sh. No change to a machine-readable line; new facts are new columns at the end or new rows.

| # | Size | Issue | Step | Files | Needs | Done when |
| --- | --- | --- | --- | --- | --- | --- |
| 0 | - | #481, #559 to #566 | **Foundations (milestone 0.3), not built here.** One mode, the state database, `liveState` gone. Merged into `0.10` when done (D1) | see ADR 0026 | none | #566: a terminal change shows in the open page, seen on a real server |
| 1 | S | #617 (a) | Events page follows the stream with a topic; paging by id (`--after`/`--before`) instead of a growing limit; no 30 s poll while the stream is open; guide entry in docs/web-interface.md; D2 decided | web/src/pages/Events.svelte, events.js, scripts/event.sh, registry.tsv, docs/api/sys.toml, openapi files, tests/web-events.*, tests/event-log.sh | D2 | the page has no timer while the stream is open; a row added in a terminal shows at once; ratchet number lowered |
| 2 | M | #483 (a) | **One place for the pending state of a row.** A module (for example web/src/rowstate.svelte.js) derives `pending(area, args)` from the job events on the stream and the job records, not from this browser's tasks only; the job event must carry the area and arguments (the key of jobkey.js): **verify first** what `job.started` carries; if it lacks the key add it to the record and the event (additive, ADR 0004). A failed job puts the row back with the error (D10) | web/src/jobkey.js, jobrecords.js, ui.svelte.js, live.svelte.js, scripts/job-record.py and rust/hobnix-core `jobs` (only if the record lacks the key), tests/web-jobkey.sh, new tests/web-rowstate.mjs | none | a job started in a terminal shows as pending in a fixture page; a failed fixture job restores the row |
| 3 | M | #483 (b) | Pages use it: Apps, Instances (and its detail), Services, Pools, Shares, Backup, Disks, Users. One page per PR after step 2; no timer "to be sure" after an action is left | web/src/pages/*.svelte (one page per PR), forms | 2 | each page shows installing, starting, stopping, removing from the job; ratchet lowered; web-ratchet baselines not raised |
| 4 | M | #885 (#484 b) | Unit state watcher (D4): service `hs-unit-watch`, calls `live_refresh` for the topics of the units the interface shows; list of topics that stay timed with the reason. The disk half of #484 is built; this step only adds the tick "verified" after hardware step H1 | scripts/unit-watch.sh (or .py), configuration.nix, scripts/lib/live-topics.tsv, read-reasons.tsv, scripts/lib/event-kinds.tsv if a kind is missing, tests with a fake feed | D4 | a fake unit feed marks exactly the listed topics; the service restarts after a kill |
| 5 | M | #486 | Measure the delay (D8, D9): per topic last and worst trigger-to-gen time written by the collector, browser sample, the Live state page shows both, a health note when over the limit | scripts/live-collect.py (or its successor), scripts/live.sh, scripts/live_measure.py, web-serve.py (sample endpoint, role viewer, rate limited), web/src/pages/LiveState.svelte, scripts/health-check.sh, docs/api/sys.toml, tests | step 0 (the store the numbers are kept in), D9 | `hs sys live status` has the new columns at the end; the page shows them; a slow fixture topic raises the note |
| 6 | M | #886 | Give the 66 timed reads a topic family or a refetch (D5); lower `timed-reads.max` to the target agreed in the PR (target to be counted when the step starts; a first cut is the "no producer" group) | scripts/web-serve.py (READS), scripts/lib/live-topics.tsv, read-reasons.tsv, timed-reads.max, hooks, pages that still poll | 3 (same page files), 0 | the number only goes down; the page list in the PR names each read that stays timed |
| 7 | M | #887 (#619 a) | Acknowledge completed (D6): `--for`, `--note`, who, `list-acks`, ack cleared when the problem resolves, events `health.acked`/`health.unacked`, an Acknowledge button on the Health page and in the Overview, no push for an acknowledged problem, the red count without them | scripts/health-ack.sh, health-check.sh, health.sh, event-kinds.tsv, docs/events.md (generated), web/src/pages/Health.svelte, Summary/Overview, inbox.js, tests/health.sh, tests/web-health-change.sh, web-inbox.mjs | D6 | a failing SMART can be acknowledged once, stays quiet, and the second failure after a resolve sends its push |
| 8 | M | #617 (b) | Job records and event kinds: `sys fm progress` reads the record, a test with an unknown field, real steps for backup verify/drill, share restore and pool changes, kind `lock`, `backup.ok`/`backup.failed` per category, tests for `backup.*`, `unlock.*`, `update.*` | scripts/fm.sh, manage-pool.sh, backup scripts, event-kinds.tsv, tests/job-steps.sh, tests/event-log.sh | none | the boxes of #617 ticked, each with a test |
| 9 | M | #485 (built: tests/live-e2e.sh at stream level, scripts/dev/testlab-browser.py live + testlab-live.tsv wired in stage 6; the real run waits for step 0 and the nested VM) | End-to-end test in test-lab stage 6: open the Apps page, install an app from a second session or the terminal, the first page shows it without reload within the D9 limit; the same for stop a container and lock the storage; fails when the limit is passed | capabilities/testlab, scripts/testlab*.sh, a playwright script, tests/testlab-*.sh | 2, 3, 0 (store), nested VM | the stage passes in the test-lab and fails when the limit is set to 0 |
| 10 | S | #888 (#619 b) | **Held (D7).** Browser notifications, opt-in | web/src/shell, a new settings key, guide | 7, D7 | see the issue |
| 11 | S | #480 | Docs and the hardware pass: guide web-interface.md (live updates, the Live state page, acknowledge), changelog, a "Hardware test" box list on every issue, `Pruefliste-Server.md` rows, epic #480 ticked | docs/ | all | tests/docs.sh green; boxes ticked only for what was seen |

Parallel lanes (steps that do not touch the same files):

- **A events and records:** 1, 8 (8 is mostly scripts and tests).
- **B rows:** 2 then 3 (page by page).
- **C sources and measurement:** 4, 5 (5 waits for step 0).
- **D acknowledge:** 7, then 10.
- **E test:** 9 last, after B.
- 6 runs after 3 because both edit the same page files.

Shared files, so these merge one at a time and rebase after each: `scripts/lib/event-kinds.tsv` (4, 7, 8; regenerate docs/events.md on every rebase,
never merge it by hand); `docs/api/sys.toml`, `docs/api/openapi.json`, `web/src/api/sys.gen.d.ts` (1, 5, 7: regenerate on every rebase);
`scripts/lib/read-reasons.tsv`, `timed-reads.max` (1, 3, 4, 6: each only lowers, so a conflict is resolved by recounting with
`python3 scripts/dev/reads-inventory.py --check`); `web/src/ui.svelte.js` (2 only); `scripts/web-serve.py` (1, 5, 6: small, separate regions);
`scripts/health-check.sh` (5, 7). Steps 4 and 7 add a service or timer to `configuration.nix`: one at a time.

## Shared with 0.10.1 (Network Map, epic #870)

Only infrastructure: the event stream and `changed` topics, the counters stream of #873 ("sampled only while a page is open") which can reuse the
"only while a page is open" idea of step 5, and the delay measurement of step 5 (a map that feels live needs the same number). This plan adds no
counters. Step 6 must not rename or remove a topic that #873 may read; 0.10.1 states its topics in its own plan.

## What needs real hardware, the test-lab or the nested VM

| Step | What to look at |
| --- | --- |
| H1 (4, #484) | Plug in and pull a real USB and a SATA disk with the Disks page open: the row appears and goes within seconds, once; boot and `hs rebuild` replay the udev events silently (as `disk-event.sh` promises). `systemctl stop|start` and a unit that crashes (`kill -9`) with the Services page open |
| H2 (2, 3) | Install, start, stop and remove an app from a terminal with the Apps page open on a second screen; a failing install puts the row back with the error. Two browsers at once |
| H3 (5) | Real numbers per topic on real hardware: the worst delay and the write load of the state database under all topics; the limit of D9 against what was seen (**do not trust the first numbers from the VM**) |
| H4 (7) | Failing SMART on a real or simulated disk: acknowledge, see it dim, resolve, fail again, the push arrives on a real channel (ntfy) |
| H5 (9) | The nested VM (ADR 0023) runs the browser stage; real hardware only repeats the three actions once |
| H6 (10) | A real browser on LAN over plain HTTP and over Tailscale HTTPS: whether the permission prompt and the notification appear |

Everything else is tested with fakes (`t quick`). Not tested on hardware yet.

## Risks

- **The store is not here.** The plan sits on #481, which is open. If 0.3 merges late, steps 5, 9 and 11 wait; steps 1 to 4, 7 and 8 do not. Mitigation: D1 (a),
  and each browser-side step is written against the stream, which works in both modes today.
- **Two sources of one truth.** A pending state from the job event and a real state from the topic can disagree for a moment (job done, topic not yet
  new). Mitigation: the pending state ends on the new gen **or** a ceiling timeout, never on the job event alone; the row shows the job's result until the topic arrives.
- **Event storms.** A rebuild replays udev events and a unit watcher sees every unit. Mitigation: the existing silence rule for known disks; the watcher
  filters to the units the interface shows and coalesces per second.
- **SQLite write load** with every topic at its interval (ADR 0026 consequence). Step 5 measures it; a document is written only when its output changed.
- **Counters hide a polling page.** A timer with a reason can stay forever. Mitigation: the number only goes down (ratchet) and every new timed read needs a reason row.
- **Acknowledging hides a real failure.** An ack that never expires is dangerous. Mitigation: `--for` snooze, an ack ends when the key changes or the problem
  resolves, the bell still lists acknowledged problems dimmed, and `hs health ack` with no argument shows them.
- **Notification API on plain HTTP** may not exist (secure context). Mitigation: D7, step 10 held, the limit documented.
- **Roles.** A new read (step 5 sample endpoint, step 7 ack) needs a role row; default admin, the sample endpoint and `list-acks` are viewer reads only after the owner confirms D2.
- **Shared page files** (steps 3 and 6) cause merge conflicts. Mitigation: one page per PR, 6 after 3.

## Check that it worked

- A change made in a terminal (stop a container, install an app, plug a disk, fail a unit) shows in the page that is open, within the limit of D9, without a reload and
  without that page owning a timer while the stream is open.
- A button shows its effect at once, also when the job was started in a terminal or by another user.
- `python3 scripts/dev/reads-inventory.py --check` is green and `timed-reads.max` is lower than 66.
- The Live state page shows last and worst delay per topic; a slow topic raises a health note.
- A failing health problem is acknowledged once, stays quiet, and the next failure after it resolved is announced.
- The test-lab browser stage passes and fails when the limit is exceeded.
