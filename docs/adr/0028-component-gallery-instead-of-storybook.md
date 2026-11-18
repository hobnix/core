# 0028: The component gallery page, not Storybook (for now)

Status: Accepted (2026-11-18)
Issue: hobnix/server#449 (gallery), hobnix/server#193 (Storybook epic)

Nothing here was seen in a browser or run on a server. The gallery builds and its coverage test passes; Not tested on hardware yet.

## Context

#449 asks for a page that shows every `ui` component in every state; #449 itself says it is cheaper than Storybook (#193) and may be enough, and
that #193 is decided once the page exists. It does now: `Developer > Components` (`/developer/components`, `web/src/pages/Gallery.svelte`).

## Decision

**Do not adopt Storybook now. Keep the gallery page, and revisit #193 only if one of the triggers below happens.**

Why:

- **It runs inside the real app.** The components read the real tokens, the real theme toggle, the real tooltip, toast and dialog mounts, and the
  real i18n. A Storybook needs its own Vite and Svelte config, a decorator that loads `tokens.css`, `base.css` and the fonts, and a copy of each mount
  (`Tooltip`, `Toast`), and then has to be kept in step with the app's build.
- **No new dependency tree.** The web build has 60 packages, all pinned. Storybook adds several hundred, a second dev server and a second CI job. The
  project pins every web dependency; that is a cost every release pays.
- **A test enforces coverage.** `tests/web-gallery.sh` fails when a `ui` component has no entry, or an entry has no state. Stories give no such
  guarantee unless a test is written for them as well.
- **Packages can use it the same way.** The page is the reference for packages that declare pages (#195): the same components, the same data-only props.

What the page does not do, and Storybook would: per-component isolated URLs, a controls panel that edits props live, automatic visual regression
snapshots, and a component docs page generated from the prop comments. The gallery's entries are plain markup with captions; props are read from the
comment at the top of each component.

**Triggers to revisit:** visual regression tests become wanted (then add Playwright screenshots of the gallery first: it is one URL); outside
contributors need to build components without running a server; or the gallery grows past what one page can carry (split it by group before adding a tool).

## Consequences

- #193 stays open as the epic but is not started; its first task, if triggered, is screenshots of this page.
- A new `ui` component needs a gallery entry in the same pull request (the test says so).
- The light/dark switch is the global one; the phone-width switch narrows the column only, so rules that depend on the window width still need a
  narrow window.
