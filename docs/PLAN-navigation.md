# Plan: navigation and pages (milestone 0.11)

Status: built 2026-11-22 on `0.11`, steps 0 to 14 merged (step 14 is the docs PR). Written 2026-11-19 on branch `0.11` (cut from `0.10`, head `a6d0e8c1`).
Epic #451 ("Navigation and page structure") with #452, #453, #454, #455, #457, #776, and #488, #487, #427. The owner decided D1 to D12 on 2026-11-20 (see "Decisions for the owner"; D2 and D3 differ from the recommendation). **Nothing was run on a server**; the release is the beta `v0.11.0-beta.1` (docs/RELEASE-NOTES-0.11.md).

**Deviations from this plan, as built**
- The group Health is named **System** (D2 c); docs/PLAN-web-design.md 2.2 and 2.5 say so.
- **Incident is a button** on Pools and on Health, not a tree entry.
- **Developer** is not a group of the design: it shows only while the `testlab` capability is on (`DEVELOPER_CAP` in nav.js).
- Step 13 (#488) is the web half only. The note recognises the code `plan.changed` as a placeholder (`RELOAD_CODES` in ui/errornote.js) until the scripts print real codes (0.12).
- The cleanup of `ui/Split` (the `.opt` rules; Files keeps it) is **tracked separately**, not part of this milestone.
- Step 11 built the axe check (test-lab stage 6, baseline `scripts/dev/axe-baseline.tsv`) and the contrast test, but the browser passes were **not run**: keyboard walk, axe on the VM, screen reader (R1). Step 12 (390 px) was a code review with fixes in `QuickLook` and the tree; the browser pass at 390 px was **not run** (R2, R3).
- The old-path table (`web/src/redirects.js`) stays through 0.12 and is removed in 0.13 (`REMOVE_IN`, D7).

Related records: docs/PLAN-web-design.md (the design this milestone builds: sections 1 to 3 are decided on 2026-11-18), docs/PLAN-live-interface.md (0.10:
`rowstate`, the event stream), docs/adr/0007-branches-and-releases.md, docs/adr/0012 (roles), docs/adr/0025-translation-scope.md, web/CLAUDE.md,
`.claude/rules/web.md`, web/design/HANDOFF.md (look and states), docs/PLAN-extensions-access.md (format of this plan).

## Goal and non-goals

**Goal.** A tree a new user understands, one page per object, and selecting a row never moves the list. Concretely: eight groups instead of twelve
top-level entries; an address for every disk, share, instance, user and pool that can be sent to someone; a quick look that slides over the list; group
pages that say how the group is doing.

**Non-goals.**
- Package and app pages (`/apps/<name>`, #474, #478): milestone 0.12, built on the Object frame this milestone makes.
- The Jobs page (#385) and the Feed template: the design places them, nothing here builds them. The tree has a slot for them (System > Jobs).
- A new look. Tokens, shell and states stay as in web/design/HANDOFF.md.
- Network Map (0.10.1) pages: a place may be added later; this plan only keeps the tree able to take it.

## What exists today (read from the code on `0.11`, 2026-11-19)

| Area | State | Where |
| --- | --- | --- |
| Tree | 12 entries under the node, about 45 places in all: Storage (7), Instances (4, Docker has one child), Marketplace, Network, Identity (3), Monitoring (4), Protection (2), Operations (4), Docs, Developer (1), Nodes, Setup, Settings (9 + one per capability). `Incident`, `Setup`, `What's new`, `Docs` are entries that are not places. A pool is a child of Storage > Pools, added at render time | web/src/nav.js (`tree`, `nodeItems`, `withPoolItems`) |
| Routes | one flat map path -> page (`routes`), six paths point to `Section`; pool pages are the prefix `/storage/pools/<name>` and Docker apps `/instances/docker/app/<name>` in `pageFor`; no other object has a page address | web/src/routes.js |
| Addresses | every address is `/node/<name>/<inner path>`; `redirects.js` only adds the node. **Old inner paths are explicitly not moved** ("plain unknown pages"): there is no table for moved pages yet | web/src/redirects.js, route.svelte.js |
| Spelling of addresses | 40 call sites in 39 files spell inner paths as literals (`go('/storage/disks?pool=')`, `href`); `readsfor.js` (prefetch) and `Search.svelte` are keyed by the same paths | grep over web/src |
| Selection | local state `selName` on 8 pages (Disks, Docker, Groups, Instances, Nodes, Shares, Users; LiveState and Files keep their own). Not in the address. Cross-page selection is `setSelection(kind, name)` then `go()`, read once by `takeSelection(kind)`; a reload loses it. The only `?` state in lists is the filter (`?pool=`) and Network's `?tab=` | web/src/select.svelte.js, pages/*.svelte |
| Side panel | `ui/Split` + `ui/Drawer` on 9 pages: Disks, Docker, Files, Groups, Instances, LiveState, Nodes, Shares, Users (Gallery and GenBlock show it too). The list narrows to make room, hides `.opt` columns between 861 and 1400 px, drops under the list below 1100 px | web/src/ui/Split.svelte, Drawer.svelte |
| Quick look | **built in 0.9 and used nowhere.** `ui/QuickLook.svelte` is the Drawer as a non-modal overlay (absolute, right, 400 px, full screen up to 860 px, "Open page" link, Escape). Escape closes it only while focus is inside it; focus return to the row is not done | web/src/ui/QuickLook.svelte (0 users) |
| Object pages | pools only (`Pools.svelte` reads the name from `route.path`). Disk, share, instance and user are drawers with tabs; a data disk's drawer has three tabs and up to nine action buttons | pages/Pools.svelte:40, Disks.svelte |
| Group pages | `pages/Section.svelte` (98 lines): one card per child page with a note from `meta`, a list of the children's children, and for Storage the pool bars. It shows what the tree shows; no state of its own except pool capacity | web/src/pages/Section.svelte |
| Menu | `ui/Menu.svelte` (More menu, with `danger` and separators) and `ui/DangerZone.svelte` exist from 0.9; no page uses them for action rows | web/src/ui/ |
| Page frame | `shell/PageFrame` (states), `PageHeader` (crumb, title, actions), `PageState`, `PageTabs` (used by Network), `LinkedObjects.svelte` (45 lines), `JobStrip.svelte` (55 lines) exist. There is no Object template component that puts them together | web/src/shell/ |
| Pool names | `LEGACY_POOLS` in `pages/storage/pool.js` and the string `'bulk'` in a few forms and `FmPlan` remain; the tree and the routes no longer fix them (#456 done in 0.4). A guard from 0.10 (pool-names ratchet) keeps comments clean | web/src/pages/storage/pool.js, files/FmPlan.svelte |
| Rows | `rowstate` (0.10): a row shows pending and failed state from job events | web/src/rowstate.svelte.js |
| Remote nodes | a node is a root of the tree (`nodeItems` by kind); a peer shows Storage, Instances and Backup as read-only summaries (`NodeFacts`), a vps/edge node the proxy pages | nav.js, routes.js |
| Top bar | search (`/`), node switcher already exists, Update and power menus, Inbox (bell). Docs and What's new are tree entries | shell/TopBar.svelte |
| Errors | `ErrorNote` (0.9) shows the text of a failure. ADR 0028 "error codes" is **Accepted** (`docs/adr/0028-error-codes.md`; the build is #488 in 0.12). The component gallery ADR is 0029 (`docs/adr/0029-component-gallery-instead-of-storybook.md`); the number clash was settled in the merge of `0.10` into `0.11` | docs/adr/ |
| Accessibility | `aria-*` on the new components (0.9); no walk through the pages, no automatic check in the test-lab browser stage (stage 6 opens every page, it does not check them) | capabilities/testlab |
| Phone | 39 `max-width` queries, `QuickLook` and the tree slide-over (`onmenu` in TopBar) are phone-aware; no page was checked as a whole at 390 px; no read-only status page | web/src |
| Tests that already guard | tests/web-routes.mjs (+ .sh), web-rowstate, web-demo.mjs, web-prefetch.mjs (every first read is in the `READS` allowlist), web-ratchet.sh, web-buttons.sh, web-undefined.sh, web-sort.sh | tests/ |

Corrections to the epic text: the epic says the quick look is to be built; it is built and unused, so #454 is a migration of nine pages and a fix to
focus handling, not a component. #456 (pool names) is done. "Menu and dialog (#447)" is done in 0.9.

A conflict between two sources of the same decision: **#452 lists ten groups** (Overview, Storage, Apps, Virtual machines, Network, Users, Backup, System,
Settings, Developer) and says "the owner decides the groups". **docs/PLAN-web-design.md 2.2/2.5 is decided (2026-11-18)** with Summary and eight
groups (Storage, Instances, Apps, Network, People, Health, Backup, Settings). They differ in names and in where VMs, Certificates and Health sit. D2 decided: the design tree with "Health" named "System" and Hardware, Updates and Certificates moved in (see D2).

## Design per issue

### #776 thin slice: the disk page

The first step, because every other page depends on the Object frame it makes. One new shell component `shell/ObjectPage.svelte` puts together what exists:
`PageFrame`, `PageHeader` (crumb, name, status `Chip`, at most the visible actions of D4 and a `Menu`), `PageTabs` (Overview first, at most four tabs in all, tab in the
address), a `LinkedObjects` panel, a `JobStrip` for this object (rowstate keys), and a `DangerZone` at the bottom whose actions open a plan that asks for the name.
Disk page: tabs Overview, SMART, Tests, Files (the names #453 gives); address `/storage/disks/<name>[/<tab>]`; the list switches from `Split` to `QuickLook` with
`?sel=<name>` and the quick look has "Open page". Findings that change the design or the component inventory are written back into docs/PLAN-web-design.md in the
same PR. The "Hardware test" box of #776 stays open until the owner has seen it on a server.

### #455 selected row and tab in the address

One helper, so that nine pages do not each invent it: `web/src/selection.svelte.js` with `selected()` (reads `route.query.sel`), `select(name, {tab})` and `close()`.
Opening a quick look **pushes** one history entry, moving to another row **replaces** it, closing goes back one entry when the quick look added it (so Back closes it
and Forward opens it again; a reload or a pasted link starts with it open). `route.svelte.js` gets `setQuery(patch, {replace})` that changes the query and leaves the
path alone. `takeSelection`/`setSelection` become a thin wrapper: `setSelection(kind, name)` + `go(path)` turns into `go(path + '?sel=' + name)`, then `select.svelte.js` is deleted
(Search, Pools, Groups, Users, Shares, ct.js use it today). A name is encoded with `encodeURIComponent`. A selection that does not exist (a link to a removed disk)
shows a "not found" line in the quick look, not an empty drawer. Tested in node (tests/web-select.mjs: the query logic is pure) and one page in the demo browser.

### #454 quick look overlay

Per page: replace `<Split>`/`<Drawer>` by the list plus `<QuickLook>`; the list is not narrowed, no column hides, the table header keeps sticking (the `.hasd` rules go
away with `Split`). Fixes in the component itself (one PR, before the page migrations): Escape closes it when focus is anywhere in the page and nothing else is open
(today only inside), a click outside closes it (not on another row: that replaces it), focus returns to the row that opened it (`data-row` + `focus()`), `aria-label`,
`role="dialog"` not modal, no scroll lock. It shows Overview, linked objects, the main actions (D4) and "Open page" for the five objects with a page; for the others
(group, node, docker app until 0.12, live state topic) there is no page, so the quick look is the whole view. `Split` stays only for Files (two panes are its point) and is
removed when Gallery stops using it. Phone: full screen under 860 px (exists).

### #453 a page per object

Disk (#776), pool (exists: align it to the frame, its name stays data), share, instance, user. Each page (D3 a, decided): the full Object template: Overview (status, key facts, links), up to three own tabs (the drawer's tabs are the start, new content is allowed), linked objects, the job strip, actions in header and `Menu`, danger section. Each page PR writes down its tabs and what each tab shows before building; this may lengthen the milestone. The list pages "only link to" the page (Open page in
the quick look, and the row's name as a link). Registry: `web/src/objects.js` maps a kind to `{ list, page, label, tabs }`; `routes.js` `pageFor` and `nav.js` `itemOf`/`titleOf`
read it, so the pool special case in four places becomes one rule and a new object adds one line. Docker apps and extensions stay as they are until 0.12.

### #452 regroup the tree

Three layers so that the visible change is small and late:
1. **Names for addresses** (`web/src/paths.js`): one table `place key -> inner path` (`P.disks = '/storage/disks'`). The 40 literals become `go(P.disks)`; `nav.js`, `routes.js`,
   `readsfor.js` and `Search.svelte` take their paths from it. A mechanical change (agent `implementer`), no behaviour change, tests/web-routes.mjs unchanged. After it, moving
   a page is a one-line change.
2. **Redirects** (`redirects.js`): a table old inner path -> new inner path, applied after the node is added, with `replaceState` (as today), covering every address of the
   old tree including `?tab=` and the pool and docker prefixes; tested by a node test that walks the old `tree` and `routes` snapshot (kept as a fixture file) and asserts that
   each old path lands on a path that `pageFor` knows (D7 decides whether this stays and for how long).
3. **The tree** (`nav.js`): the new shape of D2; Docs and What's new move to the top bar, Incident becomes an action on Pools and System, Setup becomes a banner on Summary until its
   checks are done (the page stays by address), Nodes become the SERVERS header and the existing node switcher, Developer shows only when its capability is on. Capabilities
   that are off still hide their entry, a page opened by address still works. `visible()` and the role greying (`lockedWhy`) stay. People is no longer hidden by capability `ad`.
   Settings > Releases becomes a tab of Updates (Updates now lives in System). Extension pages get their `group` (default Apps).

### #457 group pages

`Section.svelte` becomes `GroupPage.svelte`: one line of state at the top (computed by the page from reads the group's places already do: no new reads for the first cut, so the
prefetch test stays green), a card per place that shows that place's **state** (a number, a chip, the last job) instead of its description, one or two actions and a `Menu`.
Storage: pool capacity bars (exists), disks needing attention, last scrub/SMART test, shares count, vault locked or not. Backup: last result per job, next run, oldest unverified
restore, expiry dates soon. System (the former Health): problems by severity (reads the Health data), plus the places moved into it: Hardware, Updates, Certificates, last events, jobs running. The other groups (Instances, Apps, Network, People) follow D9. The rule of
#457 "no action row with more than three visible buttons" is a ratchet (tests/web-actions.sh counts `Button` siblings in `.actions`/`PageHeader` snippets per file, baseline file, number only goes down, as web-ratchet).

### #427 / #487 / #488

Decided by D10 to D12. What the recommendations mean in terms of work is in the steps table (steps 11 to 13).

## Decisions for the owner

All twelve decisions were taken by the owner on 2026-11-20 (column "Decision"); the reasoning stays as written. Record the answers as a comment on epic #451 before the first step starts. Where the answer differs from the recommendation, the Decision cell says so and the steps and risks were adjusted (D2, D3). The owner's open action: accept ADR 0028 "error codes" (it is not marked accepted here). "Cost" is what the choice costs if it turns out wrong after release. The recommendations
follow docs/PLAN-web-design.md where it already decided something.

| Id | Question | Options | Recommendation | Cost | Decision (2026-11-20) |
| --- | --- | --- | --- | --- | --- |
| D1 | In which order | (a) the thin slice first: disk page, quick look and `?sel=` on Disks alone, then the lanes; (b) regroup the tree first, pages after; (c) all in parallel from the start | (a). It makes the Object frame and the selection helper once, against real data (#776 says so); the regroup then changes labels and paths only. (c) puts three agents on `nav.js`, `routes.js` and every page at once | (b) breaks every link twice if the frame changes the addresses; (c) is the merge-conflict case of this milestone | **DECIDED 2026-11-20: (a)** thin slice first: disk page, quick look and `?sel=` on Disks alone, then the lanes. |
| D2 | The new tree | (a) the decided design (PLAN-web-design 2.2): node = Summary, then **Storage, Instances, Apps, Network, People, Health, Backup, Settings**; (b) the groups of #452: Overview, Storage, Apps, **Virtual machines**, Network, **Users**, Backup, **System**, Settings, Developer; (c) (a) with "Health" named "System" and Hardware, Updates and Certificates moved in (the third reading of #452) | (a). It was reviewed and decided on 2026-11-18, it keeps Containers and VMs in one place (Instances), and the three "is my server fine" groups become one (Health). Developer is not a group: it is shown at the bottom only while its capability is on. Name of the Health group: "Health" (a person asks "is it healthy") | (b) means a second review of the design and a fourth place for a VM; changing a group name later is a rename plus a redirect row, cheap; moving a place between groups after release breaks bookmarks (D7) | **DECIDED 2026-11-20: (c)**, not the recommendation (a). The design 2.2 tree with "Health" named **System** and Hardware, Updates and Certificates moved into System. Node = Summary, then Storage, Instances, Apps, Network, People, System, Backup, Settings; Developer only while its capability is on. Changed in this plan: Jobs slot, Incident action, group page text, steps 8 and 9, lane G, the check list; step 14 renames the group in PLAN-web-design 2.2. The redirect table (step 7) must also cover Hardware, Updates and Certificates. |
| D3 | What a page per object shows | (a) the design's Object template: Overview, up to three own tabs, linked objects, job strip, danger section, for all five; (b) the same for disk and pool, and for share, instance and user only Overview + the tabs of today's drawer (no new content); (c) Overview only on share, instance, user in 0.11, tabs follow when the objects need them | (b). The drawer tabs are known (Info/Files/..., Instance: Overview, Config, Network, Console), and nothing new has to be invented per page. Tabs of the five objects (written into the PR of each page): disk Overview, SMART, Tests, Files; pool Overview, Members, Datasets, Maintenance; share Overview, Access, Snapshots; instance Overview, Config, Network, Console; user Overview, Groups, Access | (a) invites content decisions in every page PR and delays the milestone; (c) means a page that is the drawer in a bigger box | **DECIDED 2026-11-20: (a)**, not the recommendation (b). The full Object template (Overview, up to three own tabs, linked objects, job strip, danger section) for disk, pool, share, instance and user. Steps 3, 4 and 5 are no longer "drawer tabs only": each page PR must write down its tabs and what each tab shows, and this may lengthen the milestone. The tab lists in the recommendation are a starting point, not a limit. |
| D4 | The More menu and the number of visible actions | (a) header: one primary + at most one secondary visible, everything else in a `Menu`, destructive ones only in the danger section and last in the menu (design 3.1); (b) at most three visible (#457's rule), the rest in the `Menu`; (c) primary + `Menu` only | (a) for object pages and group pages, (b) as the lint ceiling everywhere else (a ratchet: no action row over three visible buttons, number only goes down). A destructive action never has a visible button on a list or a quick look. Which action is primary is written per page in its PR | (c) hides frequent actions (Start, Stop); (b) alone leaves the nine-button row as three plus nine-minus-three clutter on pages nobody revisits | **DECIDED 2026-11-20: (a)+(b)** as recommended: object and group pages show one primary and at most one secondary action, the rest in a `Menu`, destructive ones only in the danger section; elsewhere a ratchet of at most three visible buttons. |
| D5 | Quick look versus drawer | (a) `QuickLook` overlay on all nine pages, `Split` kept for Files only; (b) overlay below 1400 px, side-by-side `Split` above where there is room; (c) keep the `Split` and fix its three faults (narrowing, hiding columns, header) | (a). One behaviour at every width, the list never moves (#454's own check), and the component exists and is tested. The cost: the overlay hides the right-hand columns of a wide table while it is open; the list stays usable and Escape or a click outside closes it | (b) is two behaviours to test and to explain; (c) cannot keep the list at its width | **DECIDED 2026-11-20: (a)** `QuickLook` overlay on all nine list pages, `Split` kept for Files only. |
| D6 | The shape of the address | (a) object `/<group>/<kind>/<id>[/<tab>]`, list `/<group>/<kind>?sel=<id>[&tab=<tab>]` (design 3.2); (b) everything in the query: `/storage/disks?sel=<id>&tab=<tab>`, the page is the list with the quick look open; (c) path for the object, query for the tab | (a). The page address looks like a place, survives renaming the list, and the quick look address differs from the page address on purpose (one is "this row in the list", the other "the object"). Node names stay in front (`/node/<n>/storage/disks/<name>`). Names with `/` or spaces are encoded; a disk name is the stable name (by-id) the app already uses. `?sel=` is the same key on every list | (b) cannot show a page-only view; (c) leaves the same object with two address shapes; changing the shape after release means redirects again (D7) | **DECIDED 2026-11-20: (a)** `/<group>/<kind>/<id>[/<tab>]` and list `?sel=<id>[&tab=<tab>]`. |
| D7 | Old addresses | (a) redirect every old inner path in a table (`redirects.js`), kept for two releases (0.11 and 0.12), then removed; (b) no redirects: today's policy "old inner paths are plain unknown pages"; (c) redirect only addresses that were stored somewhere users keep them: events and notifications deep links, the guides in docs/, search, and the new page's own back links | (a). #452 asks for it, bookmarks and e-mailed links exist, and a node test makes it cheap to prove. Remove the table by milestone, not by memory: a line in docs/PLAN-navigation.md and the redirect test says "remove in 0.13" | (b) is free but every saved link of every user ends on a blank page; (a) costs a table and a test that the next move of a page must update | **DECIDED 2026-11-20: (a)** redirect table kept for two releases (0.11 and 0.12); removal is written as "remove in 0.13" in this plan and in the redirect test. |
| D8 | The tree of a remote node | (a) keep today's trees (a peer: Storage, Instances, Backup as read-only summaries; vps/edge: the proxy pages) and only rename their entries to the new group names where they match; (b) map a peer onto the new groups with the same eight names, empty ones hidden; (c) give a remote node the full tree, greyed where its status document has no data | (a). PLAN-web-design 7.5 is still open for this and a remote node has no pages of its own for most places. The risk of (b)/(c) is a second regroup of `nodeItems` for pages that cannot show anything. Revisit when peers report more than three summaries | (b)/(c) double the work of step 5 and need a status-document change on the peer | **DECIDED 2026-11-20: (a)** keep today's trees of remote nodes and rename matching entries. |
| D9 | Which group pages get real state in 0.11 | (a) Storage, Backup and Health (the three #457 names); Instances, Apps, Network, People keep a card list (a trimmed `Section`, "state" is the count and a problem chip); (b) all seven; (c) Storage only | (a). The three named groups are where the question "is it fine" lives. The four others hold lists the tree already shows; their state line is one count plus the problem chip from the same reads | (b) is four more pages with their own reads and tests and shifts the milestone by a week; (c) leaves #457 half done | **DECIDED 2026-11-20: (a)** group pages with real state: Storage, Backup and System (the former Health); Instances, Apps, Network and People keep a card list with count and problem chip. |
| D10 | #487 accessibility | (a) in 0.11 as acceptance of the new work only: every new page and component passes a keyboard walk and an automated axe check in the browser stage; the audit of all old pages is a separate milestone issue; (b) the whole interface in 0.11 (a walk through every page, the screen reader run, contrast of both themes); (c) move it out of 0.11 | (a). The pages this milestone rewrites (nine lists, five objects, the tree, group pages) are most of the interface and must be right when they ship; a screen reader run of the main flows (sign in, unlock, install, a plan with a typed name) is one step of 0.11 that does not depend on the lanes. The full audit of what 0.11 does not touch follows in 0.12 | (b) is two weeks on top; (c) means the new frame is built without a check and fixed afterwards on nine pages | **DECIDED 2026-11-20: (a)** accessibility in 0.11 is acceptance of new work only (keyboard walk, axe check in the browser stage, one screen reader run of the main flows); the audit of the old pages follows in 0.12. |
| D11 | #488 error messages with stable codes | (a) in 0.11 only the web half, after ADR 0028 is accepted and its catalogue is on `0.11`: `ErrorNote` and `PlanDialog` show code, text and the guide link, unknown codes show the English text; the scripts that emit codes follow in their own milestone; (b) the whole issue in 0.11 (rule in CLI-DESIGN, codes in the main areas, a test that a failing command ends coded); (c) move all of it to 0.12 | (c). It is a cross-cutting change in scripts (about 600 `refuse` calls), ADR 0028 is Proposed on `develop` and its number is also used on `0.11`, and nothing in the navigation work needs it. Ask the owner to accept the ADR now so the number is fixed | (a) puts a half feature on the interface with almost no codes to show; (b) competes with the lanes for the same agents | **DECIDED 2026-11-22 by the owner, reversing the 2026-11-20 decision: (a)** the web half is in 0.11 (ADR 0028 is accepted); the scripts half of #488 (catalogue, `refuse_code`, codes in the scripts) stays in 0.12. |
| D12 | #427 phone layout and read-only status page | (a) phone: the new templates (list with full-screen quick look, object page, group page) are checked at 390 px as part of each lane; the status page and any pass over the old pages move to 0.12; (b) both in 0.11; (c) move both | (a). The phone check is free for the new components and cheap per page; a status page needs an owner decision that is not navigation: who may see it without signing in. **Admin pages are never public** (CLAUDE.md) and a status page shows names of disks and apps. The existing `viewer` role (0.8) gives a "read-only view" after sign-in without new work; a public page needs its own ADR | (b) pulls an access-control design into a navigation milestone; (c) loses the checks while the pages are fresh | **DECIDED 2026-11-20: (a)** phone check at 390 px per lane in 0.11; the read-only status page and the pass over old pages move to 0.12 (a public status page needs its own ADR; admin pages are never public). |

## Steps

Sizes: S up to a day, M two to three days, L a week. Every step adds its tests, runs `scripts/dev/t quick <names>`, `bash -n` for touched scripts and the checks below, and puts a
"Hardware test" box list into its PR (what to open on a real server). A user-visible step adds `docs/changelog/<date>-<topic>.toml`. Strings are English; German texts only where a
page already has them (docs/adr/0025). No new `sys` row is needed by any step; if one turns out to be, `python3 scripts/openapi-gen.py write` and `openapi-ts-gen.py write` go in the same commit.
**Browser pass** means `npm run demo` in `web/` (the demo mode with fixtures, tests/web-demo.mjs) opened at 1920, 1280 and 390 px, with a keyboard walk of the new page, written into the PR in
three lines (not a screenshot dump).

| # | Size | Issue | Step | Files | Needs | How it is checked |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 0 | M | #455 | **Selection and paths foundation.** `route.svelte.js` `setQuery`; `selection.svelte.js` (`selected`, `select`, `close`); `paths.js` with the table of named places and the 40 call sites converted (mechanical); `objects.js` registry (empty but for the pool) used by `pageFor`/`itemOf`/`titleOf` | web/src/route.svelte.js, selection.svelte.js, paths.js, objects.js, routes.js, nav.js, readsfor.js, 39 page files (literals), tests/web-select.mjs, web-routes.mjs | D1, D6 | `t quick web-routes web-prefetch web-select web-undefined web-ratchet`; Back/Forward test of `setQuery` in node; the literal conversion changes no address (a test greps for `go('/` literals left) |
| 1 | M | #776, #453 (disk) | **The disk page and the Object frame.** `shell/ObjectPage.svelte`, the Disk page and its tabs, the Disks list on `QuickLook` with `?sel=`, QuickLook fixes (Escape, click outside, focus return, aria). Findings written back into docs/PLAN-web-design.md | web/src/shell/ObjectPage.svelte, pages/Disks.svelte, pages/disks/*.svelte, ui/QuickLook.svelte, objects.js, docs/PLAN-web-design.md, tests/web-object.mjs | 0, D3, D4, D5 | a node test of the frame (tabs from the address, tab count ≤ 4, danger section last); browser pass; keyboard walk; **hardware**: H1 |
| 2 | S | #454 | QuickLook on the other list pages, one PR each: Groups, Nodes, LiveState (quick look is the whole view), Docker. Remove the `Split` `.opt` rules when the last user is gone | pages/Groups.svelte, Nodes.svelte, LiveState.svelte, Docker.svelte; ui/Split.svelte (last) | 1 | browser pass per page: width, columns and scroll of the list unchanged (check in the PR: `getBoundingClientRect` of the table before and after, measured with the browser tool); `?sel=` test for one page |
| 3 | M to L | #453, #454, #455 (share) | Share: page on the full Object template (D3 a: tabs and content written down in the PR), quick look, `?sel=`, More menu. The pool page moves onto the Object frame in the same lane (`Pools.svelte` is one file: one owner) | pages/Shares.svelte, pages/shares/*.svelte, pages/Pools.svelte, pages/storage/* | 1 | browser pass, keyboard walk; web-forms tests of the share plans unchanged (the plans are not touched) |
| 4 | M to L | #453, #454, #455 (instance) | Instance: page on the full Object template (D3 a; start with Overview, Config, Network, Console, content written down in the PR), quick look, `?sel=`, More menu; the VM console tab keeps its terminal frame | pages/Instances.svelte, pages/instances/*.svelte, shell/VmConsole.svelte (only the tab mount) | 1 | browser pass incl. the console tab; rowstate (pending, failed) on the row and on the page header |
| 5 | M to L | #453, #454, #455 (user) | User: page on the full Object template (D3 a; tabs and content written down in the PR), quick look, `?sel=`; Groups link here; directory users get the read-only marker | pages/Users.svelte, pages/identity/*.svelte | 1, 2 (Groups quick look) | browser pass |
| 6 | S | #457 | **Action-row ratchet.** tests/web-actions.sh and baseline; the new object pages already comply; old pages are lowered one per PR in the lane that owns the file | tests/web-actions.sh, tests/web-actions.tsv, scripts/dev (counter) | 1, D4 | the test fails on a fixture with four visible buttons; the baseline only goes down |
| 7 | M | #452 | **Redirect table and its test.** The snapshot of the old tree and routes as a fixture; the table; `replaceState` in `route.svelte.js` also for moved paths; no tree change yet | web/src/redirects.js, tests/web-redirects.mjs, tests/fixtures/old-tree.json | 0, D2, D7 | the test: every old path ends on a path `pageFor` knows; a query and a node are kept; `/node/x/...` and node-less forms both |
| 8 | L | #452 | **The tree switch.** The new `nav.js` (D2), paths moved in `paths.js` only, Docs and What's new to the top bar, Incident as an action on Pools and System, Setup banner on Summary, SERVERS header and switcher, Releases as a tab of Updates, Developer shown by capability, extension `group`, Search page entries and `readsfor.js` follow `paths.js`. The merge-hot step: see "Lanes and merge rules" | web/src/nav.js, paths.js, routes.js, redirects.js, shell/Tree*.svelte, shell/TopBar.svelte, shell/Search.svelte, pages/Summary.svelte (banner), pages/Setup.svelte, settings/layout.js, tests/web-routes.mjs | 0, 7 (and all object lanes merged or rebased), D2, D8 | web-routes, web-prefetch, web-redirects; browser pass on the tree at three widths with the phone slide-over; role greying and capability hiding checked with fixtures for roles viewer, operator, admin; every old tree entry is reachable (a test lists the new tree against the old one) |
| 9 | M | #457 | **GroupPage and the three groups:** Storage, Backup, System. A group page reads only reads its places already use (prefetch test) | web/src/pages/GroupPage.svelte, pages/groups/Storage.svelte, Backup.svelte, System.svelte, routes.js (one line each), Section.svelte (trimmed for Instances, Apps, Network, People) | 8 for Backup and Health (paths); Storage group may start after 1 | browser pass, `t quick web-routes web-prefetch`; the state lines render with locked storage, an offline pool and no data (fixtures) |
| 10 | S | #452 | Remote node trees renamed to the new group names where they match (D8); tests for peer, vps and edge | web/src/nav.js (`nodeItems`), routes.js (`peerRoutes`), tests/web-routes.mjs | 8 | web-routes; browser pass on a fixture peer |
| 11 | M | #487 (D10 a) | Accessibility acceptance: a keyboard walk of every page this milestone touches, axe in the browser stage (new test-lab check that fails on new findings only, with a baseline file), contrast of the tokens in both themes, one screen reader run over four flows | capabilities/testlab (stage 6), tests/web-a11y.*, web/src/tokens.css (if contrast fails), the pages with findings | 8, 9 | the axe check fails on a fixture with a missing label; the walk results are a list in the PR with fixed and filed items; **real browser** required (R1) |
| 12 | S | #427 (D12 a) | Phone check of the new templates at 390 px, fixes inside the new components only | ui/QuickLook.svelte, shell/ObjectPage.svelte, pages/GroupPage.svelte, shell/Tree*.svelte | 8, 9 | browser pass at 390 px of one list, one object page, one group page and the tree slide-over |
| 13 | S | #488 (D11 a) | **In 0.11 (decided 2026-11-22, web half only).** `ErrorNote` and `PlanDialog` show code, text and the guide link; an unknown code shows the English text unchanged. The scripts half of #488 stays in 0.12 | web/src/ui/ErrorNote.svelte, ui/errornote.js, shell/PlanDialog.svelte, tests/web-inbox.mjs | ADR 0028 accepted | see #488; a plan shows the coded note once a script prints `code` |
| 14 | S | #451 | Docs and close: docs/web-interface.md (tree, pages, quick look, addresses), screenshots, `tests/docs.sh` green, changelog entries per user-visible step, remove the old-path table date line (the table stays through 0.12: "remove in 0.13", D7), epic ticked, `python3 scripts/dev/untested.py` lists the hardware boxes | docs/web-interface.md, docs/changelog/*.toml, docs/PLAN-web-design.md (2.2, 2.5: rename the group Health to System) | all | docs test; boxes ticked only for what was seen |

## Lanes and merge rules

The three issues the brief names (#452, #453, #457) all edit the sidebar, the routes and the page shells. The way to keep them apart is by **file ownership and by order**, not by hoping:

- **Lane F (foundation, serial, one session): steps 0, 1.** Nothing else starts before step 0 is merged; the object lanes start after step 1. Step 0 touches 39 page files (the literal paths) and is a single mechanical PR merged **first and alone**; every other PR rebases onto it.
- **Lane P (pages, parallel, one session per page):** step 2 (four small pages), 3 (shares and pools), 4 (instances), 5 (users). Each session owns its page files and adds one line to `objects.js` and, for the page's address, to `routes.js` (resolved by `pageFor` through `objects.js`, so `routes.js` is not touched at all). They do **not** touch `nav.js`, `Section.svelte` or `redirects.js`. Two PRs never touch the same page file: the pool page goes with the share lane because shares link to pools and both live under `pages/storage/`.
- **Lane A (action-row ratchet): step 6**, after 1, in parallel with lane P (its own test files; the baseline file is the only shared one: each lane lowers its own line, conflicts are resolved by recounting).
- **Lane T (tree): step 7 can start after step 0** and runs next to lane P (only `redirects.js` and its test). **Step 8 is the one step that edits `nav.js`, `routes.js`, `paths.js` and the shell** (merge-hot) and runs **alone: after lane P's PRs are merged or rebased** (the owner merges the page PRs first; step 8 rebases on the result and only edits `paths.js`, `nav.js`, `routes.js` rows). Because pages call `go(P.x)` and not literals, step 8 changes no page file. Steps 9 and 10 follow it.
- **Lane G (group pages): step 9.** The Storage group page can be built next to lane P (new files plus one `routes.js` line); Backup and System wait for step 8. `Section.svelte` is touched only here.
- **Lane Q (quality): 11 and 12** after 8 and 9; 11's test harness (axe in stage 6) can be written earlier in a branch that touches only capabilities/testlab.
- Step 13 is outside the lanes; step 14 last.

Merge-hot files, so these merge one at a time and rebase after each: `web/src/nav.js` and `web/src/routes.js` (0, 8, 10; 1-5 add no line to either because of `objects.js`); `web/src/paths.js` (0, 8); `web/src/objects.js` (1 to 5: one line each, an append-only table so conflicts are trivial); `web/src/redirects.js` (7, 8); `tests/web-routes.mjs` (0, 8, 10); `tests/web-ratchet.tsv` and `tests/web-actions.tsv` (every page PR lowers its number: recount with the test's `--update`, never merge by hand); `web/src/pages/Section.svelte` (9 only); `docs/PLAN-web-design.md` (1 and 14); `docs/web-interface.md` and `docs/changelog/` (each PR adds a new changelog file, so no conflict; the guide is edited in step 14 only).

A "Shared with 0.12" note: step 1's `ObjectPage` is the frame that package and app pages (#474, #478) use. A change to its props after 0.11 is a change to 0.12's plan; so the props are fixed in step 1 and written into docs/PLAN-web-design.md 3.2.

## What only runs on hardware or in a real browser

| Id | Step | What to look at |
| --- | --- | --- |
| H1 | 1, 3 | The disk page on a real server against the mockup (#776 box): SMART tab with a real drive, a plug and a pull with the page open (rowstate and events, 0.10), the pool page of a real ZFS and a SnapRAID pool, the quick look on a list with 30 real disks. Not tested on hardware yet. |
| H2 | 3, 4, 5 | A share, an instance and a user opened by address from another browser (a sent link), a removed object's address (not found, not a blank page), a VM console tab on a real VM. Not tested on hardware yet. |
| H3 | 8 | An old bookmark and an old link from an e-mailed notification land on the right page; a node that is a real peer shows its tree; the locked-storage state of the tree on a real locked server. Not tested on hardware yet. |
| R1 | 11 | A real screen reader (NVDA or VoiceOver) on sign in, unlock, install an app and a plan with a typed name. Only a person can do this; the automatic check cannot. |
| R2 | 2 to 5, 12 | A real phone (not an emulated width) for the quick look, the tree slide-over and a typed-name dialog; touch targets; the on-screen keyboard over a dialog. |
| R3 | all lanes | Browser pass in `npm run demo`: layout at 1920, 1280 and 390 px, focus visible, Escape/click-outside, Back/Forward with the quick look. Done by the session of the lane and repeated once by the owner at the end. A browser pass with demo fixtures is not a pass on a server. |

Everything else is tested in node or by the shell tests (`t quick`).

## Risks

- **Merge conflicts in the tree and the routes.** Mitigation: `paths.js` and `objects.js` (steps 0 and 1) take the spelling of paths out of the pages; step 8 runs alone; lanes own files.
- **Two decided sources disagree** (#452's ten groups against the decided design). Mitigation: D2 first; a plan that starts with the wrong tree costs the redirect table twice.
- **Broken bookmarks and links in events, notifications and guides.** Mitigation: D7 (a), the redirect test, and a grep of docs/ and the event texts for old paths in step 14.
- **The overlay hides columns** the user wanted to compare while looking at a row. Mitigation: the list stays usable behind it; the quick look is closable with one key; D5 states the cost.
- **History pollution.** A quick look that pushes an entry on every row makes Back useless. Mitigation: push once, replace on switch (step 0, tested).
- **A page for each object grows by features and content decisions** (D3 (a): the full Object template on all five objects). Mitigation: at most four tabs, the action-row ratchet, and every page PR writes down its tabs and what each shows before it is built. This may lengthen the milestone: steps 3, 4 and 5 are sized M but can become L; the PR says so when one does.
- **Roles.** Every page is listed for every role and greyed by the row (0.8). New pages must use `lockedWhy`; a viewer opening an object page by address must see the page read-only, not an error. Tested with the three roles in step 1.
- **Capability-hidden entries** and the redirect: a redirect to a place that is hidden by a capability that is off lands on a page that still works by address (as today), and says "part off" through `PageFrame`.
- **Dependence on 0.10.** The job strip and the pending row need `rowstate`, merged in `0.10`; if the live-state mode is off the pages still work with the timers of 0.9 (no new reads).
- **ADR number clash (settled).** Error codes is 0028 and the component gallery is 0029; the merge of `0.10` into `0.11` kept both numbers.
- **Scope.** #487, #488 and #427 together are larger than the rest. D10 to D12 cut them; without a cut the milestone does not finish.

## Check that it worked

- Every old address of the table in `tests/fixtures/old-tree.json` opens its new page (D7 a), in node and in `npm run demo`.
- A link to a disk, a share, an instance and a user, pasted into a new browser tab, opens the same page; a link to `?sel=` opens the same quick look; Back closes it, Forward opens it.
- Opening and closing a quick look changes no width, no column and no scroll position of the list, at 1920, 1280 and 390 px (the numbers are in the PR).
- The tree has Summary and the eight groups of D2 (Storage, Instances, Apps, Network, People, System, Backup, Settings; Hardware, Updates and Certificates sit inside System) (two levels), no pool name and no entry that is not a place, and the group pages for Storage, Backup and System show state.
- No page has more than three visible action buttons (`tests/web-actions.sh` baseline lowered), and no destructive action has a visible button outside the danger section.
- `t quick web-routes web-prefetch web-select web-redirects web-actions web-undefined web-ratchet web-buttons` is green; the browser stage axe check is green with its baseline unchanged or lower.
- The hardware boxes of the issues are ticked only for what was seen; the epic lists what was not.
