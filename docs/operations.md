# Operations

Keep the server healthy without watching it: see its state, get a message on your phone when something is wrong, check disks and
memory, track expiry dates, update with a safety net, survive a power cut, and find out when the whole server is gone.

## Before you start

- A running server ([Install](install.md)).
- A phone with the ntfy app if you want push messages (free, from the app store).
- `hs` commands that change something use `sudo`; the ones that only look do not need it.

## See the state of the server

Three commands, from short to detailed:

```bash
hs status
```

```bash
hs health
```

```bash
hs doctor
```

`hs status` is the overview. `hs health` lists the problems of the health check, each with the command that helps, or says
`No problems found.` `hs doctor` answers "is everything fine?": health problems, failed and running jobs, pending parity work, locked
storage. The same three status lines appear when you sign in over SSH (`hs motd`).

A package can report a check as information, for example a gaming PC that is switched off. System > Health lists these under "For your
information" with the package named (`hs sys health info`). They are not problems: they are not counted, not acknowledged and no message is sent.

Two more checks that change nothing:

- `hs smoke` runs a quick test that the commands work on this server (needed programs installed, read-only commands run).
- `hs cleanup` finds leftovers (old containers and services, stale mounts, old generations) and prints the command that removes each.

`hs ports` lists the open ports of the server and of each container and warns when an administration page is behind the reverse proxy.
The health check itself runs every 15 minutes by a timer; it is the only thing that raises an alarm.

## See who did what

```bash
hs audit
```

Every command that changes the server leaves one line in the event log: who ran it (the user who used `sudo`, or `web`, `timer`, `job`),
when, whether it worked, and the words that were typed to find the command, for example `share add`. `hs audit 100` shows the last 100.
Nothing that was typed after those words is kept, so a password or a key given as an argument never reaches the log. Reading commands,
the timers' own hooks and the event log itself are not recorded. The lines are kept as long as the rest of the event log. Not tested on
hardware yet.

A change made in the web interface names the signed-in person (`<user>`, or `<user> via token <id>` for an API token); the token itself is never logged. Roles and tokens are in [Web interface](web-interface.md#roles-and-sign-in-of-programs).

### Locked out of the web interface

The local account (`adminuser`) is always an admin and works while the domain controller is down. If sign-in is locked after wrong tries, run `sudo hs web unlock-login` on the server. A token above viewer stops working after a day without a domain controller; create a new one with `sudo hs token create <name>` once it is back, or revoke it with `sudo hs token revoke <name>`. Planned, not built: a second factor, with a reset command for a lost one. Not tested on hardware yet.

## Get push messages

The server sends a message when its list of problems **changes**, not every 15 minutes. The route is ntfy: a service that passes messages
to the app on your phone. The last part of the address is the topic; anyone who knows it can read along, so make it long and random.

1. Install the ntfy app and subscribe to a topic, for example `https://ntfy.sh/<long-random-topic>`.
2. Give the address to the server (no rebuild needed):

```bash
sudo hs config set notifyUrl https://ntfy.sh/<long-random-topic>
```

3. Send a test:

```bash
hs health test
```

The phone shows a message titled `<server>: test`. Without `notifyUrl`, all messages only go to the journal (`journalctl -t hs-notify`),
where they are in any case. Do not point `notifyUrl` at a service on this server: while storage is locked everything is down and you would
not hear about it. Send your own message from a script with `hs notify "Title" "Text"`.

What triggers a message:

| Problem | Threshold |
| --- | --- |
| A ZFS pool is not healthy | state other than `ONLINE`, or errors in the pool |
| A ZFS pool is not imported | a pool NixOS imports at boot (`zfs-import-<pool>`) is missing from `zpool list` |
| A ZFS import or scrub unit failed | `zfs-import-*` or `zfs-scrub*` in state failed, like the `hs-*` jobs |
| A SnapRAID data or parity disk is missing or not mounted | state `MISSING` / `UNMOUNTED`; no parity disk at all |
| A disk fails its SMART self-check | health `FAIL` |
| A disk has sectors it cannot read | pending sectors above 0 |
| A disk is too hot | 55 °C or more |
| A pool, `/bulk` or the system disk is nearly full | 90 % or more |
| A scheduled job or an important service failed | each job that has `onFailure` sends its own message at once |
| The domain controller's certificate runs out | 30 days before (only with a domain) |
| A share is open to everyone | only with a domain |
| An expiry date comes close | see [Track expiry dates](#track-expiry-dates) |
| The last scrub is older than 21 days or found errors | scrub checks |

A persistent problem is repeated once a day; when everything is fixed a message titled `all clear` arrives.

**Several channels, quiet hours.** Notifications go through channels (`notifyUrl` is the channel `main`). Add a second one, with its own minimum
priority and its own quiet-hours rule:

```bash
hs notify channel providers
```

```bash
hs notify channel list
```

`hs notify channel add <name> --provider ntfy --secret url [--min-priority P] [--quiet respect|ignore]` creates one, `hs notify channel test
<name>` sends a test to it, `hs notify channel set` changes it.

**A problem you know about.** Silence one problem until it clears, or take the silence back:

```bash
hs health ack
```

`sudo hs health ack <id>` silences the problem with that id, `sudo hs health unack <id>` undoes it. After an automatic pause of the sync, scrub and
cache mover (the optional "notify and pause" reaction), `hs health resume` lifts the pause.

An acknowledged problem is not sent, not counted in `hs health`, `hs doctor`, the top bar or the Overview, and shows dimmed as "acknowledged" on
the Health page and in the bell. The acknowledgement ends by itself in three cases, so a real failure is never hidden for good:

- the problem clears: the next failure is a new problem and sends its message again;
- the problem gets worse: a worse state has its own key (a disk that was "SMART warning" and is now "SMART failing"), so it is not acknowledged;
- the time you gave is over: `--for` takes minutes, hours, days or weeks.

```bash
sudo hs health ack <id> --for 7d --note "new disk arrives on Friday"
hs health list-acks
```

`hs health list-acks` shows what is acknowledged, since when, until when, by whom and why. On the Health page and in the bell (the inbox in the
top bar) an admin acknowledges with a button and takes it back with Undo. Each change writes the events `health.acked` and `health.unacked`
(they show in the event log).

Not tested on hardware yet.

## Check the disks

```bash
hs disk list
```

The list shows every disk with a health verdict. For one disk (use the name `hs disk list` shows; `sda` is an example):

```bash
hs disk sda health
```

It prints the verdict, the age, bad sectors and errors. Start a self-test inside the disk (the disk stays usable) and read its outcome later:

```bash
hs disk sda test short
```

```bash
hs disk sda results
```

`hs disk selftest short` tests every disk. A `long` test takes hours. Disks that spin down to save power are shown by `hs disk spindown`
(`diskSpindownMinutes` in `machine.toml` sets the timer; `diskSpindownPools = { backup = 10, bulk = 30 }` gives a pool its own time, `0` means
never). `hs disk spindown power` shows which disk is asleep, how often it woke today and the power that is measured, each number with its
source. If a disk never sleeps, `sudo hs disk spindown log 24` records for a night what woke it and which systemd unit started in that
minute; the maintenance window is 03:00 to about 06:30. Details: [Storage and disks](storage-and-disks.md). Not tested on hardware yet.

**Automatic reaction.** Three switches in `machine.toml`, all off by default, decide what the server does by itself when a disk or pool is in
trouble: `autoMitigate` pauses the parity sync, the scrub and the cache mover (`hs health resume` lifts it), `autoMitigateFreeze` freezes the
apps that write to a pool above 98 % full (`hs storage incident resume` lets them run again) and `autoMitigateBackup` starts one backup when
a disk turns failing and the newest backup is older than 24 hours. None of them deletes or copies anything from disk to disk. The levels
and what each does are in [Storage and disks](storage-and-disks.md). Not tested on hardware yet.

**Trash.** Files deleted in the file manager wait in a hidden trash folder on their file system for 14 days; a timer empties it at 03:35. The
space is not free until then. See [Storage and disks](storage-and-disks.md). Not tested on hardware yet.

**Scrub.** A scrub reads everything and finds silent damage. ZFS pools scrub weekly by themselves; for SnapRAID run one by hand when the
health check says the last one is older than 21 days:

```bash
sudo hs pool bulk sync --scrub
```

Pool and disk changes (add, replace, remove) are in [Storage and disks](storage-and-disks.md).

**Fans.** Blow the dust out of the case: run the fans at full speed for 8 seconds (3 to 30) and then back as they were:

```bash
sudo hs fans clean
```

## Test the memory

The server has no ECC memory, so a RAM error shows up as crashes, random checksum errors or damaged files. Test after an unexplained crash,
after new RAM, and once when you set the server up (at least one full pass, overnight is fine). Memtest86+ is in the boot menu. The menu is
hidden by default, so ask for it once:

```bash
sudo hs reboot --menu
```

Choose **Memtest86** (it needs a monitor and keyboard on the machine; the server is off the network while it runs). Red lines are errors:
test the modules one by one and replace the bad one. Afterwards reboot normally and unlock the storage with `hs unlock`.

## Track expiry dates

Some things run out on a date and nobody remembers: a certificate, an API token, a domain. List them and the health check warns **30 days**
before, **7 days** before (urgent) and after the date, then once a day.

```bash
sudo hs expiry add cloudflare-token 2027-03-01 "create a new tunnel token in the dashboard, then run hs recipe cloudflared"
```

```bash
hs expiry list
```

```bash
sudo hs expiry remove cloudflare-token
```

Adding an existing name sets a new date, which is how you renew. Good candidates:

| What | When | How to renew |
| --- | --- | --- |
| Certificate of the domain controller | its expiry date | the health check also checks it itself; the entry is a second safety net |
| API token of a tunnel or DNS service | the date you chose | create a new token, run the recipe again |
| Domain name | renewal date at the registrar | renew; check auto-renew |
| Keys of the off-site backup (S3/B2) | key expiry | create a new key, update the backup settings |
| The rotating off-site backup disk (`offline-backup-disk`) | set by the server 30 days (`offsiteDiskDays`) after each copy to the disk | swap the disks and run `hs backup offsite now` ([Backup and recovery](backup-and-recovery.md)); it renews the date |
| Tailscale and other service keys | per service | renew in that service |

## Know that the configuration is in sync

The health check compares `/etc/nixos` with Git (locally, no network):

| Message | Meaning | Fix |
| --- | --- | --- |
| `config:dirty` | uncommitted changes in `/etc/nixos`: the system does not run from Git and `hs update` may stop | commit or undo them |
| `config:diverged` | local and upstream commits at the same time; `hs update` only fast-forwards | merge or rebase by hand |
| `config:ahead` | local commits that are not pushed | push them |
| `config:unbuilt` | the last rebuild used another revision than the checked-out one | `hs rebuild` |

New commits upstream ("behind") are not a problem. A new server that has not been rebuilt yet reports nothing.

## Update with a safety net

See what an update would bring, then run it:

```bash
hs update --preview
```

```bash
sudo hs update
```

`hs update` pulls the latest configuration into `/etc/nixos` and rebuilds. If options are new in `machine.toml.example` it puts them into your
`machine.toml` (commented out, in their place), lists them and asks whether to rebuild now or stop to set them first. If nothing is new it says
so and skips the rebuild; `--force` rebuilds anyway (so does `hs rebuild`, which always builds).

**The safety net:** if the switch fails half way, or `sshd` or Incus are not running afterwards, the previous generation is switched back and a
message says so. A terminal is asked first; without a terminal (timer, job) or with `--yes` it happens at once; `--no-rollback` switches it
off. A failed build changes nothing and needs no rollback. For five minutes after the switch the health check is watched too: a problem that
was not there before also rolls back.

| Option | Effect |
| --- | --- |
| `--yes` | rebuild without asking (also when new options appeared) |
| `--stop-on-new` | stop without asking when new options appeared; `hs rebuild` follows once you set them |
| `--no-rollback` | leave a broken system as it is |
| `--force` | rebuild even if nothing is new |
| `--verbose` | show the details |

To go back by hand to the previous generation:

```bash
sudo nixos-rebuild switch --rollback
```

`hs update` and `hs rebuild` refuse while encrypted storage is locked.

## Update channels

By default `hs update` follows the newest signed release (`stable`). Two other channels exist for a second server or a test machine. Set one
with `hs config set updateChannel beta`; it takes effect at the next `hs update` and moves nothing by itself.

| Channel | `hs update` follows | For |
| --- | --- | --- |
| `stable` (default) | the newest signed `vX.Y.Z` tag | every server that holds data |
| `beta` | the newest signed `vX.Y.Z-beta.N` or `vX.Y.Z` tag | a second server or a test machine |
| `edge` | the head of the `develop` branch | a server whose data may be lost |

```bash
hs config set updateChannel beta
sudo hs update
```

Switching to a newer channel (stable to beta, beta to edge) asks you to type the channel name. `hs update` and `hs update --preview` print the
line `channel: <name> (<tag or branch>)`. Beta and edge never update by themselves: without a terminal and without `--yes` (a timer, for
example) `hs update` stops with a note. A tag is checked against the release key in `config/trusted-keys/server.allowed_signers` and refused
when the signature is missing or wrong; `hs update` never moves to a tag that is older than the installed version. Until the first release tag
exists, every channel but edge follows the current branch as before.

In the web interface the page Settings, Releases shows the three channels side by side, marks the current one and shows the version the next
update would install. Choosing a channel opens a plan: it checks the tag signature, says whether an update is waiting and, for a newer
channel, asks you to type the channel name. The same through the command line: `hs sys release plan channel beta` and
`hs sys release start channel beta --confirm beta`. Moving to an older channel (edge to beta, beta to stable) never downgrades: the server
stays on the installed version until the channel catches up, and the plan says so. The switch itself installs nothing; the Update button on
Settings, Updates does.

Apps and extensions from the package repositories follow the same setting through `hs pkg`: on `stable` only `vX.Y.Z` tags count, on `beta` the
newest signed `vX.Y.Z-beta.N` or `vX.Y.Z` tag counts. `edge` counts as `beta` for packages, because packages are only ever taken from a signed
tag, never from a branch head. Every tag is still checked against the repository's key.

Not tested on hardware yet.

## Move to a new NixOS release

Twice a year NixOS publishes a release (for example 26.05, then 26.11). Hobnix follows one NixOS channel; a new release is a step you take
on purpose, never part of a normal `hs update`. The channel Hobnix was tested with is named in `config/nixpkgs-pin.toml`.

**A release change updates every package on the server and can fail halfway. Do it when you can reach the machine, after a backup, and
never on the day you need the server.**

Before you start: a restore test of your backup ([Backup and recovery](backup-and-recovery.md)), `hs health` clean, the checkout in sync
([Know that the configuration is in sync](#know-that-the-configuration-is-in-sync)).

1. Update Hobnix first. The release that supports the new NixOS names it in its release notes; do not move the channel before that.

```bash
sudo hs update
```

2. See the channel the server follows now.

```bash
sudo nix-channel --list
```

3. Point it at the new release (here nixos-26.11) and fetch it. This replaces the line named `nixos`; `stateVersion` in the configuration stays as it is.

```bash
sudo nix-channel --add https://nixos.org/channels/nixos-26.11 nixos
```

```bash
sudo nix-channel --update
```

4. Build and switch. This can take many minutes and restarts services.

```bash
sudo hs rebuild
```

5. If it fails or something is wrong afterwards, go back to the previous generation, then put the old channel back with step 3.

```bash
sudo nixos-rebuild switch --rollback
```

Check that it worked: `nixos-version` shows the new release, `hs health` says `No problems found.`, the services you use answer.

**For maintainers:** the release change in the repository is one pull request that changes `channel` and `rev` in
`config/nixpkgs-pin.toml` together (`bash scripts/dev/nixpkgs-pin.sh` shows the head of a channel), lets CI evaluate it, and ships with
release notes. The upgrade path (a server on the old release, switched as above) is rehearsed in the test-lab.

Not tested on hardware yet. The test-lab rehearsal of a release change is not done: see issue #435 (upgrade test).

## See what changed after an update

Every user-visible change ships with a short entry, so you can read what an update brought without reading commits.

```bash
hs changes
```

Lists the entries that the last update added (date, type, title, and the guide to read). Not tested on hardware yet.

```bash
hs changes --since 2026-10-01
```

Lists the entries from that date on. Not tested on hardware yet.

```bash
hs changes --all
```

Lists every entry. Not tested on hardware yet.

When an update finishes, the push message says how many new entries there are. In the web interface, open Operations > What's new: the
tree row and the Summary page show how many entries you have not seen yet, and the list links to the guide of each change. Not tested on
hardware yet.

## Survive a power cut: UPS

A UPS bridges short outages and shuts the server down **cleanly** before the battery runs out. Without one, ZFS, SnapRAID and the databases
in your containers risk damage at every power cut. The server reads the UPS through NUT; everything is off while `ups` is missing in
`machine.toml`.

What to buy: a line-interactive UPS **with a USB data port** (APC, Eaton, CyberPower; almost always the driver `usbhid-ups`). One without a
data port cannot shut the server down. Plan about twice the server's wattage (`hs ups` shows the load later); 5 to 10 minutes of runtime
is enough for a clean shutdown. Connect only the server (and router or switch), no heater, printer or monitor, and plug in the USB cable.

Find the driver with the UPS switched on:

```bash
nix-shell -p nut --run "sudo nut-scanner -U"
```

Put it into `machine.toml` (all keys are optional; `ups = "usbhid-ups"` is enough when only the driver is needed):

```toml
ups = { driver = "usbhid-ups", name = "ups", shutdownMinutes = 5 }
```

| Key | Meaning | Default |
| --- | --- | --- |
| `driver` | NUT driver | `usbhid-ups` |
| `name` | name of the UPS | `ups` |
| `port` | connection | `auto` |
| `shutdownMinutes` | shut down after this many minutes without mains power (0 = only when the battery reports empty) | `5` |
| `lowBatteryPercent` | charge the UPS reports as "empty" (not every driver allows it) | the UPS's value |

```bash
sudo hs rebuild
```

```bash
hs ups
```

It shows mains or battery, charge, runtime and load; the raw values are `upsc ups@localhost`. In an outage you get "power failure" on the
phone; if the power returns within `shutdownMinutes` you get "power is back" and nothing happens, otherwise (or when the battery reports empty)
the server shuts down cleanly. `hs health` also reports battery operation, an empty battery, a needed battery replacement and a UPS that cannot
be read. After a shutdown the server stays off unless the BIOS says "Restore on AC power loss: Power On" (usually what you want); and with
encrypted disks it is locked after the start (`hs unlock`).

**Test it, in this order.** First `hs ups` shows mains power and 100 %. Then pull the UPS's mains plug for about 20 seconds: `hs ups` shows
"ON BATTERY" and the phone shows "power failure"; plug it back in. For the shutdown test set `shutdownMinutes = 1`, rebuild, pull the plug and
wait a minute: the server must shut down cleanly. Plug in, start the server, read `journalctl -b -1 | tail`, and set your value again. A full
runtime test stresses the battery: do it once with a new UPS and after a battery replacement. The log of the process:
`journalctl -u upsmon -u upsd -u upsdrv -u hs-ups-deadline`. Not tested on hardware yet: it was written and tested with a fake `upsc`.

If `hs ups` says "not reachable", check the cable and `lsusb`; usually the driver is wrong. If the charge is missing in `upsc`, the driver does
not report it (the timed shutdown still works). Containers cannot read the UPS: NUT listens on the server only.

## Start faster

Measure first (no root needed):

```bash
systemd-analyze
```

```bash
systemd-analyze critical-chain
```

Time spent in the BIOS menu counts as firmware time, so reboot once, leave the BIOS alone and measure after you sign in. What usually decides:

| Part | What helps |
| --- | --- |
| Boot loader | the menu is hidden (`boot.loader.timeout = 0`); hold the space bar while starting to get it, or `sudo hs reboot --menu` |
| Network | DHCP can take several seconds after link-up when the switch port runs Spanning Tree: set the port the server uses as an **edge port** ("PortFast", "fast forwarding") in the switch. Never on a port to another switch or the router, and do not switch Spanning Tree off for the whole switch |
| Firmware | UEFI-only mode, no boot logo, the board's "fast boot", and nothing else you do not need; the options differ per board |
| SATA | a controller that reports many empty ports can make the kernel wait at each one |

Check whether the network wait is yours:

```bash
journalctl -b -u dhcpcd --no-pager
```

The time between "carrier acquired" and "leased" should be about a second. Enter the BIOS from the running server, also without a keyboard:

```bash
sudo hs reboot --firmware
```

**If the screen stays black after changing fast-boot options**, the integrated graphics may have been switched off. Plug the monitor into the
graphics card, run `sudo hs reboot --firmware` over SSH, set the integrated graphics back to enabled and save. If nothing shows even then, clear
the CMOS with the board's jumper (power cable out, bridge it for about ten seconds) and start with the monitor on the card; all BIOS values are
default afterwards. Boot time does not include `hs unlock`: with encrypted storage the server waits for it.

## Measure the live state on the state database

The live state (ADR 0026, docs/adr/0026-live-state-one-mode-one-store.md) is kept in the state database by the collector `hs-live`; there is no setting
and no Redis. This measures on your server what it costs: how many writes per minute, how much the database grows and how long a change takes to reach
the stream of the web interface. It needs `webUi = true` on a homeserver. A refresh request (a change from a terminal, `hs sys live refresh`) wakes the
topic within about a second; all other topics are read at their intervals.

See what the collector itself costs (CPU seconds since it started, reads started in the last minute per topic; no `ps` needed). The collector keeps itself in bounds: a topic is left alone for ten times as long as its last read took, and when all reads together keep more than half a core busy the timed reads slow down (`stretch` in the list; `HS_LIVE_DUTY`, `HS_LIVE_BUDGET`). Not tested on hardware yet.

```bash
hs live load
```

Measure for an hour (it offers to run as a job; the default is 30 minutes, one probe every 10 seconds):

```bash
sudo hs live measure --minutes 60
```

Watch the collector while it runs:

```bash
journalctl -u hs-live --no-pager -n 30
```

What you see: one line per minute (`minute 3 of 60: 18 probes, median 540 ms`), then the result as a list and a file `/var/lib/hs/live-measure-<date>.md`
with a `.tsv` next to it. It holds writes per minute (documents, failures, heartbeats), payload per minute, commits over 100 ms, the growth of the
database and its WAL, and the change latency (min, median, p95, max). The latency ends where the web interface puts the change into the stream queue;
the network hop and the browser's drawing time are not in it. The result has no host name. Paste the `.md` file into issue #566. Not tested on hardware yet.

### Delay per topic

The collector also keeps, for every topic that was asked to read again, the last and the worst time from the request to the new generation, and the
Live state page sends how long it needed to show it. Look at them with:

```bash
hs sys live status
```

Columns 11 to 14 hold the milliseconds (`-` = no sample yet), and the Live state page shows the same. The request time of a change from a terminal is
the second the counter was changed, so the server number is at most one second too large. A change that only comes from the timer has no trigger and no
sample. Over 10 seconds in the worst of the last 20 samples of a topic, `hs sys live check` and the Health page say so. Not tested on hardware yet.

### Pages nobody has open cost almost nothing

A few live topics exist only for a page: SMART findings (`disk-health`), free space and sizes (`monitor-disks`, `shares-overview`, `shares-deleted`,
`vault-usage`, `fm-locations`, `backup-overview`, `backup-shares`). While no page that shows them is open, the collector reads each one only
every 2 to 10 minutes (their idle interval); when you open the page it reads them at once, and the page shows `fresh` after a moment. The web interface
tells the collector what is open: it writes one lease per wanted topic into the table `demand` (30 seconds, renewed every 10 s while the page is
open). A stopped or killed web interface leaves leases that run out by themselves, and the topics go back to their idle interval. Nothing a health
check or a notification reads is ever idle. A change you make (a hook, a named event) still reads the topic at once. Look at it:

```bash
hs sys live inspect
```

The Live state page has a column Demand: `always`, `idle 5 min`, or `watched` while a page is open. A topic that rests inside its idle period shows the
state `idle`, not `stale`. Not tested on hardware yet.

## Take a performance baseline

`hs perf baseline` takes the numbers of section 14 of [the core daemon plan](PLAN-core-daemon.md#14-measure-first), so you can compare two states of the
server, for example before and after a part moves to Rust. It reads only: it changes no setting and no data and asks the collector to read nothing
again. The one file it writes is the new file you name with `--out`. The result holds numbers, the Hobnix version and the names of the page reads of
the core: no host, user, share or package name, no address, no secret.

Before each run, wait until no job, backup, parity sync or scrub runs, and do not update or rebuild during the run. Keep the same packages and apps on
between two runs that you compare. A run takes more than half an hour: start it inside `tmux`, so a lost SSH connection does not end it.
Ctrl-C stops the whole run, also while a read runs, and nothing is saved.

The file of `--out` appears when the run is done. If it cannot get that name then (something else has the name by now, or the file system of the
folder has no hard links, such as FAT or exFAT), the command fails and names the file beside it that holds the result. If it cannot write a file
there at all, it prints the result: copy it before you close the terminal. Not tested on hardware yet.

**Run 1, no page open.** Close every browser tab and app that shows the web interface and wait 15 minutes. Then run this (30 minutes, then the reads).
Not tested on hardware yet.

```bash
sudo hs perf baseline --minutes 30 --out /root/baseline-closed.tsv
```

**Time from a change to the open page.** Open the web interface in one tab and keep it visible. This second command is not read only: every 10 seconds
it counts a test counter up in the state database, it writes two result files, and when it ends the collector reads the system topics once. It also adds
some load of its own, so it does not run during a baseline. Not tested on hardware yet.

```bash
sudo hs live measure --minutes 10 --out /root/baseline-latency
```

**Run 2, one page open.** Wait 5 minutes and leave the same page open for the whole run. `--latency` copies the latency numbers of the measurement
above into the result. `--no-reads` leaves out the reads, which run 1 already timed. Not tested on hardware yet.

```bash
sudo hs perf baseline --minutes 30 --no-reads --latency /root/baseline-latency.tsv --out /root/baseline-open.tsv
```

What you see: one line per minute, then a table of the numbers and, in run 1, a table of the reads. Check that `window.page` says `closed` in run 1 and
`open` in run 2. `mixed` means that a page was opened or closed during the run: take it again.

| Lines | Meaning |
| --- | --- |
| `hs-live.*`, `hs-web.*` | CPU and memory of the service from the counters of systemd, with everything it starts. `main_process_*` is the service's own process only. After a restart during the run the CPU is `-`. |
| `hs-live.reads_per_min`, `read_wall_s_per_s`, `stretch_max` | The collector's own numbers, the same as `hs live load` shows. |
| `host.*` | The whole server, containers and VMs included. `tasks_started_per_min` counts processes and threads. `cpu_steal_cores` counts on a server that is itself a VM: CPU time its host gave to others. It is not part of `cpu_cores`. |
| `measuring.window_cpu_cores` | What the measuring itself used while it watched. |
| `delay.change_to_stored.*` | From a change to the new stored value, as the collector recorded it. |
| `delay.stored_to_page.*` | From the stored value to the page showing it. Only the Live state page records this. |
| `latency.*` | The result of `hs live measure`. It ends where the web interface sends the change; the network and the browser's drawing are not in it. |
| `reads.*`, `read.<name>.*` | Seconds of each page read: `wall_s` and `cpu_s` of one clean run, then the parts of a second run: `dispatcher_*`, `tools_*` (external tools such as `zpool`, `incus`, `systemctl`) and `rest_*` (the script, its shells, Python, `jq`). |

The delay lines count since the collector first recorded a topic, not only during the run. So `worst_ms` can stay high after the cause is gone.

**The load it adds.** While it watches: two `systemctl show` and one `jq` every 10 seconds, and a read of the live state at the start, every
5 minutes and at the end. These processes are part of `host.tasks_started_per_min`. In a count on a development computer, not on a server, one read of
the live state started about 120 processes and threads and the rest less than 60 a minute, so less than 100 a minute over a long run. A page that was
open only between two reads of the live state does not show in `window.page`. After the watching, 21 reads run one after
the other, each twice, with 1 second between two reads. They are the reads the pages run, so they cost what opening those pages costs, and one that
asks the disks can wake a sleeping disk. The read of the backup snapshots is left out, because it mounts the backup disk and locks the backup
repository.

**What it cannot measure:**

- **Processes started by one service.** Linux keeps no such counter for a service, so the number is for the whole server. Compare runs on a server
  that is otherwise quiet.
- **CPU of a service that a tool asks** (the Incus daemon, Samba, systemd). It is part of `host.cpu_cores`, not of a read's CPU time.
- A tool that a script calls by its full path counts as `rest`.
- Only the page reads of the core are timed one by one, not every topic of the collector and no read of a package. They run from your shell, not from
  the service, so a read can differ a little from the same read inside `hs-live`.
- Build time and the size of the system are not part of it.

You can also time the reads alone. Without `--skip` this includes the backup snapshots. Not tested on hardware yet.

```bash
sudo hs timing --split --skip "backup snapshots"
```

### Compare two runs

Keep the files. After the change, take the same runs again into new files (a file is never overwritten), then compare run with run. Not tested on
hardware yet.

```bash
sudo hs perf baseline --compare /root/baseline-closed.tsv /root/after-closed.tsv
```

The table shows each number before and after and the change in percent. A warning says when the two runs differ in the number of cores, in the length
or in whether a page was open. Take one run twice without a change first: a later difference that is not clearly larger than the difference between
those two says nothing. Compare `host.*` and the memory numbers only when the same apps ran. The files are plain lines of a name, a tab and a value, so
you can paste them into the plan or an issue.

## Reach the server from outside

Do not open ports at home. Use a private network:

- **Tailscale** (capability `tailscale`): the server joins your tailnet, so you reach it from anywhere. After the capability is on, join once
  by hand with `sudo tailscale up`; add `--advertise-routes=192.168.1.0/24` to reach the whole home network. `sshOverIp = false` in
  `machine.toml` then closes SSH on the network cards so it works only over Tailscale. **Set it only after SSH over Tailscale works**, otherwise
  you lock yourself out; the configuration refuses it while no private-access provider is on.
- **The web interface** has its own HTTPS option over Tailscale ([Web interface](web-interface.md)).
- Games and other public services are not tunneled by the server. Use a small public server in front (next section).

## Notice when the server is gone

A server cannot report its own power cut, crash or broken router. So it checks in every 15 minutes with something **outside** ("I am alive"),
and a second machine raises the alarm when the check-in stops. You need a second long random topic, **not** the one you subscribed to:

```bash
sudo hs config set heartbeatUrl https://ntfy.sh/<another-long-random-topic>
```

From the next health check on, the heartbeat arrives (priority "min", so your phone stays quiet). The watcher runs on an edge node (below) or
any small server: it reads that topic every five minutes and also checks that your public addresses answer. You get an **urgent** message
when no heartbeat arrived for 45 minutes or an address does not answer (or answers 5xx), at most one reminder a day, and a message when all is
well again. A 404 counts as "reachable". Put no administration pages into the watched addresses. If ntfy.sh cannot be reached from the watcher,
the heartbeat is not judged, so there is no false alarm. Anyone who knows the heartbeat topic could send a fake heartbeat: keep it secret.
This is a second net next to the health check, not a replacement.

## Run a public edge node

An **edge node** is a small server in a data centre that is the public face of your setup: it receives your mail (and queues it while the home
server is down), forwards game ports, runs the outside watcher and publishes a status document. Nothing at home is opened; the edge node and the
home server talk over Tailscale. It is a node of this repository with `role = "edge"` and the capabilities `edge-mail`, `edge-ports`,
`edge-watcher` and `edge-status`. Not tested on hardware yet: it runs in tests with stand-ins, not on a real VPS.

Plan it first on an **empty** test VPS or VM next to anything real: use a Tailscale auth key with its own tag, a separate empty ntfy topic, and
no MX record. On a machine with the installer stick:

```bash
sudo hs-install --role edge --hostname edge-test
```

The wizard asks for the disk (you type its name), your SSH key and the time zone, erases only that disk and applies the `edge` preset. On a
server that already runs NixOS, apply it yourself:

```bash
sudo hs preset apply edge
```

Put the Tailscale auth key into `/var/lib/hs/tailscale-authkey` (mode 0600, read on first start only), set the two push addresses with
`hs config set notifyUrl ...` and `hs config set heartbeatUrl ...`, and fill the section "Edge node" of `machine.toml`:

| Option | Meaning |
| --- | --- |
| `edgeDomain`, `edgeMxHost`, `edgeAcmeEmail` | the mail domain, the name of the mail host (its A record points at this VPS) and the e-mail for the certificate |
| `edgeStalwartIp`, `edgeWingsIp` | Tailscale addresses of the mail server and of the game host at home |
| `edgeGamePorts`, `edgeGameTcp`, `edgeGameUdp` | the game ports to forward |
| `edgeWatchSites` | the public addresses the watcher checks |

An empty value switches off only its part and warns at the rebuild. The build **refuses** a game port range that contains 22, 25, 80, 2222 or
41641 (never forward "everything"). Then:

```bash
sudo hs config check
```

```bash
sudo hs rebuild
```

Read the node's status document and run its health check (a dry run sends nothing):

```bash
hs sys edge status
```

```bash
hs edge health --dry-run
```

On the **home server** register the edge node and let it read the status over SSH (a key that may only say `status`, never a shell):

```bash
hs node add edge-test <tailscale-name-of-the-edge-node> --kind edge
```

```bash
hs node key edge-test
```

The second command prints a line `nodeKeys = ["ssh-ed25519 ..."]` for the edge node's `machine.toml`; rebuild there, then:

```bash
hs node status edge-test
```

Close public SSH last, and only once SSH over Tailscale works (`sshOverIp = false`, see above). The switch of DNS and MX records is never done by
a command: it is a checklist you work through by hand (`docs/PLAN-nodes.md`, "Cutover checklist"). What a trial run does not prove: real mail
delivery from the internet, outgoing mail, long game sessions through the forwarding, and a reboot of the real VPS.

## Set up a server from a blueprint

A **blueprint** is a signed, ready-made choice from a package repository: parts, a few plain settings, Docker and apps. It only fills what is
not set yet and never overwrites a value. Look first:

```bash
hs blueprint list
```

```bash
hs blueprint apply <name> --dry-run
```

Without `--dry-run` it shows the same plan, asks (a typed name for a blueprint from a repository you added, and where Docker asks for one)
and starts one background job. A failed rebuild or Docker step stops the job; a failed app does not stop the next one. An app that needs an
answer from you is left to you: it shows up in the first-run checklist with its command. When the repositories offer no blueprint, the list
is empty. Not tested on hardware yet.

## Apps that are not healthy or have an update
The weekly summary mentions an update of every app whose policy is `notify`; an app set to `pinned` is not mentioned. An update is not a
health problem. An app that runs but fails its declared check shows as unhealthy in the app catalog. See and set the policy:

```bash
hs apps policy <instance>
```

How install, retry and remove work: [Containers and apps](containers-and-apps.md). Not tested on hardware yet.

## Optional parts from hobnix/capabilities
Some optional parts of the server (capabilities) can come from the default repository `official` (the old repository `capabilities` is frozen) instead of the core. Not tested on hardware yet. They are packages of the kind `capability`: installed from a signed release, switched on, and built into the system by `hs rebuild`. Which parts live there today: none are moved yet; the pilot is planned (see "Planned" below).

See what the repository offers, then install one:

```bash
hs sys pkg capabilities
```

```bash
sudo hs pkg install <name>
```

A part that carries a Nix module is copied to `/etc/nixos/vendor/capabilities/<name>/`, and its hashes go into `vendor/capabilities.lock`. The rebuild trusts only that lock. `vendor/` is not part of the git checkout, so `hs update` never touches it. Switch the part on and build:

```bash
sudo hs ext enable <name>
```

```bash
sudo hs rebuild
```

Before it builds, `hs rebuild` checks that every part that is on is a core part or an installed package, and that its copy in `vendor/` matches the lock. If not, it stops with the name and the command to run; nothing is built. The options of an installed part appear in `hs config list`, `hs config set` and `hs config check`; they are read from files in `/var/lib/hs/generated/`, which `hs pkg install`, `update` and `remove` rewrite.

On a new server, the Optional parts step of the first-run wizard ([Install](install.md)) installs, switches on and rebuilds the parts you pick as one background job. If a step fails the job stops there; what was installed stays, off.

### Updates that wait for the core
`hs pkg updates` shows a newer release whose needs the server does not meet as a line "<name> <version> waits for core: it needs <level>". Run `sudo hs update`, then ask again.

### Put the previous version back
After `hs pkg update` replaced a part, the old copy and the old lock are kept. If the rebuild fails, `hs rebuild` shows a plan and asks you to type the name before it puts them back. You can do the same by hand, then rebuild:

```bash
sudo hs pkg rollback <name>
```

```bash
sudo hs rebuild
```

A NixOS generation rollback (boot menu) restores the old system but not `vendor/`: the next `hs rebuild` would bring the new copy back. Roll the package back first.

### Remove a part
Switch it off and rebuild first; `hs pkg remove` refuses while it is on, or while another part that is on needs it. See the plan, then remove:

```bash
hs pkg remove <name> --dry-run
```

```bash
sudo hs pkg remove <name>
```

The command asks you to type the name. Containers, data and the values in `machine.toml` stay. The option keys of the part are remembered as retired: `hs config check` then says they are unused because the part was removed, not that they are unknown.

### Backup
`hs backup config` includes `vendor/` with the other configuration files, and its list shows `vendor/` for the snapshots that hold it. Restore with `hs backup config restore --dry-run` first ([Backup and recovery](backup-and-recovery.md)).

### Planned
The checks of the two repositories against each other in CI, the release flow of hobnix/capabilities and the move of the pilot part `testlab` out of the core are planned (docs/PLAN-capabilities-repo.md, steps 10 to 12). Until then, do not expect a part to be there; `hs sys pkg capabilities` shows what is.

Not tested on hardware yet.

## What to check, and when

| When | What |
| --- | --- |
| Every day | nothing: the 15-minute health check and your phone watch for you |
| After each update | `hs health`, `hs doctor` |
| Weekly | `hs disk list`; glance at the web interface summary |
| Monthly | `hs expiry list`; `hs cleanup`; a restore test ([Backup and recovery](backup-and-recovery.md)) |
| After a crash or new RAM | the memory test |
| After a new UPS or battery | the UPS tests |
| Yearly | clean the fans; check the UPS battery age |

## Check that it worked

- `hs health test` puts a message on your phone.
- `hs health` says `No problems found.`
- `hs expiry list` shows your dates with the days left.
- `hs ups` shows mains power (when a UPS is set up).
- Stop the heartbeat for 45 minutes on purpose (or the watcher's source) and see that the alarm arrives.

## If something goes wrong

| Symptom | Cause | Fix |
| --- | --- | --- |
| No message arrives | `notifyUrl` unset or the topic differs from the one in the app | `hs config get notifyUrl`; compare; `journalctl -t hs-notify` |
| Too many repeated messages | a problem that stays | fix it, or `hs health ack <id>` |
| `hs update` stops | the checkout is dirty or diverged | see [Know that the configuration is in sync](#know-that-the-configuration-is-in-sync) |
| An update rolled back | a new problem appeared after the switch | read the message, fix the cause in the checkout, `hs rebuild` (`config:unbuilt` stays until then) |
| `hs changes` shows the newest ten | no update recorded yet (no stamp, e.g. a fresh install) | normal; the next update records it. The first update after this feature lists the backfilled entries as new |
| `hs ups` says "not reachable" | cable or wrong driver | `lsusb`, `nut-scanner -U`, `journalctl -u upsdrv -u upsd` |
| The server does not start after a power cut | BIOS setting | "Restore on AC power loss: Power On" |
| Storage is locked after a start | encrypted disks | `hs unlock` ([Encryption and vault](encryption-and-vault.md)) |
| `hs node status` does not answer | `nodeKeys` is missing on the node, the ACL lacks tcp 2222, or the vault is locked | add the key, fix the ACL, `hs unlock` |
| `mail.stalwart: false` in the edge status | the Tailscale ACL does not allow the edge node to reach port 25 of the mail server | adjust the ACL |

## Next

- [Backup and recovery](backup-and-recovery.md): the other half of keeping data safe.
- [Web interface](web-interface.md): the same health and notification pages in the browser.
- [Storage and disks](storage-and-disks.md): replacing a disk the health check flagged.
