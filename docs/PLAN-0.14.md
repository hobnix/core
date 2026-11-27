# Plan: milestone 0.14, what is built first and what moves forward from 0.15

Design record. Contributor document, not a guide. Written 2026-11-26, before the work started, from the open issues of 0.13, 0.14 and the plan
for "Core and Jobs" ([PLAN-core-daemon](PLAN-core-daemon.md), 0.15). It is a plan: what was really built is in the issues and pull requests.
Not tested on hardware yet.

## State of the milestones

| Milestone | State on 2026-11-26 |
|---|---|
| 0.13 Package Registry | beta (`v0.13.0-beta.1` tagged, notes for beta 2 in review), not released. Open: #1067, #1076, #1127, #1129, #1189 (epic), #1261 |
| 0.14 Marketplace | 33 open issues before this plan, 3 added by it |
| 0.15 Core and Jobs | decided in the plan, **not created on GitHub**: the milestone called 0.15 there is still "Translations" |

## Branches

- `0.14` is the milestone branch, cut from `develop` (docs/RELEASE-PROCESS.md). `develop` stays free for the 0.13 release.
- One `feature/<topic>` branch and pull request per topic, into `0.14`. Nothing from this round goes into `develop` or `main`.
- `develop` is merged into `0.14` as 0.13 gets fixes.
- CI did not run on a push to `0.14` (the pattern ended at `0.9`); the first commit of the branch fixes that.

## Rust: the rules come first

The ruleset exists: [CODE-PRACTICES](CODE-PRACTICES.md), the path rule and `[workspace.lints]`, under the epic #1189. No new epic is needed. An
audit against current practice found two defects in the SDK (a crash on a huge HTTP chunk size, a key printed by `Debug`) and rules that no
tool checks (panicking indexing, size limits, dependencies, a toolchain that differs from the one servers build with). These are #1307. It is
built **before** the SDK split, so the new crates start under the full rules. It also writes the async and daemon rules before 0.15 writes the
daemon.

## Moved forward from 0.15

A piece moves only when 0.14 would otherwise build it in a shape 0.15 must redo, or when it unblocks 0.15 without any daemon code.

| What | Issue | Why now |
|---|---|---|
| P0: two decision records (Proposed) and the migration map | #1308 | 0.15 starts with code; the map shows what 0.14 work must not block |
| P1 slice: protocol message types the core can use as the host | #1309 | the SDK split (#1262) decides where the types live; later means moving them twice |
| Async, daemon and SQLite rules in the code practices | #1307 | written before the first daemon code, not after |

**Not** moved forward: the operation model, the system access layer, locks, job records in SQLite, the daemon and `hobnix-web`. They depend on
the records of #1308, which the owner has not accepted, and ADR code is merged only after that.

## What this round builds, and in which order

Topics in one column run side by side; a row waits for the row above it in the same column.

| Rust | Package manager | Web | Other |
|---|---|---|---|
| #1307 rules and defects | #1265 `requires_core` upper bound, then the same-name package bug (part of #933) | #474 store and package page | #1245 long share names |
| #1262 SDK split, with #1309 | #1250 older version and hold | #477 trust labels | #1308 P0 records and map |
| #1263 command macro and drift check | | #793 fits this server, #1251 version history on the page | |
| #1264 test harness and templates | | | |

Design points fixed by this plan:

- **#1265:** `requires_core = ">=N"` keeps its shape. Released servers reject the whole signed index when one entry has another shape, so the
  upper bound is a new optional field.
- **#474:** the package page is `/marketplace/<repo>/<name>` (the stats plan and #1257 need both parts). The App catalog page stays
  ([PLAN-workloads](PLAN-workloads.md)).
- **#1250:** is new behaviour in the Python package tools, which [CODE-PRACTICES](CODE-PRACTICES.md) says not to extend. The move of those tools
  to Rust (#1267 and later) is far larger than this issue, so the change stays small and is listed as debt. The owner can reject that.

## Not in this round

| Issue | Why |
|---|---|
| #1266 web server record, #1267 move small Python programs | [PLAN-core-daemon](PLAN-core-daemon.md) 15.2 proposes to move both to 0.15, where they are rewritten as parts of the core. Building them now would be building them twice. **Owner decides** |
| #1268 remove `job-record.py` | its condition (one release with the Rust writer on servers) is not met while 0.13 is a beta, and `install.nix` does not include the `hobnix` program, so some paths still need the fallback |
| #1219 recipe SDK and jobs | mostly needs the new job system; the issue asks for a talk before building |
| #1126, #1123, #1124, #1125 | jobs for extensions, terminal and console blocks, package secrets: root-level and security design, a record first |
| #934 exclusive slots | key name and replace behaviour are open. (`pkg_slots.py` is about places in the web interface, not this) |
| #476 one updates page, #478 page per app | how an app update runs and the addresses are open; they follow #474 |
| #933 canonical package identity | needs a migration design; only its shadowing bug is in this round |
| #1252 to #1255 stats service | a new repository, a server on the internet and a privacy note: owner steps first. #1254 follows them |
| #225, #217 capabilities out of the core | needs changes in hobnix/official and a run on a real server |
| #923, #925, #269 games and importers | need real data, real hardware or another repository |
| #1269 permissions from code | optional, after #1263 |

## Check that it worked

Each topic: its tests, a review of the diff, and CI on the pull request. A step that needs a real server is written into the pull request and
goes into the hardware tracker of the milestone at merge.

## Next
- [PLAN-core-daemon](PLAN-core-daemon.md): the design 0.15 builds.
- [PLAN-package-sdk](PLAN-package-sdk.md) and [PLAN-marketplace-stats](PLAN-marketplace-stats.md): the 0.14 designs.
