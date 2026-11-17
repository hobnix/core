# Release 0.2.0 checklist

The steps, in order, to release Hobnix 0.2.0 "Safe Updates". For the owner who signs the tags; nothing here has been done yet. Prepared 2026-11-16
from the milestone branch `0.2`. The how is in `docs/RELEASE-PROCESS.md` and `docs/RELEASE-0.1-checklist.md` (sections 3 to 13 still apply:
packages first, release pull request, tag, ISO, merge back); this list says what is different for 0.2 and what is still open.

Legend: **not run** = nobody has run this step. **seen** = a person saw the result. Nothing on this list ran on physical hardware.
Not tested on hardware yet.

## What was seen (test-lab in a VM on the real server)
- Stages 1 install, 2 smoke and 3 rollback (a bad update goes back by itself) passed.

Everything below is **not run** unless it says seen.

## 1. Test-lab: the exit rule
The release is ready only when the test-lab is green on the commit that gets tagged. On the machine with the capability `testlab`:

```bash
hs testlab run --stage all --ref 0.2
```

Then read the results:

```bash
hs testlab results
```

- [x] stage 1 install, 2 smoke, 3 rollback: seen ok (#432, #161)
- [ ] stage 4 backup, then restore onto a second clean VM (#163, #165): not passed yet
- [ ] stage 5 pool and file manager on virtual disks (#415, #425): not passed yet
- [ ] stage 6 headless browser opens every web page (#416): not passed yet
- [ ] all of them again on the commit to be tagged (the run records `commit` in `stage-<n>.json`)

## 2. Upgrade run (#435)
The last release is `v0.1.0`. With the candidate on a branch (the milestone branch `0.2`, or `develop` after the merge):

```bash
hs testlab run --stage 7 --ref 0.2 --from v0.1.0
```

- [ ] `stage-7.json` says `ok` for the commit that is going to be tagged: not passed yet
- `hs update` normally follows a signed tag; the stage points the old checkout at the candidate branch, so the signed-tag path is not covered.
  Check that by hand in section 4.

## 3. Open issues of the milestone "0.2 — Safe Updates"
State on 2026-11-16 (`gh issue list --milestone "0.2 — Safe Updates" --state all`; confirm on GitHub):
- #231 update channels: open. Box open: first signed tag followed on a real server (section 4). The operations guide keeps "Not tested on hardware yet."
  until then.
- #233 release process: open. The issue text still says "scope still to be written"; the work is in `docs/RELEASE-PROCESS.md` and
  `scripts/dev/release-core.sh`. Write the acceptance criteria, then close.
- #432 test-lab stages: open. Its boxes are ticked because the stages are written; only stage 3 ran (section 1).
- #435 upgrade test: open. Boxes ticked because the stage is written; it has not run (section 2).
- #436 nixpkgs pin policy: open. Box open: the NixOS release change guide, tested in the test-lab (section 5).
- #439 CI: open. Box open: required checks on `develop` and `main`, a merge queue or "branch must be up to date" (repository settings, with #233).

Decide for each open box: do it before the tag, or move it to the next milestone with a sentence in `docs/RELEASE-NOTES-0.2.md`.

## 4. Stable on a real server, and a beta (#231, #233)
Not run.

- [ ] Cut a beta from the milestone branch: `bash scripts/dev/release-core.sh tag v0.2.0-beta.1` (needs `docs/RELEASE-NOTES-0.2.md` on `0.2`, the gate
  `scripts/dev/release-gate.sh check` in the workflow). Check it is a prerelease with the ISO and that a stable server does not offer it. The
  prerelease and ISO path of PR #545 never ran on a real tag.
- [ ] After the stable tag, follow it on a real server, as in `docs/RELEASE-PROCESS.md` ("First release 0.1.0 and the first stable server"), with
  `hs update --preview`, `hs update`, and `release-core.sh follow-check <tag>` before and `--after`. Tick the box of #231 with the output. (A server
  that already is at the tag commit shows `kept`: use one that is behind.)
- [ ] The signed-tag path of `hs update` on a server on `v0.1.0` going to `v0.2.0`: first time it is seen.

## 5. NixOS release change guide (#436)
- [ ] Follow the section "Move to a new NixOS release" of `docs/operations.md` in the test-lab, including the way back, and tick the box of #436.
  Not run; the guide is written from the scripts. Not tested on hardware yet.

## 6. Prepare the release pull request
1. Re-read `docs/RELEASE-NOTES-0.2.md`: the section "Not verified" must match what the sections above say after the runs.
2. `python3 -I scripts/lib/changelog.py validate .` and `python3 scripts/pkg.py validate`. Not run for this checklist.
3. Package repositories first (hobnix/recipes, hobnix/extensions): release them before the core (`release.sh`), as in the 0.1 checklist section 3.
4. The pull request of 0.2 into `develop` (merge commit) is a decision of the owner: `docs/RELEASE-PROCESS.md` says 0.2 is built on `develop`
   after the 0.1.0 tag; check where the release pull request into `main` comes from (`release-core.sh status`).

## 7. What the release gate checks
`scripts/dev/release-gate.sh check v0.2.0` (the workflow runs it) refuses unless: the commit is the tip of `origin/main` and a merge commit (a beta:
the tip of `origin/0.2`); `ci-ok` is green on it or on its pull request head; `docs/RELEASE-NOTES-0.2.md` exists and names 0.2 in its first three lines;
the changelog validates; the tag does not exist; the version is above `v0.1.0`; `main` contains `v0.1.0`. The notes name 0.2 in their first
line (read, not run). Run it offline with `HS_GATE_CI=skip` only on your own machine; the workflow forbids that knob.

## 8. Tag, watch, verify, merge back
Same as the 0.1 checklist sections 7 to 11, with `v0.2.0` in place of `v0.1.0`:

```bash
bash scripts/dev/release-core.sh tag v0.2.0
```

**The push starts the ISO build and creates the public release. A pushed tag cannot be taken back quietly.**

```bash
gh run watch --repo hobnix/server
```

```bash
bash scripts/dev/release-core.sh verify v0.2.0
```

Boot the ISO once (nested, `scripts/dev/nested.sh`, or the test-lab) and run `hs system info`, `hs sys release show` and open the web interface. Not run.
Then merge `main` back into `develop`. Not run.

## 9. Announce
Check the release text on the release page (the workflow uses `docs/RELEASE-NOTES-0.2.md`). Say plainly which items are UNVERIFIED and that nothing
ran on physical hardware.
