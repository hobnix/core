# Plan: package pages (0.12, 2026-11-23)

Status: plan; nothing built. Milestone 0.12 "Package Pages", epic hobnix/server#195 (Declarative WebUI). Read from the issues, ADR 0012, 0016
and 0028, docs/PLAN-web-design.md section 7 and the code on `develop` after 0.11; not run.

A package adds to the interface as data: a place in the tree, tabs, blocks drawn from a registry, a status card. No code from a package reaches
the browser (ADR 0016). The same release builds the error codes (ADR 0028) and the event declarations that the two showcase extensions need.

## Decisions already taken

- `[web.page]` is the base: it is kept and extended, the four existing pages keep working (PLAN-web-design.md 7.4, 2026-11-18). This answers the
  "to check" line of #195.
- A package names an existing group (default `apps`); the tree stays two levels; a package with several views is one place with tabs.
- ADR 0028 (error codes) is Accepted since 2026-11-20. The note on #488 that its acceptance is open is out of date.
- Roles are built (0.8: ADR 0012, package roles, role-aware web). #790 does not wait for #434 any more; `role` on a page and an action uses the
  existing package roles.

## Scope

Moved into 0.12 from earlier milestones because a 0.12 issue needs them:

| Issue | From | Why it is here |
| --- | --- | --- |
| #900 error codes catalogue | 0.1 | #488 shows the codes; the catalogue and the `code` line come first |
| #313 packages declare their events | 0.8 | #927 and #928 build on it |
| #926 `[integrations.media]` | 0.8 | #928 "auto-wiring" |
| #927 event retention classes and rollup helper | 0.8 | #928 "rollup table" |
| #899 apply of a Docker app, exit 127 | 0.6 | recipe install flow, which #424 extends (the cause is fixed per ADR 0028; check what is left) |
| #850 install dialog says "rebuilt" | 0.6 | same dialog, cosmetic |

Left where they are: #434 (built, only ADR status and test list open, stays 0.8), #450 (pages to shared components, 0.9, runs alongside),
#239 (no scope written), #613 (interactive recipe form).

## Work items and order

Four lanes that touch different files, so they can run in parallel. A wave starts when its dependencies are merged into `develop`.

### Wave 1: no dependencies

| Lane | Issue | Content | Main files |
| --- | --- | --- | --- |
| A. Placement | #790 | `group`, `after`, `[[web.page.tabs]]`, `template`, `state`, `role`; server drops unknown group or over-reading declarations; tests for each; remove the Extensions group | `scripts/hs_ext.py`, `scripts/lib/pkg_roles.py`, `web/src/nav.js`, `web/src/shell/GenericPage.svelte`, docs/PLAN-extensions.md |
| B. Blocks | #473 part 1 | registry (name, schema, component, `api-level`), `pkg.py validate` checks `[web.page]` against it, unknown block shows a note | `web/src/shell/GenBlock.svelte`, `scripts/pkg.py` |
| C. Errors | #900, then #488 | `scripts/lib/error-codes.tsv`, `errors-doc-gen.py`, docs/errors.md, run layer sets `code` in `web-serve.py`; then the rule in docs/CLI-DESIGN.md, codes on the most shown failures, web shows code, text and guide link | `scripts/lib/`, `scripts/web-serve.py`, `web/src/shell/PlanDialog.svelte` |
| D. Events | #313 | `[[events]]` in `package.toml`, installed by `hs pkg`, core table no longer holds app kinds | `scripts/pkg.py`, `scripts/lib/event-kinds.tsv`, docs/events.md |
| E. Recipe flow | #899, #850 | what is left of the exit 127 case; the banner says "rebuilt" only when a rebuild is planned | `scripts/apps-change.sh`, `web/src/forms/ops/InstallDialog.svelte` |
| F. Media manifest | #926 | `[integrations.media]` defined, validated by `pkg validate`; four recipes declare it (hobnix/recipes) | `scripts/pkg.py`, hobnix/recipes |

### Wave 2: needs wave 1

| Issue | Needs | Content |
| --- | --- | --- |
| #473 part 2: blocks chart, stat tiles, log tail, progress | B | one block per pull request, each registered with a schema and a gallery entry |
| #473 part 3: declared form block | B, C | fields with checks that end in a plan, secrets on stdin (own pull request, the largest block) |
| #472 slots | A | the list of slots (tree entry, object-page tab, overview tile, settings section, health check, row action) decided and documented with one example each; unknown slot refused at install; a package that is off shows nothing |
| #424 recipe status panel | A, B | `[web]` status panel and allowlisted actions in a recipe manifest; app page renders it; one recipe as pilot |
| #927 retention classes and rollup helper | D | class required in the declaration, housekeeping prunes by class, `upsert(month, user, kind)` helper, 5-year size test |

### Wave 3: showcase extensions (hobnix/extensions)

#924 ext-game-lobbies (pilot for two slots, per #472) and #928 ext-media-hub. Both need hardware tests, so they close with a box in the
tracker issue #1063, not as a release gate. #924 needs #472 and #790; #928 needs #926, #927 and #313.

## Dependencies at a glance

```
#790 --> #472 --> #924
#473a --> #473b, #473c, #424
#790 --> #424
#900 --> #488
#313 --> #927 --> #928
#926 --------------> #928
```

## Risks and open points

- **Slot list (#472) is a design decision.** Needs the owner's yes before code: which slots, and whether a health check slot belongs here or in
  the health work of 0.10. Wave 2 starts with a design note, not code.
- **The declared form block** touches secrets and plans. It follows the secret rules (scripts/lib/secret.sh, never argv) and is reviewed
  separately.
- **#927 depends on the store decision #481** (0.10, ADR 0026 decides one store). If #481 is not merged, #927 waits.
- **Four existing package pages** (games, posters, passthrough, ad-selfservice) must keep working: lane A keeps a regression test that loads
  each one.
- **Generated files** (CLAUDE.md): a changed `sys` row means `openapi-gen.py` and `openapi-ts-gen.py`; new event kinds mean `events-doc-gen.py`.
- Nothing here was run on a server. Each item adds its steps to the hardware-test tracker #1063 when it is merged.
