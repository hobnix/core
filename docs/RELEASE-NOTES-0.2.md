# Hobnix 0.2.0 release notes (draft)

Draft for the release "0.2 Safe Updates", built from the 36 commits (without merges) that are on `0.2` but not in `v0.1.0`, the 25 changelog entries of
`docs/changelog/` from 2026-11-10 to 2026-11-16, the issues of the milestone and the 23 decision records in `docs/adr/` (accepted 2026-11-10). Written
2026-11-16. Re-read before the tag. The same text is the body of the release pull request and of the GitHub release.

**Read this first.** Hobnix 0.2.0 is about updates you can trust, and most of that trust is not earned yet. In a virtual machine on the real
server the test-lab stages install, smoke check and rollback (a bad update goes back by itself) passed. The stages backup and restore, pool,
browser and the upgrade stage had **not** passed when this was written. The stable channel has not been followed on a real server, the guide for a
NixOS release change has not been tested in the test-lab, and no 0.2 beta has been cut. Nothing ran on physical hardware. Items marked
**UNVERIFIED** were written and tested only with fakes, fixtures and unit tests. Do not trust this release with the only copy of your data.

## What 0.2.0 is
The follow-up of 0.1.0 (released 2026-11-15): the same NixOS home server (Incus containers and VMs on ZFS or SnapRAID, Samba shares, backups, one
command `hs`, a web interface), with the machinery that lets a server on one release reach the next one: a test-lab that installs and updates real
virtual machines, a release process, update channels with betas, a policy for the nixpkgs pin, and a hardened web service.

## What was seen, and what was not
Seen, in a virtual machine on the real server (the test-lab, `hs testlab run`):
- Stage 1 install (the ISO installs unattended), stage 2 smoke check, stage 3 rollback: a bad update goes back by itself.

Not seen (see "Not verified" below): stages 4 to 6 (backup and restore on a second VM, pool and file manager on virtual disks, headless browser)
and the upgrade stage 7. The code and tests for them exist; that is not a run on a server.

## Safe updates
- **Test-lab stages** (#432): after install and smoke check, `hs testlab run --stage rollback|backup|pool|browser` and the nightly run. Written
  with fakes and unit tests; only `rollback` has run in a VM (see above).
- **Upgrade test** (#435): `hs testlab run --stage upgrade` (stage 7) installs the last release, sets up a share and an app, runs `hs update` to the
  candidate and checks health. `state.db` carries a schema version with migration steps; a database written by a newer release is refused instead of
  changed. UNVERIFIED: the stage has not run to the end.
- **Update channels** (#231): stable, beta and edge exist since 0.1.0. New: betas are cut from the milestone branch, signed, and published as
  prereleases with an ISO; stable never sees a beta. Settings > Updates shows the channel, the ref the next update would install and a warning for
  beta and edge. `hs pkg` follows the channel. UNVERIFIED on a real server: following stable (checklist section "Stable on a real server").
- **Release process** (#233): `scripts/dev/release-core.sh` (status, sync, tag, verify, follow-check), the milestone branch `0.2` that `develop` is
  synced into, a release workflow on GitHub with a second signing key (`release-ci`) that the server and each package repository trust, and
  `docs/RELEASE-PROCESS.md` as the runbook. Proven only on GitHub where the document says so.
- **nixpkgs pin policy** (#436): one file, `config/nixpkgs-pin.toml`, for CI, the ISO and servers; a weekly pull request proposes a bump.
  `docs/operations.md` has a section "move to a new NixOS release". UNVERIFIED: that guide has not been tested in the test-lab.
- **CI** (#439): a pull request runs the tests that match its files, the full set runs on `0.2`, in the merge queue and nightly; tests are sharded;
  nixpkgs comes from a cache; shellcheck only on changed files. Open: required checks on `develop` and `main`.

## Web interface security (#433, #501 to #505)
- One request-forgery gate before every changing request; a bounded login throttle; the threat model is `docs/THREAT-MODEL-web.md`.
- Foreign Host names are refused (421, DNS rebinding); add your own names with `hs config set webAllowedHosts`. The last `X-Forwarded-For` entry is
  trusted from the proxy.
- A stranger can no longer lock the only admin out; `hs web unlock-login` clears a locked address. A session list, sign out everywhere, and a password
  change ends the local admin's sessions.
- Review of the scripts behind every change the interface may start. Fixed: a dash at the start of a registry address, the loopback check for the ISO
  library (`2130706433`, `0x7f.1`), newlines in settings, `..` in share restore and in `--sel-file`, `@setting:` values in notification channels,
  `git clone` of a package repository, the full name of a new user.
- `hs ports` treats Remote Desktop and SSH of the Claude VM as admin doors.

## Installer, recovery and backup
- `hs-install --bulk-type zfs|snapraid` chooses the layout of `/bulk` before the system is built. Not tested on hardware yet.
- A fresh install has `hs` and `python3` from the first boot, so the first `hs rebuild` and `hs backup restore` work. A login prompt on the serial
  port. `hs-restore` no longer hangs on a read-only backup disk and keeps `/etc/ssh` readable.
- Recovery case B (lost data pool) was rehearsed in a VM and the installer text and guide were corrected. `hs backup restore --to /` keeps owners
  (`--keep-owner` for other targets) and creates the missing share datasets on ZFS. `hs share repair` says so when Samba is missing.
- The container restore drill works on Incus 7 and says how old the restored snapshot is; containers switched off in the backup are a choice, not a
  warning. `hs backup init` and `hs vault init` check for their tools before they erase anything. `hs first-run` fetches the core packages.

## Decisions
23 decision records (`docs/adr/`) were accepted on 2026-11-10, among them: no `release/*` branch (the milestone branch is the release branch), roles
and API tokens, capabilities as a package kind, the first-run console token, the nested test harness. The owner decisions are in
`docs/reviews/owner-decisions-0.2.md`: no release rhythm or due dates, #203 and #201 moved to Later.

## Not verified
Not tested on hardware yet. Nothing in 0.2 ran on physical hardware.
- Test-lab stages 4 to 6 (backup and restore onto a second VM, pool and file manager on virtual disks, headless browser): not passed.
- Test-lab upgrade stage 7 (#435): not passed. The checklist of 0.2 asks for it on the commit that gets tagged.
- Stable channel followed on a real server (#231, open box): not done. A beta cut from `0.2` (`release-core.sh tag v0.2.0-beta.1`): not done; the
  beta ISO and prerelease path of PR #545 never ran on a real tag.
- The guide for a NixOS release change (#436, open box): not tested in the test-lab.
- Required checks and a merge queue on `develop` and `main` (#439, open box; needs the repository settings).
- Release from GitHub with the key `release-ci`: proven only as far as `docs/RELEASE-PROCESS.md` says.
- Web sign-in changes, the Updates page, `hs web unlock-login`: tested with unit tests, not on a server.
- Everything the 0.1.0 notes list as UNVERIFIED and that is not named above as seen: the installer ISO booted on hardware, the graphical VM console,
  Docker, Unraid and Proxmox import, gateway parts.

## Known gaps
- The test-lab needs nested virtualization on its host. It is an optional part, off by default, meant for a build server.
- Languages: the documentation is English only; terminal output has German texts for most commands.
- Open work of the milestone is listed in `docs/RELEASE-0.2-checklist.md`.
