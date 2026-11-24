# Plan: Rust as the main language

Design record. Contributor document, not a guide. Written 2026-11-24 during 0.13. Builds on ADR 0001 (Rust behind the `hs sys` contract) and proposes ADR 0032 (Rust is the main language, Python is retired). Nothing here was built or run on a server; the numbers below that are not counted are marked so. Not tested on hardware yet.

## Where we are

- The core is bash, Python and Rust. Rust is `rust/` with three crates: `hobnix-core` (service layer), `hobnix-cli` (adapter: jobs, secrets so far) and `hobnix-ext-sdk` (extension protocol), about 3.9k lines. Beside it are 227 files in `scripts/` and 102 in `scripts/lib/`, bash and Python (counted 2026-11-24 with `ls`; lines of code not counted).
- ADR 0001 sets the method: strangler. A command moves when it is touched, behind its `hs sys` row, with a characterization test that passes on both implementations. It also lists what stays in shell and says shell and Python have "no deadline for removing them".
- Python programs named in the ADRs: `web-serve.py` (the web backend), `pkg.py`, `forecast.py`, `live-collect.py`, `job-record.py` (already also in Rust), `event-notify.py`, the generators (`schema-gen.py`, `openapi-gen.py`, `openapi-ts-gen.py`, `events-doc-gen.py`) and `changelog.py`. The list is not complete; step 1 below makes it complete.

## Decision proposed (ADR 0032)

1. **Rust is the main language** for the core, the tools that ship with it and the packages we write ourselves.
2. **Python is retired.** No new Python program; a Python program is replaced when ADR 0001's checklist allows, and the ones nobody touches get a scheduled move. The last Python leaves the server image when the last program is replaced. Tools that never run on a server (the generators) move last, and only because two toolchains cost more than they save.
3. **Bash stays, in a small role:** the launcher (`hs` dispatcher until it moves), installer and first run, unlock and recovery, `hs update` and its rollback, thin wrappers around one external command, and the dialogues of `ui.sh` until a later record says otherwise. This is ADR 0001's "Stays" list, unchanged. The reason for bash there is that these paths must work when the Rust binary is missing or broken.
4. **No flag day, no deadline for a single command.** Moves follow the touch rule. Python is the exception: it has a target release per program (step 2), because it is the layer with no reason to stay.

## What moves, what stays

| Area | Target | Why |
|---|---|---|
| `hs sys` contract commands (reads, plan, start, jobs) | Rust | typed checks, hot paths, shared logic (ADR 0001) |
| Job store, events, registry, manifest and package tools (`pkg.py`) | Rust | contracts with the web interface and packages; structured data |
| Web backend (`web-serve.py`) | Rust HTTP server, own ADR first (ADR 0001 decision 4) | the biggest Python program; serves root-level actions |
| Collectors and timers (`live-collect.py`, `forecast.py`, `event-notify.py`) | Rust | run every few minutes, parse structured output |
| Generators (`schema-gen`, `openapi-gen`, `openapi-ts-gen`, `events-doc-gen`, `changelog`) | Rust, last, as `xtask`-style dev tools | no server impact; removes Python from the dev environment |
| Installer, first run, unlock, `hs update` and rollback, recovery | bash | must work without the binary |
| Wrappers around one command, small glue | bash | Rust would add a build step and no safety |
| Guided dialogues (`ui.sh`) | bash for now | a later record decides; a Rust terminal UI is not planned |

## Steps

Each step is a board issue (milestone in brackets). A step is done when its characterization tests pass on both implementations for one release (ADR 0001 "Done means").

1. **Inventory** (0.13): list every `.py` and every script over 300 lines with its owner area, size and the ADR 0001 verdict (moves, stays). Output: a table in this file. No code.
2. **Practices and lints** (0.13): `docs/CODE-PRACTICES.md`, the path-scoped rule, `[workspace.lints]`, `shellcheck` warning level on changed files, `shfmt`. Existing code gets `#[allow]` with a reason or is fixed in passing.
3. **Close the Rust gaps in the job writer** (0.13 if small): the Rust writer does not know the `error` field and falls back to Python (PLAN-app-lifecycle, PLAN-recipe-orchestrator). Needed before Python can leave the job path.
4. **Package SDK design** (0.13 as a document, build in 0.14): docs/PLAN-package-sdk.md.
5. **Replace the small Python programs** (0.14 and later): `event-notify.py`, `live-collect.py`, `forecast.py`, `job-record.py` (delete after a release of side-by-side), then `pkg.py`.
6. **ADR for the Rust web server** (0.14): decides whether and how `web-serve.py` is replaced, the API version, and the cutover. The web backend moves only after this record is accepted.
7. **Move the generators and the changelog tool** (after step 5 or 6).
8. **Remove Python from the server image and the dev environment.** The release notes say so a release earlier.

Target releases for 5 to 8 are set when the inventory (step 1) shows the real size. They are not promised here.

## Shell scripts that stay: rules

- A script that stays gets no new structured-data parsing. When a change needs it, the change moves that part to Rust (the touch rule).
- The launcher keeps its fallbacks: a `rust:` row runs the binary, falls back to the script while the binary is missing (ADR 0001 decision 2).
- A bash script over about 300 lines is reviewed for a move each time it is touched.

## Risks and costs

- **Build time and size.** Rust builds are slower than editing a script. The Nix build and the binary cache (ADR 0003) carry this; the build time and closure size of `hobnix` are not measured here. Measure before step 6.
- **Editing on the server.** Today a script on `/etc/nixos` can be fixed in place. A Rust change needs a rebuild. That is acceptable for the core (changes come through `hs update`) and is the reason recovery stays in bash.
- **Contributors.** Fewer people read Rust than shell. The practices document, the SDK and the characterization tests are meant to lower that barrier; a "good first issue" label for small Rust moves helps.
- **Dependencies.** Each crate is a cost under Nix without network (CODE-PRACTICES). The `std`-only rule of `hobnix-core` stays, with `serde` and `serde_json` as the accepted exception.
- **Rewrite risk.** Every move is a behaviour change risk. The characterization test, the side-by-side release and the one-line way back are the guard; never move without them.

## Open points

1. **Decided 2026-11-24 (ADR 0032 decision 6):** the `hs` dispatcher stays a bash launcher until everything behind it is Rust, then a later record decides. The rename `hs` to `hn` is its own milestone (PLAN-extensions-access.md); `hs` stays as an alias. New Rust code and docs say `hobnix`/`hn` where they name the product, and no rename work is part of this plan.
2. A Rust terminal UI for dialogues: ADR 0001 notes that `hs-ui` (ratatui) was removed in 2026-10 because it duplicated parsing. Not planned.
3. Whether the web frontend build (Node, in `web/`) is affected: it is not; Node stays a build-time tool and is not on the server.
