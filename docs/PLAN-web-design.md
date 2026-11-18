# Plan: web design handover

Status: draft. Sections 1 and 2 have their decisions (1.4, 2.5); section 3 has its decisions (3.6); section 4 has its decisions (4.11); section 5 has its decisions (5.4); section 6 has its decisions (6.3).

The document ends when it is approved. Components (0.9), navigation and pages (0.11), package pages (0.12) and the live interface (0.10) are built against it.

## 1. Object model (#769)

An object is something the user can name, open and act on. Every object gets one address and one page. A thing that is only a setting of an object is a tab or a section on that object's page, not an object.

### 1.1 Objects and their pages

| Object | Page shape | Today | Notes |
|---|---|---|---|
| Node | object | `Nodes` (list + drawer), `NodeSummary`, `NodeHealth`, `NodeFacts` | The main node is the root, other nodes are objects. A remote node must not appear inside its own tree. |
| Pool | object | `Pools`, names `bulk` and `fast` fixed in `nav.js` and `Section.svelte` | Name comes from data (#456, #573). |
| Disk | object | `Disks` (list + drawer) | Thin slice (#776). |
| Share | object | `Shares` (list + drawer) | |
| File area | tool, not an object | `Files` | A browser over shares, not a thing with its own state. |
| Instance (container or VM) | object | `Instances` (list + drawer) | |
| Docker app | kind of App | `Docker`, `AppEditPage`, `AppWizardPage` | Same object as App below. |
| Package (recipe or extension) | object | `Marketplace`, `Extension`, no page per package yet | One page per package (#474, #478). |
| App (an installed package) | object | none, built from the manifest (#478) | Links to its package and its instance. |
| User | object | `Users` (list + drawer) | Local users and, with capability `ad`, directory users. |
| Group | object | `Groups` (list + drawer) | |
| Certificate | object | `Certificates` | |
| Backup job | object | `Backup`, `Expiry` | The target is a field of the job. |
| Job | object | none yet (#385) | Opened from any page that started it. |
| Event | list entry | `Events` (#391) | Not an object with a page: a filtered, time-ordered list that links to the object it is about. |
| Notification | list entry | `Notifications`, inbox (#619) | Same as Event. |
| Service | list entry | `Services` | Linked to the instance or app that provides it. |

Not objects: Summary, Health, Monitoring pages (Hardware, Diagnostics, Live state, Test-lab), Setup, What's new, Docs, Incident, Settings pages. They are views, checklists or settings. Section 2 places them.

### 1.2 Links between objects

An arrow is a link that every page shows, in both directions.

| From | To | Link |
|---|---|---|
| Node | all objects | the node an object lives on |
| Pool | Disk | the disks of the pool |
| Pool | Share | the shares stored on it |
| Disk | Pool | the pool it belongs to |
| Disk | Job | running or last disk job (check, replace) |
| Share | Pool, User, Group | where it is stored, who may access it |
| Instance | Pool, Share | where its data lives, what it mounts |
| Instance | App, Service | the app it runs, the services it provides |
| Package | App | installed copies |
| App | Instance, Service, Backup job | where it runs, what it provides, how it is backed up |
| User | Group, Share | membership, access |
| Backup job | any object | what it protects |
| Job | the object it changes | in both directions |
| Event, Notification | the object concerned | one link, always |

### 1.3 Rules

1. One object, one address. The address survives a reload and can be shared. Five objects have a page of their own, the others open as a quick look in their list (3.6).
2. A list shows rows of one kind of object. A row opens a quick look (#454) or the page.
3. An object page always shows its state, its links to other objects, its running or last job and its actions.
4. A name is data. No page, route or filter names a specific pool or disk.
5. A setting of an object stays on that object's page. Settings pages keep only what has no object (the machine, the web interface, updates).

### 1.4 Decisions

Decided 2026-11-18:

- **App is one object.** A Docker app is one kind of App. Every app gets one page, built from its manifest (#478). The `Docker` list becomes the Apps list filtered by kind.
- **Files is a tool of its own**, a browser over shares. It is not an object and not a tab of a share. A share page links to it.
- **A backup target is a field of the backup job**, not an object.
- **One user object.** Directory users (capability `ad`) use the same page with a read-only marker.
- **A remote node shows instances only** (assumed, not yet decided by the user; revisit in section 2).
- **No Jobs page exists today.** `nav.js` and `routes.js` have no entry; #385 adds it. The shell already has a Jobs and Logs drawer at the bottom (web/design/HANDOFF.md, "Shell"); the question for the templates is how that drawer and a Jobs page relate.

## 2. Navigation tree (#770)

Draft, not reviewed. Builds on the visual handoff of phase 1 (web/design/HANDOFF.md and the boards next to it). Look, tokens, the shell (top bar, tree, content, bottom drawer) and the states every page handles stay as they are. This document changes what is in the tree and how pages are shaped.

### 2.1 What counts as a place

A place is a page the user comes back to, to see the state of one kind of object or of one concern, and that has a short noun for a name. These are not places and leave the tree:

| Not a place | Why | Goes to |
|---|---|---|
| Incident | a one-time flow | an action on Pools and on the Health page |
| Setup | a checklist that ends | a banner on Summary while open; the page stays reachable by address |
| What's new | content, not state | the Updates page |
| Releases | a view of updates | a tab of Updates |
| Docs | a link out of the interface | the top bar |
| Nodes | the list of servers | the node switcher in the top bar, with the list as its page |
| Registries | a setting of Docker apps | a tab of Apps |
| Pool names `bulk`, `fast` | data (#456) | children come from the pool list |

### 2.2 The tree

Per node. Nine entries instead of twelve, and the three groups that each answer "is my server fine" become one.

| Group | Entries | Replaces |
|---|---|---|
| Summary | (the page itself) | Summary |
| Storage | Pools, Disks, Shares, Files, Encryption, Vault | Storage minus Incident |
| Instances | Instances, ISO images | Instances group, Docker list for instances |
| Apps | Installed, Marketplace, Registries | Apps, Docker, Marketplace |
| Network | Network (tabs: Overview, DNS, Ports, Router, Remote shares), Services | Network, Services |
| People | Users, Groups, Certificates | Identity |
| Health | Health, Jobs, Events, Notifications, Hardware, Diagnostics, Live state, Test-lab | Monitoring, Operations, and the new Jobs page (#385) |
| Backup | Backup, Expiry dates | Protection |
| Settings | General, Network and DNS, Storage, Backups, Users and access, Updates, Capabilities, Advanced | Settings minus Releases |

Extension pages (`/extensions/<name>`) are placed by a `group` key in the package's `[web.page]`, default Apps. Nothing is shown while no extension declares a page.

### 2.3 Every current entry

| Current entry | New place |
|---|---|
| Summary | Summary |
| Storage > Pools, bulk, fast | Storage > Pools; its children are the pools |
| Storage > Disks, Shares, Files, Encryption, Vault | unchanged |
| Storage > Incident | action on Pools and Health |
| Instances > Instances | Instances > Instances |
| Instances > ISO images | Instances > ISO images |
| Instances > Apps | Apps > Installed |
| Instances > Services | Network > Services |
| Instances > Docker, Registries | Apps > Installed (kind Docker), Apps > Registries |
| Marketplace | Apps > Marketplace |
| Network | Network |
| Identity > Groups, Users, Certificates | People > Groups, Users, Certificates |
| Monitoring > Hardware, Diagnostics, Live state, Test-lab | Health > same |
| Operations > Health, Notifications, Events | Health > same |
| Operations > What's new | Settings > Updates |
| Protection > Backup, Expiry dates | Backup > same |
| Docs | top bar |
| Nodes | top bar node switcher |
| Setup | banner on Summary |
| Settings > General ... Advanced | unchanged |
| Settings > Releases | Settings > Updates, tab |
| proxyserver and peer pages | unchanged for now; section 3 covers remote nodes |

### 2.4 Rules

1. A group has at least two places, or it is a place itself (Summary, Network).
2. No group page that only lists its children: a group page shows the state of the group and one or two actions (#457).
3. A capability that is off hides its entry, as today. A page opened by address still works.
4. Names are nouns for what the user sees; no entry is named after a task.
5. Pools, disks and other data never appear as fixed entries.

### 2.5 Decisions

Decided 2026-11-18:

- **Instances and Apps stay two groups.** Nine entries per node.
- **Expiry dates stays in Backup.**
- **Certificates are in People, Services in Network.**
- **The Jobs drawer stays and the Jobs page (#385) sits beside it.** How the two relate (what each shows) is for the page templates, section 3.
- **The Setup banner shows until every check is done.**

## 3. Page templates (#771)

Draft, not reviewed. Six shapes cover every page of the tree. A page picks one; it does not invent a seventh. What exists today: `shell/PageFrame` (storage locked, part off, node unreachable), `shell/PageHeader` (crumb, title, subtitle, actions), `shell/PageState` (loading, empty, error with old data), `ui/Split` + `ui/Drawer` (list and side panel), `ui/Wizard` (one question per step), `pages/Section` (group overview). The states themselves are decided in web/design/HANDOFF.md and stay.

### 3.1 The frame every page shares

Top to bottom: `PageFrame` states, `PageHeader` (crumb, name, status, actions), the page body. Actions: at most two primary ones in the header, everything else in a More menu (#457, menu component #447). An action never runs directly: it opens a plan, and the job shows in the drawer. A destructive plan makes the user type the name of the thing.

### 3.2 The six templates

| Template | Used for | Body | Address |
|---|---|---|---|
| **Group** | Storage, Instances, Apps, Network, People, Health, Backup | one line of state for the group, a card per place that shows that place's state (not a description), one or two actions | `/<group>` |
| **List** | Disks, Shares, Instances, Installed apps, Users, Groups, Certificates, Nodes, Marketplace (card view), Updates | filter tabs, `Table`, create action in the header, empty state with the one action that creates the first row; a row opens the quick look | `/<group>/<kind>`, selected row in `?sel=` (#455) |
| **Object** | one disk, pool, share, instance, user, package or app | header with status chip and actions; tabs (Overview first, then the object's own); a panel of linked objects; a strip with the running or last job; actions that destroy at the bottom, through a plan | `/<group>/<kind>/<id>[/<tab>]` |
| **Feed** | Events, Notifications, Jobs, Health problems | time-ordered entries with filters; each entry links to the object it is about; acknowledge where it applies (#619) | `/<group>/<kind>`, filters in the address |
| **Flow** | first-run wizard, app wizard, storage incident, capability setup | `Wizard` steps with progress, a way out that loses nothing, a last step that opens the object page | `/<group>/<kind>/new` or `/setup` |
| **Settings** | Settings pages | form built from `layout.gen.json`, grouped by section, saved through a plan | `/settings/<page>` |

Two pages are exempt from a template and use only the frame: **Files** (two-pane file manager, web/design/HANDOFF.md "Files") and the **browser terminal**. Summary is a Group page of its own kind: status lines that each open their owner page, a usage bar per pool, shortcuts that open plans.

### 3.3 Quick look

The quick look replaces the drawer. It is an overlay above the list (component from #447, `ui/Drawer` is the starting point), so selecting a row never narrows or moves the list. It shows the object's Overview, the linked objects and the main actions, plus "Open page". The row stays in the address (`?sel=`), so a reload or a shared link opens the same quick look. On a phone it is full screen.

### 3.4 Jobs: drawer and page

- **Drawer** (bottom, on every page): jobs running now and those finished since this session opened; one line each, with progress and Cancel. For watching what you started.
- **Page** (Health > Jobs, #385): history with filters, per node, a record per job with its steps and result. For finding out what happened.
- **Strip on an object page**: the jobs of that object, last first, each linking to its record on the Jobs page.

All three read the same job records (jobs and events, #480) and follow events; none polls.

### 3.5 What changes for today's pages

| Today | Becomes |
|---|---|
| 9 pages with `Split` + `Drawer` | List, with the drawer as quick look |
| `Section` (6 routes) | Group, with state per place |
| `AppWizardPage`, `SettingsPage` wizard steps, CapabilitySettings wizard | Flow |
| `SettingsPage` and `CapabilitySettings` | Settings |
| about 20 hand-built plain pages | Object, Feed or Group, decided per page in the matrix (#774) |
| `Files` | exempt |

### 3.6 Decisions

Decided 2026-11-18:

- **Seven objects get an Object page:** disk, pool, share, instance, user (#453), and package and app (#474, #478; changed by 6.3). Every other object (group, certificate, service, backup job, node, app and so on) has an address and a quick look, and its page is the List with `?sel=`. An object moves up to an Object page when its quick look no longer fits; that is a change to this document. The table in 1.1 lists the shape each object had before this decision; read "object" there as "address and quick look" for everything but the five.
- **At most four tabs** on an Object page: Overview plus up to three of its own. History is the job strip, not a tab.
- **Health problems is a Feed.** Severity, acknowledge and undo are features of a Feed entry.
- **Settings pages stay generated forms.** No Settings page becomes an Object page. One exception, decided in 6.3: Settings > Updates is a List page (#476).
- **Destructive actions sit in a marked section at the bottom** of the Object page, each through a plan that asks for the name.

## 4. Behaviours that cross pages (#772)

Draft, not reviewed. Each behaviour is decided once, here, and carried by one component or store. A page that needs it uses that; it does not build its own. Read from the issues and `web/` on `develop` (2026-11-18), not seen in a browser. Nothing of the live state ran on a server yet.

| # | Behaviour | Rule | Carried by | Issues |
|---|---|---|---|---|
| 4.1 | Pending state | A row, card or header shows "installing", "stopping" and so on from the job record at once, and switches to the real state when the topic changes. A failed job puts the row back and says why. No page reads again on a timer "to be sure" after an action. | one shared place keyed by `web/src/jobkey.js`; the chip in `ui` | #483, #448 |
| 4.2 | Live data | The interface follows events. Polling is only the fallback while the event stream is down. The top bar shows the age of the data. | `data.svelte.js`, `shell/Fresh` | #480, #486 |
| 4.3 | Actions | An action opens a plan listing each step; it never runs directly. A destructive plan makes the user type the name of the thing. The result shows in the Jobs drawer. | `shell/PlanDialog`, `ui/Button` | web/design/HANDOFF.md |
| 4.4 | Errors | Every error says what happened, the likely reason and one next step, with a stable code, a link to the guide section, and the English text for a code the web does not know. The same shape for a refused plan, a failed job and a page that cannot read. A page error keeps the old data visible with its age. | one error component (a `Banner` variant) and `PageState` | #488 |
| 4.5 | Problems and notifications | Health problems can be acknowledged (quiet until the problem resolves and fails again, optionally for a time). An acknowledged problem is dimmed, is not in the red count and sends no push. A notification inbox lives in the top bar. | Feed template, bell in the top bar | #619 |
| 4.6 | State in the address | The selected row (`?sel=`), the tab and the filters are in the address. Back closes the quick look, forward opens it again. A shared link opens the same view. | route helper next to `route.svelte.js` | #455 |
| 4.7 | Keyboard and screen reader | Every action is reachable and startable by keyboard. Focus is visible. A dialog traps focus and returns it. A state is said in words, never only by a colour dot. Contrast holds in both themes. An automatic check runs in the browser stage of the test-lab. | every `ui` component; `StatusDot` takes a label | #487, #447 |
| 4.8 | Phone | Up to 860 px: the tree is a slide-in drawer, optional columns are hidden, the quick look and plans are full screen, a wizard shows one question per screen. | the shell, `Table`, overlays | #427, web/design/HANDOFF.md |
| 4.9 | Roles | An action the user may not start is shown, disabled, with the reason. The server enforces the role; the web only explains. A viewer sees every page without a plan. | `ui/Button` takes "not allowed" with a reason | #434 |
| 4.10 | Trust | A package says "Official, signed" or "Community" on its card and its page, and "Tested on a real server" with a date, or "Not tested". The same words are used for extensions. | one chip in the Marketplace and app pages | #477 |

### 4.1 Details that the table leaves out

- **Pending versus real state.** The row shows pending while a job for its key runs, and the real state afterwards. If the job fails, the row shows the real state and a coded error (4.4) until the user dismisses it.
- **A job that asks for input.** A running job that needs an answer shows a toast on whatever page the user is on. It names the job and links to its record, where the question is answered. Until then the job shows as waiting, not as running.
- **Stream down.** The top bar shows that live updates are off and the data age keeps counting. Pages start polling at the slow fallback rate; the polling and its ratchet (`timed-reads.max`) stay as they are.
- **Acknowledge.** The entry stays in the Feed, dimmed, with who acknowledged it and until when. Undo is always offered. The count in the bell and in Summary leaves acknowledged entries out.

### 4.11 Decisions

Decided 2026-11-18:

- **The bell counts unacknowledged problems plus unread notifications.** Acknowledged problems are left out.
- **The read-only status page is the viewer role** seeing the normal pages without plans or action buttons. It needs a sign-in. There is no separate public page, which keeps the rule that admin pages are never public.
- **A failed job's coded error stays on the row until the user dismisses it.**
- **Acknowledge defaults to "until it resolves"**, with a snooze in the More menu.
- **A stream outage shows only in the top bar**, no banner.

## 5. Component inventory (#773)

Draft, not reviewed. Each component is traced to the templates (3.2) and behaviours (section 4) that need it. A component with one user is not shared and stays in its page. Counts are from the survey of 2026-11-18 (files that use the tag, rough). `ui` components know nothing about the server; `shell` components may read the stores (jobs, events, session).

### 5.1 What exists and what changes

| Component | Today | Change | Needed by |
|---|---|---|---|
| `Button` | about 57 files | takes "not allowed" with a reason (4.9); icon variant with tooltip and screen-reader label (#446) | every template |
| `StatusDot` | about 33 | takes a text label, so a state is never only a colour (4.7) | List, Object, Feed |
| `Chip` | about 17 | one of `Chip` and the `tag` class stays (#446); gets a kind for trust (4.10) and for the status in an Object header | List, Object, Marketplace |
| `Banner` | about 31 | gets a coded error variant (4.4) | every template |
| `Kv`, `EmptyState`, `Skeleton`, `Field`, `TextInput`, `Textarea`, `Select`, `Combobox`, `Checkbox`, `Switch`, `ChoiceList`, `Tooltip` | in use | none | Object, Settings, Flow |
| `PageTabs` | 3 pages | tab in the address (4.6); used by Object pages and for list filter tabs | Object, List |
| `Drawer` | 12 files | becomes the quick look overlay (3.3), built on `Dialog` | List |
| `Split` | 9 pages | removed after the quick look replaces it; the list no longer narrows | List |
| `Wizard` | 2 pages | sits on a `Stepper` with progress (#448) | Flow |
| `Table`, `UsageBar`, `Spark` (shell) | in use | `Table`: selected row in the address, row action menu; a card view of the same rows for the Marketplace (6.3) | List |
| `PageHeader` (shell) | in use | status chip beside the name, More menu for actions beyond two (3.1) | every template |
| `PageFrame`, `PageState` (shell) | in use | none | every template |
| `PlanDialog`, `CreateDialog` (shell) | in use | rebuilt on `Dialog` (#447) | every action |
| `JobRecords`, `BottomPanel` (shell) | in use | feed the job strip and the Jobs page; one shared pending lookup (4.1) | Object, Feed |
| `Fresh` (shell) | in use | none | top bar |

### 5.2 New components

| Component | Where | What | Needed by | Issue |
|---|---|---|---|---|
| `Card` / `Section` | `ui` | header slot, actions; replaces the `class="card"` blocks (58 files) | Group, Object, Settings | #445 |
| `Row`, `Stack`, one muted text style | `ui` | gaps from the tokens; replaces `mute` and `muted` | all | #445 |
| `Icon`, icon variant of `Button` | `ui` | one list of names | all | #446 |
| `Dialog` | `ui` | focus trap, Escape, backdrop; base of plans, create and quick look | all actions | #447 |
| `Menu` | `ui` | the More menu and row actions | every template | #447 |
| `Toast` | `ui` | a job that asks for input, and short results that need no dialog (5.4) | every page, via the shell | #447 |
| `QuickLook` | `ui` | overlay above a list; the `Drawer` reworked | List | #447 |
| `Progress`, `StepList` | `ui` | job step and progress | Jobs, Flow, Object job strip | #448 |
| `Timeline` | `ui` | time-ordered entries with filters; an entry has severity, object link, optional acknowledge | Feed | #448 |
| `Stepper` | `ui` | the steps of a Flow; under `Wizard` | Flow | #448 |
| `ErrorNote` | `ui` | code, what, why, next step, link to the guide | every template | new |
| `StateCard` | `ui` | a `Card` with status dot, one line and a link; the card of a Group page | Group (8 pages) | new |
| `LinkedObjects` | `shell` | related objects with status, linking both ways (1.2) | Object (5 pages), quick look | new |
| `JobStrip` | `shell` | the running or last jobs of one object | Object (5 pages) | new |
| `DangerZone` | `ui` | the marked section for destructive actions | Object (5 pages) | new |
| `Inbox` (bell and list) | `shell` | the count of 4.11 and the notification list | top bar, Feed | new |

### 5.3 Left out on purpose

`GenBlock`, `GenericPage`, `Terminal`, `VmConsole`, `Halftone`, the file manager parts and `Search` have one user each or are tools. They stay where they are. A Spinner is the global `spin` class, not a component.

### 5.4 Decisions

Decided 2026-11-18:

- **`Toast` stays in #447.** Its use: a job that is running asks for input (a recipe that needs an answer), and the user may be on any page. The toast names the job and links to it; the question is answered in the job's record. Short results that need no dialog use it too. This behaviour is added to 4.1.
- **`Card` and `Section` are one component:** `Card`, with an optional header and actions.
- **Two new issues** for the components that have none: one for the Group and Object page pieces (`StateCard`, `LinkedObjects`, `JobStrip`, `DangerZone`), one for `ErrorNote` and `Inbox`.
- **`ui` is pure, `shell` may read the stores.** The rule holds for every component in 5.2.
- **#448 is split in three:** `Progress` with `StepList`, then `Timeline`, then `Stepper`.

## 6. Feature-to-page matrix (#774)

Draft, not reviewed. Every open web issue, and the issues of other areas that add or change a page, mapped to a page, a template and the components. Read from the issue titles and the bodies I read for sections 3 to 5; the pages of #434, #239 and #313 are inferred from their titles. Epics and issues with no page (#484 udev events, #485 and #486 tests, #580) are left out.

### 6.1 The matrix

| Issue | Page | Template | Components | Note |
|---|---|---|---|---|
| #385 Jobs page | Health > Jobs | Feed | `Timeline` (#784), `Progress`, `StepList` (#448), `ErrorNote` | The Jobs page beside the drawer (3.4); Jobs was missing from the tree and is added to 2.2 |
| #391 Events view | Health > Events | Feed | `Timeline` | |
| #617 job records, event kinds, Events page | Health > Jobs, Events | Feed | `Timeline` | |
| #619 acknowledge, inbox | Health (problems), top bar | Feed | `Timeline`, `Inbox` (#783) | |
| #483 pending state from the job | every list and Object page | behaviour 4.1 | the chip, `JobStrip` (#782) | |
| #488 error messages | every page | behaviour 4.4 | `ErrorNote` (#783) | |
| #452 regroup the tree | the tree | section 2 | `Tree` (shell) | |
| #453 a page per object | disk, pool, share, instance, user | Object | `Card`, `LinkedObjects`, `JobStrip`, `DangerZone` (#782), `PageTabs` | Gap G2 |
| #454 quick look | every List page | List | `QuickLook` (#447) | |
| #455 selection in the address | every List page | List | route helper | |
| #456 pools from data | Storage > Pools, tree, Section | List, Object | none | Same fix as #573 (G6) |
| #457 group pages | the 7 groups and Summary | Group | `StateCard` (#782), `Menu` (#447) | |
| #427 phone and read-only status page | every page | behaviour 4.8, role viewer | the shell | The status page is the viewer role (4.11) |
| #487 accessibility | every page | behaviour 4.7 | every `ui` component | |
| #434 roles and API tokens | Settings > Users and access, user Object page | Settings, Object | `Button` "not allowed" (#446) | Pages inferred |
| #462 two-factor and single sign-on | Login, Settings > Users and access, user Object page | exempt, Settings, Object | `Field`, `TextInput` | Login is outside the templates (G5) |
| #183 first-run wizard | `/setup` and the first run | Flow | `Wizard`, `Stepper` (#785) | |
| #181 storage discovery in the wizard | Flow step, then Disks | Flow | `Stepper`, `LinkedObjects` | |
| #179 network step | Flow step | Flow | `Stepper` | |
| #581 first-run checklist | Summary banner | Group | `Banner` | The banner of 2.1, until every check is done |
| #573, #574, #576 pools, single disk | Pools, Summary messages | List, Object | none | |
| #575 local users without a directory | Users | List | none | One user object (1.4) |
| #424 status panel from the manifest `[web]` | the app's Object page | Object | `Kv`, `StateCard`, `Button` | Overlaps #478, #195 (G7) |
| #478 a page for every installed app | Apps > Installed | Object | as #424 | Gap G2 |
| #195 packages declare pages | `/extensions/<name>`, app pages | built from the templates | `GenericPage` | G7 |
| #474 Marketplace as a store | Apps > Marketplace | needs a decision | `Card`, `Chip` (trust) | Gap G4 |
| #477 trust shown plainly | Marketplace, package and app pages | behaviour 4.10 | `Chip` kind | |
| #476 one place for updates | Settings > Updates | needs a decision | `Table`, `Progress` | Gap G3 |
| #268 package builder | Apps > Marketplace > Builder | Flow | `Wizard`, `Stepper` | |
| #239, #313, #197 extension permissions, events, SDK | Extension pages, Events | Feed, built from the templates | `GenericPage` | Pages inferred |
| #426 file manager | Storage > Files | exempt | `Progress`, `StepList`, `Dialog` | |
| #492, #493 translations | every page | all use `tr()` | `ErrorNote` codes | No page of its own |
| #461 demo mode | every page | review tool | fixtures per template | Use it for the mockups (#775) |
| #449, #450 gallery, move the pages | developer section | exempt | all `ui` | The order of #450 should follow the groups of 2.2 |

### 6.2 Gaps and overlaps

| # | Finding | Why it matters |
|---|---|---|
| G1 | Jobs had no place in the tree. | Fixed: Health > Jobs, in 2.2. |
| G2 | #474 and #478 give a package and an installed app their own page, but 3.6 says only five objects get an Object page. | Package and App need an Object page, or the Marketplace and app pages are built differently. |
| G3 | #476 (updates for the system, apps and packages in one place) is a list with actions and progress, but 3.6 says Settings pages are generated forms. | Settings > Updates cannot be a generated form. |
| G4 | #474 wants cards, categories and Installed and Updates tabs. No template has a card view. | The List template needs a card view, or the Marketplace is a page of its own. |
| G5 | The Login page and the first-run setup have no template. | They are exempt like Files, or a Flow. |
| G6 | #456 (0.11) and #573 (0.4) are one fix: pool names from data. | Do it once, in 0.4; close #456 into it. |
| G7 | #424, #478 and #195 each describe a page built from a manifest. | One renderer for all three, or they diverge. |

### 6.3 Decisions

Decided 2026-11-18:

- **G2: Package and App get an Object page.** Seven objects have one (see 3.6). The package page and the app page are built from the manifest.
- **G3: Settings > Updates is a List page** (system, apps and packages), an exception to the generated forms. It stays under Settings in the tree.
- **G4: the List template gets a card view.** The Marketplace uses it, with categories as filter tabs and Installed and Updates as tabs. The card view is part of `Table` (5.1).
- **G5: Login and first-run setup are exempt** from the templates, like Files. The first-run wizard (#183) is a Flow after sign-in.
- **G6: #456 is closed into #573.** The pool-name fix is done once, in 0.4.
- **G7: one renderer** builds the manifest pages of #424, #478 and #195. It uses the Object template.
