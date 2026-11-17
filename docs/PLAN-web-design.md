# Plan: web design handover

Status: draft, section 1 only, decisions in 1.4 made. Epic: hobnix/server#768, milestone 0.8.5. Read from the code and issues on `develop` (2026-11-18), not seen in a browser.

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

1. One object, one address, one page. The address survives a reload and can be shared.
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
- **No Jobs page exists today.** `nav.js` and `routes.js` have no entry; #385 adds it.
