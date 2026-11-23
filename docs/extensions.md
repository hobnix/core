# Extensions

Run, check and limit extensions: commands that speak the protocol, services that stay running, the permissions a package declares and what the server enforces of them, and the events it sends. For the person who installs and runs extensions; to write one, see [Write an extension](extensions-sdk.md).

Not tested on hardware yet: everything below was checked by tests with fakes (a fake `systemd-run`, a fake supervisor), not on a real server.

## Before you start

- A running server ([Install](install.md)) and an extension package: `hs pkg` fetches it from a repository ([Containers and apps](containers-and-apps.md)).
- The package asks for API level 10 or newer (`requires_core = ">=10"`) when it uses `protocol` or `[service]`.
- Everything here that changes something needs `sudo`.

## See what is installed

```bash
hs ext list
```

Each extension with its state (on or off), its commands and the permissions it declares (`not declared` when it has none). Declared permissions are not a sandbox for commands: a command runs as root unless its row says `confine` (below).

## Switch an extension on or off

```bash
sudo hs ext enable <package>
```

The package is refused when its manifest uses more than its `permissions` cover (a web read without `web.read`, an `[[events]]` entry without a matching `events.emit`), when `requires` names something that is off, or when `requires_core` is above the API level of the server. `sudo hs ext disable <package>` is the reverse.

## Run a command

```bash
hs ext <package> <command>
```

A package whose manifest says `protocol = [1]` speaks the command protocol: the core starts the program once per call, sends one JSON request on stdin and reads JSON lines back (`progress`, `log`, `event`, then one `result`). The core prints `result.data` as tab-separated lines (an empty cell is `-`), or `result.text` for a person; `hs sys ext <package> <command>` prints only the data. Exit status: 1 the extension said `ok = false`, 124 timeout, 130 cancelled, 70 protocol error, 69 the program did not start. A call ends at its limit (30 s, or the `timeout:<seconds>` flag of its row, at most 3600): SIGTERM, five seconds of grace, then SIGKILL to the whole process group. A package without `protocol` keeps the older shell contract unchanged. The keys are in [Package API](Package-API.md#level-10-milestone-08-protocol-timeout-and-service-keys); the format is [ext-protocol-v1.schema.json](api/ext-protocol-v1.schema.json) and ADR 0010.

## Run a service

A package with a `[service]` table has one process that stays: a collector or an event consumer. One unit per package, `hs-ext-svc@<package>.service`, runs `hs ext svc-run <package>`; you do not call that yourself.

```bash
hs ext status
```

Shows each service that is on: `starting`, `running`, `degraded`, `stopping`, `stopped` or `failed`, why, and since when (`hs sys ext status` is the machine form). The service answers a health check every `health_interval` seconds (default 30); missed answers make it `degraded`.

```bash
sudo hs ext start <package>
```

Starts the service and forgets an earlier failure. `sudo hs ext stop <package>` stops it, and it stays stopped, also after a reboot, until you start it again. A crashed service is restarted by the unit; the fifth failure within ten minutes ends the restarts, sets the state to `failed` and writes one core event, `ext.service-failed` (level error, subject: the package, payload: the last failure code).

## Check what a package may do

Permissions are a list in `package.toml`, such as `fs.write:/srv/data`, `events.emit:pkg.<name>.*`, `net:lan`, `devices:gpu`. What the core really enforces, and what it does not:

| Permission | Enforced? | How |
| --- | --- | --- |
| `events.emit:<glob>` | yes | every `emit` message of a service and every `hs event emit --pkg <name>` is checked against it; a kind outside it is dropped with one warning per kind |
| `web.read`, `web.change` | yes | the web interface skips a package whose reads or changes are not covered |
| `fs.write`, `fs.read`, `devices:gpu` | services, and commands with `confine` | systemd properties (below) |
| `net`, `host`, `secrets`, `events.subscribe` | no | declared and shown only; `net` has no firewall meaning in this release |

A command without the flag `confine` is not confined: it runs as root and may call `hs`, `incus` and `systemctl`. A package without `permissions` shows as `not declared` in `hs ext list`; the repository check (`pkg.py repo-check`) fails for it.

### Confinement of a service

`hs ext start` writes a drop-in for the unit from the permissions: `ProtectSystem=strict`, `ProtectHome=yes`, `PrivateTmp=yes`, `NoNewPrivileges=yes`, no capabilities, `PrivateDevices=yes` unless `devices:gpu`, `ReadWritePaths=` from `fs.write` (plus the state folder of the bridge), `ReadOnlyPaths=` from `fs.read`. The secret locations are hidden: `/var/lib/hs` is an empty read-only folder apart from the granted state below `/var/lib/hs/ext/`, `/var/lib/hs/ext-svc` and the package's own folder `/var/lib/hs/<package name>`, and `/root`, `/etc/shadow`, `/etc/gshadow`, `/etc/ssh` and `/etc/nixos` are inaccessible. A path that overlaps them (`fs.read` or `fs.write`), or an `fs.write` below `/etc`, `/boot` or `/nix`, is refused when the manifest is checked and when the unit is written, with the reason. Not limited: the rest of the file system stays readable, the network is open, and the service runs as root. A path that is not allowed (relative, `..`, `/`) means the service is not started. A package without `permissions` gets the strict defaults only and may write nothing but its own state; the start warns about it.

### Confinement of a command

A row of `commands.tsv` with the flag `confine` runs through `systemd-run` with the same properties. It needs `protocol = [1]` and a `permissions` list. If `systemd-run` is missing, or the list is missing, the command does not run (exit 69); it never falls back to unconfined. It is partial: reading the file system, the network and calls to `hs`, `incus` and `systemctl` are not limited, and a confined command cannot write `/etc/hs`, and `fs.write` cannot name it (below `/etc` is refused).

## Events of a package

A package declares the events it sends as `[[events]]` in `package.toml` (kind, level, payload keys, optional notification text). The core reads the declarations of installed packages for levels, the catalogue (`hs event kinds`, shown "when installed") and the notification rules. A package with `[[events]]` must have `events.emit` ([Events](events.md)).

A service gets the events it subscribed to (`subscribe` globs) as `event` messages and acknowledges each one. The last acknowledged id is a file, `/var/lib/hs/ext-cursors/<package>`. After a crash or restart the core delivers what was not acknowledged again; at most 100 events are on their way at once. A service that starts for the first time gets events from then on, not the past.

A service sends `emit` for an event of its own. The kind must be `pkg.<package>.<what>`. At most 50 emits a minute count; the 51st is dropped with one warning per burst in the journal. A `snapshot` message replaces the live topic `ext-<package>-<topic>` (at most 256 KiB, a new generation only when the data changed). Writing an event by hand for a package:

```bash
sudo hs event emit pkg.<package>.<what> <subject> "<text>" --pkg <package>
```

## Roles of a package's web pages

Each `[[web.reads]]` and `[[web.changes]]` entry may say `role = "viewer"`, `"app-manager"` or `"admin"`; none means admin. The web interface applies the higher of that role and the role of the core row the entry calls. See [Web interface](web-interface.md#roles-and-sign-in-of-programs).

### Where a package's page sits

`[web.page]` may say where the page goes and what shape it has. Not tested on hardware yet.

| Key | Meaning |
| --- | --- |
| `group` | one of `storage`, `instances`, `apps`, `network`, `people`, `system`, `backup`, `settings`; default `apps`. An unknown name drops the whole declaration of the package |
| `after` | a place in that group (the last word of its path, e.g. `pools`, or another package's name); the places of the core keep their order, packages follow alphabetically |
| `[[web.page.tabs]]` | `title` and its own `[[web.page.tabs.blocks]]`: one place with tabs, never a third level in the tree |
| `template` | `list`, `object` or `feed`; default `list` when the first block is a table |
| `state` | `{ read, dot, line }`: one declared read; `dot` and `line` are field numbers of its first row (`dot` is ok, warn, bad, info or off); one dot and one line for the card on the group page and the Apps list |
| `role` | on the page and on each action: `viewer`, `app-manager` or `admin` (same as for reads); the server checks and passes it on, the web interface shows a button above the person's role disabled, with the reason; the page role is the floor for the page's buttons |

### Blocks

Each `[[web.page.blocks]]` entry has a `type`. `hs pkg validate` checks it against the block list (`web/src/shell/block-registry.json`): a missing required key, a key the block does not have or a value of the wrong type fails. Not tested on hardware yet.

| Block | What it shows | Required keys |
| --- | --- | --- |
| `table`, `kv`, `cards`, `text`, `empty`, `gallery` | rows, key and value cells, cards, text, an empty state, pictures | see the Components page in Developer |
| `chart` | a series over time: field `value` (a field number, default 1) of each row of `read` is one point, oldest first; `max` scales it (default: the highest point), `hot` marks points at or above it, `unit` is written beside the newest value | `read` |
| `stat` | tiles from the first row of `read`: `items` is a list of `{ label, col, unit, fmt, map }`; `map` (`{ value = ["ok", "running"] }`) adds a state dot with a word | `read`, `items` |
| `log` | the tail of a log: `stream` is a `/api/logs/stream/...` path, `read` the `/api/sys/...` read that serves while the stream is down; `lines` is how many lines are kept (default 200, at most 2000), `follow` (default true), `every` seconds of the fallback read. It follows the stream, so there is no timer while the stream is up | `stream`, `read` |
| `progress` | a bar with the percent beside it: `read` with the field numbers `value`, `max`, `labelCol` and `state` of its first row, or `job` (the slug of a job, followed through the job events); `label`, `unit`. A read follows its `topic` (give one, or it is polled every `every` seconds) | `read` or `job` |

A block whose `type` the web interface does not know shows a note instead of the block.

A page, a tab or a `state` that reads something the package did not declare is dropped with the whole package declaration, like any other page.

### Slots of a package

A package fills places in the interface with data. The slots are `page`, `tab`, `action`, `health` and `state`; anything else under `[web]` is refused
by `hs pkg validate` and at install, with the list of known slots. Any slot may say `requires = "<capability or extension>"`: while that part is off
the slot shows nothing, and the install dialog says "adds a card once X is on". Not tested on hardware yet.

| Slot | Example in `capability.toml` |
| --- | --- |
| page | `[web.page]` with `title = "Sync"` and `group = "apps"` |
| tab | `[[web.page.tabs]]` with `title = "Settings"` and its own blocks; `requires` hides it while the part is off |
| action | `[[web.actions]]` with `id = "sync"`, `label = "Start sync"`, `plan = ["ext/<package>", "sync"]`, `role = "app-manager"`, `main = true`: a button in the page header and on the Apps > Installed row (one main action, the others under More); the plan may only change the package's own area |
| health | `[[health]]` with `id = "stale"` and `read = "checks"`: the read (kind `tsv`, no arguments) prints `level<TAB>message` rows with level `ok`, `warn` or `bad`; a `warn` or `bad` row shows in System > Health with the package named, and can be acknowledged like any problem |
| state | `[web.page.state]` with `read`, `dot` and `line`: one dot and one line on the card |

## Check that it worked

- `hs ext list` shows the extension as on, with its permissions.
- `hs ext status` shows the service as `running`.
- `hs ext <package> <command>` prints what the command should.
- After `sudo kill -9` of the service process, `hs ext status` shows it `running` again within a few seconds.

## If something goes wrong

| Symptom | Cause | Fix |
| --- | --- | --- |
| `hs ext enable` refuses with "not covered" | the manifest uses more than `permissions` | add the permission or remove the use |
| State `failed`, event `ext.service-failed` | five failures in ten minutes | `journalctl -u hs-ext-svc@<package>`, fix, then `sudo hs ext start <package>` |
| "The confinement of '<package>' could not be written" | a `fs.*` path is not allowed | use an absolute path without `..` |
| A confined command exits 69 | no `systemd-run`, or no `permissions` list | add `permissions = [...]` to the manifest |
| A service cannot write a folder | the folder is not in `fs.write` | add `fs.write:<path>` and run `sudo hs ext start <package>` |
| "emit ... dropped" in the journal | the kind is outside `events.emit`, or more than 50 a minute | declare the kind, or send fewer events |

## Next

- [Write an extension](extensions-sdk.md)
- [Package API](Package-API.md)
- [Web interface](web-interface.md)
