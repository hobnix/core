# Plan: extensions and access (milestone 0.8)

Status: **Decisions D1 to D20 Accepted 2026-11-18** (recommended options, except D2: the group names carry the prefix `hn-`); the steps are not built yet. Proposed 2026-11-17. Design record for
epic [#197](https://github.com/hobnix/server/issues/197) (Extension Protocol and SDK) and its open children
[#239](https://github.com/hobnix/server/issues/239), [#313](https://github.com/hobnix/server/issues/313),
[#434](https://github.com/hobnix/server/issues/434) and [#462](https://github.com/hobnix/server/issues/462). It checks the facts of the issues against the
code of branch `0.8` (2026-11-17), names where the code differs from what the issues assume, and gives an ordered list of steps, each sized for one
pull request, in lanes that can run in parallel. Steps 15 to 17 and 20 change who may sign in or what a package may do on a server and are marked
"security" in the Steps table. Nothing in this plan was run; Not tested on hardware yet.

See also: [PLAN-extensions.md](PLAN-extensions.md) (package folder, web declaration, boot hook), [PLAN-packages.md](PLAN-packages.md),
[PLAN-selfservice.md](PLAN-selfservice.md) (the first extension with its own service and its own sign-in), [PLAN-web-backend.md](PLAN-web-backend.md),
[PLAN-web-auth.md](PLAN-web-auth.md) (lockout and sessions, built in 0.2), [PLAN-events.md](PLAN-events.md), PLAN-web-design.md (the web design record, section 4.9, 6 and 7; the file arrives in 0.8 when `develop` is merged), [PLAN-storage-nas.md](PLAN-storage-nas.md)
(the style of this page), ADR 0004 (job record), ADR 0005 (events), ADR 0006 (API in front of the CLI), ADR 0008 (packages and trust), ADR 0010 (command
protocol), ADR 0011 (service lifecycle), ADR 0012 (roles and tokens), ADR 0014 (permissions), ADR 0015 (Wasm: deferred), ADR 0022 (first-run console
token), ADR 0023 (nested test harness).

## Problem

Two halves of one question, "who may do what on this server":

1. **Packages.** Extensions and recipes are root code. ADR 0010 and 0011 decided a protocol and a service lifecycle and ship reference runners; ADR 0014
   decided "declare and disclose". But no package uses the protocol, no service extension can run, the permissions are checked only against the
   manifest, and no package declares the events it provides. A third party cannot yet write an extension in Go or Rust and know what the core promises.
2. **People.** Every web login is `admin` (root-equivalent). A household member cannot look without being able to change; a script cannot call the API
   without a browser session; a password is the only factor on a public project that starts root commands.

The two halves meet in one place: the check in front of every `hs sys` call in `scripts/web-serve.py` (ADR 0012 rule 9). That is why they are one milestone.

## What exists today (read from the code on 2026-11-17, branch `0.8`)

| Part | State | Verdict |
| --- | --- | --- |
| Command protocol (#237, ADR 0010) | `scripts/lib/ext_proto.py` (reference runner), `docs/api/ext-protocol-v1.schema.json`, tests/ext-proto.sh, fixture `tests/fixtures/ext-proto/ext.py`. **Nothing calls the runner**: grep finds `ext_proto` only in its own files and tests. `hs ext` and `hs sys ext` still run the shell contract. No `protocol = [1]` key and no per-row timeout in `scripts/pkg.py` or `scripts/hs_ext.py` | Wire it (steps 1, 2) |
| Cancel of a web job (ADR 0010 rule 7) | ADR says `hs_job` cancel must send SIGTERM to the process group; listed as follow-up 2 and not checked here | Verify, then fix (step 3) |
| Service extensions (#238, ADR 0011) | `scripts/lib/ext_service.py` (supervisor), `docs/api/ext-service-v1.schema.json`, tests/ext-service.sh, fixture svc.py. **No `[service]` table is read, no `hs-ext-svc@.service` unit exists** (configuration.nix has only `hs-ext-boot.service`, line 437), no `hs ext status|start|stop|svc-run`, no cursor directory, the kind `ext.service-failed` is not registered. ADR rules 2, 3, 10 and 12 are "specified, not built" | Build (steps 4 to 6) |
| SDK (#240) | Rust crate `rust/hobnix-ext-sdk` with tests/ext-sdk-rust.sh. No shell or Python helper, no Go; no `hs create package --template` for an extension (#265 names only the recipe template) | Rust done; shell and Python helpers, Go example, `hs pkg new --template extension --protocol shell\|python` and docs/extensions-sdk.md done (step 7, `sdk/`, scripts/lib/ext_sdk.sh and .py, tests/ext-sdk-examples.sh) |
| Wasm (#266, ADR 0015) | Decided: defer, keep ADR 0010 transport-neutral | Nothing to build; a standing rule for steps 1 and 2 |
| Permissions (#239, ADR 0014) | `permissions = [...]` in package.toml, vocabulary in `scripts/lib/pkg_perms.py` (`web.read`, `web.change`, `events.emit`, `events.subscribe`, `fs.*`, `net`, `host`, `secrets`, `devices`), `pkg.py perms-check`, `hs ext enable` refuses a package whose permissions do not cover its own `[[web.*]]` and `[[events]]`, `hs_ext.ext_declarations` skips it; an update that adds a permission needs the typed name. `permissions` is optional ("not declared" still installs). **No recipe (0 of 38) and no extension (0 of 4: ad-selfservice, games, passthrough, posters) declares any.** Commands, `fs`, `net`, `host`, `secrets` are not enforced; ADR 0014 steps 2 and 3 are undecided | Make it real in stages (steps 8 to 11) |
| Package events (#313) | `scripts/lib/pkg_events.py`, `pkg.py` validates `[[events]]` and installs `<state>/pkg-events/<name>.tsv`, `hs event kinds` lists them (#378). Recipes: **no manifest has `[[events]]`**; the media events still live in the shared helper `hs-media-notify.py` (referenced from recipes/radarr and recipes/sabnzbd `run.sh`) and in core `event-kinds.tsv`. Not checked: whether state-db level lookup, the event-notify rules and the docs/events.md catalogue already read the installed declarations (acceptance boxes 3 and 4 of the issue) | Audit first (step 12) |
| Roles (#434, ADR 0012) | **Nothing enforced.** The ADR header says "Accepted (2026-11-10)" while its Decision section and the issue say Proposed. `scripts/web-serve.py` has no role (grep: `role` appears only in pool and recipe-run code, and `--by <user> --role admin` for job answers at line 3093). Sessions (`class Sessions`, line 608): user, realm, times, ip, credential fingerprint; list and end routes exist (#504). `docs/api/sys.toml` has 202 lines and no role field. `docs/adr/0012-roles-sys-rows.tsv` lists 238 rows, `registry.tsv` now has 279 `sys` rows: **the table has drifted** | Regenerate, then enforce (steps 13 to 16) |
| Audit actor (ADR 0012 decision 8) | `scripts/lib/audit.sh` reads `HS_ACTOR`; **no script or web-serve.py sets it** (grep over scripts), so a web change is logged as `web`, as the ADR suspected | Confirmed; fix in step 14 |
| API tokens | None. No `Authorization: Bearer` handling in web-serve.py | Build (step 17) |
| Sign-in | Domain Admins via `ntlm_auth` + winbind, local `adminuser` via `unix_chkpwd`; throttle by address (#502 option C), session cookie hash in `/run/hs-web/sessions.json`; first-run console token (ADR 0022) | Base for steps 19 to 22 |
| Two-factor, SSO (#462) | None (no TOTP or OIDC code in scripts/). The issue says the security review (#433) comes first | Blocked on #433 for scope, not for design (D17) |
| Self-service password (PLAN-selfservice) | Extension `ad-selfservice` with its own service and port; it is the one existing package with a long-running process, started by `sys ext ad-selfservice boot` | First candidate for a `[service]` conversion (step 6) |

Facts that differ from what the issues assume:

- **#197 "Protocol is shell + TSV, no JSON-RPC, no enforced permissions"** is out of date. JSON Lines protocols (ADR 0010, 0011), a Rust SDK, signed
  repositories, `permissions` and their manifest check exist. What is missing is that nothing *uses* them: the runners are reference code and tests.
  The epic's review boxes ("keep or rework?") are answered by this page: keep, wire in.
- **#239 has no acceptance criteria** (the issue text is one line plus a comment). The criteria are written here (step 8 to 11, "Check that it worked").
- **#434 "ADR 0012 accepted or changed"**: the ADR is marked Accepted but proposes ("Decision (proposed)") and leaves four points open (AD group names,
  token rate limit, the role field and its test, extension manifests). D1 asks the owner to confirm and settle those.
- **#313 acceptance on the recipes side** names sonarr, radarr, sabnzbd and maintainerr; the table location was not found by name in the recipes
  checkout, only the callers (step 12 finds it).
- **#462 "TOTP ... the local admin can always get in from the console"**: today the console route is the first-run token (ADR 0022) and `passwd`; a
  recovery for a lost second factor has to be a root command, because the web server must not offer one (D16).
- **ADR 0012 counts** (116 viewer, 14 app-manager, 108 admin of 238 rows) are not valid for 279 rows; the generated file is redone in step 13.

Not verified: that the dispatcher of `hs ext` has no second code path that already calls `ext_proto` (only grep was used); the state of
`hs-media-notify.py` and where its table lives (it is not in the checkout read); whether `state-db.py`, `event-notify.py` and `docs/events.md` read
`pkg-events/` (step 12 settles it); the PLAN-packages.md text (not reread); whether `hs_job` stops a job with SIGTERM to the group; behaviour of any
of this on a NixOS host; no test was run (Windows).

## Design

### Q1 One protocol, two runners (#197, #237, #238, #240)

Keep ADR 0010 and 0011 as accepted. The work is making them real:

- **Manifest.** `protocol = [1]` (commands) and a `[service]` table (`exec`, `subscribe`, `health_interval`) in package.toml; per-row `timeout` as a flag
  in commands.tsv. `pkg.py validate`, `repo-check` and `hs ext enable` check them. A row without the key keeps the shell contract (ADR 0010 rule 10).
- **Dispatcher.** `hs ext <name> <cmd>` and `hs sys ext <name> <cmd>` call `ext_proto.py` for a protocol row and render `data` to TSV or text (`-` for an
  empty field); the machine-readable shape of every existing `sys ext` row does not change (CLAUDE.md contract).
- **Services.** One static unit template `hs-ext-svc@<name>.service` in configuration.nix (like `hs-ext-boot.service`, no rebuild per package), whose
  `ExecStart` is `hs ext svc-run <name>` = `ext_service.py`. `hs ext status|start|stop`, state in `hs sys ext status` (new row), core kind
  `ext.service-failed` registered in `event-kinds.tsv`, cursor files in `/var/lib/hs/ext-cursors/<name>`, snapshots stored as live topic
  `ext-<name>-<topic>` (the existing live path of PLAN-extensions "Live reads"), 50 emits a minute per service.
- **Transport neutral** (ADR 0015 rule 3): no rule may depend on a pid, an inherited descriptor or an environment variable.
- **SDK.** Rust exists. Shell and Python get a small helper (one file each, stdlib only, the same message types); Go is a documentation example, not a
  library (D3). A guide `docs/extensions-sdk.md` follows GUIDE-TEMPLATE.md and shows one extension per language that the test suite really runs.

### Q2 Permissions: from disclosed to enforced (#239, ADR 0014)

Today a permission is a sentence. Enforcement in four stages, each useful alone; the owner decides how far to go (D5 to D8):

1. **Required and honest.** `permissions` becomes required for a package in a repository that passes `repo-check` (D5); recipes and extensions are
   given theirs (an audit of what each script touches, one PR per repository). An undeclared package still runs while installed, with a warning in
   `hs pkg list` and `hs ext list`.
2. **Enforce what the core already mediates.** The core is the middleman for events and for the web: `events.emit` is checked on every `emit` message and
   every `hs event emit --pkg`, not only against the manifest at enable time; `web.read`/`web.change` already are. A call outside the declaration is
   dropped with one warn line a minute.
3. **Confine services with systemd** (ADR 0014 step 2, ADR 0011 unit): properties generated from the permissions of a service: `ProtectSystem=strict`,
   `ReadWritePaths=` from `fs.write`, `ReadOnlyPaths=` from `fs.read`, `NoNewPrivileges`, `PrivateDevices` unless `devices`, `PrivateTmp`. `net` stays
   **declared only** until the owner says what `net = lan` means for the firewall (D6; it touches network and firewall, so it is a question, not an
   implementation).
4. **Commands** run as root unconfined and say so (ADR 0014 step 3, the broker, stays undecided: D7). A command that wants confinement can opt in to
   `systemd-run --pipe --wait -p ...` with the same properties (D7, option B); not the default, because commands call `incus` and write `/etc/hs`.

The docs keep saying "root-trusted" for commands. "Enforced" is only used for the three things above.

### Q3 Packages declare their events (#313)

The design of the issue stands. Order: audit what is merged (step 12), finish the core side (levels, rules and catalogue read the installed
declarations; the kind registration test covers core scripts only; both forms accepted), then the recipes PR (the table into the manifests of sonarr,
radarr, sabnzbd, maintainerr; `hs-media-notify.py` only emits), then the core drops the old form one release later. A package with `[[events]]` must have
`events.emit` (already checked). The Rust port of `event-notify.py` stays a separate issue (as the issue says).

### Q4 Roles (#434, ADR 0012)

Build what the ADR decides, in this order:

1. **The role field.** `docs/api/sys.toml` (or a file next to it that `scripts/openapi-gen.py` reads) carries `role` per row; the generator copies it to
   `docs/api/openapi.json` as `x-hs-role` and to `web/src/api/sys.gen.d.ts`. A missing role means `admin`. tests/openapi.sh fails for a `plan` or
   `start` row marked `viewer`, and for a new row without a decision (the explicit admin list is a file, so adding a row forces a review).
2. **The check** is one function in `scripts/web-serve.py`, after session or token and before the allowlist entry runs; 403 with the required role; the
   page asks `GET /api/session` for the role.
3. **`HS_ACTOR`** is set by the web server for every spawned command (`<user>` or `<user> via token <id>`), made safe by `audit_actor`. A test starts a
   change through the web server and finds the person in `hs sys audit`.
4. **Role source.** Three AD groups for domain people (names: D2), the local account is `admin`; cached for the session; tokens re-read hourly; refused
   above `viewer` after one day without a domain controller (ADR 0012 decision 6).
5. **Tokens.** `hs token create|list|revoke` with `sys token ...` rows (a token never creates tokens), format `hn_` + 32 random bytes base64url, sha256
   in a 0600 file under `/var/lib/hs`, expiry 90 days default and 1 year at most, `Authorization: Bearer`, no cookie, no CSRF need. Rate limit per
   token id and per address, on top of the existing address throttle (D4).
6. **Sessions page** narrows "all sessions" to own sessions for non-admins (PLAN-web-auth, parts 2 and 3) in the same function.
7. **Packages.** `role = "viewer|app-manager|admin"` per `[[web.reads]]` and `[[web.changes]]` (default `admin`); the effective rule is the higher of the
   package's and the row's (ADR 0012 decision 9). `ext/<name>` areas take the declared role.

### Q5 Two-factor and single sign-on (#462)

Build on the roles step: a second factor and an identity provider both end in "a session with a user and a role".

- **TOTP** (RFC 6238, SHA-1, 30 s, 6 digits, stdlib only: `hmac` and `struct`; no new dependency). Secret per user in a root-owned 0600 file (D14), shown
  once as an `otpauth://` text and QR (the QR is drawn in the page from the text; no image service). One-time use per time step (a code is accepted once).
  Ten recovery codes, stored as hashes, each usable once. Login becomes two requests: password check, then a short "second factor pending" token that
  carries nothing else and expires in 5 minutes. The throttle of PLAN-web-auth applies to the second step too.
- **Who needs it.** Setting `webTotp = off|admins|everyone` (D15), default `off` so an update never locks anyone out; the first admin enrols from the
  Account page. The local `adminuser` is covered, with the **console reset** `hs web totp reset <user>` (root only, typed user name, audit line) as the
  way back in (D16).
- **OpenID Connect** as a second sign-in method: authorization code flow with PKCE, one provider configured by issuer URL, client id and secret (the
  secret through `scripts/lib/secret.sh`, never argv or environment), role from a configured claim or group list, else `viewer` (D18). The redirect URL must
  be on the private interface or a TLS route; **the web interface never gets a public route** (CLAUDE.md rule), so OIDC works for people on the LAN or the
  VPN, not from the open internet. Password sign-in stays on; turning it off needs a typed word and keeps the local account (D19).
- **Order.** The security review (#433) settles the threat model first. This plan can be built without it, but TOTP and OIDC must not ship before it ends.

## Steps

Sizes: S up to a day, M two to three days, L a week. Every step adds its tests, `bash -n` for touched scripts, `scripts/dev/t quick <names>`,
`python3 scripts/pkg.py validate` for manifests, German help text, a changelog entry when users see it, for every new `sys` row
`python3 scripts/openapi-gen.py write` and `python3 scripts/openapi-ts-gen.py write` in the same commit and a smoke probe for each read,
`python3 scripts/schema-gen.py write` after a schema change (never edit the generated files). Output only through scripts/lib/ui.sh. Security
steps: no secret through argv or environment, tests with fakes (no real domain controller), refusals tested as much as successes.

| # | Size | Step | Files | Needs | Done when |
| --- | --- | --- | --- | --- | --- |
| 1 | M | **#197 a** manifest keys `protocol = [1]`, per-row `timeout`, `[service]` table: parse and validate | scripts/pkg.py, scripts/hs_ext.py, scripts/lib/pkg_*.py, docs/Package-API.md, tests/ext.sh, tests/pkg-validate | D9 | validate refuses a bad table; an old manifest unchanged |
| 2 | M | **#197 b** dispatcher runs protocol rows through `ext_proto.py`, renders `data` to TSV/text; a demo package in the extensions repository | scripts/hs, scripts/lib/registry-load.sh, scripts/lib/ext_proto.py, tests/ext-proto.sh, extensions repo | 1 | a fixture protocol row prints the same bytes as its shell twin; a timeout stops the group |
| 3 | S | Web job cancel sends SIGTERM to the process group (ADR 0010 rule 7); verify first | scripts/lib/job.sh (or the job module), tests | 2 | a fixture job that traps SIGTERM writes `cancelled` |
| 4 | M | **#197 c** service unit `hs-ext-svc@.service`, `hs ext svc-run\|status\|start\|stop`, `sys ext status`, kind `ext.service-failed` | configuration.nix, scripts/ext.sh, scripts/lib/ext_service.py, scripts/lib/event-kinds.tsv, registry.tsv, docs/events.md (generated), tests/ext-service.sh | 1 | the fixture service runs under a fake supervisor; failing five times in ten minutes emits one event |
| 5 | M | **#197 d** event delivery with cursor, snapshots as live topics, emit rate limit | scripts/lib/ext_service.py, scripts/live-collect.py, scripts/hs_ext.py, tests | 4 | kill and restart redelivers the unacked event once; a 51st emit is dropped with a warning |
| 6 | M | Convert `ad-selfservice` to a `[service]` extension (replaces its boot row); keep its behaviour | extensions repo (ad-selfservice), docs | 4, 5 | its tests pass; `hs ext status` shows it |
| 7 | M | **#197 e** SDK: shell and Python helpers, Go example, `hs create package --template=extension`, guide `docs/extensions-sdk.md` | scripts/create-package.sh (or the existing `hs create`), packages/, docs/, tests/ext-sdk-*.sh | 2, D3 | the three examples run in tests |
| 8 | S | **#239 a** `permissions` required by `repo-check`; audit of recipes and extensions; warning for undeclared packages | scripts/pkg.py, scripts/lib/pkg_perms.py, recipes and extensions repositories (one PR each), tests/pkg-perms.sh | D5 | the CI of both repositories declares every package |
| 9 | M | **#239 b** `events.emit` enforced per call (`event` messages and `hs event emit --pkg`) | scripts/event-emit.sh (or the emit path), scripts/lib/ext_service.py, tests | 4, 8 | an emit outside the declaration is dropped and warned once |
| 10 | M | **#239 c** systemd confinement of services from `permissions` (fs, devices; `net` declared only) | configuration.nix (the template unit), scripts/ext.sh (drop-in writer), tests, ADR 0014 note | 4, D6 | a service cannot write outside `fs.write` in a nested VM run |
| 11 | S | **#239 d** commands: opt-in confinement `confine = true` per row (D7) and the honest wording in install and update prompts | scripts/lib/ext_proto.py (wrapper), docs, tests | 10, D7 | a confined fixture command fails to write outside its paths |
| 12 | M | **#313 a** audit of #378 against the acceptance boxes; finish core: level lookup, rules loader, catalogue "when installed", both forms accepted | scripts/state-db.py, scripts/event-notify.py, scripts/lib/pkg_events.py, scripts/events-doc-gen.py, docs/events.md, tests | none | each box of the issue ticked or a test added |
| 13 | M | **#313 b** recipes: `[[events]]` in sonarr, radarr, sabnzbd, maintainerr; `hs-media-notify.py` only emits; core drops the old kinds one release later | recipes repository, scripts/lib/event-kinds.tsv | 12, 8 | recipe tests pass against the core; core kinds list has no `pkg.` media kinds |
| 13a | M | **#926** manifest block `[integrations.media]` for media recipes: an extension lists installed media apps (radarr, sonarr, jellyfin, sabnzbd) and gets their local API key as a scoped credential through `scripts/lib/secret.sh` (never argv or environment). Parse and validate in `pkg validate`, then the four recipes declare it. **Not built yet.** | scripts/pkg.py, scripts/lib/pkg_*.py, scripts/hs_ext.py (listing and scoped credential), docs/Package-API.md, tests/pkg-validate (or tests/pkg.sh), tests/ext-sdk-*.sh, recipes repository (radarr, sonarr, jellyfin, sabnzbd; one PR) | 13, 8 | validate refuses a bad block and accepts the four recipes; an extension fixture lists installed media apps and reads a key without it appearing in argv or the environment |
| 13b | M | **#927** event retention classes: each declared `[[events]]` entry carries `retention = "ephemeral\|audit\|metric"` (required, validated); housekeeping prunes by class; rollup helper for extensions (upsert by month, user, kind, documented in the SDK). **Not built yet; waiting for the store decision in #481**, because the rollup table and the pruning live in whatever store #481 picks. Part of #917 (1.0 showcase). | scripts/lib/pkg_events.py, scripts/pkg.py, scripts/state-db.py (or the store #481 names), scripts/event-notify.py, housekeeping script, scripts/lib/event-kinds.tsv, docs/events.md (generated), docs/extensions-sdk.md, SDK helpers (step 7), tests/pkg-events.sh, tests/state-db.sh | 12, #481 | an event without a class is refused by validate; housekeeping drops each class on its own schedule in a fake clock; the rollup helper upserts by (month, user, kind); a test with 5 years of fake data stays small |
| 14 | M | **#434 a** regenerate the roles table for 279 rows; role field in `sys.toml`, generator, `x-hs-role`, ts types, tests (admin default, no viewer change) | docs/api/sys.toml, scripts/openapi-gen.py, scripts/openapi-ts-gen.py, docs/adr/0012-roles-sys-rows.tsv, web/src/api/sys.gen.d.ts, tests/openapi.sh | D1 | a new row without a decision fails CI |
| 15 | L | **#434 b** the check in web-serve.py, role from groups, `HS_ACTOR`, `GET /api/session` role, 403 body; `hs users` creates the three groups (security) | scripts/web-serve.py, scripts/users.sh, scripts/lib/audit.sh, tests/web-login-test.py, tests/web-roles-test.py (new) | 14, D2 | a viewer, an app-manager and an admin session each get exactly the allowlisted calls; the audit line names the person |
| 16 | M | **#434 c** role-aware web interface: hide what a role cannot use, Sessions page own-only for non-admins | web/src/**, web tests | 15 | fixture sessions per role show the right pages |
| 17 | L | **#434 d** `hs token create\|list\|revoke`, `sys token ...` rows, Bearer handling, hourly owner re-check, rate limit, web page (security) | scripts/token.sh (new), scripts/web-serve.py, registry.tsv, sys.toml, web/src/pages/Tokens.svelte, tests | 15, D4 | a token never exceeds its owner's role; a disabled owner kills it within the hour in a fake clock |
| 18 | M | **#434 e** package roles: `role` per `[[web.reads]]`/`[[web.changes]]`, effective = higher of both; validate; page declaration | scripts/hs_ext.py, scripts/pkg.py, web-serve.py (ext part), docs/PLAN-extensions.md, tests/web-ext-test.py | 15, 8 | an extension read marked admin is 403 for a viewer |
| 19 | L | **#462 a** TOTP: enrolment, two-step login, recovery codes, `webTotp`, `hs web totp reset` (security) | scripts/web-serve.py, scripts/lib/totp.py (new), scripts/web-totp.sh (new), config/schema.toml (+ generated), registry.tsv, web login page and Account page, tests/web-totp-test.py | 15, D14 to D16, #433 | RFC 6238 test vectors pass; a replayed code is refused; reset restores sign-in |
| 20 | L | **#462 b** OpenID Connect: provider setup (`hs web sso set\|show\|off`), code flow with PKCE, role mapping, login button, local account kept (security) | scripts/web-serve.py, scripts/lib/oidc.py (new), scripts/web-sso.sh (new), registry.tsv, sys.toml, web, tests with a fake provider | 19, D17 to D19, #433 | a fake provider signs in a viewer and an admin; a bad state, nonce or signature is refused |
| 21 | S | Docs: new guide `docs/extensions.md` (SDK, protocol, permissions, events), `web-interface.md` (roles, tokens, TOTP, SSO), `operations.md` (lost second factor), `docs/Package-API.md`, ADR 0012 and 0014 status lines, changelog | docs/ | 1 to 20 | tests/docs.sh green |
| 22 | S | Hardware and VM test (table below); tick the issues' "Hardware test" boxes with what was seen | the issues | all | "Not tested on hardware yet." removed only for what was seen |

Parallel lanes after the decisions: **A protocol** (1, 2, 3, then 4, 5, 6, 7), **B permissions** (8 first, then 9 after 4, then 10, 11), **C events** (12, 13, then 13a and 13b; 12 and 13 are independent
of everything else; 13b waits for #481), **D roles** (14, 15, then 16, 17, 18), **E sign-in** (19, 20 after 15). Shared files: 15, 17, 19 and 20 all edit
`scripts/web-serve.py` and `tests/web-login-test.py`, and 18 edits its extension part: they merge one at a time (15, 17, 18, 19, 20), and the
lane E steps rebase after each of them; 1, 4, 9 and 18 touch `scripts/pkg.py` or `scripts/hs_ext.py`; 4, 10 edit `configuration.nix`; 14, 17, 20 and 4 add
`sys` rows, so openapi.json and sys.gen.d.ts are **regenerated on every rebase, never merged by hand**; 19 changes `config/schema.toml` (regenerate
after each rebase). 8 and 13 are PRs in other repositories (recipes, extensions): they merge after the core step they depend on, because CI runs the
recipes' tests against the core. Step 22 comes last.

## Design alignment

Checked against docs/PLAN-web-design.md (sections 4.9, 6 and 7) on 2026-11-18. The design record is a draft; where it and this plan meet, this is how they fit. Nothing here was run; Not tested on hardware yet.

1. **Roles in the web follow behaviour 4.9.** An action the user may not start is shown disabled with the reason; the server still enforces the role (step 15), the web only explains. A viewer sees every page without a plan. The merged step 16 hides what a role cannot use, so a new step **16b** changes it: disabled with a reason instead of hidden, and no page is dropped for a viewer.
2. **Package roles.** This plan puts `role` on each `[[web.reads]]` and `[[web.changes]]` entry (D13, step 18). The design (7.3, issue #790, milestone 0.12) puts `role` on the page and on each `[[web.page.actions]]`, default admin. Rule: the effective role of an action is the higher of the action's or the page's role and the role of the read or change it calls, so the new keys can only raise it. Step 18 stays as planned.
3. **Placement.** The Tokens page (step 17), and the two-factor and SSO settings (steps 19 and 20), live under Settings > Users and access (6.1; the design marks these pages as inferred). The login page is outside the page templates (G5) and uses the shared `Field` and `TextInput` components. A package or service page lands in Apps when it names no group (7.4). One renderer, `GenericPage`, serves #424, #478 and #195 (G7).
4. **#776** (thin slice of a disk page) waits for 0.4 and 0.8 to leave the Disks page free. 0.8 does not touch the Disks page.
5. **Trust labels** (Official, Community, tested date) are derived by the core from the repository and the index, not a manifest key (7.3). No 0.8 work.

## What only runs on hardware (or in the nested VM)

| Step | What to look at on a real server or in the nested VM |
| --- | --- |
| 2, 3 | a protocol extension in a container-free host call; Ctrl-C and the web "stop" reach the process; a hung command ends at its timeout |
| 4, 5, 6 | a service starts at boot (`hs-ext-boot` and the template unit), is restarted after `kill -9`, `hs ext stop` survives a reboot; `ad-selfservice` still changes a real domain password |
| 10, 11 | a confined service cannot write outside its paths on NixOS (systemd properties are version-dependent); `incus` from a confined command fails as declared |
| 15, 16, 17 | three real domain users in the three groups sign in and see what their role sees; a viewer's POST gets 403; a token from a script (`curl`) works, expires, dies when the user is disabled in AD; DC down: local account and viewer tokens work, higher tokens refused after a day (fake clock first) |
| 19 | a real authenticator app (two apps), clock drift of a minute, recovery code, `hs web totp reset` over SSH |
| 20 | one real provider (for example a self-hosted Keycloak or Authentik in an Incus container, then a public one); group claim mapping; sign in over the LAN and over Tailscale |
| 13 | a real Sonarr/Radarr event reaches the notification channel with the new declarations |
| 13a | an extension on a real server lists the installed media apps and reads a key that works against the app's API (Not tested on hardware yet.) |
| 13b | housekeeping prunes a real state store by class after weeks of events (Not tested on hardware yet.) |

Everything else is checked by tests with fakes (`t quick`) and, for units, in the nested VM (`t vm`, ADR 0023).

## Risks

- **Locking everyone out.** Roles, TOTP and OIDC can leave nobody able to sign in. Mitigation: the local account is always `admin`, never needs TOTP unless
  an admin turned it on for it, and `hs web totp reset` and the existing `hs web unlock-login` work from a root shell; `webTotp` defaults to `off`;
  OIDC never replaces the password without a typed word.
- **Roles are enforced only in the web server.** `sudo hs` stays unlimited (ADR 0012 consequences). The docs say so; a "viewer" is not safe against someone
  with a shell.
- **A wrong role on one row is a privilege hole.** Mitigation: default `admin`, the CI test, the generated file reviewed by the owner (D1), and tests per
  role (the issue's last box) that call every `sys` row as every role against the allowlist.
- **Domain-controller outages.** Roles come from AD groups; the cache rule and the day limit are decided in ADR 0012; tested with a fake DC.
- **Tokens are bearer secrets.** Mitigation: shown once, hashed, expiry required, role capped at the owner's, no token management by tokens, rate limit,
  audit line with the token id, never the token.
- **systemd confinement breaks a service that calls `incus` or writes `/etc/hs`.** Mitigation: it applies to services only; a service declares `host:incus`
  and gets the socket path read-write; the nested-VM run before it ships; undeclared packages stay unconfined.
- **Requiring `permissions` breaks third-party packages.** Mitigation: a warning for one release, the CI of the two repositories fails first (D5).
- **OIDC adds an outbound call and a parser of tokens to a root-adjacent process.** Mitigation: one small module, signature and `nonce` checks, a fixed
  clock skew, only RS256/ES256, no `none`; no public route (CLAUDE.md); a review by the security issue first.
- **Two ways to write a command** (shell and protocol) double the tests. Mitigation: the demo package and the dispatcher test run both; the shell contract
  is frozen.
- **Machine-readable contracts.** No existing `sys` row changes shape; new facts get new rows (`sys ext status`, `sys token list`, `sys web sso`).

## Naming

`hn` is the future command and prefix (a rename milestone, `hs` to `hn`, is planned later; `hs` stays as an alias). Names that live in the domain, on user disks or in token strings carry the final prefix now: the AD groups `hn-viewers` and `hn-app-managers`, and any visible token prefix `hn_`. Paths under `/var/lib/hs`, unit names and `hs` commands stay as they are and move together in the rename milestone.

## Decisions for the owner

All Accepted by the owner on 2026-11-18. The accepted answer is the "Proposed" column, except D2 (changed, see its row). The recommended option is first in each Options cell. "Hard to change later" says what a wrong choice costs after release.

| Id | Question | Options | Proposed | Hard to change later |
| --- | --- | --- | --- | --- |
| D1 | ADR 0012 status (#434) | confirm Accepted and settle the open points below in the ADR text; keep as is; rework | **Accepted 2026-11-18:** Confirm, record the answers to D2 and D4 in the ADR, regenerate the rows table | Medium: the role per row is a promise to scripts |
| D2 | Names of the AD groups | `hs-viewers`, `hs-app-managers`, Domain Admins; configurable names in machine.toml (default the same); prefix `hobnix-` | **Accepted 2026-11-18, changed:** configurable in machine.toml, defaults `hn-viewers` and `hn-app-managers` + Domain Admins (see Naming); `hs users` creates them only after a plan and a typed name, never into an existing domain without asking | Medium: group names live in the domain |
| D3 | SDK languages | Rust (done) + shell + Python helpers + Go example; Rust only; a Go library too | **Accepted 2026-11-18:** Rust, shell, Python helpers; Go as an example | Low |
| D4 | Token rate limit and lockout | per token id (60 failures a minute locks the id 5 min) + per address; only per address; none | **Accepted 2026-11-18:** Both, on top of the existing address throttle | Low |
| D5 | `permissions` required? | required for packages in a repository (CI fails), warning at install for older ones; always optional; required at once | **Accepted 2026-11-18:** Required in CI, warning in `hs` for one release, then refuse to enable | Medium: third-party manifests |
| D6 | Meaning of `net = lan\|internet` | declared only; systemd `IPAddressAllow` for services; firewall rule per service | **Accepted 2026-11-18:** Declared only in 0.8; the owner decides the firewall meaning later (touches network and firewall) | Medium |
| D7 | Confining commands (ADR 0014 steps 2/3) | opt-in `confine = true` with `systemd-run`; none until a broker exists; broker + unprivileged user now | **Accepted 2026-11-18:** Opt-in confinement, documented as partial; broker only if third-party packages become a goal (also ADR 0015 trigger a) | High: it decides what a package may ever do |
| D8 | Per-call check of `events.emit` | enforce at the core on every emit; manifest only (today) | **Accepted 2026-11-18:** Enforce on every emit | Low |
| D9 | When may a manifest use `protocol = [1]` | any package after step 1; only packages that raise `requires_core`/api level; behind a setting | **Accepted 2026-11-18:** Any package that requires api level >= the one step 2 bumps (`scripts/lib/api-level`, now 9) | Medium: api level is a promise |
| D10 | Service state names and unit shape (ADR 0011) | as in the ADR; add `paused`; | **Accepted 2026-11-18:** As in the ADR | Medium |
| D11 | Service restart policy | the ADR's `Restart=on-failure`, 5 starts in 10 minutes; unlimited with backoff | **Accepted 2026-11-18:** The ADR's | Low |
| D12 | Event cursor storage | files in `/var/lib/hs/ext-cursors/<name>` (the ADR); rows in state.db | **Accepted 2026-11-18:** Files | Medium |
| D13 | Role of a package read or change | `role` per entry (default admin); one role per package; none | **Accepted 2026-11-18:** Per entry, default admin | High: it is a manifest format (public) |
| D14 | TOTP secret storage | root-owned 0600 file per user in `/var/lib/hs/web-totp/`; sealed in the vault (needs unlock after boot); in the session file | **Accepted 2026-11-18:** The 0600 file: the vault is locked after boot and the local account needs the page then | High: a stored secret format |
| D15 | Who must use a second factor | setting `webTotp = off\|admins\|everyone`, default off; always for admins; per user | **Accepted 2026-11-18:** The setting, default off | Low |
| D16 | Lost second factor | `hs web totp reset <user>` as root over SSH or the console, typed user name, audit line; recovery codes only; a second admin may reset | **Accepted 2026-11-18:** Reset command + recovery codes; no web reset by another admin | Medium |
| D17 | SSO scope | OpenID Connect only, one provider; OIDC plus SAML; a bundled provider package | **Accepted 2026-11-18:** One OIDC provider, authorization code with PKCE | Medium |
| D18 | Role from SSO | a configured claim or group list per role, else `viewer`; every SSO user is admin; role chosen by an admin per user | **Accepted 2026-11-18:** Claim/group mapping, else `viewer` (least privilege) | High |
| D19 | Password sign-in after SSO | stays on; may be switched off with a typed word, local account always kept; forced off | **Accepted 2026-11-18:** Stays on; may be switched off, local account kept | Medium |
| D20 | Security review (#433) as a gate | steps 19 and 20 wait for it; build and merge to `0.8` without releasing; no gate | **Accepted 2026-11-18:** Build now, release 0.8 only after #433 ends | Low |

## Check that it worked

- A protocol fixture extension answers through `hs ext demo ping` and `hs sys ext demo ping` with the bytes of its shell twin; a service fixture
  shows `running` in `hs ext status`, is restarted after a kill, redelivers an unacknowledged event once and its 51st emit in a minute is dropped.
- A package without `permissions` shows "not declared" and a warning; one whose `[[events]]` are not covered is refused at `hs ext enable`; an emit of a
  kind outside `events.emit` is dropped with a warning.
- `hs event kinds` lists the media events as "when installed" from the recipes' manifests; the core `event-kinds.tsv` has no media kind; the recipes'
  tests pass against the core.
- Every `sys` row has a role in `openapi.json`; a viewer, an app-manager and an admin session each run exactly their rows (tests per role); a web change
  shows the person in `hs sys audit`.
- `hs token create` shows a token once; with it `curl -H "Authorization: Bearer ..."` reads as the role of its owner, cannot create a token, stops at its
  expiry and when the owner is disabled.
- With `webTotp = admins`, an admin sign-in asks for a code, refuses a replayed one, accepts a recovery code once, and `hs web totp reset adminuser`
  turns it off for that user; a fake OIDC provider signs in a `viewer` and an `admin` and refuses a wrong `state`, `nonce` or signature.
- (Steps 13a and 13b, not built yet.) `pkg validate` refuses a media block or an event retention class it does not know and a declared event without
  one; an extension fixture lists installed media apps and gets a scoped key; housekeeping prunes by class and five years of fake rollup data stay small.
