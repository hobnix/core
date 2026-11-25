# 0014: Extension permissions: declare and disclose first, confine services next

Status: Accepted (2026-11-10): declare and disclose (step 1 and 1b, built in hobnix/server#239). Step 2 (confining services) and step 3 (a command broker) are not decided; open points 2 and 3 stay open until third-party packages are a goal.
Update 2026-11-18 (implemented in 0.8, not tested on hardware yet): `permissions` is required by the repository check; `events.emit` is enforced on every emit; services are confined by a systemd drop-in from `fs.*` and `devices`; a command row with `confine` runs through `systemd-run`; `net` stays declared only; there is no broker. Guide: docs/extensions.md. The owner accepted D5 to D8 of docs/PLAN-extensions-access.md (permissions required in CI; `net` declared only; opt-in confinement of commands; `events.emit` enforced on every emit); steps 2 and 3 follow that plan.
Step 1 as built: `permissions = [...]` in package.toml (optional for now: absent shows as "not declared"), vocabulary and checks in scripts/lib/pkg_perms.py, validated by `pkg.py validate`, `repo-check` and at install; shown by `hs ext list`, `hs pkg install|update`; new permissions in an update need the typed package name or `--accept-permissions`. A declared permission is NOT a sandbox: commands run as root.
Step 1b (#239): the declaration is enforced against the manifest at run time. `hs_ext.ext_declarations` (web reads, changes, pages, live topics) skips a package whose `permissions` do not cover what its manifests use, and `hs ext enable` refuses it (`pkg.py perms-check`); a package without `permissions` is not checked. Not tested on hardware yet.
Issue: hobnix/server#239 (epic #197). Related: ADR 0010 (command protocol, #237), ADR 0011 (service lifecycle, #238); both Proposed in their own pull requests.

This record writes down the options and a recommendation. It does not enforce anything: no manifest declares a permission today, and no
document decides on a sandbox, so enforcement would mean inventing both the vocabulary and the mechanism (and `net` is a network and firewall
decision, which the owner takes).

## Context (checked 2026-11-07 on develop)
- package.toml / capability.toml declare NO permission list. The fields that look like one: `needs` (docker, share, tailscale) and `uses` (gpu)
  of recipes (scripts/pkg.py: NEEDS, USES) are *requirements the recipe installs or asks for*, checked against the run.sh header, not a grant
  that anything enforces. Extensions declare `requires`, `provides`, `extension`, `nix`, `[[web.reads]]`, `[[web.changes]]`, `[web.page]`, `[[events]]`.
- Already enforced (by loaders, tested): the namespace of command rows, scripts only under scripts/ or the package folder, no `legacy:` rows,
  web calls only through the declared reads/changes allowlist, page blocks only over declared reads, event kinds only `pkg.<name>.*`.
- docs/PLAN-extensions.md "Security" states the decision of record: every command runs as root, installing a package is trusting its author,
  trust comes from signed tags and the diff shown by `hs pkg update` (ADR 0008 rules 5 and 6). No sandbox decision exists in any PLAN or ADR.
- ADR 0010 (#237) and 0011 (#238) add two more things a package does that need a policy: a service process, and `emit` of event kinds.

So there is no declared permission the core could enforce today other than what it already enforces. Enforcing more means first inventing the
vocabulary and picking a mechanism; the mechanism decides what a package can do (files, network, host commands), which the task says not to
guess when it touches network or storage. Hence: proposal only.

## Decision options

### A permission vocabulary (draft, for the owner to cut down)
| Key | Meaning | Today |
| --- | --- | --- |
| `web.read` / `web.change` | the declared reads and changes | enforced by web-serve.py |
| `events.emit = [kinds]` | kinds the package may write | kinds are prefix-checked, not per call |
| `events.subscribe = [globs]` | event kinds a service receives (ADR 0010) | specified |
| `fs.write = [paths]` | paths below /var/lib/hs/ext/<name>, /etc/hs/..., a share | none |
| `fs.read = [paths]` | same, read only | none |
| `net = none/lan/internet` | outgoing connections | none (touches network: owner) |
| `host = [commands]` | `hs` commands or system tools it may call (incus, systemctl, ...) | none |
| `secrets = [names]` | secrets read through scripts/lib/secret.sh | none |
| `devices = [gpu, ...]` | devices | `uses` of recipes |

### Mechanisms
1. **Declare and disclose (no enforcement).** `permissions = [...]` is required in the manifest, validated by `pkg.py validate`, shown by `hs ext list`,
   `hs pkg install` and in the diff of `hs pkg update` (a new permission is highlighted and needs the typed name). Cheap, honest about being trust,
   and the prerequisite of everything else. It does not stop a malicious package.
2. **systemd confinement for services and jobs.** A service (ADR 0010) already runs as a unit, so `ProtectSystem=strict`, `ReadWritePaths=` from `fs.write`,
   `PrivateNetwork=` or `IPAddressAllow=` from `net`, `NoNewPrivileges`, `PrivateDevices` follow from the manifest with no new code. Commands run through
   `hs` as root; they could be wrapped by `systemd-run --pipe --wait -p ...` with the same properties. Enforces fs and net for real, but:
   `net` properties (IPAddressAllow, PrivateNetwork) are a network and firewall decision, and a root process can undo most of it unless the unit
   drops root (`User=` or DynamicUser), which breaks packages that call `incus` (needs the socket) or write /etc/hs.
3. **Unprivileged user per package plus a command broker.** The package runs as `ext-hs-<name>` and asks the core for privileged things through a
   request channel (the "open point" of ADRs 0009 and 0010), which checks `host`, `secrets` and `events.emit` against the manifest. This is the only
   design that enforces `host` and `secrets`; it is also a rewrite of every package that today calls hs commands directly (games, posters,
   ad-selfservice, passthrough, arr) and of the shell contract.
4. **Do nothing beyond what is enforced** and say so on the install prompt (current state).

## Recommendation (the decision this record proposes)
Step 1 now (declare, validate, disclose, show in the update diff); step 2 for services only, as part of the ADR 0010 unit, once the owner has decided
what `net` may mean (it is the firewall's business); step 3 only if third-party packages become a goal, since it needs the broker and a migration.
Do not claim enforcement for commands until step 3: root commands can read any file the manifest does not list.

## Consequences (if the recommendation is accepted)

- Step 1 is a small change (a manifest key, `pkg.py validate`, text in `hs ext list`, `hs pkg install` and the update diff) and can be a follow-up issue.
- Packages stay root-trusted until step 3; documentation must say so, and must not call a declared permission "enforced".
- Step 2 changes configuration.nix (the unit of ADR 0011) and needs a hardware run: "Not tested on hardware yet".

## Open points (decisions needed from the owner)
1. Is "trust the author, show what they ask for" (step 1) enough for v1, or must commands be confined too?
2. What may `net = lan|internet` mean, and who enforces it (unit properties vs the firewall)? (touches network, firewall)
3. May a package ever run as non-root (needs the broker)?

## Step 2 as built: confinement of services (2026-11-18, docs/PLAN-extensions-access.md step 10, #239 c)
Update 2026-11-23 (#1130, found by reading the code, not run): the first build put the whole unit `hs-ext-svc@<name>` in the sandbox. That unit is the
bridge (scripts/lib/ext_service.py), which writes `state.db` (emit), the snapshots and the cursors under `/var/lib/hs` and reads the package folder, so a
service could not emit, roll up, read an integration key or even start under the empty `/var/lib/hs`. Now the unit `hs-ext-svc@<name>` is NOT sandboxed
(configuration.nix) and the bridge starts the service as the transient unit `hs-ext-run-<name>` with `systemd-run --pipe --wait`, with the properties below
(the same mapping as a confined command, `ext_service.py confined_program`). `hs ext start|enable` only checks the permissions (a path that is relative, has
`..`, `.` or `//`, or is `/` is refused and the service is not started) and removes a drop-in of an older version. What reaches the confined service:

- its own package folder when it lies below `/var/lib/hs` (`BindReadOnlyPaths`); a package folder below `/etc/nixos` is hidden by `InaccessiblePaths` (open point);
- the key of every `integration:<name>` it declared, as one systemd credential per providing package, `integration-<name>-<provider>` (hobnix/core#1135: the provider is the `package` column of `hs pkg integrations`, so a service picks the key of a row without guessing; a provider without a `key_file` gives none; the old one-name `integration-<name>` for the first keyed provider stays for one release, deprecated) (`LoadCredential=`, read by systemd as root, so it needs no
  mount): in `$CREDENTIALS_DIRECTORY`, never argv or environment, `/var/lib/hs` stays hidden. `hs ext svc-run` names the files through `integration_credentials`
  (scripts/lib/integration.sh: the declared check of `pkg.py integration-key` and `secret_state`; a locked or missing key is skipped with a warning);
- only a key file below `/var/lib/hs/<providing package>/` (no `..`, no link out of that folder, the caller is not the provider, the provider name is not a core folder: `RESERVED` in
  `pkg_integrations.py`, the one list): `pkg_integrations.key_file_problem` is used by the validator, `grant` (so `integration_key`) and the bridge. The providing package is the registered one
  (`pkg.py integration-grants`, one line per keyed provider; each goes through the same strict path), not read from the path. The file must be a regular file; no link is allowed except one to exactly the vault file that `secret.sh` designates for that path (`pkg_integrations.designated`: `<vault>/secrets/<path below /var/lib/hs>`, what `secret_prepare` creates), never to another vault file.
  systemd reads a credential as root, and a check before `systemd-run` could be raced by a link swap, so the bridge does not give systemd the original path: `read_key` opens it ONCE without following a link,
  checks the open descriptor (regular, not world writable, at most 64 KiB, `/proc/self/fd` still inside the provider's folder or the vault) and the bridge writes a private 0600 copy in a 0700
  folder below `/run/hs-ext-cred/<name>` (parent 0700 too); `LoadCredential=` reads that copy, and the folder is removed as soon as the service is `running` (systemd has loaded it), at the end, and by a sweep at the next bridge start. Because the service runs as root, `/run/hs-ext-cred` and `/var/lib/hs-vault` are in `InaccessiblePaths` of the transient unit (`SECRET` in ext_confine.py); the unit sees only its own credential in `$CREDENTIALS_DIRECTORY`. Running services as an unprivileged user instead is #1134. A package whose name is not its folder name, or a second package with the same name, is ignored (`pkg.py manifests`), and core folder names (`RESERVED`, tested against the code) cannot be providers. (An fd path `/proc/self/fd/N` was not chosen: it would not survive into the transient unit.)
- the transient unit is bound to the bridge unit (`BindsTo=`), stopped before a start and at the end, has a `TimeoutStopSec` and the PATH of the bridge (`--setenv`);
- `state.db` writes only through service messages handled by the bridge: `emit` (kind covered by `events.emit`) and `rollup` (ADR 0011: only a kind of the
  package that its `[[events]]` declare with `retention = "metric"`); no mount of `/var/lib/hs`. Reading `state.db` or `hs sys state ...` from the service is not possible.

| From the package | systemd property |
| --- | --- |
| always | `ProtectSystem=strict`, `ProtectHome=yes`, `PrivateTmp=yes`, `NoNewPrivileges=yes`, `CapabilityBoundingSet=` (none), `PrivateDevices=yes`, `ReadWritePaths=-/var/lib/hs/ext-svc` |
| always (hardening, ADR 0031 decision 5) | `ProtectKernelTunables`, `ProtectKernelModules`, `ProtectKernelLogs`, `ProtectControlGroups`, `ProtectClock`, `ProtectHostname`, `RestrictNamespaces`, `RestrictRealtime`, `RestrictSUIDSGID`, `LockPersonality` (all `yes`), `SystemCallArchitectures=native`, `SystemCallFilter=~@mount @swap @reboot @module @raw-io @cpu-emulation @debug @obsolete` with `SystemCallErrorNumber=EPERM`, `RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK` (unix sockets and the network stay: `net` is not filtered, no `IPAddressAllow`; netlink for `ip` and `hs` tools). Not set, because a violation is invisible before a hardware run: the allow list `SystemCallFilter=@system-service` (a call outside it kills the process with SIGSYS and no message), `ProtectProc=invisible` and `ProcSubset=pid` (`hs` and tools read /proc), `MemoryDenyWriteExecute` (Python). Riskiest of the set: `RestrictNamespaces` and the syscall filter; the hardware test runs a real service and a confined command. |
| `fs.write:<path>` | `ReadWritePaths=-<path>` (and nothing else is writable) |
| `fs.read:<path>` | `ReadOnlyPaths=-<path>` |
| `devices:gpu` | `PrivateDevices=no`, `DevicePolicy=closed`, `DeviceAllow=char-drm rw` |
| `net:<x>` | nothing: declared only (D6); a comment in the drop-in |
| dynamic user (`ext_confine.properties(..., dynamic=True)`, `--dynamic`; every extension service, #1134. Not tested on hardware yet) | `DynamicUser=yes`, `User=hsx-<name>` (at most 31 characters), `StateDirectory=ext-hs/<name>`, `StateDirectoryMode=0700`, `UMask=0077`, `BindPaths=-/var/lib/ext-hs/<name>:/var/lib/hs/<name>` instead of the bridge state; `devices:gpu` adds `SupplementaryGroups=render video` |
| dynamic user, `fs.read:<path>` of server state or of another extension | refused with `ext.dynamic-read` |
| dynamic user, `fs.write:<path>` | only below `/var/lib/hs/<name>` (no line: the state bind covers it); anything else is refused with `ext.dynamic-write` |
| no `permissions` | the "always" row only, plus a warning |

What it does NOT cover (say so wherever confinement is mentioned): the file system stays readable (for a service, which runs as its own user `hsx-<name>` since #1134, as far as the file modes allow; Not tested on hardware yet) except the secret locations
(since #947: `/var/lib/hs` is an empty tmpfs apart from the granted `ext`, `ext-svc` and own-name (`/var/lib/hs/<package>`) state, `/root`, `/etc/shadow`, `/etc/gshadow`, `/etc/ssh` and `/etc/nixos` are inaccessible, and an `fs.read` or `fs.write` that overlaps them, or an `fs.write` below `/etc`, `/boot` or `/nix`, is refused; everything else is only read only); the network is open whatever `net` says; `host`, `secrets`
and `events.*` are not systemd's business; no host socket is hidden (a service reaches what its user may open); the `ext.service-failed`
event is written by the bridge, which is no longer confined (#1130). Commands are not confined unless a row opts in (below). Not tested on hardware yet: the units are only evaluated in CI (#1130: the transient unit, `LoadCredential` and the stop of the transient unit by the bridge were not run),
the VM stage `confine` (scripts/dev/nested_stages.py) is written but has not been run.

## Step 3 as built: opt-in confinement of commands (2026-11-18, docs/PLAN-extensions-access.md step 11, #239 d)
A row of `commands.tsv` with the flag `confine` is run by the dispatcher (scripts/lib/ext_proto.py) through `systemd-run --pipe --wait` with the
same properties as a service (`ext_confine.properties`, one mapping). Since #1134 that is the dynamic mapping above: the command runs as `hsx-<name>`, not
as root, writes only `/var/lib/hs/<name>`, and the state folder is prepared first like for a service (a problem: exit 69, no run). It needs `protocol = [1]` and `permissions` (validated in scripts/lib/pkg_protocol.py);
at run time no `systemd-run`, no `permissions` or a bad path means exit 69 and no run. The install and update prompts print what it covers and what it
does not (reads as far as the file modes allow, network, `hs`/`incus`/`systemctl` are not blocked). Other commands stay root and unconfined; a broker stays undecided (D7). Not tested on
hardware yet: the real `systemd-run` was not run, and whether SIGTERM to the runner stops the transient unit (cancel, timeout) is unverified.
