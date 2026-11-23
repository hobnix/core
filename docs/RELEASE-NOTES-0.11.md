# Hobnix 0.11.0 release notes

Draft release notes of the release "0.11 Navigation and pages", built from the changelog entries of `docs/changelog/` that are on `0.11` but not in
`v0.10.0` and from the plan `docs/PLAN-navigation.md`. Written 2026-11-22 for `v0.11.0-beta.2`.

**Read this first.** This is a beta. Nothing in 0.11 has been run on a real server, and the browser passes for accessibility and the phone layout have
not been run (see "Not tested yet"). Every item below is built and covered by the tests of the repository. Not tested on hardware yet. The tracker
issue "Hardware test: 0.11" lists the boxes to check on a server. A box that is not ticked is postponed, it never blocks the release.

## What 0.11 is
A tree a new user understands, one page per object, and a selected row that never moves the list. Web interface only; no command, setting or
machine-readable output changed.

## The new tree
- **Eight groups** instead of twelve entries: Storage, Instances, Apps, Network, People, System, Backup, Settings. Hardware, Updates and Certificates
  are in System, the Network map in Network, Services in Network, Marketplace and Docker in Apps.
- **Docs and What's new** are buttons in the top bar, **Incident** is a button on Pools and on Health, the list of servers opens from the Servers
  header, and Releases is a tab of Updates. **Developer** shows only while the test-lab capability is on.
- **Old addresses and bookmarks keep working** and open the new place. The redirect table is kept through 0.12 and removed in 0.13.
- The tree of another server (peer, edge, VPS) keeps its pages; its Health entry is now called System.

## Pages
- **A page per object:** disk, share, instance and user (and the pool as before), at `/storage/disks/<name>`, `/storage/shares/<name>`,
  `/instances/ct/<name>`, `/people/users/<name>`, with tabs, a header with at most two visible actions, a More menu and a danger section.
- **Quick look:** selecting a row opens a panel over the list on Groups, Nodes, Docker and Live state. The list keeps its width; the address carries
  `?sel=`, so reload, Back and a pasted link work. The Disks, Shares, Instances and Users lists have no quick look: each row ends with its actions
  (see "Changes since beta.1").
- **Group pages** for Storage, Backup and System show one line of state and a card per place with its state. The other groups keep the card list.
- **A refused change** shows its error code and a link to the guide in the plan dialog (web half of #488; the scripts print the codes from 0.12).
- **Network map:** the page that draws how the server reaches the network, with live traffic (the map arrived on the 0.10 line; see
  [Web interface](web-interface.md)).
- **Phone:** the quick look and the tree slide-over use touch targets of 44 px.

## Changes since beta.1
- **Fixed:** the Shares and Instances lists showed "No shares yet" or "No instances yet" although entries existed (#1080). The model values are
  now read through getters; the test `web-model-getters` guards it.
- **Row actions instead of a quick look** on Disks, Shares, Instances and Users. Each row ends with its actions: Disks **Open disk**; Shares
  **Browse files** and **Open share**; Instances **Open instance**, Start/Stop and Restart; Users **Edit**, **Change password** and **Open user**.
  The Instances list shows a failed job as a "failed" chip on the state; the full note is on the instance page.
- **Fixed:** a link to a missing `troubleshooting.md` in the docs was removed (#1082).

## For developers
- An action row has at most three visible buttons (`tests/web-actions.sh`, ratchet). Pages spell paths through `web/src/paths.js`.
- Accessibility checks: `tests/web-a11y.sh` (contrast of the tokens in both themes) and an axe check in test-lab stage 6 with a baseline file
  (`scripts/dev/axe-baseline.tsv`); it fails on new findings only.
- The error code `plan.changed` is a placeholder until the scripts half of #488 (0.12). The cleanup of `ui/Split` is tracked separately.

## Not tested yet
The whole release on hardware: Not tested on hardware yet. Boxes are in the tracker "Hardware test: 0.11". In particular:
- The disk, share, instance and user pages and their row actions on a real server (a plug and pull with the page open, a VM console tab).
- A sent link opened from another browser, and the address of a removed object.
- An old bookmark and an old link from a notification land on the right page; a real peer node shows its tree; the tree of a locked server.
- The group pages on a server with a degraded pool, a failed backup and open problems.

Not run in a browser, so not seen by anybody:
- **Step 11, accessibility:** the keyboard walk of every touched page, the axe check on the VM, and a screen reader (NVDA or VoiceOver) over sign in,
  unlock, install an app and a typed-name plan.
- **Step 12, phone:** the 390 px pass of a list, an object page, a group page and the tree slide-over, and a real phone.

## Known issues
- The `Split` side panel is still used by Files.
- The audit of the accessibility of the old pages is a separate item; this release checks the new work only.
- Issues of milestone 0.11 stay open on the board until their hardware boxes are ticked.
