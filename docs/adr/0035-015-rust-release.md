# 0035: 0.15 is the Rust release, and rules have no exceptions

Status: Accepted (2026-11-28) by the owner. The **Decided** items are rules. The **Proposed** items are not confirmed.
Issue: hobnix/core#1189 (epic: Rust as the main language). Related: ADR 0001, 0032, 0033, 0034, docs/PLAN-core-daemon.md, docs/PLAN-rust.md,
docs/PLAN-game-servers.md, docs/CODE-PRACTICES.md.

## Context

What is true today, checked on `develop` on 2026-11-28 (paths relative to the repository):

- **Moving for its own sake is not allowed.** ADR 0001 "When a command moves to Rust" lets a command group move only when it "is being changed
  anyway for a feature or a fix" ("No move for the move's sake, except the pilot") **and** at least one "good reason" holds.
- **0.15 is smaller than the whole move.** ADR 0033 D13 and docs/PLAN-core-daemon.md section 15.2 put steps P0 to P4 into 0.15; P5 (Rust CLI) to P8
  (remove `sys`, `web-serve.py` and Python) come later.
- **Old code stays for one release** beside the new code (ADR 0001 "Done means"), so a release can never be the one that removes what it ports.
- **New features beside the move** are already ruled out: docs/PLAN-core-daemon.md section 13 lists "new product features added while old ones
  move" under "Not in this plan". The game server work (hobnix/core#1409) and the autopilot (#1370) were added to milestone 0.15 in spite of it.
- **The rules have exceptions.** Baselines let files off a check (`tests/shellcheck-ratchet.tsv`, `tests/rust-size-ratchet.tsv`,
  `tests/pool-names-ratchet.tsv`, `tests/web-ratchet.tsv`), `.leak-allow` and lists inside tests let findings off, code carries per-line and
  per-file suppressions, docs/PLAN-rust.md records three Python programs as debt, and `HS_ALLOW_PRIMARY=1` overrides a guard. Three process rules
  let a gate be skipped: the label `agent-pr` skips the DCO check, a new security advisory only reports on a pull request, and a test-lab run
  ticks `[lab]` boxes of a hardware-test tracker.
- **One server.** The owner is the only one who runs Hobnix, and accepts that 0.15 takes long.

## Decision

### Decided

0.15:

1. **0.15 moves the code to Rust,** as much of it as ADR 0032 decision 3 and ADR 0033 D12 do not keep in bash. A command group moves because
   0.15 is the Rust release: neither the "touch it, move it" condition nor a "good reason" of ADR 0001 is needed. This replaces both in ADR 0001,
   the touch rule in docs/PLAN-rust.md and "when it is next changed" in docs/CODE-PRACTICES.md "Shell". The other conditions of ADR 0001 stay:
   characterization tests first, the output in the OpenAPI document, errors mapped to the exit codes.
2. **0.15 holds steps P0 to P8** of docs/PLAN-core-daemon.md, with `hobnix-web` (P6) and the improvements of the Rust SDK. This replaces ADR 0033
   D13. The order of the steps stays, storage last.
3. **A 0.15 beta that has run on the owner's server is the side-by-side release.** Old and new code ship together in that beta with the way back.
   After it has run there, the old code is removed before 0.15.0. This replaces "one release" in ADR 0001 "Done means", ADR 0032 decision 4,
   docs/PLAN-core-daemon.md section 15 and the migration map, for the moves made in 0.15.
4. **No new product features in 0.15** while old ones move (section 13 of the plan stays as written). The feature work of the game servers and of
   the autopilot moves to a later milestone. Design records, the prototype (#1410) and the backup fix (#1408) stay, so that the new core leaves
   room for the features. The fix of #1408 is written in Rust, with the port of the backup command.

Rules without exceptions:

5. **No rule has exceptions.** No list of files, findings or lines that a rule does not apply to, no tolerated baseline, no suppression of one
   finding, no debt entry and no manual override. Where code cannot follow a rule as written (a command line program has to print), **the rule's
   text says where it applies,** for a whole kind of code, and the tool is configured to match. When work collides with a rule, the rule, the
   order or the scope is changed by a decision, for everyone.
6. **The existing exceptions are removed.**
7. **The label `agent-pr` no longer skips the DCO check.** An AI tool still never adds a sign-off; a person signs off the commits of an AI
   session. This replaces the skip in CLAUDE.md "Git", CONTRIBUTING.md, `.github/workflows/dco.yml` and `scripts/dev/dco-check.sh`.
8. **A new security advisory fails a pull request** as it fails a push. This replaces `continue-on-error` of the advisory step in
   `.github/workflows/ci.yml` and the sentence in docs/CODE-PRACTICES.md "Dependencies".
9. **Only a run that a person saw ticks a box** of a hardware-test tracker. This removes the test-lab exception of CLAUDE.md "Board"
   (`tick --box <k> --lab ...`).

Items 7 to 9 apply when the change that builds them is merged; until then CI and the tools behave as before.

### Proposed (needs the owner's confirmation)

10. **What "has run on the owner's server" means** (item 3): each moved command group has a step in the hardware-test tracker of 0.15 that names
    the beta, and the old code is removed only when that box is ticked. An unticked box keeps the old code and does not follow CLAUDE.md's rule
    that an unticked box moves on with the next release.
11. **What counts as a new product feature** (item 4): something a person can do with Hobnix that they could not do with 0.14. Ports, fixes,
    work on the core, the daemon, the job system, `hobnix-web` and the Rust SDK that the move needs, and design records are not.
12. **The announcement of step P8** ("announced one release earlier") is made in the release notes of the beta.
13. **All existing exceptions are gone before 0.15.0** is released.
14. **Until an existing exception is gone** it may only shrink, and nothing is added to it.

## What changes in older records on acceptance

The text of these records is not edited. Each has a Status note that points here.

| Record | Change |
|---|---|
| 0001 Rust behind the `hs sys` contract | "When a command moves to Rust": the "touch it" condition and the "good reason" requirement do not apply in 0.15 (item 1). "Done means": for moves made in 0.15 the beta is the one release (item 3). Both lists "Stays" stand, except that human commands move with the Rust CLI (ADR 0033 D4, step P5). |
| 0032 Rust is the main language | Decision 4: the same change of "one release side by side" (item 3). The rest stays. |
| 0033 One Rust core, one daemon | D13 is replaced: 0.15 holds P0 to P8 (item 2). In the table "What changes in older records", "one release side by side" reads with item 3. |

## Consequences

- Easier: one decision on what 0.15 is; no port waits for a feature; a rule that passes means what it says.
- Harder: 0.15 is much larger than "Core and Jobs" was, with no release in between that removes old code before 0.15.0; game servers and the
  autopilot come later; the backup fix waits for the port of the backup command, and storage and backup are last in the order; a person has to
  sign off every commit of an AI session and see every lab run; a new advisory can block an unrelated pull request until it is solved.
- Until #1408 is built, a volume attached with `hs ct <name> storage add <pool>` is not in the backup. The owner's server had no such volume on
  2026-11-28.
- Follow-up: file the issues per area from the migration map; remove the exceptions; build items 7 to 9; move the feature issues out of 0.15.

## Open points

1. The milestone that takes the feature work (item 4). Which issues move is the owner's call.
2. Python for extensions once Python leaves the server image (ADR 0033 open point 4, hobnix/core#1383). Step P8 needs it.
3. The web server record (hobnix/core#1266) is needed before the first route of `web-serve.py` is replaced.
4. Which shell stays: ADR 0033 D12 names the kinds; no count of the lines exists.
5. Nothing here is built. Not tested on hardware yet.
