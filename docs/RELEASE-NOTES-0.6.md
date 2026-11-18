# Hobnix 0.6.0 release notes (draft)

Draft for the release "0.6 App Lifecycle", built from the commits (without merges) that are on `0.6` but not in `v0.5.0`, the 17 changelog entries
of `docs/changelog/` since then and the issues of the milestone. Written 2026-11-18. Re-read before the tag. The same text is the body of the release
pull request and of the GitHub release.

**Read this first.** 0.6.0 changes how apps are installed, shown and removed: one Install for every package (a plan first, then one guided job), one set
of stages (available, installed, on, running), a health check per app, and a clear Remove that keeps or deletes the data. In a virtual machine on the
real test-lab server the stages install, smoke check, rollback, backup and restore and pool passed on the tip of `0.6` (2026-11-18, commit b45c6128);
and the upgrade from v0.5.0 passed (same commit). Stage 6 (browser) never ran there (no playwright on the server). Items marked **UNVERIFIED** were written and tested only with fakes,
fixtures and unit tests, not with a real app on a real server: no app was installed, updated or removed through the new dialog on hardware, and the
web interface of this version was not looked at by the owner yet. Do not trust this release with the only copy of your data.

## What 0.6.0 is
Apps have a life: you see what an install will do before it runs, a failed install says where it stopped and can start again from there, an app says
whether it is healthy, and removing an app asks what to do with its data.

## Install
- **One Install** (#465): the plan of an app is read from its signed release before anything is installed (what it creates, what it needs, which
  questions it asks); the install runs as one job with the steps read, needs, ask, run, check and done. The web interface has one dialog for apps,
  extensions and parts (plan, questions, review, steps, result with an Open button). UNVERIFIED with a real app.
- **See before installing**: `hs sys pkg show` reads what a package is and does from its newest signed release; the install uses exactly that release.
- **A failed install** (#466) names the step (read, needs, ask, run, check) and the reason; Retry starts again at that step (a recipe phase runs again
  as a whole); Remove what was created removes only what the run made, after you type the name of the app. UNVERIFIED.
- **Several instances of one app** (#471) only where the package says `instances = "many"`: a second one takes a name like `<app>-<word>`; other
  packages refuse it in the plan.

## Apps
- **One lifecycle** (#467): every package has the stages available, installed, on, running, with notes such as update, pending or stopped; the
  Marketplace and Apps pages show them and offer Install, Update and Remove (`hs sys pkg states`, `hs sys apps list`).
- **Health** (#468): an app that declares a health check (a container, a TCP port or an HTTP address) shows healthy, not healthy or stopped; the page
  follows the event stream and polls only while the stream is down.
- **Versions and update policy** (#470): the Apps page shows the version of the app next to the version of the package, and says when the release
  offers a newer one; `hs apps policy <instance> pinned|notify` (notify is the default). Automatic updates of apps (snapshot, health check, rollback)
  are in the code but hidden and off.
- **Remove**: the plan lists what goes (the instance, its service description, its fixed address in UniFi) and what stays; the data is kept by
  default, deleting it needs the name of the app twice.
- **Start at boot** (#614): `hs ct <name> autostart on|off` and a switch on the Instances page; off removes the flag and Incus brings the instance
  back in the state it had.
- **Fix** (#612): deleting an instance releases its fixed IP in newer UniFi versions (longer client ids); if UniFi cannot be reached the command says
  so in one line.

## Packages
- **App contract and store fields** (#469): `package.toml` carries description, icon, category, app version and, for an app, the contract tables
  (API level 9); `hs pkg new` and the package builder write them. Core recipes must carry the contract from `requires_core >= 9`.

## Test-lab
Everything the 0.5 notes say; stage 5 creates the pool fast with `--use apps` and the SnapRAID pool with `--use data --kind snapraid` and runs the
rebuild after it; the unattended installer asks no admin name question.

## Not in this release
- Apps that update themselves (hidden and off), importing a Docker Compose file as an app, the hardware box of every item above.
- Live state on by default (see the 0.3 notes); booting the ISO on real hardware (#175).

## Not verified
- A real app through the new Install, Remove and retry; health checks on a real server; the start-at-boot flag across a reboot; the UniFi IP release.
- The headless browser stage (6) never ran.
- The unlock page of this version.
