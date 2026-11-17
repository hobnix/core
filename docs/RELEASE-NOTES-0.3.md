# Hobnix 0.3.0 release notes (draft)

Draft for the release "0.3 Foundations", built from the 19 commits (without merges) that are on `0.3` but not in `v0.2.0`, the 6 changelog entries of
`docs/changelog/` since then and the issues of the milestone. Written 2026-11-17. Re-read before the tag. The same text is the body of the release
pull request and of the GitHub release.

**Read this first.** 0.3.0 is a small foundation release. In a virtual machine on the real test-lab server the stages install, smoke check, rollback,
backup and restore, pool, and the upgrade from v0.2.0 passed on the tip of `0.3` (2026-11-17). The browser stage (6) was skipped there (no
playwright on the server). Nothing ran on physical hardware, and nobody has looked at the web interface of this version. Items marked
**UNVERIFIED** were written and tested only with fakes, fixtures and unit tests.

## What 0.3.0 is
The follow-up of 0.2.0 (released 2026-11-17). It prepares the next steps (live state in the state database, cleaner web code) and makes the test-lab
much faster. Most of the planned live-state work (issues #559, #561 to #566, #481) is **not** in this release: only the decision (ADR 0026) and the
measurement path are.

## What changed
- **The `hs` commands print English only** (#491): the German catalog of the commands is gone; the web interface keeps its own language setting.
  `hs first-run` asks for the default language of the web interface.
- **Every read has a topic or a written reason to poll** (#482): a ratchet test lets the number of timed reads only go down.
- **Old page addresses that redirected are removed** (#423, web). A bookmark of an old address now shows the not-found page.
- **Web building blocks**: form field components (Field, TextInput, Select, Textarea, Checkbox), a ratchet for raw form elements, own styles and
  hex colours, and an inventory script (`python3 scripts/dev/web-inventory.py`).
- **Live state, step 1 of ADR 0026** (measurement only, off by default): `liveState = "db"` reads topics from the state database, a heartbeat row and
  `hs live measure` for the write load and latency. UNVERIFIED on a real server (#560, #566 are open).
- **TODO.md is retired**: `/work`, the session hook and the roadmap page read the GitHub board.
- **Test-lab, faster** (#712): the installer ISO is cached per commit, the stage command lines are checked against the repository without a VM, and
  stages 3 and up start from a golden copy of the installed VM. Measured: stages 1 to 5 together 22 minutes, stage 7 20 minutes, stage 3 on a
  golden copy 4.5 minutes instead of 12.

## Not in this release
- Live state on by default with one store, the removal of the Redis option, the single status on the Data page, the rewritten docs (#481,
  #559, #561 to #565).
- A real-server check that a terminal change shows in the open page (#566) and the notification channels on a server (#420).

## Not verified
- The web interface of this version (stage 6 skipped).
- Everything on physical hardware.
- `liveState = "db"` on a real server.
