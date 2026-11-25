# Package history, older versions, likes and install counts

Plan for four things around the marketplace: a version history per package, installing an older version, likes and install counts from a
small service of our own, and a website that shows them and opens a package on the reader's server. It builds on
[PLAN-registry](PLAN-registry.md) and [PLAN-website](PLAN-website.md). This is a plan: nothing here is built. **Not tested on hardware yet.**

## Before you start
- The signed index and what the server checks: [PLAN-registry](PLAN-registry.md), `scripts/lib/pkg_index.py`, `scripts/pkg_repo.py`.
- The marketplace pages are milestone 0.14 (hobnix/core#205, #474); the public website is hobnix/core#489.
- State on 2026-11-25: the official index is published at `packages.hobnix.dev/official/index.json`, lists only the current version of each
  package, and no package has a change text (`meta.changes`).

## Decisions (owner, 2026-11-25)

| Question | Decision |
| --- | --- |
| Where likes and counts live | A stats service of our own. No GitHub Discussions, reactions or release assets |
| Account for a like | None |
| Counting installs | Opt-in, off by default |
| Fetching and showing likes and counts | On by default, with an off switch |
| Where the service runs | Developed on the owner's home server, not reachable from the internet; moved to a small VPS before anything public uses it |
| Where the history lives | In the signed index, because it decides which code is installed |
| Where the numbers live | In a separate, unsigned `stats.json`; they never decide anything |

## Version history in the index (0.13)

Each entry gets an optional list `versions` with the **older** versions, newest first, at most 10. The entry itself stays the current one.

```json
"jellyfin": {
  "version": "1.4.2", "commit": "<sha>", "tree": "sha256:<hash>",
  "versions": [
    { "version": "1.4.1", "date": "2026-11-20T09:12:00Z", "path": "recipes/jellyfin",
      "commit": "<sha>", "tree": "sha256:<hash>", "requires_core": ">=13",
      "changes": "Fix the address of the web page", "yanked": false }
  ]
}
```

- A second new field, `date`, on the entry itself says when the current version was first published.
- **Source: git, not the previous index.** The build walks the first-parent history of the commit it publishes. For each older version it
  takes the newest commit that still had it, which is what servers received last, and hashes the package folder there with `tree_hash`.
  `date` is the commit date of the first commit that had the version. The build already checks out the full history (`fetch-depth: 0`).
- Why not carry the list over from the previous index: the build downloads that file without checking its signature (it only reads the
  serial). Copying entries from it would sign content nobody checked.
- Only versions lower than the current one are listed. A commit where the manifest is missing or unreadable, or where the folder is
  refused by `tree_hash`, is left out. History follows the current path only: a renamed or moved package starts a new history.
- `yanked` and `yanked_reason` come from `yanked.toml` of the commit being published, so an old version can be withdrawn later.
- `format` stays 1. A client ignores unknown fields, so servers without this keep working. As with `binaries`, only the builder side
  (`strict`) refuses a bad row; a client leaves a malformed row out.
- Size: at most about 10 rows per package, far below the 20 MB limit of the client.
- **The published branches are never rewritten** (`main` of official; `pins` of community, where each pins commit has the previous one as
  parent). A force-push would make listed commits unfetchable. A branch rule enforces it.

### Change text

`scripts/dev/prepare-release.sh` already finds the merged pull requests per package to choose the bump level. It also writes their titles
to `[meta] changes` of each package it bumps. The release pull request shows the text, and the owner can edit it there. Each release
replaces the text, so it describes one version. Versions published before this have no text.

## Installing an older version (0.14)

`hs pkg install <name> --version <x.y.z>`, and a list on the package page. Installing uses the same pinned commit and tree hash check as any
other install.

| Rule | Detail |
| --- | --- |
| Kinds | Apps (recipes) and extensions. Capabilities change the system and keep the one-step `hs pkg rollback`; blueprints have no older install |
| Which versions | Only those in the current signed index of the repository the package came from; never a yanked one; `requires_core` must fit |
| Permissions | Checked again against the installed copy, as for an update |
| Confirmation | A plan (from, to, code difference), the data warning, the typed package name, run as a background job |
| Data | **An older version does not make app data older.** An app whose database was changed by a newer version may not start. The plan says so and offers a backup first |
| Running app | Changing the package changes nothing until the recipe runs again. A recipe may not handle going back; `--check` shows what it would do |
| Hold | An older install sets `hold` for the package in `installed.toml`. `hs pkg hold` and `hs pkg unhold` set and lift it by hand |

A held package is skipped by "update all" and by automatic updates, is not counted in the update badge, and is shown as "Held at x.y.z".
Updating it by name asks first and lifts the hold. The app policy `pinned` is not enough: it still allows a package update.

New `sys` rows (versions list, plan and start) are added; the shape of existing machine-readable lines does not change.

## The stats service (0.14)

A new repository `hobnix/stats`: one small Rust program with one SQLite file, at `stats.hobnix.dev`. No admin web page; the operator works
with a command on the machine.

### Requests

| Request | Body | Does |
| --- | --- | --- |
| `POST /v1/likes` | repo, package, like key | adds a like; repeating it changes nothing |
| `POST /v1/likes/remove` | repo, package, like key | removes it |
| `POST /v1/installs` | repo, package, version, action (`install` or `update`) | adds one to the day's total |
| `GET /v1/stats.json` | none | the totals, cached |

```json
{ "format": 1, "generated": "2026-11-25T04:00:00Z",
  "packages": { "official/jellyfin": { "likes": 12, "installs": 340, "updates": 95 } } }
```

The service fetches the signed official and community indexes, verifies them, and accepts only a repository, package and (for installs)
version listed there, current or in `versions`. Anything else is refused and not stored.

### What is stored

| Table | Columns | Never stored |
| --- | --- | --- |
| `installs` | repo, package, version, action, day, count | single reports, anything about a server |
| `likes` | repo, package, SHA-256 of the like key, day | the key itself, an IP address, a time of day |

### Likes without an account

- On the first like the server makes a random secret and keeps it in a root-only file. The secret never leaves the server.
- The like key sent for a package is an HMAC of `<repo>/<package>` made with that secret. The same server gets the same key for the same
  package, so it has one like per package and can remove it, but the service cannot link its likes of different packages by their keys.
- All users of a server share the like. The web page asks the local server, which sends the request: the browser never sees the key and
  never contacts the service. The key goes in the request body, never in argv or the environment (`scripts/lib/secret.sh`).
- A like is only sent when somebody presses the button. The button says that it sends an anonymous like to `stats.hobnix.dev`.
- If the secret is lost (a new installation), earlier likes stay counted and the server can like again.

### Counting installs

- Off by default. The first-run wizard asks, and Settings changes it. An existing server stays off until somebody turns it on.
- A report goes out after a **successful** install or update, for packages of `official` and `community` as configured by the core, and
  for no other repository: a private package name must not leave the server.
- It carries no like key and no server id. A failed or slow report never blocks or fails an install, and is not retried.
- Going back to an older version and `hs pkg rollback` are not reported.
- The number means "installs reported by servers that opted in". The interface and the website say that.

### Showing the numbers

- The server fetches `stats.json` together with the index refresh and keeps the last good copy. No copy: the numbers are not shown.
- The file is untrusted input: size limit, whole numbers of zero or more, unknown fields ignored.
- **Likes and counts never change trust, the Verified badge, what may be installed, or the default sort order.**
- Fetching and showing is **on by default**, and Settings has a switch to turn it off. A server that fetches the file shows its address to
  the service, as fetching the index shows it to the index host. This does not turn on counting installs.
- Proposed config keys (in `config/schema.toml`): `packageStats` (fetch and show, on), `packageStatsReport` (count installs, off),
  `packageStatsUrl` (the address; a development server points it at the test service).

### Abuse and privacy

Without accounts and server ids, both numbers can be faked with a script. The service limits that and cannot prevent it: a small body limit,
rate limits per address (per /64 for IPv6) held in memory only, a daily cap per package, and an operator command that removes the likes or
counts of a package for a range of days.

The service sees the address of whoever connects. It uses it for the rate limit and writes it nowhere: no access log in the program or in
the proxy in front of it. A short privacy note on the website says so, and is online before the service is public.

### Running it

1. **Development:** on the home server, in a container of its own, reachable from the test server only. No public route, no DNS record.
2. **Public:** a small VPS (about 4 to 5 EUR a month) with HTTPS. This happens before a released version of Hobnix or the website uses it.
3. **Backup:** a daily copy of the SQLite file (the SQLite backup command, not a copy of the open file) to a second machine.
4. **Moving later** (for example to a dedicated Hobnix server): stop writes, copy the file, start there, change DNS. Servers only know the
   address.

If the service is down, installing works, the numbers get old, reports are lost, and pressing "Like" shows an error.

## The website (with hobnix/core#489)

- A page per package is built from `index.json` and `stats.json`: description, pictures, trust label, version history, numbers. The site
  stays static and is rebuilt daily. If `stats.json` cannot be read, the pages are built without numbers.
- The website only shows likes. A like is given on a Hobnix server.
- The numbers come from servers that opted in. The website itself still has no analytics.

### "Open on my server"

1. The button goes to `hobnix.dev/open/#repo=official&package=jellyfin`.
2. The first time, the page asks for the address of the reader's server and keeps it in that browser (local storage). It can be changed.
3. The browser then opens `<server address>/marketplace/official/jellyfin`.

| Rule | Why |
| --- | --- |
| The link opens a page. It never installs, likes or adds a repository | A link on any site could point there |
| The server address comes only from what the reader typed, never from the link | No open redirect |
| Only `http` and `https` addresses are accepted | A `javascript:` address would run code |
| `repo` is `official` or `community`; `package` must match the package name pattern | Nothing else reaches the address |
| Both are after the `#`, and the address stays in the browser | The website host learns neither |
| The web interface keeps the target through the login | Otherwise the button ends on the start page |

The website never contacts the server, so no route becomes public and "admin pages are never public" is unchanged. This is the one
exception to "the site never links to a running instance" in [PLAN-website](PLAN-website.md).

## Order of work

The issues hold the "done when" lists.

| Step | Milestone | Issue | Needs |
| --- | --- | --- | --- |
| V1 | 0.13 | hobnix/core#1247: `date` and `versions` built from git, validator, tests (open point 3 of hobnix/core#1069) | none |
| V2 | 0.13 | hobnix/core#1248: prepare-release writes `[meta] changes` from pull request titles | none |
| V3 | 0.13 | hobnix/core#1249: update the pinned core commit in official, forbid force-push, check the published history; same for community with hobnix/core#1076 | V1, V2 |
| O1 | 0.14 | hobnix/core#1250: install an older version, hold and unhold | V1 |
| O2 | 0.14 | hobnix/core#1251: package page with history list, older install and held state (with hobnix/core#474) | O1 |
| S1 | 0.14 | hobnix/core#1252: `hobnix/stats`, the service, its tests, the operator command | V1 |
| S2 | 0.14 | hobnix/core#1253: like and unlike, report installs, fetch `stats.json`, config keys | S1 |
| S3 | 0.14 | hobnix/core#1254: like button, numbers, first-run question, settings | S2, hobnix/core#474 |
| S4 | 0.14 | hobnix/core#1255: VPS, `stats.hobnix.dev`, backup, privacy note; before the 0.14 release | S1 |
| W1 | 1.0, with hobnix/core#489 | hobnix/core#1256: website package pages with history and numbers | V1, S4 |
| W2 | 1.0, with hobnix/core#489 | hobnix/core#1257: website button and the route `/marketplace/<repo>/<name>` kept through login (with hobnix/core#933) | W1 |

## Open points
- Channels (open in [PLAN-registry](PLAN-registry.md)): with one index per channel, each has its own history.
- Whether a package with a data format change can mark "do not go back past this version". Not part of the first version.
- Which data protection duties the owner has as the operator of the service. Not checked.

## Check that it worked

For the plan: the owner has read it. For each step, once built:

- The published index lists earlier versions of a package that was bumped, and each listed version installs with a matching tree hash.
- With counting off, a test service receives nothing during an install and an update.
- With the service stopped, an install ends successfully.

## If something goes wrong

| Symptom | Cause | Fix |
| --- | --- | --- |
| The index has no `versions` after the change | official still uses the old pinned core commit | Update the pin in its `index.yml` (step V3) |
| A listed version cannot be fetched | The published branch was rewritten | Restore the commits, or let the next build drop the rows |
| Likes jump for one package | Scripted requests | Remove that range of days with the operator command |
| No numbers in the marketplace | No `stats.json` copy, or `packageStats` is off | Check the setting and the address |

## Next
- [PLAN-registry](PLAN-registry.md): the index this history is part of.
- [PLAN-website](PLAN-website.md): the site that shows the package pages.
