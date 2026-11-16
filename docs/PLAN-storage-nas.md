# Plan: storage and NAS (milestone 0.7)

Status: **Accepted 2026-11-16, D1 to D20 as recommended (D2 name `.hn-trash`).** Design record for epic
[#189](https://github.com/hobnix/server/issues/189) (Storage Management) and its open children #418, #419, #425, #426, #460, #463 and #527. It checks
the facts of the issues against the code of branch `0.7` (2026-11-16), names where the code differs from what the issues assume, and gives an
ordered list of steps, each sized for one pull request. Steps 4, 8, 9, 11, 12 and 15 change or delete files or disks on a server and are marked
"destructive" in the Steps table. Nothing in this plan was run; Not tested on hardware yet.

See also: [PLAN-disk-health.md](PLAN-disk-health.md) (SMART baseline), [PLAN-hardware-runbook.md](PLAN-hardware-runbook.md) (what is run on the
real server), [PLAN-app-lifecycle.md](PLAN-app-lifecycle.md) (Q4, `[app.backup]`), [PLAN-jobs.md](PLAN-jobs.md), [PLAN-events.md](PLAN-events.md),
ADR 0004 (job record), ADR 0005 (events), ADR 0006 (API in front of the CLI), ADR 0023 (nested test harness), the guides
[storage-and-disks.md](storage-and-disks.md) and [backup-and-recovery.md](backup-and-recovery.md).

## Problem

The epic asks for "Unraid-grade storage". Most of the pieces exist (pools, adoption, SnapRAID, health, replacement, recovery, alerts, off-site
copy, spin-down, a file manager), but four things stop a person who comes from Unraid or Synology:

1. The file manager cannot write (`fileManagerWrite` is off and was never tested on disks), has no trash and no folder sizes.
2. Taking over an Unraid server is a seven-step guide with a window without protection, not one guided flow, and was never run on disks made by Unraid.
3. A small backup disk forces "all of a container or nothing", so containers are left out and a lost server comes back without its apps.
4. The only copy outside the house is a restic address typed by hand with credentials in a shell file, the same password, and no retention.

Spin-down and the further alert levels are built in part and never measured.

## What exists today (read from the code on 2026-11-16, branch `0.7`)

| Part | State | Verdict |
| --- | --- | --- |
| Adoption of disks with files | No `scripts/adopt.sh` (the epic names it): adoption is `hs pool <pool> add --role adopt` in `scripts/manage-pool.sh` (lines 306 to 370, 1066 to 1162). `adopt_fs` accepts xfs, ext4, btrfs, also inside LUKS opened with **this server's** passphrase (`crypt_get_pass`); refuses ntfs/exfat/vfat. `adopt_inspect` mounts `ro,norecovery` (xfs) / `ro,noload` (ext4), a dirty log is refused. Then it **writes the label** `bulk-data-NN` (`xfs_admin -L`, `e2label`, `btrfs filesystem label`) and **renames** every top folder into `shares/<disk>-<name>` (`--merge`: the plain name), `chown` only with `--chown`. Parity is a later, separate `add --role parity` that erases the disk. Web: adopt mode in `web/src/forms/storage/AddDisks.svelte`; `sys pool plan|start bulk adopt` via pool-change.sh. tests/adopt.sh; only ext4 loop images were exercised (notes: no xfs driver in the sandbox) | Keep the technique; the Unraid flow (#460) is a guided layer on top, with a new order (D9) |
| Unraid read-only look | `hs migrate check [--parity <disk>]` (scripts/migrate-check.sh): filesystem, LUKS, readable, used size, SMART, parity size against the largest data disk; changes nothing | Reuse as the plan's first half |
| Unraid guide | storage-and-disks.md "Move existing disks into the server (for example from Unraid)": install snapraid, `migrate check`, `add --role adopt --dry-run`, adopt one disk, `share repair`, then parity (erases the old Unraid parity, "a window without protection") | Becomes the guide of the guided flow |
| Unraid app templates | `hs docker import-unraid` (scripts/import-unraid.sh, lib/unraid_import.py): Community Apps XML to a compose draft; UNVERIFIED beyond fixtures | Out of scope here (it is the 0.6 #269 side) |
| Pool import (ZFS) | `hs pool <pool> import` (scripts/pool-import.sh, #181): never `-f`, the typed word is a disk name | Not touched |
| Replace, remove, recover | `hs pool bulk replace|remove|convert|close [--drain]`, `hs disk <m> move|detach|attach|recover|recover-finish` (disk-recover.sh: photorec, disk read-only, output on another data disk); `hs storage incident [replace|pause|resume]` (storage-incident.sh, #255 closed); `hs disk replace` (disk-replace.sh, guided). recover was tested in an Incus VM on XFS; `recover-finish` was never run on a real disk (epic) | Epic "to check": a VM stage and the hardware step (steps 15, 17) |
| Spin-down (#463) | **Built, global, opt-in**: `diskSpindownMinutes` (schema, default 0) -> `hs-disk-spindown.service` -> `disk-spindown.sh apply` = `hdparm -S` on rotational bulk/parity/backup members, never SSD/NVMe/system/`fast`; `hs disk spindown status` (tsv: dev, rotational, member, state from `hdparm -C`, minutes). Maintenance window rule (notes, Storage): HDD jobs between 03:00 and 06:00, SMART reads with `-n standby`, tests/maintenance-window.sh greps for it. `monitor.sh --disks` field 13 `power` = spinning\|asleep\|- (`power_of`, `hdparm -C`) | Per pool, measurement and page state are missing |
| SMART readers | `disk-health.sh --readings` (`-n standby`, `--wake <names>`), monitor.sh (`-n standby` or the exporter), smartctl exporter (capabilities/metrics/module.nix, `maxInterval = "5m"`, comment "leaves disks in standby alone"), capacity.sh SSD wear (`smartctl -A` only on `ROTA == 0` disks, cached 1 h); the daily baseline wakes a disk unread for 6 days; self-tests and `hs disk <d> health` wake on purpose. `disk-erc.sh` (`smartctl -l scterc`) at boot | Mostly safe; measure, do not trust the comments (step 5) |
| File manager backend (#425, #426) | `scripts/fm.sh` (889 lines) + lib/fm.sh: `sys fm locations|pair|ls|plan|start|progress`; the same-files rule (a pool disk and the pool of its array are never both sides) is enforced in `pair` and `plan`; delete needs `--confirm "delete N files"`; plan says "Delete is permanent: there is no trash"; folder bytes are 0 ("sizes of folders are not measured"). `write_on` reads the runtime setting `fileManagerWrite` (schema `store = "settings"`, default `false`). tests/fm.sh with folders standing in (HS_FM_TEST) | Write path exists; trash, du, pause, `hs fm` missing |
| File manager VM check | scripts/dev/nested_stages.py stage 5 `pool()`: two virtual disks become SnapRAID `bulk`, `hs config set fileManagerWrite true`, **one copy** disk to disk. No move, delete, rename, mkdir, no guard refusal, no ZFS | #425 extends this stage |
| File manager page | web/src/pages/Files.svelte (two panes, Info with path, disks, flags, lock; glob filter); no owner/mode, path not editable | #426 |
| Capacity and mitigation (#419) | lib/capacity.sh (called by health-check.sh): `forecast:<volume>` from state.db `usage` readings (maths in scripts/forecast.py), `ssd:<dev>:wear|wear-high`, `space:cache-backlog`. `autoMitigate` (settings, default false) = level 1 (health-check.sh lines 384 to 411): SMART-failing/BAD disk, degraded ZFS or a bulk problem writes `/run/hs-bulk.paused`; `bulk_lock_job` and the cache mover skip; lifts itself when the cause is gone; `hs health resume`. "Nearly full" is **not** a trigger in the code, although the schema text says "a pool is nearly full" | Level 1 fix + levels 2 and 3 (D19, D20) |
| App freeze | `hs storage incident pause [<instance>]` freezes the apps that write to an affected share; `resume` | The building block of level 2 |
| Container backup (#527) | backup.sh `cmd_now`: containers listed in `/var/lib/hs/backup-instances` are read from `$INCUS_ROOT/<name>/rootfs` (only while running); fixed excludes `ct_excludes` (proc sys dev run tmp var/tmp var/cache apt lists journal docker overlay2/image lost+found); dump hook first (`/var/lib/hs/backup-dump/<ct>`, lib/backup-dump.sh). VMs: `incus export` to one file. No per-container include or exclude | #527 adds rules (D12) |
| App contract | `[app.backup] mode = instance|paths|none`, `paths`, `dump` are validated (scripts/lib/pkg_app.py lines 204 to 212, docs/Package-API.md), written by `pkg_new.py`; **nothing in backup.sh reads them** | The default source of #527 rules |
| Container drill | `hs backup drill ct [<ct>]`: newest snapshot into a throwaway instance without network, boots it, deletes it (lib/ct-image.py) | A partial container cannot boot; needs its own drill (D13) |
| Off-site copy (#418) | `hs backup offsite set <repo>|now|off`, `sys backup plan|start offsite-set|offsite-now|offsite-off`: any restic address (folder, `sftp:`, `b2:`, and by restic also `s3:`, `rest:`), **same password** as the backup disk (`init --from-repo --copy-chunker-params`), credentials in `/var/lib/hs/backup-offsite.env` written by hand, **sourced as shell and exported** into restic's environment (`R_off`, backup.sh line 546; only `secret_state` is used from secret.sh); copied with `restic copy` after every nightly run; failure warns, health complains after 3 days; `--state` masks a password in the URL | Make it a guided target with its own secret handling (D14 to D17) |
| Expiry | `hs expiry add|remove`, `sys expiry list|plan|start`, health warns 30 and 7 days before | The swap reminder of the offline disk (D18) |
| Machine-readable rows | `sys pool *`, `sys disk *`, `sys fm *`, `sys backup state|shares|overview|snapshots|plan|start`, `sys monitor disks` (13 fields) | Never change their shape; new facts go in new rows |

Facts that differ from what the issues assume:

- **#460 "nothing is written to a data disk before parity is built"**: today's adoption writes the label and renames folders on the data disk
  first, and the parity disk (usually the old Unraid parity) is erased afterwards. bulk-mount.sh finds members **by label**, so "write nothing
  first" needs a second way to know a member (by filesystem UUID) until parity is synced (D9). Also "the shares become shares": that is
  `--merge`, not the default per-disk naming (D10).
- **#460 encrypted arrays "are separate cases"**: adoption already opens LUKS, but only with this server's one passphrase; an Unraid array with
  another passphrase or a keyfile does not open (D11).
- **#463 "a spin-down time per pool or disk"**: one global time exists; the Disks page already receives a `power` field, but no "asleep" text was
  found in web/src. Nothing was measured.
- **#425 "the checks were not run"**: a nested-VM stage exists for copy only (nested_stages.py `pool()`); move, delete, rename and the guard are new.
- **#426 "the open design questions at the end of the plan"**: `docs/PLAN-file-manager.md` is referenced by fm.sh, lib/fm.sh, schema.toml,
  web-serve.py, Files.svelte and tests, but **the file is not in the tree** (no git history either). The same holds for docs/PLAN-mitigation.md and
  docs/PLAN-hidden-pool-disks.md named in the notes. Its questions are answered here (D1 to D4) and the references are pointed at this page (step 1).
- **#419 "notify and pause merged"**: true for failing disks and degraded pools; a full pool does not pause anything, contrary to the schema text.
- **#418 "a copy to another Hobnix server is built"**: what is built is a generic restic address (`sftp:` to any host). No Hobnix-to-Hobnix pairing
  was found (remote.sh shares are read-only Samba mounts, node-remote.sh answers `status` only). The off-site repository has **no forget/prune**:
  only `restic copy` runs, so it grows without end.
- **CLAUDE.md "secrets never through argv or the environment"**: the off-site credentials are exported into restic's environment today (D15).

Not verified: whether the smartctl exporter on NixOS really passes a standby check (the module comment says so, its flags were not read);
whether `hdparm -C`, `zpool status` and `df` keep an idle disk asleep on the real controllers (notes say so); whether `state.sh collect` (every
minute) and scripts/live-collect.py read SMART at all; where SnapRAID's content files are kept (bulk-mount.sh was not read; this decides D9);
the on-disk layout Unraid writes (partition start, MBR or GPT, XFS features, LUKS version, owner 99:100) is from memory, not from a disk;
whether restic reads S3 keys from a credentials file (`AWS_SHARED_CREDENTIALS_FILE`) and REST credentials from `--repository-file` for every
backend (D15); the Backup web page's off-site dialog and the Disks page in a browser; ADRs 0004, 0005, 0006, 0008 and 0027 and PLAN-disk-health,
PLAN-hardware-runbook were not reread for this page; no test was run (Windows).

## Design

### Q1 File manager: write on, trash, sizes, pause, commands (#425, #426)

- **Write checks in a VM** (step 2): nested stage 5 grows from one copy to the full list, on SnapRAID **and** on a ZFS `bulk`: copy and move disk
  to disk and share to share, rename, mkdir, delete (with `--confirm`), an overwrite choice, a cancelled job (`hs sys jobs stop`, nothing unverified
  removed), and the guard: `sys fm pair disk:data-01 pool:bulk` must say `refused`, and a `start` with that pair must refuse. Each step compares
  checksums before and after. `fileManagerWrite` default after that: D1.
- **Trash** (D2): delete becomes "move to trash" on the same filesystem (a rename, never a copy): `<filesystem root>/.hn-trash/<YYYY-MM-DD>/<path>`
  plus a small `.hn-trash/<date>/.origin` list. Hidden from fm listings, Samba (`veto files`) and the backup (`--exclude`); emptied after 14 days by
  the 03:35 job (inside the maintenance window). "Delete for good" stays, with the typed confirm. The folder name lives in ONE constant in `scripts/lib/fm.sh`, so a later rename of `hs` to `hn` is one line; trash is emptied after 14 days, so the code only has to read both names for 14 days. `sys fm plan restore` puts a trashed item back.
- **Sizes**: `sys fm du <loc> --path P` as a background job (it walks folders, so it may wake disks: the plan says so), result cached per folder
  with its mtime; the Info panel shows owner, group and mode (read from `stat`, no change in this milestone).
- **Pause** (D3): no SIGSTOP. "Pause" = stop the job and keep its list; "Continue" = a new job with `--conflict skip --verify size` over the same
  selection. The bulk lock is never held by a paused job.
- **`hs fm`** (D4): user commands `hs fm locations|ls|du` (read) and `hs fm copy|move|delete` (guided: the plan first, the typed confirm, a job),
  as thin wrappers over `sys fm`. Registry rows, German help, a smoke probe for each read.
- **Editable path**: the path above each pane is an input; a typed path is checked by `sys fm ls` (refusal text shown), never resolved in the browser.

### Q2 Spin-down that is measured (#463)

- **What may wake a disk** (D6): only the maintenance-window jobs, a person's action, and the baseline's "unread for 6 days". Step 5 adds
  `hs disk spindown log` (root): samples `/sys/block/<d>/stat` (kernel counters, no disk access) and `hdparm -C` every minute for N hours and writes
  which disk woke when, and the systemd units that ran in that minute. tests/maintenance-window.sh is extended to every timer and collector that
  is not in the table of the notes (state collect, live collect, deck, capacity).
- **Per pool** (D5): `diskSpindownMinutes` stays the default; a new one-line inline table `diskSpindownPools = { backup = 10, bulk = 30 }` overrides
  per pool name (0 = never). Schema item, `schema-gen.py write`, `hs config check` refuses an unknown pool name. No per-disk value.
- **Page**: the Disks page shows asleep / spinning from field 13 of `sys monitor disks` (exists); a new read `sys disk power` (dev, state, since,
  wakes today) feeds the Overview card. Power use (D7): measured numbers only, from what reports them (the UPS through the existing UPS code, CPU
  package through RAPL `/sys/class/powercap`), each with its source; no estimate per disk.
- **ZFS** (D6): allowed, the plan line says how it wakes (a raidz wakes all its disks, a mirror one after the other) and that hourly
  `shareSnapshots` keeps a pool awake; `hs config check` warns on that pair.

### Q3 Take over an Unraid server (#460)

- **Layouts** (D8). Taken over: array data disks with one xfs or btrfs file system (also xfs/btrfs inside LUKS that the passphrase opens, D11),
  one or two parity disks (no file system; erased or replaced, never read). Refused with a reason: ZFS-formatted array disks (Unraid 6.12),
  multi-device btrfs, a cache pool as data (it is copied, see guide), a dirty log, a keyfile-only LUKS, a data disk larger than the new parity.
- **One guided flow** `hs migrate unraid` (+ `sys migrate plan|start unraid`): reads `migrate check`, asks which disk is the old parity (typed by
  its by-id name), shows one plan (disks, shares that will appear, what is erased, the unprotected window, the order), then a background job.
- **Order** (D9). With a spare disk at least as large as the largest data disk: (1) data disks are mounted **read-only by UUID** (a new record
  `/var/lib/hs/adopting/<uuid>`, read by bulk-mount.sh, no label written), (2) SnapRAID parity is built on the spare (content files on `fast` or the
  system disk, never on a data disk), (3) only after a finished sync are labels written and folders moved, (4) the old Unraid parity becomes free
  (offered as second parity). Without a spare: today's order, the window stated in the plan, and the typed name is the old parity disk.
- **Shares** (D10): Unraid's user shares are the top folders across disks, so the Unraid flow uses `--merge`; a folder name that is reserved
  (`shares sensitive global homes printers`) is renamed with a suffix and listed. Ownership: `nobody:users` (99:100) stays unless `--chown`.
- **Fixtures** (step 7): a test helper builds loop disks the way Unraid makes them (partition 1, xfs or btrfs, LUKS variant, a parity disk without
  file system, files owned 99:100, the same top folder on two disks); the nested harness gets an Unraid stage. A real Unraid trial in a VM is the
  hardware case.

### Q4 Back up chosen parts of a container (#527)

- **Where and how** (D12): one file per instance, `/var/lib/hs/backup-rules/<ct>`, lines `include <absolute path in the instance>` and
  `exclude <restic glob>` (restic's pattern rules; no `!` negation, no gitignore re-include). No file = the whole instance (today). Seeded by the
  recipe run from `[app.backup] mode = "paths"` (manifest) **only when the file does not exist**; a person's edit always wins. Part of the host
  snapshot (it is under /var/lib/hs).
- backup.sh: an instance with rules is backed up as `restic backup --tag ct:<name> --tag partial` of the included paths below its rootfs, with
  `ct_excludes` and the rule excludes; the dump hook still runs first.
- **Show and change**: `hs backup ct <ct> paths` (in/out with sizes from the SSD rootfs), `hs backup ct <ct> include|exclude|reset <path>`;
  `sys backup rules <ct>` (new read) and `sys backup plan|start rules --name <ct> --set ...` (new actions). `sys backup overview` keeps its shape;
  the "partial" fact goes into the new read.
- **Restore and drill** (D13): a partial container cannot boot from its snapshot. Its restore is "run the recipe again from its package, then put
  the paths back while the app is stopped"; its drill restores the paths into a temp folder and checks that each included path and each dump file
  came back non-empty (no boot). The backup guide says what a partial restore gives back.

### Q5 A copy outside the house (#418)

- **Targets** (D14): the dialog offers S3-compatible, restic REST server, SFTP and a folder (the rotating disk, Q6) by kind, asks the fields of
  that kind, and writes the restic address itself. A typed restic address stays possible for the rest (B2 and others).
- **Secrets** (D15): the address goes into `/var/lib/hs/backup-offsite.repo` and restic gets `--repository-file`; S3 keys go into a credentials
  file restic reads by path; REST and SFTP passwords inside the repository file. All three are created through `secret_prepare` (vault when there
  is one), mode 0600, entered with `ask_secret` (terminal) or stdin (web), never on argv. The old `backup-offsite.env` is parsed strictly as
  `KEY=VALUE` (no sourcing) until it is migrated once.
- **Own password** (D16): a new off-site repository gets its own password (`restic copy --from-password-file` takes both), stored like the local one
  and shown once with "write it down"; the existing one keeps the shared password.
- **Retention** (D17): today none. S3/SFTP/folder: `forget` with the same 7/4/6 rule and a Sunday prune from this server. REST: the target runs
  `rest-server --append-only` (so this server cannot delete), prune runs on the target. A second Hobnix server becomes such a target through a
  small recipe or extension (`backup-target`), out of this milestone's core work unless D17 says otherwise.
- **Restore from it**: `hs backup restore|find|drill --repo offsite`; Case C of the guide uses it.

### Q6 Rotating offline disk (#418, D18)

A second disk labelled `backup-offsite` (never offered as free, like `backup`) is a folder repository of Q5. When it is plugged in, the disk event
(`disk-event.sh`, which today never touches a disk) only sends "plugged in: copy now?"; `hs backup offsite now` (or the web button) copies and then
renews `hs expiry` entry `offline-backup-disk` to today + N days (default 30). The health check warns before the date, as for every expiry entry.

### Q7 Further mitigation levels (#419)

- **Level 1 fix**: a pool that is full in less than the urgent forecast or above 95 % joins the triggers that pause sync, scrub and mover (what the
  schema text already promises).
- **Level 2, "stop writes"** (D19): the apps that write to the affected share are frozen with the existing `storage incident pause` code, when the
  pool is above 98 % or full in less than one day; Samba stays as it is; one push message names the apps and `hs storage incident resume`.
- **Level 3, "start a copy when a disk is about to drop"** (D20): when a disk turns `failing` and the newest backup is older than 24 hours, run
  `hs backup now` (it only reads the pool and writes the backup disk). A disk-to-disk copy is never automatic: the message names `hs disk <d> move`.
- Each level is its own bool setting next to `autoMitigate` (`autoMitigateFreeze`, `autoMitigateBackup`, default false); `autoMitigate` keeps its
  meaning and type.

## Steps

Sizes: S up to a day, M two to three days, L a week. Every step adds its tests, `bash -n` for touched scripts, `scripts/dev/t quick <names>`,
German help text, a changelog entry when users see it, for every new `sys` row `python3 scripts/openapi-gen.py write` and `python3
scripts/openapi-ts-gen.py write` in the same commit and a smoke probe for each read, `python3 scripts/schema-gen.py write` after a schema change
(never edit the generated files). Output only through scripts/lib/ui.sh. Destructive steps: plan first, the typed NAME of the disk or instance
that changes, a background job for long work.

| # | Size | Step | Files | Needs | Done when |
| --- | --- | --- | --- | --- | --- |
| 1 | S | Point the dangling `PLAN-file-manager.md` / `PLAN-mitigation.md` references at this page; fix the `autoMitigate` schema text or the code (Q7 level 1) | scripts/fm.sh, lib/fm.sh, config/schema.toml (+ generated), web-serve.py, Files.svelte, tests/fm.sh, tests/docs.sh | none | `grep PLAN-file-manager` finds nothing; tests/schema.sh green |
| 2 | M | **#425** nested stage 5: move, delete, rename, mkdir, overwrite, cancel, guard refusal, on SnapRAID and ZFS, checksums | scripts/dev/nested_stages.py, docs/dev-environment.md | D1 | `t vm` stage passes once (seen, not claimed) |
| 3 | S | `fileManagerWrite` default after step 2 and the hardware run (D1) | config/schema.toml (+ generated), docs/changelog | 2, 17 | default as decided; new installs only |
| 4 | M | **#426 a** trash (rename into `.hn-trash`, restore, 14-day empty, Samba veto, backup exclude) — destructive | scripts/fm.sh, lib/fm.sh, scripts/backup.sh (exclude), Samba config, a timer in capabilities/storage/module.nix, tests/fm.sh | D2 | delete moves, restore puts back, empty after 14 days in a fake clock |
| 5 | M | **#463 a** measure: `hs disk spindown log`, maintenance-window test over every timer and collector, exporter flag checked | scripts/disk-spindown.sh, tests/maintenance-window.sh, tests/disk-spindown.sh, registry.tsv | D6 | the test lists every unit; the log names a waking unit in a fake sysfs |
| 6 | M | **#463 b** `diskSpindownPools`, `sys disk power`, asleep on the Disks page, power numbers with source | config/schema.toml (+ generated), scripts/disk-spindown.sh, monitor.sh (shape unchanged), web/src/pages/Disks.svelte, registry.tsv, sys.toml, smoke.sh | 5, D5, D7 | per-pool values applied in a test; page shows asleep from a fixture |
| 7 | M | **#460 a** Unraid fixtures (loop disks made the Unraid way) and an Unraid nested stage (read-only: `migrate check` and the plan) | tests/lib-unraid.sh (new), tests/adopt.sh, scripts/dev/nested_stages.py | D8 | xfs, btrfs, LUKS and parity fixtures; refusals for ZFS and keyfile |
| 8 | L | **#460 b** read-only members by UUID until parity is synced (bulk-mount.sh), content files off the data disks — destructive | scripts/bulk-mount.sh, scripts/manage-pool.sh, lib/bulkpath.sh, tests/adopt.sh, tests/bulk-switch.sh (root) | 7, D9 | a fixture array syncs parity with no write to a data disk (checksums of the block devices equal) |
| 9 | M | **#460 c** `hs migrate unraid` + `sys migrate plan|start unraid`: one plan, typed old-parity name, job; `--merge` default; web dialog — destructive | scripts/migrate-unraid.sh (new), migrate-check.sh, pool-change.sh, registry.tsv, sys.toml, web/src/forms/storage/*, tests | 8, D10, D11 | the fixture array becomes `bulk` with merged shares; both paths (spare / no spare) |
| 10 | M | **#426 b** `sys fm du`, owner/mode in Info, editable path, busy state for `ui/Button.svelte`, `hs fm` user commands, pause = stop + continue | scripts/fm.sh, registry.tsv, sys.toml, web/src/pages/Files.svelte, ui/Button.svelte, tests/fm.sh, web tests | 4, D3, D4 | du of a fixture folder; continue skips what was copied |
| 11 | M | **#527 a** rule file, seeding from `[app.backup]`, partial backup, `hs backup ct <ct> paths|include|exclude|reset`, `sys backup rules` — changes the backup | scripts/backup.sh, backup-change.sh, recipes/_lib.sh (seed), lib/pkg_app.py (read), registry.tsv, sys.toml, smoke.sh, tests/backup.sh | D12 | a fixture instance backs up only its paths; `--overview` byte-equal |
| 12 | M | **#527 b** partial restore (recipe again + paths) and partial drill (paths, dumps non-empty) — destructive | scripts/backup.sh, tests/backup-drill-ct.sh, docs/backup-and-recovery.md | 11, D13 | drill passes on a fixture; restore runs the recipe stub then the paths |
| 13 | M | **#418 a** guided target kinds, repository and credentials files via `secret_prepare`, strict parse of the old env, own password, retention, `--repo offsite` for restore/find/drill | scripts/backup.sh, backup-change.sh, lib/secret.sh (no change expected), web/src/pages/Backup.svelte, sys.toml, tests/backup.sh, tests/backup-change.sh | D14 to D17 | a local `rest-server` and a folder target in tests; no secret in `ps` or env of the parent |
| 14 | S | **#418 b** rotating disk `backup-offsite`, plug-in message, expiry renewed after each copy | scripts/backup.sh, disk-event.sh (message only), expiry.sh, manage-pool.sh (never free), tests | 13, D18 | a loop disk with the label gets the copy and a new expiry date |
| 15 | M | **#419** levels 2 and 3 behind their own settings; level 1 full-pool trigger if not done in step 1 — changes running apps | scripts/health-check.sh, lib/capacity.sh, storage-incident.sh, config/schema.toml (+ generated), tests/mitigation.sh | 1, D19, D20 | fake pool at 99 % freezes the fixture app once; failing disk with old backup starts one backup |
| 16 | S | Docs: storage-and-disks (Unraid flow, spin-down, trash), backup-and-recovery (partial, off-site, rotating disk), operations, web-interface; changelog entries | docs/ | 2 to 15 | `tests/docs.sh` green |
| 17 | S | Hardware test (table below) and the epic's checks: replace a disk on SnapRAID and ZFS, recover + `recover-finish` on a real disk, storage alerts; tick the issues' "Hardware test" boxes with what was seen | the issues | all | "Not tested on hardware yet." removed only for what was seen |

Parallel lanes after the decisions: A file manager (1, 2, then 4, 10; 3 last), B spin-down (5, 6), C Unraid (7, 8, 9), D backup (11, 12, then 13,
14), E alerts (15 after 1). Lanes are independent except for shared files: steps 1, 4 and 10 all edit `scripts/fm.sh` and run one after the other;
11, 12, 13 and 14 all edit `scripts/backup.sh` (and 11, 13 `backup-change.sh`) and must not run together, and 4 adds a backup exclude, so it goes
before 11; 8 and 9 edit `manage-pool.sh`, and 14 too (the `backup-offsite` label is never free); 1, 3, 6 and 15 change `config/schema.toml` and the
generated files, so they merge one at a time with `schema-gen.py write` run again after each rebase; 4 and 6 may both touch
`capabilities/storage/module.nix`. Every step with a new `sys` row regenerates openapi.json and sys.gen.d.ts; on a rebase conflict regenerate,
never merge them by hand.

## What only runs on hardware

| Step | What to look at on a real server |
| --- | --- |
| 2, 3, 4, 10 | copy, move, rename, delete and restore from trash in the web page on a real SnapRAID and a ZFS pool; `pair` refuses a pool disk with its pool; checksums equal; a paused copy continues |
| 5, 6 | `diskSpindownMinutes = 30` for 24 h: `hs disk spindown log` shows wake-ups only between 03:00 and 06:00 and on use; the Disks page says asleep; UPS watts asleep against awake; one HBA and one USB case |
| 7 to 9 | disks made by a real Unraid (trial in a VM with passed-through disks, or a real box): 3 xfs data (one xfs-encrypted), 1 btrfs, 1 parity; files checksummed before; `hs migrate unraid` with a spare disk (no block written to a data disk until the sync ended: compare a hash of each device) and without; shares merged; read from Windows |
| 11, 12 | a container with only its config and database in the backup: size on the backup disk, the partial drill, a restore after removing the container, a rebuild (Case A) with it |
| 13 | an S3 bucket and a `rest-server --append-only` on a second machine: copy, a file restored with `--repo offsite`, Case C host files read from off-site; `ps` shows no key |
| 14 | plug the rotating disk, copy, the expiry date moves; leave it out past the date, the warning comes |
| 15 | fill a test pool: forecast, pause, then freeze of the writing app; a disk marked failing starts one backup |
| 17 | `hs pool bulk replace` of a data disk (SnapRAID) and a mirror disk (ZFS); `hs disk <d> recover` then `recover-finish` on a real data disk; pull a disk: the alert and `hs storage incident` |

Everything else is checked by tests with fakes and loop devices (`t root`) and in the nested VM (`t vm`).

## Risks

- **The Unraid takeover writes to the only copy of someone's data.** Mitigation: the spare-disk order (D9) writes nothing until parity is synced;
  without a spare the plan names the window and the typed word is the old parity disk; the guide says "copy what matters elsewhere first".
- **Read-only members by UUID are a new state in bulk-mount.sh**, the most sensitive script (restartIfChanged false, branch swaps). Mitigation:
  its own step (8), root tests on loop devices, a VM run before it ships; the record is removed after labelling.
- **Trash keeps space used** on a full pool. Mitigation: shown in the plan and in `sys fm locations` free bytes; "delete for good" stays.
- **Spin-down and controllers**: some HBAs or USB bridges drop a disk that sleeps or ignore `hdparm -S`; a ZFS pool may log I/O delays on wake.
  Mitigation: opt-in, per pool, the measured log, a note in the guide per tested controller only.
- **A partial backup restores less than a person thinks.** Mitigation: the plan shows in/out with sizes, the snapshot tag `partial`, the drill and
  the report say "partial", the restore needs the package.
- **Off-site credentials**: a backend whose keys restic takes only from the environment breaks the secrets rule (D15); then the exception is
  limited to restic's own child process and written down.
- **Automatic freeze stops apps unattended.** Mitigation: its own switch, off by default, one message, `resume`, never Samba or data.
- **Machine-readable contracts**: `sys monitor disks`, `sys backup overview|state`, `sys fm *` keep their shape; new facts get new rows.

## Decisions for the owner

The "Recommended" answer is first in each row. "Hard to change later" says what a wrong choice costs after release.

| Id | Question | Options | Recommended | Hard to change later |
| --- | --- | --- | --- | --- |
| D1 | `fileManagerWrite` default (#425) | stays false until the hardware run, then true for new installs only (an existing setting file is kept); true for all; false for good | False until step 17 saw it, then true for new installs | Low |
| D2 | Trash location (#426) | `.hn-trash/<date>/` at the root of each file system (rename), 14 days; one central trash (copies across disks); no trash (snapshots and backup) | Per file system, rename only, 14 days, hidden from Samba and backup | Medium: files land there on every server |
| D3 | Pause of a copy | stop + continue as a new job with skip; SIGSTOP/SIGCONT | Stop + continue; a stopped process would hold the bulk lock | Low |
| D4 | `hs fm` commands | read commands + guided copy/move/delete through the plan and typed confirm; read only; none | Read + guided changes | Low |
| D5 | Spin-down setting shape (#463) | global `diskSpindownMinutes` + inline table `diskSpindownPools`; per disk by serial; global only | Global + per pool (a serial changes on replace) | Medium: a machine.toml key |
| D6 | What may wake a disk, and ZFS | only window jobs, a person, the 6-day baseline; ZFS allowed with the wake pattern in the plan, warn with `shareSnapshots`; SnapRAID only | As stated; ZFS allowed with warnings | Low |
| D7 | Power use | measured only (UPS, RAPL), with source; plus estimates per disk | Measured only | Low |
| D8 | Unraid layouts taken over (#460) | xfs/btrfs data disks, LUKS that the passphrase opens, 1 or 2 parity; refuse ZFS array disks, multi-device btrfs, keyfile LUKS, cache pools as data; also import ZFS array disks | The first list; the refusals named in the plan | Medium: it is a promise in the guide |
| D9 | Order of the takeover | with a spare disk: read-only by UUID, parity first, labels after the sync; without: today's order with the window stated; always today's order | Both paths, the plan picks; the typed word is the old parity disk | High: bulk-mount member identity |
| D10 | Unraid shares | merged by folder name (Unraid's user shares); per disk `<disk>-<folder>` | Merged in the Unraid flow; generic adopt keeps per disk | Medium: share names are paths in apps |
| D11 | Unraid encryption | the Unraid passphrase becomes this server's when no encrypted disk exists yet, else add a key slot with this server's passphrase after a header backup (a header write, shown in the plan); refuse all encrypted arrays; keyfile refused | As first; keyfile refused | High: one passphrase for every disk |
| D12 | Partial backup rules (#527) | `/var/lib/hs/backup-rules/<ct>` with `include`/`exclude` lines, restic globs, seeded once from `[app.backup]`; in machine.toml; gitignore syntax with `!` | Per-instance file, restic globs, seeded once, edits win | High: files on every server and in the host snapshot |
| D13 | Restore of a partial container | recipe again from its package + paths put back, drill = paths and dumps, no boot; paths into the existing instance only | Recipe + paths; drill without boot | Medium |
| D14 | Off-site targets (#418) | S3, REST, SFTP, folder as kinds + a typed address; only a typed address (today); cloud providers by name | Four kinds + typed address | Low |
| D15 | Off-site secrets | `--repository-file` + credentials file by path, via `secret_prepare`, never sourced; keep the env file (breaks the secrets rule); store in machine.toml (never) | Files by path; an env exception only for restic's child if a backend needs it | Medium: migration of the old env file |
| D16 | Off-site password | own password for a new repository, shown once; the same as the backup disk (today) | Own password; existing ones keep theirs | High: a repository key |
| D17 | Off-site retention and deletion | forget/prune from here for S3/SFTP/folder, append-only REST with prune on the target, a `backup-target` package for a second Hobnix server later; no retention (today); same forget everywhere | As first; the `backup-target` package in a later milestone | Medium |
| D18 | Rotating offline disk | label `backup-offsite`, message on plug-in, copy by a person, expiry renewed (30 days); automatic copy on plug-in; decide against | Message + copy by a person + expiry | Low |
| D19 | Level 2 "stop writes" (#419) | freeze the writing apps of the share (existing incident pause) at > 98 % or < 1 day, own switch; Samba read-only; nothing automatic | Freeze apps, own switch `autoMitigateFreeze`, off | Low |
| D20 | Level 3 "copy when a disk is about to drop" | `hs backup now` when a disk turns failing and the backup is older than 24 h, own switch `autoMitigateBackup`; also an automatic disk-to-disk copy; nothing | Backup only, never a disk-to-disk copy; `autoMitigate` keeps its type | Low; changing the type of `autoMitigate` would be high |

## Check that it worked

- `hs sys fm start delete` moves into `.hn-trash` and `sys fm plan restore` brings it back; a pool disk paired with its pool is refused in `pair`
  and in `start`; the nested stage passes on SnapRAID and ZFS.
- `hs disk spindown log` over a night lists wake-ups only in the window; the Disks page says asleep; `sys monitor disks` is unchanged.
- `hs migrate unraid --dry-run` on the fixture array lists disks, merged shares, the parity that is erased and the order; with a spare disk the
  device hashes of the data disks are equal before and after the parity sync.
- A container with rules is in the backup with tag `partial`, its drill passes, `sys backup overview` is byte-equal to before.
- `hs backup offsite now` copies to a REST and an S3 target, `hs backup restore latest <path> --repo offsite` gives a file back, and no key shows in
  `ps` or `/proc/<pid>/environ` of backup.sh.
- A fake pool at 99 % with `autoMitigateFreeze = true` freezes the fixture app and sends one message; `hs storage incident resume` lets it run.
