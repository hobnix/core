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
3. **Unprivileged user per package plus a command broker.** The package runs as `hs-ext-<name>` and asks the core for privileged things through a
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
`hs ext start|enable` writes `/run/systemd/system/hs-ext-svc@<name>.service.d/10-confine.conf` (scripts/ext.sh `svc_confine`, text made by
scripts/lib/ext_confine.py) and runs `daemon-reload`; the template unit in configuration.nix carries the same strict floor, so a unit started
without its drop-in is still strict. A path that is relative, has `..`, `.` or `//`, or is `/` is refused and the service is not started.

| From the package | systemd property |
| --- | --- |
| always | `ProtectSystem=strict`, `ProtectHome=yes`, `PrivateTmp=yes`, `NoNewPrivileges=yes`, `CapabilityBoundingSet=` (none), `PrivateDevices=yes`, `ReadWritePaths=-/var/lib/hs/ext-svc` (the bridge's own state) |
| `fs.write:<path>` | `ReadWritePaths=-<path>` (and nothing else is writable) |
| `fs.read:<path>` | `ReadOnlyPaths=-<path>` |
| `devices:gpu` | `PrivateDevices=no`, `DevicePolicy=closed`, `DeviceAllow=char-drm rw` |
| `net:<x>` | nothing: declared only (D6); a comment in the drop-in |
| no `permissions` | the "always" row only, plus a warning |

What it does NOT cover (say so wherever confinement is mentioned): the service still runs as root and the file system stays readable except the secret locations
(since #947: `/var/lib/hs` is an empty tmpfs apart from the granted `ext`, `ext-svc` and own-name (`/var/lib/hs/<package>`) state, `/root`, `/etc/shadow`, `/etc/gshadow`, `/etc/ssh` and `/etc/nixos` are inaccessible, and an `fs.read` or `fs.write` that overlaps them, or an `fs.write` below `/etc`, `/boot` or `/nix`, is refused; everything else is only read only); the network is open whatever `net` says; `host`, `secrets`
and `events.*` are not systemd's business; a service can still reach the `incus` socket and the host's other sockets; the `ext.service-failed`
event is written by the bridge (scripts/lib/ext_service.py) into /var/lib/hs/state.db, which a confined unit may not write, so that event
needs a follow-up (an unconfined `ExecStopPost=+`). Commands are not confined unless a row opts in (below). Not tested on hardware yet: the unit is only evaluated in CI,
the VM stage `confine` (scripts/dev/nested_stages.py) is written but has not been run.

## Step 3 as built: opt-in confinement of commands (2026-11-18, docs/PLAN-extensions-access.md step 11, #239 d)
A row of `commands.tsv` with the flag `confine` is run by the dispatcher (scripts/lib/ext_proto.py) through `systemd-run --pipe --wait` with the
same properties as a service (`ext_confine.properties`, one mapping). It needs `protocol = [1]` and `permissions` (validated in scripts/lib/pkg_protocol.py);
at run time no `systemd-run`, no `permissions` or a bad path means exit 69 and no run. The install and update prompts print what it covers and what it
does not (reads, network, `hs`/`incus`/`systemctl`, secrets). Other commands stay root and unconfined; a broker stays undecided (D7). Not tested on
hardware yet: the real `systemd-run` was not run, and whether SIGTERM to the runner stops the transient unit (cancel, timeout) is unverified.
