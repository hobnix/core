# Web interface

A page in your browser to look at the server and make the common changes: disks and pools, shares, containers, users, backup, tasks and
settings. It does not replace `hs`, it sits on top of it: every change runs the same command you would type, and shows you first what it
would do.

## Before you start

- A running server ([Install](install.md)) with its storage unlocked (`hs unlock`).
- An account that may sign in: a member of **Domain Admins** (sign in with the plain user name, without the domain prefix) or the local
  `adminuser`. Other domain users cannot sign in, even with the right password. While storage is locked only `adminuser` can.
- Not tested on hardware yet: the flows were checked against stand-ins. Try harmless things first (run a task, change a share's rights, run a
  short disk self-test); reboot, delete and add-disk last.

## Switch it on

```bash
sudo hs config set webUi true
```

```bash
sudo hs rebuild
```

The first build downloads the page's libraries and takes a few minutes. The page then listens on `http://<server address>:8480`. Other
options, all set the same way with `hs config set <key> <value>` (never edit `machine.toml` with `sed`):

| Option | Default | Meaning | Needs `hs rebuild` |
| --- | --- | --- | --- |
| `webPort` | `8480` | port of the page, the direct address `http://<server address>:8480`. With the gateway proxy on (`capabilities = ["gateway"]`) port 80 belongs to Traefik, so `webPort` must not be 80; the page is then also at `http://<siteName>.<realm>/` | yes |
| `webTailscale` | `false` | HTTPS through Tailscale, see below | yes |
| `webLan` | `true` | keep the plain-HTTP address on the home network | yes |
| `webDocs` | `true` | the Docs page | yes |
| `webAccent` | `#9184d9` | main colour as `#rrggbb` | no |
| `webTerminal` | `false` | the browser terminal, see below | no |

## Use HTTPS over Tailscale

Without it the page is plain HTTP on your home network: passwords cross it unencrypted. With `webTailscale` the page listens on the server
only, and Tailscale turns it into HTTPS with a real certificate for members of your tailnet.

```bash
sudo hs config set webTailscale true
```

Then do two things once by hand: join the tailnet on the server and switch on **HTTPS certificates** (and MagicDNS) in the Tailscale
admin console.

```bash
sudo tailscale up
```

```bash
sudo hs rebuild
```

The address is `https://<server>.<your-tailnet>.ts.net`. Check it with `tailscale serve status` and `systemctl status hs-web hs-web-tailscale`.
To remove the plain-HTTP address on the home network, set `webLan` to `false` and rebuild. The page is **never** reachable from the internet
and never gets a reverse-proxy route: it is an administration interface.

## Sign in

Choose **Domain account** or **Local admin** on the sign-in page. With storage locked, the domain controller is down too: sign in as
`adminuser`, and the summary shows a box to unlock the storage (type the passphrase; after five wrong tries the page makes you wait).
Sessions end after 8 hours without activity, after 12 hours at most, and when the page restarts.

## Finish the first setup

On a new server the sign-in page asks for the one-time code from the server's screen ([Install](install.md)). After you choose the password, the
**First setup** wizard opens: account, storage, preset, optional parts, done. The storage step lists the pools that are already on the disks (**Import** opens a plan), the empty disks (tick an even number, at least two, name the pool, **Create the pool** opens a plan) and the disks it only shows (erase those on their disk page first). **Finish** (or skipping every step and finishing) removes it; it never comes back. What is
still open stays on the **Setup** page. Not tested on hardware yet.

## If the sign-in is locked

Five wrong passwords from one address make the page refuse that address for 30 seconds, then longer (up to 15 minutes). A wrong guess
for your user name from somewhere else does not lock you out: the right password always works from an address that is not locked. If you
are locked out and cannot wait, run this on the server console (over `ssh` or at the keyboard):

```
sudo hs web unlock-login
```

It restarts the page (the same as `sudo systemctl restart hs-web`), which clears the lock. Sessions that are signed in stay signed in.
`sudo hs web unlock-login --dry-run` shows what it would do and changes nothing. Not tested on hardware yet.

## See who is signed in

**Settings > Users and access** has a **Sessions** table: user, browser, address, when each signed in and was last seen. Your own is marked
**this browser**. **Sign out** ends one session (ending your own returns you to the sign-in page); **Sign out all other sessions** ends
every one but yours. Do this when you left a browser signed in somewhere else, or after you changed a password.

- Changing the password of the local admin (`adminuser`) ends its web sessions within 30 seconds, and an open browser terminal ends too; sign in again with the new password.
- Changing a domain password does **not** end web sessions. Use **Sign out all other sessions**, or wait: a session ends after 12 hours at most.

Not tested on hardware yet.

## Roles and sign-in of programs

The web interface has three roles; each includes the one before. A call a role may not make is refused with a 403 that names both roles, and runs nothing. Not tested on hardware yet.

| Role | May | Comes from |
| --- | --- | --- |
| viewer | look: every page that reads | the domain group `hn-viewers` |
| app-manager | also change instances and apps (the `apps`, `ct`, `recipes`, `docker` and `jobs` areas) | the domain group `hn-app-managers` |
| admin | everything, including users, secrets and the vault | Domain Admins, and the local account (`adminuser`) |

The highest role of a person's groups wins; a person in none of the three cannot sign in. The group names can be changed in machine.toml (`webViewerGroup`, `webAppManagerGroup`). The role is read at sign-in and kept for that session. Every row of `hs sys` has its least role in [docs/adr/0012-roles-sys-rows.tsv](adr/0012-roles-sys-rows.tsv); a row without a decision is admin.

```bash
sudo hs group roles
```

Creates the two groups in the domain: it shows a plan first and asks you to type the domain name. Add people to them with the tools of [Users and shares](users-and-shares.md).

The page shows every page to every role. A page or button the role may not use is greyed with a lock and "Needs the admin role"; it stays clickable and opens a page that names the role. A button that starts a change (a plan, a form, a job) is greyed the same way for a role below the one the server asks for, and its tooltip says "Your role (viewer) may not do this. It needs admin."; the role of each button follows the area of its change in `scripts/lib/sys-roles.tsv`, the table the server uses, and `tests/web-roles-ui.sh` fails when a change button has no such gate. Not tested on hardware yet. The Vault and the identity pages need admin. Under Settings, Users and access, a role below admin sees its own sessions only. Roles are enforced in the web server only: anyone with `sudo` on the server is not limited, so a viewer is not safe against a person with a shell.

The audit log names the signed-in person for every change made in the web interface (`<user>`, or `<user> via token <id>`): `hs audit`.

### API tokens

A program (curl, a script, a dashboard) signs in with a token instead of a cookie. A token belongs to a person and never has more than that person's role.

```bash
sudo hs token create <name> --role viewer --days 90
```

Prints the token once; it starts with `hn_`, and only its sha256 is kept, so it cannot be shown again. The default role is viewer, the default life 90 days, the longest 365; there is no token without an expiry. Use it like this:

```bash
curl -H "Authorization: Bearer <token>" http://<server>:8480/api/sys/status
```

`hs token list` shows name, id, owner, role, expiry and state (never the token). `sudo hs token revoke <name>` asks you to type the name. The Tokens page under Settings, Users and access does the same for app managers and admins. A token can only plan and start changes and read; it cannot create tokens or use users, secrets, unlock, the terminal or the VM console, and it cannot start changes whose result would outlive it (SSH keys, packages, settings, system updates, routes, network, domain, nodes, migration, extension changes); it can change containers, backups, shares, Docker, apps, jobs, notifications, health, expiry and ISOs. A signed-in domain session is re-checked like a token: when its person is disabled or leaves the groups it ends, and a lowered role applies, within the hour. A token ends at its expiry and when its owner is no longer in a role group (checked at least once an hour). While no domain controller answers, a token above viewer is refused after one day. 60 wrong tries in a minute lock that token id for five minutes, and wrong tokens count against the address like wrong passwords.

Planned, not built: a second factor (TOTP) and single sign-on (OpenID Connect). Both wait for the security review.

## Find your way around

The tree on the left, the task panel at the bottom (Tasks, Jobs, Logs, disk events, reports) and search on top (press `/`). The top bar
shows the server name, a node switcher, how old the data on screen is (with a refresh button), the storage state, the theme toggle and the
buttons **Update**, **Reboot** and **Shut down**.

The **Jobs** tab of the task panel has two views. **Job records** lists what the server ran, newest first, also after the job is gone
(finished, failed, cancelled, or interrupted by a restart), with state, step, progress and how long it took; click a row for the source,
who started it and the error text of a failed job. The record opens to the right of the list (list about 60 %, record about 40 %, each
scrolls on its own), so the list never moves and the record needs no scrolling; on a phone it opens full screen with a close button. The
selected row is highlighted; a row opens with Tab and Enter or Space. The list updates when a job changes, without polling (it polls every 15 s only while the
event stream is down). A state this page does not know is shown as text. **Scheduled** is the list of timers with **Run now**.
Not tested on hardware yet.

**Events** (System > Events) shows what happened on the server, newest first, and every signed-in role may read it. New entries appear
at once while the event stream is open; the page asks the server again every 30 s only while the stream is down. **Show more** loads the
next 100 older entries (by their number, `hs event list --before <id>`), so a long list stays fast. Filter by source, level, kind and time.
Not tested on hardware yet.

The left tree has Summary (the server itself) and eight groups. Click a group to open its page, which says in one line how the group is doing.

| Group | Places |
| --- | --- |
| Storage | Pools, Disks, Shares, Files, Encryption, Vault |
| Instances | Instances (containers and VMs), ISO images |
| Apps | Installed (the recipes), Docker, Marketplace (apps and extensions, the repositories, the Package builder) |
| Network | Network (addresses, router networks, DNS names, open ports), Services, Network map |
| People | Users, Groups |
| System | Health, Events, Notifications, Hardware, Updates (with a Releases tab), Certificates, Diagnostics, Live state, Test-lab |
| Backup | Backup, Expiry dates |
| Settings | General, Network and DNS, Storage, Backups, Users and access, Capabilities, Advanced |

**Docs** and **What's new** are buttons in the top bar, **Incident** is a button on Pools and on Health, and the list of servers opens from the
**Servers** header of the tree. **Setup** is a banner on Summary until you mark it done. **Developer** (the components gallery) shows at the bottom
only while the test-lab capability is on. The tree of another server (peer, edge, VPS) keeps its own pages; its Health entry is called System too.

### Group pages
**Storage**, **Backup** and **System** show one line of state (healthy, a warning, a problem, or no data) and one card per place with its state:
pools with capacity, disks that need attention, shares and encryption (locked storage shows as locked, not empty); the last backup and the dates
that run out; open problems, updates, certificates, the UPS and recent events. They read only what their places read already. The other groups
show a card list.

### Object pages and the quick look
A disk, a share, an instance and a user each have a page of their own, and so has a pool:

| Object | Address (inner path) | Tabs |
| --- | --- | --- |
| Pool | `/storage/pools/<name>` | none |
| Disk | `/storage/disks/<name>[/<tab>]` | Overview, SMART, Tests, Files |
| Share | `/storage/shares/<name>[/<tab>]` | Overview, Access, Snapshots |
| Instance | `/instances/ct/<name>[/<tab>]` | Overview, Config, Network, Console |
| User | `/people/users/<name>[/<tab>]` | Overview, Groups, Access |

A page has a header with one main action (Start or Stop, Browse files, Edit) and at most one more; the rest are under **More**, and a destructive
action (Delete, Roll back) is in the danger section at the end and asks you to type the name. Running jobs show on the header and on the row.

On the Groups, Nodes, Docker and Live state lists, selecting a row opens a **quick look** over the list: the list keeps its width and columns. The address carries the row (`?sel=<name>`),
so reload, Back and Forward and a pasted link work. Escape closes it, and **Open page** goes to the object page. On a phone the quick look covers the
screen. The Disks, Shares, Instances and Users lists open no quick look. The **Instances** list: each row ends with an **Open instance** button (and the name is a link) next to Start/Stop and Restart. The **Disks** list: the table already shows the data and cannot scroll sideways, so each row ends with an **Open disk** button (and the name is a link) that goes to the disk page; on the Missing filter the row has a **Forget** button. The **Shares** list: each row ends with **Browse files** and **Open share** buttons (and the name is a link); the share page holds the rest. The **Users** list: each row ends with **Edit**, **Change password** and **Open user** (built-in accounts are read-only and have no Edit or password button). An address of a removed object says "not found".

### Addresses
Every address is `/node/<name>/<inner path>`, for example `/node/myserver/storage/disks/sda`. The old addresses (Identity, Protection, Operations,
Monitoring, Marketplace and the other places of 0.10 and before) are kept in a redirect table and open the place that took over, so bookmarks and links
in old notifications still work. The table is kept through 0.12 and is removed in 0.13: change old bookmarks before then.

A refused change shows the code of the reason, the text and a link to the guide in the plan dialog (for a code the page does not know, the text only).

Not tested on hardware yet. The keyboard walk, the axe check in the browser and the 390 px pass for these pages were not run.

**Settings** has subpages in the left tree: **General** (name, language, look, the Nodes link), **Network and DNS**, **Storage**, **Backups**,
**Users and access** (SSH keys, web access, the terminal, Active Directory), and, in the System group, **Updates** (installed revision, how many changes are
waiting upstream, the update channel with the version the next update would install (beta and edge carry a warning: they can break things and are never applied by themselves), **Update**, a link to What's new, and **Sync new options** for new keys in `machine.toml`), **Capabilities** (every optional
part and extension with its switch) and **Advanced** (every key, read-only ones too, and **Check** for typos in `machine.toml`). Each
capability that is switched on and has settings of its own (the gateway, metrics, Tailscale ...) also gets a page under **Capabilities**:
the switch, then its keys. A capability that is off keeps its page, so you can switch it on there. The address `/settings` shows an overview of
all subpages. **Backups** asks its two questions (new shares, new containers) one per screen, with a review of the current values first; **Advanced** on that page shows the plain keys. **Network and DNS** also asks one question per screen (local names, who may use the shares, the DHCP range, the Incus web UI, the network card last; a new card makes the plan ask you to type its name). **Storage** asks how often the SnapRAID parity is updated (SnapRAID only), whether shares get snapshots (ZFS only) and when idle disks go to sleep; switching snapshots off only stops the timer. **Users and access** asks whether the web interface offers a terminal (a change takes effect at once, the plan warns that every signed-in user gets a shell as adminuser) and, if so, the idle time and the longest connection. **General** asks for the language, the time zone (checked against the zone files, so `Mars/Base` is refused) and the keyboard layout first, then keeps Appearance, Nodes and its other fields. Not tested on hardware yet.

Installed extensions add pages under **Extensions**. The first start shows the **Setup** checklist until you mark it done.

The numbers on a page are read from a cache that is kept fresh while someone is signed in; the top bar says how old they are. The refresh
button reads them again at once.

## The dashboard

A page with one tile for each app of the server, on a big screen or a phone. Not tested on hardware yet.

```bash
sudo hs config set dashboard web
```

Not tested on hardware yet. The page is **Services** with the dashboard card when you are signed in. For a wall screen open
`http://<server address>:8480/dashboard` (use your `webPort`): full screen, no sign-in. That address answers only while
`sudo hs config set dashboardOpen true` is set, and only to computers in your home network and over Tailscale. Everyone there sees the
titles, descriptions, links and state of every tile. Not tested on hardware yet.

A container gets a tile when its service says so:

```bash
sudo hs services declare jellyfin --container jellyfin --port 8096 --want dashboard
```

Not tested on hardware yet. The recipes do this for you. For a container set up before its recipe did it, `sudo hs services declare-known`
describes it. Not tested on hardware yet.

If you used the Homepage app before: `sudo hs update` sets `dashboard` to `web` and leaves the old container alone. Remove it when you like
(`sudo hs ct homepage remove` asks you to type the name). Not tested on hardware yet.

## Make a change

Every change shows a **plan** first: what would happen, in which order, and the exact command. Nothing runs before you press **Start**.
Red plans (not reversible: erase a disk, delete a user, reboot) make you type a word, usually the name of the thing that changes. A plan can
also say "needs one more value" or "refused", with the reason. Long work runs as a task in the background and goes on when you close the
page; open **Tasks** to see its log. Passwords and passphrases never go into a command or a log, they are passed on standard input.

A create dialog shows its form and a placeholder at once and asks for the plan when it opens, then 300 ms after your last edit. An older
question is cancelled, and the server stops the check it was running. **Start** is enabled only for the plan of what the form shows now.
The server answers the same plan again for 5 seconds without running it again; any change you start clears that. Not tested on hardware yet.

To see how long plans and changes take, read the log. One line per plan and start, with no values and no passwords:

```bash
journalctl -u hs-web | grep 'web timing'
```

A line reads `web timing: plan pool bulk add --disks * 1834 ms run rc=0 status=ok`: the command with values as `*`, the time, then
`run` (it ran), `cached` (answered again), `timeout` (took over 60 s) or `gone` (you changed the form, the check was stopped), the exit code and
the result. Not tested on hardware yet.

### Toasts report jobs
**Start** closes the plan dialog at once. A small message (a toast) at the bottom right then says what happens: "Running in the background",
"done", or, when the server refuses, the reason with a **Show plan** button that opens the plan again. When the job ends, a second toast says
whether it worked and opens its log in **Tasks**. A job that stops to ask a question raises a toast with **Open the job**, on every page and
also when you closed the install dialog; it goes away when the question is answered. The steps in the install dialog follow the job as it
moves. Docker start, stop and restart of an app are jobs too: the answer comes at once, the row shows pending until the job ends, and the end toast says how it went. Not tested on hardware yet.

### Install and remove apps
The Apps page has one **Install** dialog for every package: plan, questions, steps, result. A failed install shows the step and offers **Retry**
and **Remove what was created**. **Remove** keeps the data unless you choose **Delete the data** and type the name. Each app shows its stage
(available, installed, on, running), a health mark and its app version next to the package version. Details:
[Containers and apps](containers-and-apps.md). Not tested on hardware yet.

## Use a terminal in the browser

Off by default. It adds a **Terminal** button next to Update (a shell as `adminuser`, like an SSH login; `sudo` asks for that user's
password) and on a container's page (a shell inside the container, like `incus exec <name> -- bash`).

```bash
sudo hs config set webTerminal true
```

The server shell also works while storage is locked, so you can run `hs unlock` there. The connection ends after 30 minutes without typing,
after 8 hours, on sign-out and when you close the window; at most 4 at a time. The shell itself keeps running in tmux, so a long job survives:
the next terminal reattaches to the same shell, and only `exit` or a reboot ends it. Change the limits:

```bash
sudo hs config set webTerminalIdleMinutes 240
```

```bash
sudo hs config set webTerminalMaxHours 48
```

The journal records only "opened" and "closed" with user and target, never the input.

### The graphical console of a virtual machine

With the terminal switched on, a running virtual machine's page also shows a **Console** button (containers keep the terminal). It asks
Incus for the screen of the VM and relays it to the browser over the same kind of ticketed connection as the terminal; no port of the VM is
opened and nothing about the VM changes (ADR 0021). At most 2 consoles run at a time, 1 per sign-in, with the same idle and time limits as
the terminal. The window connects, but the picture itself is not shown yet: the viewer library is not bundled with this version, and the window says
so. UNVERIFIED on a real virtual machine: not tested on hardware yet.

## Change the colour

```bash
sudo hs config set webAccent '#4fb286'
```

The logo, buttons and highlights follow the accent; light colours read better on the dark theme. The theme toggle in the top bar switches
dark and light (it follows your system by default). No rebuild is needed.

## Get a browser notification

The bell in the top bar lists problems and warnings while you look at the page. If you want a message on your desktop while the page is open in
another tab or window, turn it on: **Settings > General > Browser notifications**. It is off by default and is kept in this browser only: another
browser, or another computer, has its own switch.

1. Turn the switch on. The browser asks once for permission to show notifications; this is the only moment it asks, never when the page loads.
2. Leave the page open in a background tab. A new problem that is not acknowledged, or a new warning or error, raises a notification with a short text
   (no serial numbers or other identifiers). Clicking it brings the tab to the front and opens the page of the thing it is about.

Nothing is raised for a problem you acknowledged, for something that was already open when you turned the switch on, twice for the same thing, or
while you are looking at the page. This uses the notification function of the browser only: no push service, no account, and nothing leaves the server.

It does not work everywhere. Browsers only allow notifications on a secure page. On plain HTTP over your home network (`http://server`) most
browsers have no notification function, and the switch is greyed with the reason; use the HTTPS address of [Use HTTPS over Tailscale](#use-https-over-tailscale)
or `localhost`. If you blocked notifications for the site once, the switch says so; allow them again in the site settings of the browser and turn the
switch on again. A browser that is closed, or a page that is not open, shows nothing: the notification channels (email, push) of
[Notification rules](notify-rules.md) stay the way to reach you then. Not tested on hardware yet.

## Pages for storage and backup

- **Disks** has a **Sleep** column (asleep or spinning) and, in the detail of a disk, since when it sleeps and how often it woke today; the numbers
  come from `hs sys disk power`. How to set the sleep time: [Storage and disks](storage-and-disks.md).
- **Pools** has **Take over Unraid**, the dialog behind `hs migrate unraid`: pick the data disks, the old Unraid parity disk and, if you have
  one, a spare disk; the dialog shows the plan, asks for the passphrase of encrypted Unraid disks and runs a background job. The same page shows
  a banner when the health check paused the parity sync, the scrub and the cache mover.
- **Files** (Storage > Files) shows two panes with a path input, owner and mode in Info, "Calculate size" for a folder, and Pause and Continue
  for copy and move. Delete does not pass the permanent option, so the server moves the items into the trash (the dialog still words it as
  "Delete permanently", and the page has no trash view yet; see [Storage and disks](storage-and-disks.md)).
- **Backup** shows the off-site copy ("Set up off-site copy" for S3, a REST server, SFTP or a folder), copies to it now and can stop it. A new
  off-site repository gets its own password, shown once: write it down. The same page shows the restore points and restores files.

Not tested on hardware yet.

## Read the guides in the page

The **Docs** page shows these guides and the generated command reference without fetching anything. `hs docs build` writes them (`hs update`
runs it); if they are not built yet the page says so. Without the web interface, `hs help` lists the commands and the guides are the files in
the `docs/` folder of the repository.

## What only works in the terminal

Some things stay in the terminal on purpose: setting up the backup disk (`hs backup init`, it erases a disk), restoring
the whole system, the per-instance backup rules (`hs backup ct <name> paths|include|exclude|reset`), the restore of one instance with its paths (`hs backup restore ct <name>`), restoring items from the file manager's trash, the recipe `domain`, creating the vault (`hs vault init`), the sign-in to the reverse proxy, anything that asks questions, and the `machine.toml` keys the Settings page does not offer
(for example `sshKeys`, `hostName`, addresses).

## Live state

Live state has no setting: on a server with the web interface the collector `hs-live` keeps the status of every page in the state database and tells
the browser through `/api/events` when something changes. The Summary page updates within about a second or two after a change, without polling. If the
collector stops, the pages keep their last data and mark it as old; `sudo hs sys live status` and `hs sys live check` show the state. A `liveState` line in
`machine.toml` from an older version is ignored (`hs config check` says so). To measure the cost on your server see [Measure the live state on the state database](operations.md#measure-the-live-state-on-the-state-database).

A page is told only about the topics it reads. The browser opens one stream per tab (`/api/events?topics=...&sid=...`) and, when you go to another page, sends the
new list in a short `POST /api/events/subscribe` (`{sid, topics}`; only for the stream of the same session). Job and health events are never filtered. A stream
opened without `topics` (an older page, a script) gets every topic, as before. Not tested on hardware or in a real browser yet.

The Diagnostics page lists every live topic (topic, interval, age, generation, exit code, error and error time) and
follows the same stream, falling back to polling every 5 seconds. The `live` topic row describes the previous collection by design. Not tested on hardware yet.

The fixed reads of the Storage pages (Pools, Disks, Shares, Encryption, Vault, file locations, Other disk) use live state too: they come
from the state database, have no polling timer while the stream is open, and the refresh button in the top bar refreshes them. Selected disk, share and
file details (SMART history, access lists, snapshots, directory contents) stay direct. The pools `bulk` and `fast` have their own topics;
other pool names are read directly. While storage is locked the pool and share panels keep their last value (or show "refreshing") until
unlock refreshes them. Not tested on hardware yet.

The Summary and top bar, Health, Settings, the Instances and Services pages, the Marketplace and Apps, and the Network pages (gateway status, routes
and health, DNS names, router networks and clients, open ports, remote shares) use live state too: their fixed lists come from the state database and update
over the stream. A change from the terminal, from the web interface or from a job refreshes only the pages it can affect; a finished job refreshes
everything. Reads that need an argument (one service, one user) and on-demand reports stay direct. Pages whose feature is off
(gateway, Active Directory, router connection) show nothing for it. Not tested on hardware yet.

The Users and Backup pages follow the same rule: the user and group lists, the domain controller certificate state, the backup state and the list of
shares and instances with their backup switch come from the state database and update after a user, share, instance or backup change. One user's or group's details,
the snapshots and the file search of the backup stay direct (they open the backup disk). Not tested on hardware yet.

### How fast a change shows

The limits are in `scripts/lib/live-limits.tsv`: 5 seconds for a topic whose change script announces it, 20 seconds for a topic that is only read on a timer.
`tests/live-e2e.sh` (run by `scripts/dev/t quick live-e2e`) starts the web server on a real state database, opens a page model that has no timer and
follows `/api/events`, and then changes an app list, a container and the storage state: the page must show the new state within the limit and read
exactly once. It fails when the limit is passed. It does not run the Svelte code or a browser and has no real Incus or storage behind it
(the browser stage of the test-lab and the timing on a server are #485 and #486). Not tested on hardware yet.

### Services that stop or crash

A unit that stops, starts or fails while a page is open shows within a second or two, also when it was stopped from a terminal (`systemctl stop`) or crashed.
The service `hs-unit-watch` (web interface on, not on an edge node) listens on the system bus and, for the units the interface shows, marks their
topics: failed `hs-*` units (Health), job units, extension services, `bulk-mount`, `samba-smbd`, the ZFS import and scrub units, Incus, Docker and the gateway proxy.
The list is `scripts/lib/unit-topics.tsv`. The collector's timer stays as the safety net: if the watcher is down, the pages are still right within
their interval. Disk plug and pull events come from udev, not from this service. These topics stay timed, because nothing announces a change:
SMART values (`disk-health`), free space and temperatures (`monitor-disks`, `temp-disks`), sensors (`hardware`), the UPS, waiting updates,
traffic counters and the UniFi clients.

Check that it works: `systemctl status hs-unit-watch`, open the Services page and run `sudo systemctl stop docker` (then `start`): the Docker row changes without a reload.
Not tested on hardware yet.

### Logs follow a stream

The log views (the Logs tab of an instance and of a Docker app, the instance log window, the Logs and Disk events tabs of the task panel) show new lines as
they are written, without asking again and again. Each open view holds one stream of its own (`GET /api/logs/stream/<ct|docker|system|events>`,
server-sent events): the server starts `hs sys ... follow` for it, sends the last 200 lines first and then every new line, and ends the command when the
view closes, the tab goes away, you sign out or the stream ends.

- **Who sees what:** the same role as the read the view replaces (instance and Docker logs: app manager, system journal: admin, disk events: viewer).
  A log may hold secrets, so a stream is never cached and never part of a live topic.
- **Limits:** 4 open log streams per person and 8 in all (`HS_WEB_LOGS_USER_MAX`, `HS_WEB_LOGS_MAX`), apart from the 32 event streams. A browser keeps
  only 6 connections to one server and the page holds one for its events, so a view opens its stream only while it is shown, never when the pointer
  passes over a link, and a switched-off *Follow* closes it.
- **A tab nobody sees:** a stream with no visible tab closes after 15 minutes and opens again, with a fresh fill, when the tab is shown.
- **When the stream is not there** (limit reached, the server restarting, the command ended): the view falls back to the old timed read until the stream is
  back.

Not tested on hardware yet.

## See the network map

Network > Network map draws how this server reaches the network: the way out, the gateway, the host, its bridges, the instances and their services,
with the traffic as moving dots (more and faster dots for more traffic; none for none). The same facts as a table: the button above the map.

The full guide is [Network map](network-map.md).

1. Open Network > Network map. The graph as text: `sudo hs sys netmap`.
2. Hover or press Tab to reach a node; Enter or Space opens its details, with a link to the page of that node where there is one.
3. The map follows the server: an instance that starts or stops changes the graph by itself. The traffic comes from a stream of its own
   (`GET /api/netmap/stream`, about every 2 seconds, only while the page is open, 4 streams in all). When the stream is not available the page says so
   and reads the counters every 5 seconds until it is back.
4. In demo mode (`npm run demo` in `web/`) the page shows a made-up graph with made-up traffic; nothing is read from a server.

The page loads when you first open it, so the other pages do not wait for it. Not tested on hardware yet.

## Inspect the live state

When live state is on, one page lists every topic the collector reads and what is stored for it.

1. Open System > Live state. The same list as text: `sudo hs sys live inspect`.
2. Read a row: Source is the `hs sys` command the topic runs, Every is how often it is read, State is `fresh`, `stale`, `failing`, `never`,
   `pending` or `off` (its capability is off), Age is the time since the last good reading, Gen counts the readings, Exit and Error are the
   last failure with its time, Capability, Groups and (when known) Needs say when it is read and which changes wake it.
3. Press Refresh on a row to ask the collector to read that topic now. The row updates by itself a moment later.
4. Press Raw to see the stored output of the topic: the first 64 KiB, and how many bytes there are in total.

Topics of extensions appear with an "extension" tag and come and go with their package. With the capability `live-state` off the page only
says so. The page updates over the same stream as the others and polls every 5 seconds while the stream is down. Not tested on hardware yet.

## Check that it worked

- Open the page and sign in; the summary shows your server and its disks.
- `systemctl status hs-web` says `active (running)`.
- `curl -s http://127.0.0.1:8480/api/hello` answers on the server itself (use your `webPort`; with `webTailscale` the page listens on the
  server only).

## If something goes wrong

| Symptom | Cause | Fix |
| --- | --- | --- |
| "Domain sign-in is not available" | storage is locked or the controller VM is not running | sign in as `adminuser`, unlock, start `dc1` |
| "Too many tries. Wait ... seconds." and you are sure of the password | five wrong tries from your address | wait, or run `sudo hs web unlock-login` on the server |
| A page stays empty or says "could not be read" | the command behind it does not answer, for example storage is locked | run it in a terminal: `sudo hs sys <area> <command>` |
| A list looks old right after a change | the page re-reads every few seconds | wait, or press the refresh button |
| The build stops with `hash mismatch ... got: sha256-...` | the frontend's dependencies changed | put the shown value into `npmDepsHash` in `pkgs/hs-web.nix`, rebuild |
| 403 "Your role (viewer) may not do this" | the person's domain group gives a lower role | add them to `hn-app-managers` or Domain Admins, then sign in again |
| 401 with a token | expired, revoked, or its owner left the groups | create a new one: `sudo hs token create <name>` |
| The page is not reachable from another PC | wrong port or `webLan` is `false` | check `webPort`, use the Tailscale address |

`journalctl -u hs-web -e` shows what the page logs (sign-ins and changes, never passwords).

## Next

- [Users and shares](users-and-shares.md) and [Storage and disks](storage-and-disks.md): the tasks behind the pages.
- [Operations](operations.md): health, notifications and updates.
