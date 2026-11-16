# Package API

What a package (`package.toml`) may say to the core, and from which API level. The level is the number in `scripts/lib/api-level` (`hs pkg api`);
a package states the lowest level it needs in `requires_core = ">=N"` and the core refuses one that needs more (ADR 0008, rule 4). The design
is in [PLAN-app-lifecycle](PLAN-app-lifecycle.md) (Q4 and Q5); the states of a package are in ADR 0027.

**These field names are a contract.** The Apps and Marketplace pages and the later steps of the lifecycle plan (0.11, 0.13) read them. After this
page is merged a field is renamed or removed only with an API level bump and one level in which the old name still works. Adding an optional key
is a bump too, because an older core would refuse the unknown key.

## Level 9: the app contract and store fields

All keys are optional. A manifest written before level 9 validates unchanged. A package that uses any of them states `requires_core = ">=9"`
(`pkg.py validate` names it when it does not). They belong to recipes first; an extension that owns a service may use them later.

### Store fields (top level of package.toml)

| Key | Value | Rule |
| --- | --- | --- |
| `description`, `description_de` | text | one paragraph, at most 500 characters |
| `icon` | `"ph:<name>"` or `"<file>.svg"` | a Phosphor name, or an SVG in the package folder: at most 20 KB, no `<script`, no `on...=` handler, no external reference |
| `category` | id | one of `config/package-categories.toml`: media files network home games tools dev admin |
| `upstream` | address | `https://...` |
| `app_version` | text | the app release this package version pins; set at release time. The running version is read on the server, never looked up |
| `screenshots` | list of paths | at most 5, `.png` or `.webp` inside the package, each at most 300 KB |

The package index (`index.toml`) carries `icon`, `category` and `app_version` as well (optional); `pkg.py repo-check` compares them with the
package. Description, pictures and `[app.uses]` are read from the package itself.

### `[app]` tables

```toml
[app]
instances = "one"                 # one | many; default one
autostart = true                  # default of the instance's boot flag
[app.health]
check = "http"                    # container (default) | tcp | http
port = 8096                       # tcp and http: required
path = "/health"                  # http only; starts with /
timeout = 5                       # seconds, 1 to 60
[app.backup]
mode = "instance"                 # instance (default) | paths | none
paths = []                        # mode paths: absolute paths inside the instance, at least one
dump = "postgres-compose"         # optional dump kind, "-" for none
[app.routes]
default = "web"                   # must name one of the routes below
web = { port = 8096, scheme = "http", exposure = "private-ok" }   # scheme http|https; exposure never-public|private-ok|public-ok
[app.update]
kind    = "pin"                   # pin | os | manual
default = "notify"                # automatic | notify | pinned
[app.version]
source = "image-tag"              # image-tag | http-json (path + pointer, both start with /) | exec (command = ["word", ...])
[app.remove]
keeps = ["data volume", "share"]  # plain English, shown in the Remove dialog
data  = ["/var/lib/app"]          # what "delete the data" deletes
[app.uses]
ram_mb = 4096
disk_gb = 20
ports = [2283]
gpu = false
```

An unknown key in any `[app]` table is an error. A route that is public-ok and marked `admin = true`, or whose container and port are in
`ADMIN_TARGETS` of `scripts/services.py`, is refused: a manifest cannot make an admin page public.

### How strict

| Package | Without the contract / store fields |
| --- | --- |
| a recipe flagged `core = true` in the index | error: `[app.health]`, `[app.backup]`, `[app.routes]`, `[app.update]`, `[app.remove]` and the store fields `description`, `icon`, `category`, `app_version` are required |
| a recipe that carries any store field | warning until `description`, `icon`, `category` and `app_version` are all there |
| any other recipe | validates; `pkg.py repo-check` prints a warning on stderr |

`pkg.py validate --warn` prints the same warnings for a tree. `pkg.py check-draft` (the package builder) reports errors only.

Not tested on hardware yet. The fields are validated; the server does not read them until the later steps of the lifecycle plan.
