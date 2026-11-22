# Roadmap

Where Hobnix is going and what is open now. For people who want to help or to know what comes next.

**The source is the GitHub project board** ([Hobnix Roadmap](https://github.com/orgs/hobnix/projects/1)), not this page. This page is a
snapshot of it, made with `python3 scripts/roadmap-gen.py write` (it runs `gh project item-list`), and can be behind. The second table is made
from `TODO.md` in the same way. Nothing between the markers is edited by hand. Status and priority of an issue are changed on the board.

## Positioning

- **For whom:** the home user of Unraid or a hand-built NAS who wants apps, shares and backups on a system that can be read and rebuilt.
- **Three things Hobnix does better:** rollback of the whole system; a server rebuilt from a backup disk and a passphrase (both not run on a
  real server yet: #161, #163); a server that is a readable git repository with a plan before every change.
- **Out of scope before 1.0:** clusters with shared state, high availability, live migration. ADR 0013 stays a record of why, not a plan.
  Epics outside this (multi-node management, networking management) sit in the milestone "Later — after 1.0".

## Milestones

The milestones are releases in order of work, not dates. An issue without a milestone is not planned yet.

<!-- BEGIN board (python3 scripts/roadmap-gen.py write) -->

### Documentation

3 issues, 0 done.

| Issue | Status | Priority | Title |
| --- | --- | --- | --- |
| [#207](https://github.com/hobnix/server/issues/207) | Backlog | P1 | Epic: Documentation and Community |
| [#271](https://github.com/hobnix/server/issues/271) | Backlog | - | Funding: GitHub Sponsors and OpenCollective |
| [#416](https://github.com/hobnix/server/issues/416) | Backlog | - | Work through every guide on a real server and record the date |

### Later â€” after 1.0

4 issues, 0 done.

| Issue | Status | Priority | Title |
| --- | --- | --- | --- |
| [#201](https://github.com/hobnix/server/issues/201) | Backlog | P1 | Epic: Networking Management |
| [#203](https://github.com/hobnix/server/issues/203) | Backlog | P2 | Epic: Multi-node Management |
| [#920](https://github.com/hobnix/server/issues/920) | - | - | Router providers for OPNsense, OpenWrt and UPnP (ingress.port_forward) |
| [#977](https://github.com/hobnix/server/issues/977) | Backlog | - | Epic: Build the web components on UI SDK behaviors (evaluate, then migrate) |

### 0.1 â€” Trustworthy Foundation

73 issues, 60 done.

| Issue | Status | Priority | Title |
| --- | --- | --- | --- |
| [#128](https://github.com/hobnix/server/issues/128) | In Progress | P0 | Epic: Unified Job System |
| [#139](https://github.com/hobnix/server/issues/139) | In Progress | P0 | Epic: Event Architecture |
| [#147](https://github.com/hobnix/server/issues/147) | In Progress | P0 | Epic: Reactive Live-state |
| [#159](https://github.com/hobnix/server/issues/159) | In Progress | P0 | Epic: Reliability and Recovery |
| [#163](https://github.com/hobnix/server/issues/163) | In Progress | P0 | Rebuild rehearsal in a VM from backup disk and passphrase (TODO A5) |
| [#430](https://github.com/hobnix/server/issues/430) | In Progress | - | Test-lab: run the install, update and restore checks in an Incus VM on the server |
| [#520](https://github.com/hobnix/server/issues/520) | In Progress | - | Release the core from GitHub in 0.1 (bring the release workflow of #515 to develop, prove it with a beta tag) |
| [#523](https://github.com/hobnix/server/issues/523) | In Progress | - | CI check: a package that changed since the last tag must have a raised version |
| [#534](https://github.com/hobnix/server/issues/534) | In Progress | - | VM and domain controller restore: missing guide steps, --tag host, wrong messages |
| [#161](https://github.com/hobnix/server/issues/161) | Ready | P0 | Run the auto-rollback on the real server and record the result |
| [#522](https://github.com/hobnix/server/issues/522) | Ready | - | Release the package repositories from GitHub (shared workflow for recipes, extensions, capabilities) |
| [#846](https://github.com/hobnix/server/issues/846) | Backlog | - | Flaky CI tests: job-step-live and dialogues (Broken pipe) |
| [#900](https://github.com/hobnix/server/issues/900) | Backlog | - | Error codes: stable named codes in one catalogue (ADR 0028) |

Done: [#121](https://github.com/hobnix/server/issues/121), [#122](https://github.com/hobnix/server/issues/122), [#123](https://github.com/hobnix/server/issues/123), [#124](https://github.com/hobnix/server/issues/124), [#125](https://github.com/hobnix/server/issues/125), [#126](https://github.com/hobnix/server/issues/126), [#127](https://github.com/hobnix/server/issues/127), [#129](https://github.com/hobnix/server/issues/129), [#131](https://github.com/hobnix/server/issues/131), [#133](https://github.com/hobnix/server/issues/133), [#135](https://github.com/hobnix/server/issues/135), [#137](https://github.com/hobnix/server/issues/137), [#141](https://github.com/hobnix/server/issues/141), [#143](https://github.com/hobnix/server/issues/143), [#145](https://github.com/hobnix/server/issues/145), [#149](https://github.com/hobnix/server/issues/149), [#151](https://github.com/hobnix/server/issues/151), [#153](https://github.com/hobnix/server/issues/153), [#155](https://github.com/hobnix/server/issues/155), [#157](https://github.com/hobnix/server/issues/157), [#165](https://github.com/hobnix/server/issues/165), [#167](https://github.com/hobnix/server/issues/167), [#169](https://github.com/hobnix/server/issues/169), [#171](https://github.com/hobnix/server/issues/171), [#252](https://github.com/hobnix/server/issues/252), [#253](https://github.com/hobnix/server/issues/253), [#286](https://github.com/hobnix/server/issues/286), [#288](https://github.com/hobnix/server/issues/288), [#289](https://github.com/hobnix/server/issues/289), [#290](https://github.com/hobnix/server/issues/290), [#291](https://github.com/hobnix/server/issues/291), [#292](https://github.com/hobnix/server/issues/292), [#293](https://github.com/hobnix/server/issues/293), [#294](https://github.com/hobnix/server/issues/294), [#295](https://github.com/hobnix/server/issues/295), [#296](https://github.com/hobnix/server/issues/296), [#297](https://github.com/hobnix/server/issues/297), [#298](https://github.com/hobnix/server/issues/298), [#322](https://github.com/hobnix/server/issues/322), [#323](https://github.com/hobnix/server/issues/323), [#324](https://github.com/hobnix/server/issues/324), [#385](https://github.com/hobnix/server/issues/385), [#386](https://github.com/hobnix/server/issues/386), [#387](https://github.com/hobnix/server/issues/387), [#388](https://github.com/hobnix/server/issues/388), [#389](https://github.com/hobnix/server/issues/389), [#390](https://github.com/hobnix/server/issues/390), [#391](https://github.com/hobnix/server/issues/391), [#392](https://github.com/hobnix/server/issues/392), [#393](https://github.com/hobnix/server/issues/393), [#396](https://github.com/hobnix/server/issues/396), [#397](https://github.com/hobnix/server/issues/397), [#398](https://github.com/hobnix/server/issues/398), [#399](https://github.com/hobnix/server/issues/399), [#414](https://github.com/hobnix/server/issues/414), [#415](https://github.com/hobnix/server/issues/415), [#417](https://github.com/hobnix/server/issues/417), [#521](https://github.com/hobnix/server/issues/521), [#567](https://github.com/hobnix/server/issues/567), [#607](https://github.com/hobnix/server/issues/607)

### 0.2 â€” Safe Updates

14 issues, 13 done.

| Issue | Status | Priority | Title |
| --- | --- | --- | --- |
| [#439](https://github.com/hobnix/server/issues/439) | Blocked | - | CI: test develop after each merge, faster quick tests, required checks |

Done: [#185](https://github.com/hobnix/server/issues/185), [#219](https://github.com/hobnix/server/issues/219), [#231](https://github.com/hobnix/server/issues/231), [#233](https://github.com/hobnix/server/issues/233), [#254](https://github.com/hobnix/server/issues/254), [#432](https://github.com/hobnix/server/issues/432), [#433](https://github.com/hobnix/server/issues/433), [#435](https://github.com/hobnix/server/issues/435), [#436](https://github.com/hobnix/server/issues/436), [#437](https://github.com/hobnix/server/issues/437), [#438](https://github.com/hobnix/server/issues/438), [#458](https://github.com/hobnix/server/issues/458), [#464](https://github.com/hobnix/server/issues/464)

### 0.2.1 â€” Faster test-lab

1 issues, 0 done.

| Issue | Status | Priority | Title |
| --- | --- | --- | --- |
| [#712](https://github.com/hobnix/server/issues/712) | In Progress | - | Test-lab: a faster run that does not grow with every roadmap step |

### 0.3 â€” Foundations

9 issues, 8 done.

| Issue | Status | Priority | Title |
| --- | --- | --- | --- |
| [#420](https://github.com/hobnix/server/issues/420) | Backlog | - | Notifications: run channels, routing and the web page on a server; choose the next providers |

Done: [#423](https://github.com/hobnix/server/issues/423), [#431](https://github.com/hobnix/server/issues/431), [#442](https://github.com/hobnix/server/issues/442), [#443](https://github.com/hobnix/server/issues/443), [#444](https://github.com/hobnix/server/issues/444), [#482](https://github.com/hobnix/server/issues/482), [#491](https://github.com/hobnix/server/issues/491), [#560](https://github.com/hobnix/server/issues/560)

### 0.4 â€” Install and Onboarding

14 issues, 11 done.

| Issue | Status | Priority | Title |
| --- | --- | --- | --- |
| [#173](https://github.com/hobnix/server/issues/173) | In Progress | P0 | Epic: Installation and Onboarding |
| [#175](https://github.com/hobnix/server/issues/175) | Backlog | P0 | Boot the ISO on real hardware or a VM, record what breaks |
| [#459](https://github.com/hobnix/server/issues/459) | Backlog | - | Epic: Works on a machine that is not the author's |

Done: [#179](https://github.com/hobnix/server/issues/179), [#181](https://github.com/hobnix/server/issues/181), [#183](https://github.com/hobnix/server/issues/183), [#573](https://github.com/hobnix/server/issues/573), [#574](https://github.com/hobnix/server/issues/574), [#575](https://github.com/hobnix/server/issues/575), [#576](https://github.com/hobnix/server/issues/576), [#577](https://github.com/hobnix/server/issues/577), [#580](https://github.com/hobnix/server/issues/580), [#581](https://github.com/hobnix/server/issues/581), [#596](https://github.com/hobnix/server/issues/596)

### 0.5 â€” Capabilities Repository

7 issues, 7 done.

Done: [#177](https://github.com/hobnix/server/issues/177), [#221](https://github.com/hobnix/server/issues/221), [#224](https://github.com/hobnix/server/issues/224), [#228](https://github.com/hobnix/server/issues/228), [#229](https://github.com/hobnix/server/issues/229), [#235](https://github.com/hobnix/server/issues/235), [#615](https://github.com/hobnix/server/issues/615)

### 0.6 â€” App Lifecycle

22 issues, 18 done.

| Issue | Status | Priority | Title |
| --- | --- | --- | --- |
| [#187](https://github.com/hobnix/server/issues/187) | In Progress | P0 | Epic: Application Lifecycle |
| [#613](https://github.com/hobnix/server/issues/613) | In Progress | - | Interactive recipe: the wizard form's address is asked again in the dialog; a run on an existing app cannot ask again |
| [#899](https://github.com/hobnix/server/issues/899) | In Review | - | Apply of a Docker app fails with "exit 127" when its images are not downloaded yet |
| [#850](https://github.com/hobnix/server/issues/850) | Backlog | - | Install dialog warns "the server is rebuilt" for an app that does not rebuild (ntfy) |

Done: [#237](https://github.com/hobnix/server/issues/237), [#238](https://github.com/hobnix/server/issues/238), [#240](https://github.com/hobnix/server/issues/240), [#257](https://github.com/hobnix/server/issues/257), [#263](https://github.com/hobnix/server/issues/263), [#264](https://github.com/hobnix/server/issues/264), [#265](https://github.com/hobnix/server/issues/265), [#266](https://github.com/hobnix/server/issues/266), [#267](https://github.com/hobnix/server/issues/267), [#465](https://github.com/hobnix/server/issues/465), [#466](https://github.com/hobnix/server/issues/466), [#467](https://github.com/hobnix/server/issues/467), [#468](https://github.com/hobnix/server/issues/468), [#469](https://github.com/hobnix/server/issues/469), [#470](https://github.com/hobnix/server/issues/470), [#471](https://github.com/hobnix/server/issues/471), [#612](https://github.com/hobnix/server/issues/612), [#614](https://github.com/hobnix/server/issues/614)

### 0.7 â€” Storage and NAS

10 issues, 3 done.

| Issue | Status | Priority | Title |
| --- | --- | --- | --- |
| [#189](https://github.com/hobnix/server/issues/189) | In Progress | P0 | Epic: Storage Management |
| [#418](https://github.com/hobnix/server/issues/418) | In Progress | - | Backup target outside the house (cloud or another server) |
| [#419](https://github.com/hobnix/server/issues/419) | In Progress | - | Capacity alerts: further automatic mitigation levels |
| [#425](https://github.com/hobnix/server/issues/425) | In Progress | - | File manager: run the write checks in a VM, then switch `fileManagerWrite` on |
| [#460](https://github.com/hobnix/server/issues/460) | In Progress | - | Take over the disks of an Unraid server in place |
| [#527](https://github.com/hobnix/server/issues/527) | In Progress | - | Back up only chosen parts of a container (include and exclude paths, like a .gitignore) |
| [#699](https://github.com/hobnix/server/issues/699) | Backlog | - | hs pool bulk add as a job leaves /bulk unmounted (mergerfs ends with the job unit) |

Done: [#255](https://github.com/hobnix/server/issues/255), [#426](https://github.com/hobnix/server/issues/426), [#463](https://github.com/hobnix/server/issues/463)

### 0.8 â€” Extensions and Access

11 issues, 0 done.

| Issue | Status | Priority | Title |
| --- | --- | --- | --- |
| [#197](https://github.com/hobnix/server/issues/197) | In Progress | P1 | Epic: Extension Protocol and SDK |
| [#239](https://github.com/hobnix/server/issues/239) | In Progress | P1 | Enforce extension permissions instead of only declaring them |
| [#313](https://github.com/hobnix/server/issues/313) | In Progress | - | Packages declare the events they provide |
| [#434](https://github.com/hobnix/server/issues/434) | In Progress | - | Roles and API tokens: build what ADR 0012 decides |
| [#462](https://github.com/hobnix/server/issues/462) | Backlog | - | Two-factor login and single sign-on for the web interface |
| [#926](https://github.com/hobnix/server/issues/926) | - | - | Manifest block [integrations.media] for media apps |
| [#927](https://github.com/hobnix/server/issues/927) | - | - | Event retention classes (ephemeral, audit, metric) and a rollup helper for extensions |
| [#944](https://github.com/hobnix/server/issues/944) | - | - | Security: tokens may reach rows that outlive the token (ssh-key, pkg, config, system) |
| [#945](https://github.com/hobnix/server/issues/945) | - | - | Security: a domain session keeps its role for up to 12 hours |
| [#946](https://github.com/hobnix/server/issues/946) | - | - | Security: viewer can list file names of sensitive shares and search backups |
| [#947](https://github.com/hobnix/server/issues/947) | - | - | Security: extension confinement leaves secrets readable; no deny list for fs.write |

### 0.8.5 â€” Web Design

8 issues, 8 done.

Done: [#768](https://github.com/hobnix/server/issues/768), [#769](https://github.com/hobnix/server/issues/769), [#770](https://github.com/hobnix/server/issues/770), [#771](https://github.com/hobnix/server/issues/771), [#772](https://github.com/hobnix/server/issues/772), [#773](https://github.com/hobnix/server/issues/773), [#774](https://github.com/hobnix/server/issues/774), [#775](https://github.com/hobnix/server/issues/775)

### 0.9 â€” Web Components

14 issues, 10 done.

| Issue | Status | Priority | Title |
| --- | --- | --- | --- |
| [#191](https://github.com/hobnix/server/issues/191) | In Progress | P1 | Epic: Component Library |
| [#450](https://github.com/hobnix/server/issues/450) | In Progress | - | Web: move the pages to the shared components, group by group |
| [#193](https://github.com/hobnix/server/issues/193) | Backlog | P1 | Epic: Storybook and Design System |
| [#879](https://github.com/hobnix/server/issues/879) | Backlog | - | Web: Storybook set up in web/ (first stories) |

Done: [#445](https://github.com/hobnix/server/issues/445), [#446](https://github.com/hobnix/server/issues/446), [#447](https://github.com/hobnix/server/issues/447), [#448](https://github.com/hobnix/server/issues/448), [#449](https://github.com/hobnix/server/issues/449), [#461](https://github.com/hobnix/server/issues/461), [#782](https://github.com/hobnix/server/issues/782), [#783](https://github.com/hobnix/server/issues/783), [#784](https://github.com/hobnix/server/issues/784), [#785](https://github.com/hobnix/server/issues/785)

### 0.10 â€” Live Interface

21 issues, 0 done.

| Issue | Status | Priority | Title |
| --- | --- | --- | --- |
| [#483](https://github.com/hobnix/server/issues/483) | Testing | - | An action shows at once: rows take their pending state from the job event |
| [#952](https://github.com/hobnix/server/issues/952) | Testing | - | SnapRAID: per-share skipped folders and removal limits for the parity sync |
| [#480](https://github.com/hobnix/server/issues/480) | Backlog | - | Epic: The interface follows events, it does not poll |
| [#481](https://github.com/hobnix/server/issues/481) | Backlog | - | Live state on by default, one mode, one store (decide: Redis or the state database) |
| [#484](https://github.com/hobnix/server/issues/484) | Backlog | - | More event sources: disks plugged and pulled (udev), units that start, stop or fail (systemd) |
| [#485](https://github.com/hobnix/server/issues/485) | Backlog | - | End-to-end test: an action updates the open page without a reload, within seconds |
| [#486](https://github.com/hobnix/server/issues/486) | Backlog | - | Measure the delay from "something changed" to "the browser shows it" |
| [#559](https://github.com/hobnix/server/issues/559) | Backlog | - | Live state: named events instead of broad wake-up groups |
| [#561](https://github.com/hobnix/server/issues/561) | Backlog | - | Live state: collector writes documents to the state database |
| [#562](https://github.com/hobnix/server/issues/562) | Backlog | - | Live state: web reads topics and /api/events from the database only |
| [#563](https://github.com/hobnix/server/issues/563) | Backlog | - | Live state: remove the liveState option and the Redis service |
| [#564](https://github.com/hobnix/server/issues/564) | Backlog | - | Live state: one status on the Data page and in hs sys live status |
| [#565](https://github.com/hobnix/server/issues/565) | Backlog | - | Live state: rewrite docs for the state database |
| [#566](https://github.com/hobnix/server/issues/566) | Backlog | - | Live state: real-server check, a terminal change shows in the open page |
| [#617](https://github.com/hobnix/server/issues/617) | Backlog | - | Follow-ups of the 0.1 acceptance audit: job records, event kinds, Events page |
| [#619](https://github.com/hobnix/server/issues/619) | Backlog | - | Acknowledge a health problem (quiet until it resolves and fails again) and a notification inbox |
| [#896](https://github.com/hobnix/server/issues/896) | Backlog | - | Jobs: plan dialog closes on Start, toasts report the job; Docker start/stop/restart as jobs |
| [#965](https://github.com/hobnix/server/issues/965) | - | - | Role-gate every change button: viewer still sees enabled buttons (disk add and others) |
| [#971](https://github.com/hobnix/server/issues/971) | - | - | Events timeline has no card or background, hard to read |
| [#972](https://github.com/hobnix/server/issues/972) | - | - | App install wizard shows step 1 while the job is at the last question, and the question gives no toast |
| [#973](https://github.com/hobnix/server/issues/973) | - | - | Jobs page: list and detail side by side (about 60/40), selection stays visible without scrolling |

### 0.10.1 â€” Network Map

9 issues, 0 done.

| Issue | Status | Priority | Title |
| --- | --- | --- | --- |
| [#870](https://github.com/hobnix/server/issues/870) | Backlog | - | Epic: Network map of this server |
| [#871](https://github.com/hobnix/server/issues/871) | Backlog | - | Web: UI SDK spike (pinned beta, one component, story) |
| [#872](https://github.com/hobnix/server/issues/872) | Backlog | - | Backend: hs sys netmap (graph document) |
| [#873](https://github.com/hobnix/server/issues/873) | Backlog | - | Backend: counters stream for the map (sampled only while a page is open) |
| [#874](https://github.com/hobnix/server/issues/874) | Backlog | - | Web: layout function for the map (graph in, positions out) |
| [#875](https://github.com/hobnix/server/issues/875) | Backlog | - | Web: draw the map (SVG nodes, canvas traffic dots) |
| [#876](https://github.com/hobnix/server/issues/876) | Backlog | - | Web: map without a mouse (roving focus, detail popover, table view) |
| [#877](https://github.com/hobnix/server/issues/877) | Backlog | - | Web: network map page and demo-mode data |
| [#878](https://github.com/hobnix/server/issues/878) | Backlog | - | Test and docs: network map |

### 0.11 â€” Navigation and Pages

10 issues, 0 done.

| Issue | Status | Priority | Title |
| --- | --- | --- | --- |
| [#427](https://github.com/hobnix/server/issues/427) | Backlog | - | Mobile-friendly web interface and a read-only status page |
| [#451](https://github.com/hobnix/server/issues/451) | Backlog | - | Epic: Navigation and page structure |
| [#452](https://github.com/hobnix/server/issues/452) | Backlog | - | Web: regroup the tree (fewer groups, only places) |
| [#453](https://github.com/hobnix/server/issues/453) | Backlog | - | Web: a page per object (disk, pool, share, instance, user) instead of a drawer with tabs |
| [#454](https://github.com/hobnix/server/issues/454) | Backlog | - | Web: quick look as an overlay, so selecting a row never moves the list |
| [#455](https://github.com/hobnix/server/issues/455) | Backlog | - | Web: the selected row and tab live in the address |
| [#456](https://github.com/hobnix/server/issues/456) | Backlog | - | Web: pools come from data, not from fixed names |
| [#457](https://github.com/hobnix/server/issues/457) | Backlog | - | Web: group pages that show the state of the group, one or two main actions plus a More menu |
| [#487](https://github.com/hobnix/server/issues/487) | Backlog | - | Accessibility: the whole interface by keyboard and with a screen reader |
| [#776](https://github.com/hobnix/server/issues/776) | Backlog | - | Web design: thin slice, the disk page |

### 0.12 â€” Package Pages

8 issues, 0 done.

| Issue | Status | Priority | Title |
| --- | --- | --- | --- |
| [#195](https://github.com/hobnix/server/issues/195) | Backlog | P1 | Epic: Declarative WebUI |
| [#424](https://github.com/hobnix/server/issues/424) | Backlog | - | Recipes: status panel and allowlisted actions from the manifest `[web]` section |
| [#472](https://github.com/hobnix/server/issues/472) | Backlog | - | Slots: the fixed places where a package may add to the interface |
| [#473](https://github.com/hobnix/server/issues/473) | Backlog | - | The block list is the component library: a registry with schemas, and the blocks that are missing |
| [#488](https://github.com/hobnix/server/issues/488) | Backlog | - | Error messages: what happened, why, and the next step, with a stable code |
| [#790](https://github.com/hobnix/server/issues/790) | Backlog | - | Packages place their pages: group, order, tabs, template and card state in [web.page] |
| [#924](https://github.com/hobnix/server/issues/924) | - | - | ext-game-lobbies: lobbies card, worlds and console tab, wake link |
| [#928](https://github.com/hobnix/server/issues/928) | - | - | ext-media-hub: media statistics, poster trigger and storage suggestions |

### 0.13 â€” Package Registry

2 issues, 0 done.

| Issue | Status | Priority | Title |
| --- | --- | --- | --- |
| [#217](https://github.com/hobnix/server/issues/217) | In Progress | P0 | Epic: Capabilities repository and channels |
| [#225](https://github.com/hobnix/server/issues/225) | Backlog | P0 | Create hobnix/capabilities, move the first optional capability as a pilot |

### 0.14 â€” Marketplace

12 issues, 0 done.

| Issue | Status | Priority | Title |
| --- | --- | --- | --- |
| [#205](https://github.com/hobnix/server/issues/205) | Backlog | P2 | Epic: Marketplace and Ecosystem |
| [#269](https://github.com/hobnix/server/issues/269) | Backlog | - | Import Unraid templates and Proxmox vzdump archives |
| [#474](https://github.com/hobnix/server/issues/474) | Backlog | - | Marketplace as a store: cards, categories, Installed and Updates, a page per package |
| [#475](https://github.com/hobnix/server/issues/475) | Backlog | - | The package index refreshes by itself |
| [#476](https://github.com/hobnix/server/issues/476) | Backlog | - | One place for updates: the system, apps and packages |
| [#477](https://github.com/hobnix/server/issues/477) | Backlog | - | Trust shown plainly: official or community, and a "tested on a real server" date |
| [#478](https://github.com/hobnix/server/issues/478) | Backlog | - | A page for every installed app, built from its manifest |
| [#793](https://github.com/hobnix/server/issues/793) | Backlog | - | Marketplace: a "fits this server" check from the package's declared needs |
| [#923](https://github.com/hobnix/server/issues/923) | - | - | Game recipes: gold-standard set and a generic custom-game-server |
| [#925](https://github.com/hobnix/server/issues/925) | - | - | hs pkg import-egg: turn a Pelican/Pterodactyl egg into a recipe draft |
| [#933](https://github.com/hobnix/server/issues/933) | - | - | Package identity <repo>/<package>: official shorthand, scoped updates, shadowing warning |
| [#934](https://github.com/hobnix/server/issues/934) | - | - | Exclusive capability slots: conflict check and replace flow at install |

### 0.15 â€” Translations

4 issues, 0 done.

| Issue | Status | Priority | Title |
| --- | --- | --- | --- |
| [#490](https://github.com/hobnix/server/issues/490) | Backlog | - | Epic: Translations (English is the base, the web interface is translated, German first) |
| [#492](https://github.com/hobnix/server/issues/492) | Backlog | - | Web: one catalog file per language, English as the base, a check that nothing is missing |
| [#493](https://github.com/hobnix/server/issues/493) | Backlog | - | Web: translate the page bodies to German, completely |
| [#494](https://github.com/hobnix/server/issues/494) | Backlog | - | Packages: titles and web texts per language in the manifest, no shell catalogs |

### 0.16 â€” Virtualization

8 issues, 2 done.

| Issue | Status | Priority | Title |
| --- | --- | --- | --- |
| [#199](https://github.com/hobnix/server/issues/199) | Backlog | P1 | Epic: Incus and VM Management |
| [#260](https://github.com/hobnix/server/issues/260) | Backlog | - | VM hardware step: GPU and PCIe passthrough, network bridge |
| [#261](https://github.com/hobnix/server/issues/261) | Backlog | - | Graphical VM console (VNC or SPICE) next to the serial console |
| [#262](https://github.com/hobnix/server/issues/262) | Backlog | - | Hobnix-in-Hobnix test harness: nested instances from the ISO |
| [#929](https://github.com/hobnix/server/issues/929) | - | - | hs twin: clone a server's configuration into a local VM for rehearsal |
| [#930](https://github.com/hobnix/server/issues/930) | - | - | Test-lab fault injection: broken unit, bad route, degraded disk |

Done: [#258](https://github.com/hobnix/server/issues/258), [#259](https://github.com/hobnix/server/issues/259)

### 0.17 â€” Networking and Multi-node

7 issues, 1 done.

| Issue | Status | Priority | Title |
| --- | --- | --- | --- |
| [#421](https://github.com/hobnix/server/issues/421) | Backlog | - | Node: a remote server owned by someone else as a read-only node |
| [#422](https://github.com/hobnix/server/issues/422) | Backlog | - | Edge role: rehearse on a VM or a spare VPS |
| [#918](https://github.com/hobnix/server/issues/918) | - | - | Capability interface ingress.port_forward and overridable [[ports]] per instance |
| [#919](https://github.com/hobnix/server/issues/919) | - | - | router-unifi: port forwards on a UniFi gateway as an ingress.port_forward provider |
| [#921](https://github.com/hobnix/server/issues/921) | - | - | edge-ports: VPS edge node with protocol-aware stubs and wake events |
| [#922](https://github.com/hobnix/server/issues/922) | - | - | Demand-driven hibernation: idle timeout, wake on connect, snapshot before restart |

Done: [#256](https://github.com/hobnix/server/issues/256)

### 1.0 â€” Stable Ecosystem

7 issues, 0 done.

| Issue | Status | Priority | Title |
| --- | --- | --- | --- |
| [#268](https://github.com/hobnix/server/issues/268) | Backlog | - | WebUI package builder: create, edit and package from the browser |
| [#479](https://github.com/hobnix/server/issues/479) | Backlog | - | Bundles: install several apps that belong together in one go |
| [#489](https://github.com/hobnix/server/issues/489) | Backlog | - | A public website: landing page and the documentation outside the repository |
| [#495](https://github.com/hobnix/server/issues/495) | Backlog | - | Epic: Blueprints: pick what the server is for and get it set up in one run |
| [#917](https://github.com/hobnix/server/issues/917) | - | - | Epic: 1.0 showcase: game edge, media hub, PC twin, flight recorder |
| [#931](https://github.com/hobnix/server/issues/931) | - | - | Flight recorder: redacted diagnostic bundle and prefilled issue (capabilities/feedback) |
| [#932](https://github.com/hobnix/server/issues/932) | - | - | Flight recorder: authenticated submission and rollback post-mortem draft |

### No milestone

21 issues, 8 done.

| Issue | Status | Priority | Title |
| --- | --- | --- | --- |
| [#955](https://github.com/hobnix/server/issues/955) | Testing | - | Hardware test: 0.1 â€” Trustworthy Foundation |
| [#956](https://github.com/hobnix/server/issues/956) | Testing | - | Hardware test: 0.2 â€” Safe Updates |
| [#957](https://github.com/hobnix/server/issues/957) | Testing | - | Hardware test: 0.3 â€” Foundations |
| [#958](https://github.com/hobnix/server/issues/958) | Testing | - | Hardware test: 0.4 â€” Install and Onboarding |
| [#959](https://github.com/hobnix/server/issues/959) | Testing | - | Hardware test: 0.5 â€” Capabilities Repository |
| [#960](https://github.com/hobnix/server/issues/960) | Testing | - | Hardware test: 0.6 â€” App Lifecycle |
| [#961](https://github.com/hobnix/server/issues/961) | Testing | - | Hardware test: 0.7 â€” Storage and NAS |
| [#962](https://github.com/hobnix/server/issues/962) | Testing | - | Hardware test: 0.9 â€” Web Components |
| [#1047](https://github.com/hobnix/server/issues/1047) | Testing | - | Hardware test: 0.10.1 â€” Network Map |
| [#1062](https://github.com/hobnix/server/issues/1062) | Testing | - | Hardware test: 0.11 â€” Navigation and Pages |
| [#1063](https://github.com/hobnix/server/issues/1063) | Testing | - | Hardware test: 0.12 â€” Package Pages |
| [#989](https://github.com/hobnix/server/issues/989) | - | - | Hardware test: 0.8 â€” Extensions and Access |
| [#990](https://github.com/hobnix/server/issues/990) | - | - | Hardware test: 0.10 â€” Live Interface |

Done: [#209](https://github.com/hobnix/server/issues/209), [#211](https://github.com/hobnix/server/issues/211), [#213](https://github.com/hobnix/server/issues/213), [#216](https://github.com/hobnix/server/issues/216), [#270](https://github.com/hobnix/server/issues/270), [#315](https://github.com/hobnix/server/issues/315), [#316](https://github.com/hobnix/server/issues/316), [#317](https://github.com/hobnix/server/issues/317)

<!-- END board -->

## Open work from TODO.md

`TODO.md` is the working list of the maintainers: bigger pieces than one issue, with the history of what was merged and what was run on a
real server. An item can appear here and on the board.

<!-- BEGIN todo (python3 scripts/roadmap-gen.py write) -->

| Section | Done | Items |
| --- | --- | --- |
| A. Make what exists trustworthy | 1 | 7 |
| B. Features that fit the design | 0 | 9 |
| C. Recipes (when one is needed, we do it) | 0 | 0 |
| D. Nodes: every server is a node of one repo (design agreed 2026-10-27) | 0 | 4 |
| E. Notifications as a capability (decided 2026-10-27) | 0 | 3 |
| F. Web interface: one source of truth per object (decided 2026-10-27) | 2 | 5 |
| G. File manager (description 2026-10-28) | 2 | 5 |

Not done yet:

| Item | State | What |
| --- | --- | --- |
| A1 | in progress | CI on pull requests only (action minutes ran out when every push ran) |
| A2 | needs a decision | Work through the guides on the real server (steps marked "Not tested on hardware yet.") in blocks (first hs... |
| A3 | needs a decision | Run the recipes never run on the server, in this order |
| A5 | open | Rebuild rehearsal in a VM from only the backup disk and the passphrase (turns docs/backup-and-recovery.md f... |
| A6 | in progress | Monthly restore-drill report pushed to ntfy (the drills exist |
| A7 | open | Housekeeping |
| B8 | in progress | hs update with auto-rollback |
| B9 | in progress | One interface for app-database dumps (Postgres for Immich / Synapse / Authentik, SQLite for the arr apps) s... |
| B10 | in progress | VM coverage in hs backup ct (Incus VMs, not only the domain controller) |
| B11 | open | Later: a cloud (or other) backup target next to the local disk. Not needed now. (The backup to the other se... |
| B12 | in progress | Capacity and trend alerts (pool fill forecast, SSD wear, cache-mover backlog, backup growth, from state.db... |
| B13 | in progress | Notification routing |
| B14 | in progress | Web: the proxyserver pages need the keys the status document still lacks (mail, watcher, game_ports, certif... |
| B15 | in progress | arr: Recycling Bin in Radarr and Sonarr (set by hand now), Remove Completed on the SABnzbd client, the Jell... |
| B16 | open | Investigate the sudo stall of 3 to 5 s (winbind group lookup suspected; sampler log /tmp/slowsudo.log) |
| D1 | in progress | Node registry (hs node add\|list\|remove, local node first), web tree with nodes at the top, the proxyserver... |
| D2 | open | The cousin's server as a read-only node (reuses hs sys deck, the one-read status document) |
| D3 | in progress | A minimal base profile (users, SSH, hs, Tailscale, health, notify) and the edge capabilities (mail, game po... |
| D4 | open | Cut over side by side (the VPS carries the MX and the public ports) |
| E1 | in progress | Plan and step 1 (channel store, provider interface, ntfy as provider #1, hs notify channel ...) |
| E2 | in progress | The Notifications web page |
| E3 | in progress | A second provider (Matrix or email), then the rest as needed |
| F3 | in progress | ; not run in a browser against the real server) Redesign, then retire the duplicated routes |
| F4 | in progress | Game streaming and Posters are capabilities games and posters, off by default (nothing in the tree on a fre... |
| F5 | in progress | Extensions: a package manifest with a [web] section (page as data: reads, actions, a fixed layout; no JavaS... |
| G1 | open | Design from the owner, answers to the open questions at the end of the plan |
| G4 | open | Safety switch: fileManagerWrite is off by default. Run the file manager checks in a VM (copy, move, delete,... |
| G5 | open | Not built: fm du and Calculate size, pause, trash, hs fm ... user commands, the editable path field, owner... |

<!-- END todo -->

## How to take part

- Pick an issue with the label `good first issue` ([CONTRIBUTING.md](https://github.com/hobnix/server/blob/develop/CONTRIBUTING.md)), or ask in a Discussion.
- A change to storage, the network or the firewall is discussed in an issue before it is built.
- Decisions that are hard to undo are written down as records: [Architecture decisions](adr/README.md).
