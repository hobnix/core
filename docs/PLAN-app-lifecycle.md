# Plan: one lifecycle for apps and packages (milestone 0.6)

Status: **Accepted 2026-11-16**: the owner accepted all recommended answers D1 to D17 (table "Decisions for the owner"); #269 moves to a later
milestone (the board is updated separately). Design record for epic
[#187](https://github.com/hobnix/server/issues/187) and its open children #465, #466, #467, #468, #469, #470, #471 and #269, with the three bugs #612,
#613 and #614 that fit into the steps they touch. Nothing is built by this page. It checks the facts of the issues against the code of branch `0.6`
(2026-11-16), names where the code differs from what the issues assume, and gives an ordered list of steps, each sized for one pull request. This plan
changes no storage, network or firewall behaviour by itself; steps 7, 9, 11 and 13 delete or change things on a server and are marked. Not tested on
hardware yet.

Read together with ADR 0004 (job record), ADR 0008 and 0009 (capabilities and packages, a capability is a package kind), ADR 0018 (interactive recipe
runs), docs/PLAN-packages.md, docs/PLAN-jobs.md, docs/PLAN-recipe-orchestrator.md and docs/PLAN-capabilities-repo.md. Milestones 0.11 (navigation) and
0.13 (marketplace) build on this one: the state words (Q1) and the manifest fields (Q4, Q5) are the contract they read, so they are decided once here.

## Problem

A person wants "install Immich" and later "stop it", "update it", "take it away, keep the photos". Today that is four places and three vocabularies:

1. Marketplace > Check for updates > **Install** (only copies a signed package into `/var/lib/hs/packages/current`; nothing runs).
2. Instances > Apps > the recipe's own form (a second dialog) > a job.
3. For an extension: `hs ext enable`; for a capability: `hs sys parts start enable` and a rebuild.
4. Removal: `hs pkg remove` (the copy only), `hs ct remove` (the container; storage stays), a UniFi reservation and a Zoraxy route by hand.

When step 2 fails halfway there is a container, a share or a route and no way to say "undo what this run made". Apps show "the container runs", not
"the app answers". The recipe is version 1.0.0, the app inside is whatever its pin says, and nobody can see either next to the other.

## What exists today (read from the code on 2026-11-16, branch `0.6`)

| Part | State | Verdict |
| --- | --- | --- |
| Package kinds | `scripts/pkg.py`: `KINDS = ("recipe", "extension", "capability")`; `manifest_problems` checks name, semver, title, `requires_core`, `audience`, recipe `needs`/`uses`/`runs`/`input`/`ask`, events, permissions; the recipe fields must agree with the `# kind/needs/uses/runs/input/ask` header lines of `run.sh` | Extend with optional tables (Q4, Q5); API level is **8** (`scripts/lib/api-level`) |
| `package.toml` fields | `name, version, kind, title, title_de, requires_core, audience, needs, uses, runs, input, [[ask]], [[events]], [web.*]`. No icon, category, description, picture, upstream, resource use, health, backup, remove or update declaration | The gap of #468 and #469 |
| Install (fetch) | `hs pkg install <name>` (`scripts/pkg_repo.py`): newest signed tag of the repository, read-only copy into `current/<name>`, record in `installed.toml`; web: `sys pkg plan\|start install` (`scripts/pkg-change.sh`), **inline**, never a job; red (typed name) only for an added repository | Reuse as step 1 of the flow |
| Marketplace state | `sys pkg market` columns: `name, kind, repo, available, installed, state (new\|current\|update\|waits\|orphan), core, audience, title`; the page shows "not installed / installed 1.0.0 / 1.0.0 → 1.1.0 / repository gone" and a trash button for **every** installed kind | The old shape stays (ADR 0004 rule); `state` says only "package copy", nothing about running |
| Run a recipe | `hs recipe <name> [--name ct]` runs `run.sh` (idempotent, `_lib.sh`); web: `sys recipes plan\|start <recipe> run [--set K=V]… [--interactive]` (`scripts/recipe-change.sh`); `--interactive` starts `scripts/recipe-orchestrate.sh` as an orchestration job with sub-jobs per `# phases:` word, questions through `ask_q` (ADR 0018). **Recipes are not converted to phases or `ask_q` yet** (PLAN-recipe-orchestrator "Not built"): a run is one sub-job and asks only through `setting` and the fixed-address loop | Extend: this is the engine of "one Install" |
| Recipe state | `sys recipes list` (`recipes-list.sh`): `installed\|partly\|not installed\|parked\|unknown` from whether the instances named in the recipe's `ct=` line exist; no notion of running, health, or Docker-child state beyond a `docker` label | Replace by Q1 |
| Extension / capability state | `sys parts list` (on\|off, nix yes\|no), `sys parts pending` (rebuild pending), `sys ext list` | Map onto Q1 |
| Capability bundle | `scripts/pkg-bundle.sh` (`sys pkg bundle plan\|start <a,b>`): install the packages and what they require, switch on, `hs rebuild`, as **one background job** that stops at the first failure; wizard step of #229 | The precedent for #465: same plan-then-job shape |
| Job record | ADR 0004: states `queued running ok failed cancelled interrupted` plus `waiting` (ADR 0018); `step {n, of, text}` and `progress` written with `hs_job_step` (scripts/lib/job.sh); `error {category, ...}`, `result`, `parent`, `kind`, `initiator`; the Rust writer does not know `error` and falls back to Python | Reuse; steps get a fixed vocabulary (Q3) |
| Services (routes, tiles) | `scripts/services.py` descriptors in `/var/lib/hs/services.d/<name>.toml`: title, container, port, scheme, names, exposure, public paths, auth, headers, stats, **`health` (optional, a path)**, `icon`, `group`, `description`; written by `declare_service` in the recipe; a person's choices (exposure, public paths, auth) survive a re-run | Routes and health already have a runtime form; the manifest declares the same facts earlier (Q4) |
| Backup | `hs backup ct` snapshots whole instances; `backup_with_dump <name> "hs-dump …"` in `_lib.sh` declares a database dump and puts the container in the nightly backup (scripts/lib/backup-dump.sh) | Declare it in the manifest (Q4) |
| Update | `hs pkg update` shows the git diff and replaces the package copy; a running app does **not** change until `hs recipe <name>` runs again; `hs recipe <name> --check` prints `current` or `would update: <piece> (old -> new)` per piece; `piece`/`fetch_pinned`/`ensure_image` in `_lib.sh`; `hs sys recipes versions` shows package version available vs applied, not the app's | Q6 |
| Remove | `hs pkg remove <name>`: refused while on or required; deletes the copy only. `hs ct <ct> remove` (manage-ct.sh `--delete`): typed name, deletes the instance and its snapshots, **attached storage stays**, releases the UniFi reservation, then says "Remove … any Zoraxy rule by hand". Nothing knows which share, route or reservation a recipe made | Q3 (ledger) |
| Several instances | `hs recipe <name> --name <ct>` (= `RECIPE_NAME`): separate answers (`recipe-<ct>.conf`) and a service descriptor named after the container; the manifest cannot say "this recipe cannot run twice" (PLAN-packages "Open points") | Q7 |
| Autostart | `manage-ct.sh --set autostart=yes\|no` sets Incus `boot.autostart` (`true`/`false`); `ensure_container` creates with `boot.autostart=true`; `--list` has an `autostart` column; no `hs ct <ct> autostart` word, no page switch, no default per kind | #614 |
| Docker apps | A recipe that `runs` in `docker` is a child of the container `docker` (files in `APP_DIR`); the Instances page has its own Docker flow (docker-app-change.sh, PLAN-docker-instances.md) | One state vocabulary, two readers (Q1) |
| `hs sys` of the interface | Marketplace and Apps are separate pages reading `sys pkg market` and `sys recipes list\|versions`; `RunRecipe.svelte` (step wizard) + `RunQuestions.svelte` (waiting dialog) already exist | The dialog of #465 is these two joined |

Facts that differ from what the issues assume:

- **#465 "this joins them with `pkg install`"**: true, but the plan page must show what the app creates *before* anything is installed, and `sys recipes
  asks` and the wizard steps read the recipe from `current/`, which does not exist yet. The manifest of the newest verified tag is already in the local
  clone that `hs pkg fetch` made, so a read-only `pkg show` (step 6) gives plan and questions without installing.
- **#468 "services declare health"**: the descriptor has an optional `health` path but nothing reads it; no page shows it.
- **#612 is a guard that is too strict, not a wrong id.** `scripts/unifi.sh` line 83 allows `PUT rest/user/<id>` only for ids that match
  `^[0-9a-f]{24}$|^u[0-9]+$`; `clear-ip` takes `._id` from `GET rest/user`; the id in the report, `c61a053c-23ef-4b55-abab-4e98fa9e8149`, is a UUID, so
  the script's own allowlist refuses it before any request is sent. `manage-ct.sh` line 414 then ends the call with `|| true` and prints a closing line
  that tells the person to do it by hand. Whether this UniFi version accepts a PUT with a UUID id was **not** checked.
- **#613 is not explained by the code I read.** In `recipe-change.sh`, non-secret answers of the wizard go to the job as `RECIPE_<KEY>`
  (`env_lines`, only for questions whose `when` holds; `value_of` falls back to the default), the qBittorrent recipe reads `answer WG_ADDR` and asks only
  when that is empty. So either the form did not send `WG_ADDR`, or the value was lost between `HS_JOB_ENV` of the orchestration unit and the sub-job
  (`recipe-orchestrate.sh` copies only variables that match `^RECIPE_[A-Z0-9_]+=` from its own environment), or the recipe asked through a path that
  does not call `answer`. Step 2 begins with a test that reproduces it; I did not run anything.
- **#614 is half there.** The column and the setter exist (`--list`, `--set autostart=`); what is missing is the word, the page switch, the default
  and the unlock behaviour. `hs unlock` was not read.

Not verified: the web flow in a browser (nothing was run; this is Windows); whether `hs unlock` starts "the instances set to autostart" through the
same flag; Incus' behaviour for an unset `boot.autostart` (restore the last state) is from its documentation, not from the server; the open issues of
milestones 0.11 and 0.13 (the listing for those milestones came back empty); ADR 0009 and the Unraid/Proxmox part of #269 were not read in full.

## Design

### Q1 The states (#467)

One vocabulary for every kind. Four **stages** in a line, plus **flags** that do not change the stage:

| Stage | Meaning | recipe | extension | capability |
| --- | --- | --- | --- | --- |
| `available` | in a repository index, not on this server | not fetched | not fetched | not fetched |
| `installed` | the signed package copy is in `current/` | copy there, no instance | copy there, off | copy there, off (vendored if it has a module) |
| `on` | what it is for exists and is switched on | its instance(s) exist (the recipe has run) | switched on (`capabilities` on-mark) | switched on in machine.toml |
| `running` | it is live and doing its job | instance running **and** its declared health check passes | its units/timer active, or `on` when it has none | built into the running system (no pending rebuild) |

Flags (any stage): `update` (a newer release exists), `waits` (the release needs a newer core), `orphan` (the repository is gone), `pending` (a rebuild
changes it: `sys parts pending`), `failed` (an install job ended `failed` or `interrupted` and nothing was cleaned up; carries the step, Q3),
`unhealthy` (running but the declared check fails), `stopped` (recipe: `on` but the instance is stopped on purpose). For a recipe the stage is **per
instance** (Q7): the package is `installed` once; each instance has its own `on`/`running`.

The interface verbs, the same for all kinds: **Install** (available to `on`, as one job, Q2; for a capability it includes the rebuild exactly as the
bundle job does today), **Remove** (back to `available`, data stays unless asked, Q3), **Update**. Two more only where they make sense: **Start/Stop**
(instances; recipe kind only) and **Turn off/on** (extension and capability, the secondary button; it is what `hs ext` and `sys parts` do).

New read, old shapes untouched: `hs sys pkg states` (and `sys apps list`, Q2): `name, kind, stage, flags (comma list or -), repo, available, installed,
instances, title`. `sys pkg market` and `sys recipes list|versions` stay exactly as they are, because the web reads them by position. The ADR
(0027, "Package lifecycle states") records the words, because 0.11 and 0.13 depend on them.

### Q2 One Install, one job (#465)

Entry: the **Install** button of a package (Marketplace) or of an app card opens one dialog. The dialog is `RunRecipe` + `RunQuestions` made one
component; the page stays.

1. **Plan (read only, nothing installed).** `hs sys apps plan install <name> [--repo R]` reads the manifest of the newest verified tag (step 6) and
   answers key/value lines as the other plans: what it is (title, description), the version and tag that will be installed, what it creates (instance
   name and runtime, share, ports, memory and disk from `[app.uses]`, Q5), **what it needs** (`needs`, each marked present or missing and what would be
   done about it), the questions (`[[ask]]` as the wizard's steps), `long yes`, and `confirm_name` for a package of an added repository (unchanged
   rule). ADR 0008 rule 6 stays: no package copy is written before the person has seen this and pressed Install.
2. **The job** (`hs sys apps start install <name> ...` → `status started`, `unit`, `job`): one orchestration job (the engine of ADR 0018), one record,
   steps in a fixed vocabulary (Q3): `read` (fetch the tag **shown in the plan**, `hs pkg install --tag`; refuse when it no longer verifies or the
   version moved: the person saw 1.2.0, not 1.3.0) → `needs` → `ask` (the form's answers come as `--set`, secrets as the secrets folder; whatever the
   form did not cover is asked as a dialog question, #613) → `run` (the recipe, one sub-job per `# phases:` word) → `check` (the declared health, Q4)
   → `done` (`result`: where to open it, where the data lives, how it is backed up). `hs pkg install` and `hs recipe` stay separate commands.
3. **Needs** (`docker`, `share`, `tailscale`, today refusals): each is a plan line and a job step. `docker` = the core recipe `docker` (installed
   and run as part of the same job); `share` = the question "which share" (an existing one, or the recipe's default is created and recorded in the
   ledger, Q3); `tailscale` = switch the capability on, which needs a rebuild: shown in the plan with its duration, run as in `pkg-bundle.sh`.
4. **Extension and capability** use the same dialog and job, with fewer steps (`read`, `needs`, `on`, `check`; a capability with a module adds `rebuild`).
   `sys pkg bundle` becomes a caller of the same code, so there is one implementation of "install, switch on, rebuild".
5. **Last screen**: Open `<app>` (the first route, else `ip:port`), where the data lives, backup status (Q4), and the job link.

New rows: `sys apps list|show <name>` (reads), `sys apps plan|start install|retry|cleanup|remove|update|policy <name>` (changes; the same plan/start
pattern as `sys pkg`). Each is a `sys` row: `openapi-gen.py`, `openapi-ts-gen.py`, a probe in `smoke.sh` for each read, German help text.

### Q3 A failed install: the step, retry, clean up (#466)

- **Steps have names.** The record's `step.text` is one of `read, needs, ask, run:<phase>, check`; a failure sets `error {category, step, text, tail}`
  with the last lines of the sub-job's log (the existing `error` field; the Rust writer must learn it, or the Python fallback stays, see PLAN-jobs).
  The Jobs page and the dialog show "failed at: run: configure" and the lines.
  Built (step 9): the record ends after the job wrapper wrote `error`, so the failed Install job writes its step, reason and tail into the record's `result`
  (`status failed, failed_step, reason, tail, package, repo, tag, instance`); the `error` field stays the wrapper's `exit` category.
- **Retry** = `sys apps start retry <job>`: a new orchestration that starts at the failed step (`--from <step>`), with the answers already given
  (stored in `recipe-<ct>.conf` and the job's secrets folder is removed only when the job ends for good). Retry is **per step and per recipe phase**;
  a recipe step that fails in the middle of a phase re-runs the whole phase, which is safe because recipes are idempotent (pins and stamps skip what is
  current). No resume inside a phase (decision D7).
- **Created ledger.** Today nothing knows what a run made. New `scripts/lib/created.sh`: `created <kind> <id> [detail]` appends a line to
  `/var/lib/hs/apps/<instance>.toml` **only when this run created the thing** (`existed=false`), never for something that was already there. Called
  by `ensure_container` (instance), `fixed_address` (UniFi reservation, address), `declare_service` (descriptor, routes it made through the
  reconciler), the storage helpers (share created, attach), the installed.toml record, a Zoraxy rule if the recipe makes one. The same file is the **app
  record** later steps read (policy, instance names, the declared contract resolved at run time).
- **Remove what was created** = `sys apps start cleanup <job>`: plan first (the ledger in reverse, each line naming what goes), typed name of the app,
  then removes route, descriptor, reservation, instance, share it created. **Data is asked separately**: a created share or volume holding data is a
  second question, default keep. Never touches what the ledger does not list; a retry over an existing app therefore cannot delete the old app.
- Apps made before this milestone have no ledger. Their Remove (step 11) builds a **read-only discovered list** from the manifest declaration and the
  descriptor and shows it as the plan; it never guesses beyond the instance and the descriptor named after it.
- Tested with a fixture recipe in `tests/fixtures/pkgtree` that fails at a chosen phase (`RECIPE_FAIL_AT`), and with the fake incus/unifi that the
  existing tests use.

### Q4 The app contract (#468)

Optional `[app]` tables of `package.toml` (recipe kind first; an extension that owns a service may use them later). All optional, `requires_core` of
a package that uses them goes to **9** (one bump for Q4 and Q5, step 5).

```toml
[app]
instances = "one"                 # one | many (Q7); default one
autostart = true                  # default for the instance's boot flag (#614): services true, tools false
[app.health]
check   = "http"                  # container (default) | tcp | http
port    = 8096
path    = "/health"               # http: any 2xx or 3xx is healthy
timeout = 5
[app.backup]
mode  = "instance"                # instance (the nightly instance backup, default) | paths | none
paths = []                        # mode paths: inside the instance
dump  = "postgres-compose"        # optional: the hs-dump kind that backup_with_dump declares; "-" none
[app.routes]
default  = "web"                  # the route names it offers; the descriptor stays what the recipe writes at run time
web      = { port = 8096, scheme = "http", exposure = "private-ok" }
[app.update]
kind    = "pin"                   # pin (the recipe's pins move with the package) | os (apt/nix inside) | manual
default = "notify"                # automatic | notify | pinned (Q6)
[app.version]
source = "image-tag"              # image-tag | http-json | exec: how the RUNNING app version is read (Q6)
[app.remove]
keeps   = ["data volume", "share"]   # plain English, shown in the Remove dialog
data    = ["/var/lib/immich"]        # what "delete the data" deletes (inside the instance, or a named share)
```

Rules:

- **The manifest is the source, the run is the proof.** `declare_service` defaults port, scheme, exposure and health from the manifest; the recipe may
  still pass its own value, and `pkg.py validate` refuses a manifest whose `[app.routes]` name a different exposure than a never-public rule allows
  (`ADMIN_TARGETS` in `scripts/services.py` stays the guard; a manifest cannot make an admin page public). The package's CI dry-runs the recipe and
  compares the declared route names with what `declare_service` would write.
- Apps shows **healthy / not healthy** from the declared check (`sys apps list` runs `tcp`/`http` against the instance address with a short timeout;
  results cached for a few seconds and refreshed by events, ADR 0005, not polled), falling back to "the container runs" when nothing is declared.
- Remove offers **keep the data** (default) and **delete the data** (a typed name, the destructive rule of CLAUDE.md) from `[app.remove]` plus the
  ledger. `pkg.py validate` checks the tables; the five `core = true` recipes and the ten of step 14 must carry them (CI error for these, a warning for
  others, so old and third-party packages stay valid).

### Q5 Fields for a store (#469)

All optional, on the same bump to API level 9:

```toml
description    = "Photos and videos with face search."       # one paragraph, en; description_de
icon           = "ph:image"        # a Phosphor name, or a file "icon.svg" in the package (<= 20 KB, no scripts)
category       = "media"           # from config/package-categories.toml (media files network home games tools dev admin)
upstream       = "https://immich.app"
app_version    = "1.118.2"         # the app release this package version pins; set at release time
screenshots    = ["shots/library.png"]   # at most 5, <= 300 KB each, png/webp, read from the package folder
[app.uses]
ram_mb = 4096   disk_gb = 20   ports = [2283]   gpu = false   # what the plan shows; `uses` (gpu) stays as it is
```

- **The index carries what a list needs**: `icon`, `category`, `app_version` (index.toml gets three optional keys; `repo-check` compares them with the
  package). Description, pictures and `[app.uses]` are read from the package through `pkg show` / `sys pkg asset <name> <file>` (clone, no install).
- **No live lookup of upstream versions** from the server (no calls to GitHub per app; privacy and offline): `app_version` is what the release
  says, the running version is read locally (Q6).
- `hs pkg new` and the web package builder write the fields; `check-draft` validates them. Ten recipes are filled in as a start (step 14).
- Pictures are untrusted files from a package: only the listed extensions, size capped, served with a fixed content type through the existing
  asset path of the web server; an SVG icon is rejected when it contains `<script`, `on*=` or an external reference. Components of a package stay
  isolated as in ADR 0016.

### Q6 Package version and app version, update policy (#470)

- **Two numbers, side by side**: the package's `version` (what the recipe is) and the app's running version, read by `[app.version]`: `image-tag`
  (the tag of the pinned image in the compose file or the instance), `http-json` (a path and a JSON pointer on the app's own API), or `exec` (a
  command inside the instance with a fixed timeout). `sys apps list` carries both; Apps and the update dialog show "Immich 1.118.2 (package 1.0.0)".
- **Update shows what changes first**: the plan of `sys apps plan update <name>` is `hs recipe <name> --check` (per piece: `would update: image
  (1.118.2 -> 1.119.0)`) plus the package diff and, for a major, `CHANGES.md` (PLAN-packages). Nothing runs until Start.
- **Policy per app**: `automatic | notify | pinned`, default `notify`, stored in the app record (`/var/lib/hs/apps/<instance>.toml`, key `policy`), set
  by `sys apps start policy <name> <value>`. `notify`: `hs health` does not alarm (an update is not a problem), the Apps card and the weekly summary say
  it. `pinned`: no notice, `hs pkg update` of the package is still possible but the app is not run again. `automatic`: a timer (step 13) updates the
  package **and runs the recipe** only for a patch or minor package release, never a major, never a package whose diff touches `needs`, `commands.tsv`
  or `[web.*]` (PLAN-packages trust rule), only inside a configurable quiet window, after an instance snapshot, then the `check` step; on a failed
  check it restores the snapshot and the previous package copy (`hs pkg rollback`), keeps the app on `notify` and sends one push message. Automatic is
  off for added repositories.

### Q7 Several instances of one app (#471)

Decision (recommended): **yes, where the package says so.** `[app] instances = "many"` (default `one`). What exists already is used: `--name <ct>` /
`RECIPE_NAME`, a separate `recipe-<ct>.conf`, a service descriptor named after the container. Naming: the first instance is the recipe's default
name; further ones are `<recipe>-<word>` (the person picks the word; `[a-z0-9-]`, at most 40 characters, unique across instances **and** services),
checked in the plan, not at run time. The plan of a second install of an `one` package says so and refuses. The ports and the fixed address of the
second instance are asked again (a default is never reused). Lifecycle: the **package** is installed once; **instances** carry `on`/`running`/health,
update policy and the ledger; removing the package is refused while an instance exists. Game servers (`pelican`), `arr` and `docker` stay `one`
until a recipe has been tried with two. Written down in the ADR of Q1; no code beyond the field, the plan check and the naming helper (step 16).

### Q8 Bugs inside the steps

- **#612** (step 1, first because it is small and found on the real server): in `scripts/unifi.sh` the id guard also accepts a UUID
  (`^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`); `manage-ct.sh` no longer swallows the failure: it prints one translated line
  ("The fixed IP in UniFi was not given back: <reason>. Remove it there by hand") and only prints the "remove by hand" line when that is true. The
  raw `PUT rest/user/<id>` text never reaches the person. Test: `tests/unifi.sh` with a fake API that returns a UUID `_id`. Hardware: delete one
  instance that holds a reservation and look at UniFi.
- **#613** (step 2): reproduce with a test that runs `recipe-change.sh start qbittorrent run --interactive --set WG_ADDR=10.2.0.2/32 --set …` against
  a fake `hs_job`/orchestrator and prints what each sub-job's environment contains; find where `RECIPE_WG_ADDR` is lost; fix; add the rule "a question
  whose key was given up front is never asked again, and the dialog asks only what the form did not cover" as a test of `ask_q`. The second half
  ("a wizard run on an existing container cannot ask again") is solved by the Install/retry flow: `--ask` becomes `sys apps start run <name> --ask`,
  which sets `RECIPE_ASK=1` for the orchestration (step 8).
- **#614** (step 3): `hs ct <ct> autostart on|off` (sets `boot.autostart`), a "starts at boot" column in `hs ct list` and on the Instances page
  (switch on the instance page), the default from `[app] autostart` (step 5; until then services on, tools off by a list in the recipe), the plan
  dialog says it, and "Stop" on the page offers "also keep it off at boot". Semantics (decision D14): **on** = `boot.autostart=true`; **off** = the key
  unset, so Incus restores the instance's last state (a stopped instance stays stopped, a running one comes back); a hard "never" (`false`) is not
  offered. `hs unlock` (not read yet) must start exactly the instances Incus would start, not its own list.

## Steps

Sizes: S up to a day, M two to three days, L a week. Every step adds its tests, `bash -n` for touched scripts, `scripts/dev/t quick <names>`,
`python3 scripts/pkg.py validate`, German help text, a changelog entry when users see it, and for every new `sys` row `python3
scripts/openapi-gen.py write` and `python3 scripts/openapi-ts-gen.py write` in the same commit and a smoke probe for each read.

| # | Size | Step | Files | Needs | Done when |
| --- | --- | --- | --- | --- | --- |
| 1 | S | **#612**: UUID ids accepted by the guard, translated honest message and closing line in `--delete` | scripts/unifi.sh, scripts/manage-ct.sh, tests/unifi.sh, i18n de | none | test with a UUID `_id` releases the reservation; a refusal prints one plain line |
| 2 | S | **#613**: reproduce, fix the lost `RECIPE_<KEY>`; "asked up front is not asked again" test | scripts/recipe-change.sh, recipe-orchestrate.sh, recipes/_lib.sh, lib/ask.sh, tests/recipe-orchestrate.sh | none | the failing case is a test, then green |
| 3 | S | **#614** autostart word, column, page switch, "keep it off", `hs unlock` check | scripts/manage-ct.sh, ct-change.sh, web/src/pages/instances/*, scripts/unlock*, registry.tsv, tests | D14 | `hs ct x autostart off` + simulated boot start only the flagged instances |
| 4 | M | States: ADR 0027, `sys pkg states` (+ `sys apps list` stub reading the same), mapping per kind, Marketplace and Apps use the words and one Install/Remove/Update | docs/adr/0027-…, scripts/pkg.py, pkg.sh, registry.tsv, docs/api/sys.toml, web/src/pages/Marketplace.svelte, Apps.svelte, tests/pkg.sh | D1 to D3 | the same state words for the three fixtures; the old reads byte-equal |
| 5 | M | Manifest: `[app]` contract and store fields, API level 9, `validate`/`repo-check`/`check-draft`, `config/package-categories.toml`, index keys, fixture packages | scripts/pkg.py, pkg_repo.py, lib/api-level, config/, tests/fixtures/pkgtree, docs/Package-API.md, tests/pkg.sh | D8 to D10 | good and bad fixtures; an old manifest is unchanged |
| 6 | S | `hs sys pkg show <name>` (manifest, asks and steps of the newest verified tag from the clone, no install) and `sys pkg asset` | scripts/pkg_repo.py, pkg.sh, registry.tsv, tests/pkg-repo.sh | 5 | plan data for a package that is not installed; an unsigned tag refused |
| 7 | M | **Created ledger**: `lib/created.sh`, calls in `ensure_container`, `fixed_address`, `declare_service`, storage helpers; app record file | scripts/lib/created.sh, recipes/_lib.sh, services.sh, tests/created.sh | D6 | a run writes only what it created; a re-run over an existing app writes nothing |
| 8a | M | **One Install, backend**: `sys apps plan|start install`, orchestration with steps `read needs ask run check done`, tag pinned from the plan, `result`, `--from`, `RECIPE_ASK`; `sys pkg bundle` becomes a caller | scripts/apps-change.sh (new), recipe-orchestrate.sh, pkg-bundle.sh, pkg_repo.py (`--tag`), registry.tsv, tests/apps-change.sh | 4, 6, 7, D4, D5 | a fixture install from a local repository ends `ok` with a result; plan shows needs |
| 8b | M | **One Install, web**: one dialog (plan, form steps, waiting questions, progress by step, last screen) from Marketplace and Apps | web/src/forms/ops/Install*.svelte, RunRecipe/RunQuestions merged, Marketplace.svelte, web tests | 8a | the dialog drives the fixture end to end in the web tests |
| 9 | M | **#466** error with step, Retry from it, "Remove what was created" (plan, typed name, data question); fixture recipe failing on purpose | scripts/apps-change.sh, lib/job.sh, web dialog, tests/fixtures/pkgtree, tests/apps-change.sh | 7, 8a, D7 | fail at `run:configure`, retry continues there, cleanup leaves nothing the ledger lists |
| 10 | M | **Health**: `sys apps list` runs the declared check, events refresh it, Apps shows healthy / not healthy / stopped | scripts/apps-list.sh, services.sh, web/src/pages/Apps.svelte, smoke.sh | 4, 5 | fake http/tcp targets give each state; no polling while the event stream is up |
| 11 | M | **Remove with keep/delete data** from `[app.remove]` + ledger (discovered list for older apps); `hs ct remove` and `hs pkg remove` point to it | scripts/apps-change.sh, manage-ct.sh, web dialog, tests | 7, 9 | keep leaves the data and the share; delete needs the typed name |
| 12 | M | **#470 versions and notify**: `[app.version]` reader, both numbers in Apps, `sys apps plan update` from `--check` + diff, policy field `notify\|pinned`, weekly summary line | scripts/apps-version.sh, recipes-versions.sh (unchanged shape), web, tests | 5, 10 | the running version of a fixture is shown; plan lists the pieces |
| 13 | M | **Automatic updates** with snapshot, quiet window, health check and rollback; off for added repositories | scripts/apps-autoupdate.sh, timer in configuration.nix, tests | 11, 12, D12 | a failing fixture update is rolled back and notifies once **Built 2026-11-16, hidden and off** (setting `appsAutoupdateEnabled`, notes in docs/Entwicklungsnotizen.md). Not tested on hardware yet. |
| 14 | M | Core recipes carry the contract and ten recipes the store fields (hobnix/recipes, three pull requests: contract for the five `core` recipes, store fields for ten, the rest later) | the recipes repository | 5 | its `check` green against core 0.6; `repo-check` passes |
| 15 | S | `hs pkg new` and the package builder write the fields (#469) | scripts/pkg_new.py, web/src/pages/PackageBuilder.svelte, tests/pkg-new.sh | 5 | a new package passes validate with the tables |
| 16 | S | **#471**: `instances` field, plan refusal and naming check, ADR text | scripts/apps-change.sh, pkg.py, docs | 5, 8a | a second install of a `one` package is refused in the plan |
| 17 | S | Docs: guides (containers-and-apps, operations, web-interface), changelog, ADR status, this page listed in docs/categories.tsv and docs/README.md | docs/ | 8 to 13 | `tests/docs.sh` green |
| 18 | S | Hardware test of 1, 3, 8 to 13 on a real server; tick the issues' "Hardware test" boxes with what was seen | the issues | all | "Not tested on hardware yet." removed only for what was seen |

Parallel lanes after the decisions: A (bugs: 1, 2, 3, independent of everything), B (4, then 10), C (5, 6, then 14 and 15), D (7, then 9 and 11). Step 8a
waits for 4, 6 and 7; 8b for 8a; 12 and 13 for 10 and 11; 16 for 8a. Steps 4 and 5 both edit `scripts/pkg.py` and must not run at the same time;
7 and 2 both edit `recipes/_lib.sh`; 8a, 9 and 11 all edit `scripts/apps-change.sh` and go one after the other.

## What only runs on hardware

| Step | What to look at on a real server |
| --- | --- |
| 1 | delete an instance that has a UniFi reservation: the reservation is gone, no raw API text |
| 3 | reboot (after `hs unlock`): only flagged instances start; a stopped one with the flag off stays stopped; confirm Incus restores the last state when the key is unset |
| 8 | Install a package that was never fetched, answer the form and one dialog question, watch the steps, press Open |
| 9 | make a recipe fail (unreachable image), Retry, then "Remove what was created": container, route and UniFi reservation gone, data question asked |
| 10 | stop the app inside its instance: Apps says not healthy, the container still runs |
| 11 | remove with "keep the data", install again, the data is back; remove with "delete the data" needs the typed name |
| 12, 13 | an app with a pinned image updates through the plan; an update that breaks the health check is rolled back |

Everything else is checked by tests with fakes (incus, UniFi, a local signed package repository).

## Risks

- **The ledger is a new source of truth** next to Incus, the descriptors and installed.toml. Mitigation: it only lists what a run created, removal
  re-checks each line against the real thing before deleting, and an app without a ledger is never removed by guesswork.
- **Cleanup deletes.** Steps 7, 9 and 11 follow the rule: plan, typed name of the app, data asked separately and kept by default.
- **A rebuild inside an Install job** (needs `tailscale`) can fail or take minutes and ends the SSH session of someone who is working. Mitigation:
  shown in the plan, run as the existing bundle job does (stops at the first failure), never silent.
- **Automatic update runs a recipe as root unattended.** Limited by D12 (patch/minor, default repositories, snapshot, health check, rollback); until
  step 13 is tested on hardware the default stays `notify` and the `automatic` choice is hidden.
- **Recipes are not converted to phases or `ask_q`** (PLAN-recipe-orchestrator). Install works with one phase per recipe (one `run` sub-job) and asks
  only what `setting` asks; "retry from a step" is then coarser for unconverted recipes. Conversion stays recipe by recipe in hobnix/recipes.
- **0.11 and 0.13 read these words and fields.** After step 4 and 5 are merged, changing a state word or a field name needs an API level bump and a
  one-release deprecation (ADR 0008 rule 4).
- **#269 (Unraid templates, vzdump import)** is not in this plan's steps: it needs the Compose importer and the VM wizard (its own acceptance says
  so), ADR 0024 already decides the Proxmox side, and nothing in Q1 to Q7 needs it. Recommended: move it to a later milestone (D15).

## Decisions for the owner

The "Recommended" answer is first in each row.

| Id | Question | Options | Recommended |
| --- | --- | --- | --- |
| D1 | The stage words (Q1) | `available, installed, on, running` + flags; add `set up` for recipes; keep each kind's own words | The four stages + flags; they are what #467 names and what 0.11/0.13 will read |
| D2 | One verb in the interface (Q1) | Install = through `on`, Remove = through `available`, Turn off/on as secondary for extension/capability; Install = fetch only (today) | Install/Remove/Update for all kinds; Start/Stop for instances; Turn off/on secondary |
| D3 | How the new states are read | new `sys pkg states` + `sys apps list`; a new column on `sys pkg market` | New reads; old reads stay byte-equal (ADR 0004; the web reads by position) |
| D4 | Plan before anything is installed (Q2) | manifest read from the verified clone (`pkg show`), job installs exactly that tag; install the copy first, then plan | Read from the clone; the job refuses a tag different from the one shown |
| D5 | A need that requires a rebuild inside Install (Q2) | allowed, shown in the plan with its duration, run like the bundle job; refused with "turn on X first" | Allowed, as a plan line and a step |
| D6 | The created ledger (Q3) | one record per app in `/var/lib/hs/apps/<instance>.toml`, only what the run created; discovery at removal time only | Record per app; apps without one get a read-only discovered list in the plan |
| D7 | Retry granularity (Q3) | per orchestration step and recipe phase, whole-phase re-run; resume inside a phase | Per step/phase; recipes are idempotent so a phase re-runs safely |
| D8 | Where the contract lives (Q4) | `[app]` tables in `package.toml`, manifest as source for `declare_service` defaults; keep it only in `run.sh` | Manifest tables; CI dry-runs the recipe and compares |
| D9 | Strictness | optional for all, required (CI error) for the five core recipes and the ten filled ones; required for every recipe | Optional for all, required for the core five and the ten; others get a warning |
| D10 | Store media (Q5) | Phosphor name or small SVG, screenshots in the package (max 5, 300 KB), fixed category list, index has icon/category/app_version; pictures hosted elsewhere | In the package, capped; category list in `config/package-categories.toml` |
| D11 | App version source (Q5, Q6) | `app_version` from the release + running version read locally; live lookup of upstream releases | No server-side upstream lookup |
| D12 | Automatic updates (Q6) | `automatic\|notify\|pinned`, default notify; automatic only patch/minor, default repositories, snapshot + health check + rollback, hidden until tested; no automatic mode in 0.6 | Policy per app, automatic gated as listed |
| D13 | Where the policy lives (Q6) | in the app record; in machine.toml | App record (it is per instance, not per machine setting) |
| D14 | Autostart semantics (#614) | on = `true`, off = unset (restore last state); off = `false` (never at boot); a third explicit value | on/off as stated; no "never" |
| D15 | #269 Unraid/Proxmox import | move to a later milestone; keep in 0.6 as the last step | Move it; no step depends on it |
| D16 | Several instances (Q7) | yes where the manifest says `many`, `<recipe>-<word>`, default `one`; yes for every recipe; no | Yes where declared |
| D17 | Where the new rows live | one family `sys apps` for instances, `sys pkg` for packages; extend `sys recipes` | `sys apps`, with `sys recipes` and `sys pkg` unchanged |

## Check that it worked

- `hs sys pkg states` gives the same four stages for a recipe, an extension and a capability fixture; `sys pkg market` and `sys recipes list` are unchanged.
- Install of a package that is not fetched: the plan appears first, nothing is in `current/` until Start, the job ends `ok` with a `result` and the
  Jobs page shows the steps.
- A recipe that fails at `run:configure` shows that step and its last lines; Retry continues there; "Remove what was created" removes only what the
  ledger lists and asks about data.
- Apps shows not healthy when the declared check fails although the instance runs; Remove keeps the data when asked to.
- `hs ct x remove` on an instance with a UniFi reservation (UUID id) releases it.
- `python3 scripts/pkg.py validate` accepts an old manifest and a manifest with the new tables.
