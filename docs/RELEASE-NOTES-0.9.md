# Hobnix 0.9.0 release notes (draft)

Draft for the release "0.9 Web Components", built from the changelog entries of `docs/changelog/` that are on `0.9` but not on `develop` after 0.8 (9) and
the commits of the milestone. Written 2026-11-20. The same text is the body of the release pull request and of the GitHub release.

**Read this first.** 0.9.0 is a web interface release: one shared set of parts (cards, dialogs, progress bars, timelines, steppers) now draws the pages, so
they look and behave the same. Almost nothing here changes what the server does. Nothing was run on real hardware and no owner has looked at the pages in a
browser yet; the checks are the automated web tests and builds. Items marked **Not tested on hardware yet** have not been tried on a real server. Pages were
moved group by group, so a page can have changed in small ways (spacing, wording of a button, where a tooltip sits): see "Not verified".

## What 0.9.0 is
A web interface built from one component library instead of page-by-page markup, a gallery page that shows every part, and a demo mode that runs the
interface with made-up data.

## The shared component library
- **Layout**: Card, Row, Stack and Muted for page structure.
- **Overlays**: Dialog, Menu, Toast and QuickLook. A dialog keeps the keyboard focus inside and gives it back when it closes.
- **Progress**: one Progress bar and one StepList. The percent is always written next to the bar, and a job without a known total shows a moving bar instead of
  a wrong number. The Jobs page and the file manager use it.
- **Timeline**: the Events page lists events newest first, grouped by day, with the level written as a word and the filters above the list.
- **Stepper**: the app wizard, the install dialog and the storage incident page list their steps with a number or a mark and a word for the state; in the
  app wizard a finished step can be opened again.
- **Errors and the bell**: ErrorNote shows a code, the likely reason, one next step and a link to the guide. A bell in the top bar counts the problems nobody
  acknowledged plus the warnings that arrived since you opened the page; each entry opens the page of what it is about.
- **State parts**: StateCard, LinkedObjects, JobStrip and DangerZone.
- **Icon and Chip**: one name list for icons, icon-only buttons, and Chip kinds for trust and status.

## Pages on the shared components (#450)
The storage pages, shares, users and groups, instances and Docker, settings, node, router and builder forms, backup, vault and expiry pages, and the file
manager moved to the shared parts group by group, and the last raw inputs became shared fields (new Slider). The file manager keeps the behaviour of 0.8
(single pane, folder size, trash wording).

## For developers
- **Component gallery**: `Developer > Components` shows every shared part in its sizes, busy, disabled and error states, in light or dark and at phone width. It
  replaces Storybook for now (ADR 0029, `docs/adr/0029-component-gallery-instead-of-storybook.md`; the triggers to revisit are in the record).
- **Demo mode** (#461): `npm run demo` in `web/` starts the interface with made-up data (a healthy server, a degraded pool, locked storage, one pool or three
  pools). Plans open, but no change is ever started.

## Fixes
- **Disks page**: the sleep state and measured power of the disks load on a real server; the web server now allows that read (read-only). The sidebar no
  longer requests two router reads that need an address.
- **Settings > Updates** shows its page again (the status tag was never computed).

## Not in this release
- Live state on by default and booting the ISO on real hardware (#175), as before.
- Storybook (decided against for now, see above).

## Not verified
- No page was checked in a browser by the owner on a real server. The automated web tests, the gallery coverage test and the build passed in development.
- Every item marked "Not tested on hardware yet": the disk sleep and power columns on real disks, and all pages against a real server rather than the demo data.
- The merge of `develop` (0.8 work, file manager changes) with the component moves was resolved by hand in the file manager and backup pages; look at both.
