# 0030: UI SDK for the Network Map: use it for behaviour, pinned, one part at a time

Status: Accepted (2026-11-21), spike result
Issue: hobnix/server#871 (epic #870, docs/PLAN-network-map.md)

The build, the gallery and the checks below were run on a developer machine (Windows, Node, Vite dev server in demo mode). Not tested on hardware yet.

## Context

The Network Map is the pilot for UI SDK (`@ui-sdk/svelte`, headless behaviour: keyboard, focus, popup placement; the drawing and the look stay ours). The plan asked the spike to
decide whether it builds, takes our tokens and passes our checks before the map depends on it. The Storybook of the issue text became the component gallery
(ADR 0029), so the "story" is a gallery entry.

## What was done

- `@ui-sdk/svelte@0.1.0-beta.13` and `@ui-sdk/core@0.1.0-beta.13`, both exact in `web/package.json` (the Svelte adapter has `@ui-sdk/core` as a peer dependency, so both are needed).
  `0.1.0-beta.13` is the `latest` and `beta` tag on npm (2026-11-19). The plan named beta.11; that version was never published (10, then 12).
- `web/src/ui/NodePopover.svelte`: the detail popover of a node, on `Popover`, `PopoverTrigger`, `PopoverContent`, `PopoverTitle`, `PopoverClose` from `@ui-sdk/svelte/popover`. The look is
  the `.np-*` block in `web/src/base.css`, tokens only (`--panel-3`, `--line-2`, `--r`, `--shadow`, `--accent`).
- A gallery entry `NodePopover` (two states). No page uses it yet.

## Finding

| Question | Answer |
| --- | --- |
| Builds | Yes. `vite build` passes with Svelte 5.57.3 (peer needs `>=5.33`). No config change, no plugin: the package ships `.svelte` files and the existing Svelte plugin compiles them. |
| Themes | Yes. Every part carries a `data-slot` and state attributes (`data-starting-style`, `data-side`); our classes and tokens style them. Dark and light follow the tokens with no extra work. |
| Behaviour seen | In demo mode: the content has `role="dialog"`, focus moves inside on open, Escape closes, focus returns to the trigger. Not seen: touch, screen reader, a popover at a viewport edge (the second gallery state is there to look at that). |
| Our checks | Green: `tests/web-gallery.sh`, `web-ratchet.sh` (no own `<style>` block, no hex), `web-buttons.sh`, `web-icons.sh`, `web-demo.sh`. `web-undefined.sh` fails on `shell/JobRecords.svelte` with and without this change. |
| Bundle size | **Main chunk 1,136.05 kB, gzip 377.58 kB, before; 1,235.56 kB, gzip 414.16 kB, after: +99.5 kB, +36.6 gzip (+9.7 %) for one popover.** The CSS grew by 0.6 kB. The tree-shaking is not the issue as much as the shared core (popup placement, focus, the part runtime): a second part should cost far less, but that was **not measured**. No bundle-size gate exists in `tests/` today, so nothing failed; the number is the finding. |
| License | Apache-2.0 for both packages (`LICENSE` ships in the tarball). Compatible with our dependencies; keep the notice if the files are ever vendored. |
| Install weight | 3.5 MB (svelte) and 6.1 MB (core) unpacked, mostly types and the parts we do not import. `npm audit` reports 0 vulnerabilities. |

## Risks

- **Beta, released almost daily** (13 versions in 8 days, two of them in one day). An upgrade is its own pull request; the gallery entry is the first thing to look at after it.
- **Size.** 37 kB gzip on first use. The map page is one route of one bundle today; if size matters, load the map and its parts lazily (`import()` of the page) so the other pages do not pay.
- **Our look is a CSS block we maintain.** Each SDK part we use needs its `.np-*`-style block in `base.css`; keep them small and named per component.
- **API drift** in `@ui-sdk/core` controllers: we use the Svelte parts only, never the core primitives directly.

## Decision

**Use it for behaviour, for some parts, pinned; go for the map.** The map's access part (issue 876: roving focus across the nodes, a detail popover, a drawer) takes the popover (and the roving focus
part, to be spiked inside that issue) from UI SDK. Drawing, layout and the table view stay ours. Conditions:

1. Exact pin of both packages; an upgrade is its own pull request that rebuilds the gallery.
2. A part is adopted when the issue that needs it adds its gallery entry, with a state per behaviour that was seen.
3. The map page loads lazily, and the size of the main chunk is written in the pull request that first imports the SDK from a page.
4. If a beta breaks a part, that part falls back to hand-written behaviour (as the plan already says); nothing else in the map depends on it.

The existing `ui` components stay as they are: this decision does not move Menu, Drawer or Dialog to the SDK.

## Consequences

- `web/package.json` has two new dependencies, `web/src/ui/NodePopover.svelte` and its gallery entry stay as the reference for the next part.
- Issue 876 may import from `@ui-sdk/svelte/*` subpaths only (never the root, which pulls every part).
