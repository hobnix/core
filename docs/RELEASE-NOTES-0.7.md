# Hobnix 0.7.0 release notes (draft)

Draft for the release "0.7 Storage and NAS", built from the changelog entries of `docs/changelog/` that are on `0.7` but not in `v0.6.0` (13) and the
issues of the milestone. Written 2026-11-18. The same text is the body of the release pull request and of the GitHub release.

**Read this first.** 0.7.0 is about disks, pools and backups: taking over old disks and an Unraid server, a trash in the file manager, off-site backup
targets, backups of only chosen parts of an instance, automatic reactions to a full pool, and sleep times for disks. In a virtual machine on the real test-lab server the stages install, smoke check, rollback, backup and restore and pool passed on the tip of `0.7` (2026-11-19, commit f751607b); the upgrade from v0.6.0 passed on the same commit. Stage 6 (browser) never ran
there (no playwright on the server). Almost everything here touches data or disks and was written and tested with fakes, fixtures, loop devices and
virtual disks, not on real hardware: items marked **Not tested on hardware yet** have not been tried on real disks. The owner looked at the web interface of
`v0.7.0-beta.1` on 2026-11-19; what was found is under "Known problems" below. Do not trust this release with the only copy of your data, and keep a copy of anything on a disk you let it adopt.

## What 0.7.0 is
Storage you can take over and look after: old disks and Unraid servers come in with clear reasons when they cannot, the file manager gets a trash, the
backup reaches off-site targets and rotating disks, and the server reacts before a pool fills or a disk drops.

## Pools and old disks
- **Old disks that cannot be adopted say why**: adopting and `hs migrate check` refuse ZFS-formatted disks, a btrfs over several disks, a file system with
  an unreplayed log and a LUKS disk that only a key file opens, each with its reason, before anything is written.
- **Adopting with a spare disk is safe**: `hs pool bulk add --role adopt --disks <data-disks> --spare <spare-disk>` mounts the disks read-only, builds the
  parity on the spare disk and writes labels and moves folders only after the sync has finished. Without `--spare` the plan says the data is not protected.
- **Take over an Unraid server** (`hs migrate unraid`, web: Pools, Take over Unraid): one plan for the data disks, the old parity disk and an optional
  spare, then a background job. Folders of the same name become one share, reserved names get the suffix -adopted, the old parity disks become parity only
  after the first sync, and encrypted disks get an extra key slot after a header backup.
- **Automatic reaction** (both off by default): `autoMitigateFreeze` freezes the apps that write to a pool above 98 % full (`hs storage incident resume`
  lets them run again); `autoMitigateBackup` starts one backup when a disk turns failing and the newest backup is older than 24 hours. `autoMitigate` also
  pauses parity sync, scrub and cache mover on a full pool, as the setting always said. Nothing is deleted or copied from disk to disk.

## File manager
- **Folder sizes, owner and mode, typed paths, pause**: a folder can be measured (a background job), owner, group and mode are shown, the path above each pane is
  an input the server checks, and a copy or move can be paused and continued. `hs fm locations|ls|du|copy|move|delete` shows the plan and asks for the typed
  confirmation first.
- **Delete moves into a trash**: a hidden trash on the same file system (instant); items can be put back for 14 days, then it is emptied at 03:35. "Delete
  for good" still needs the typed confirmation.

## Backup
- **Off-site targets**: S3, a REST server, SFTP or a folder (Backup, Set up off-site copy, or `hs backup offsite set --kind ...`); keys and passwords go into
  root-only files; a new repository gets its own password, shown once; old backups are thinned out (7 daily, 4 weekly, 6 monthly) and pruned on Sundays; REST is
  append-only; `hs backup list|find|restore|drill` take `--repo offsite`.
- **A rotating backup disk**: a disk labelled backup-offsite is a folder target; plug-in message, copy by hand (`hs backup offsite now`), a swap reminder
  after 30 days (`offsiteDiskDays`). Nothing is copied by itself.
- **Back up only chosen parts of an instance**: `hs backup ct <name> paths|include|exclude|reset`; a recipe with `[app.backup] mode = "paths"` starts with
  those paths. `hs backup restore ct <name>` runs the recipe again and puts the paths back (plan first, you type the instance name); `hs backup drill ct`
  checks it without booting it and reports "partial".

## Disks
- **What wakes a sleeping disk**: `sudo hs disk spindown log 24` watches the spinning disks for 24 hours without waking them.
- **A sleep time per pool**: `diskSpindownPools = { backup = 10, bulk = 30 }` in `machine.toml`; `hs config check` refuses an unknown pool; the Disks page
  shows asleep or spinning; `hs disk spindown power` lists sleep state, wakes today and the measured power with the source of each number.

## Test-lab
Everything the 0.6 notes say; stage 5 names the virtual disks by their by-id names, reads the answer of the pool job as one line, knows the file manager trash (plain delete moves, `--permanent` asks for the confirmation) and waits for a stopped file manager job to report. The stage found one real bug, fixed in this release: `hs sys fm progress` showed a job stopped before its first state as running for good (it says cancelled now).

## Not in this release
- Apps that update themselves (hidden and off), importing a Docker Compose file as an app (see the 0.6 notes).
- Live state on by default; booting the ISO on real hardware (#175).

## Known problems
Found in the web check of `v0.7.0-beta.1`, not fixed in 0.7.0, planned for 0.8:
- The file manager can be slow: reading a folder took up to a minute (#907).
- The web has no view of the trash and no Restore button, and the Delete button tooltip still says "Delete for good" (#908). Restore works on the command line only through the backend, not through an `hs fm` command yet.
- The second pane cannot be closed, so with two panes some actions are blocked when the dropdowns refuse the pair (#909).
- Folder sizes show only in the Info panel (F3); Cancel is only in the banner of a running job; `hs fm` alone prints no help (#910).

## Not verified
- Web check of `v0.7.0-beta.1` by the owner: the file manager (delete into the trash, copy, move), the Unraid take-over page, the backup pages and the Disks page looked right. Not tried: the off-site backup targets with a real server, the rotating backup disk, partial instance backups, and the automatic reactions on a full pool.
- Every item marked "Not tested on hardware yet": adopting real disks, the Unraid take-over, off-site targets on real S3, REST and SFTP servers, the trash on a
  real pool, spindown on real disks, the automatic reactions on a real full pool.
- The headless browser stage (6) never ran.
