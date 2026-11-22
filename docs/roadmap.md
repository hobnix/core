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
| [hobnix/core#207](https://github.com/hobnix/core/issues/207) | Backlog | P1 | Epic: Documentation and Community |
| [hobnix/core#271](https://github.com/hobnix/core/issues/271) | Backlog | - | Funding: GitHub Sponsors and OpenCollective |
| [hobnix/core#416](https://github.com/hobnix/core/issues/416) | Backlog | - | Work through every guide on a real server and record the date |

### Later â€” after 1.0

4 issues, 0 done.

| Issue | Status | Priority | Title |
| --- | --- | --- | --- |
| [hobnix/core#201](https://github.com/hobnix/core/issues/201) | Backlog | P1 | Epic: Networking Management |
| [hobnix/core#203](https://github.com/hobnix/core/issues/203) | Backlog | P2 | Epic: Multi-node Management |
| [hobnix/core#920](https://github.com/hobnix/core/issues/920) | - | - | Router providers for OPNsense, OpenWrt and UPnP (ingress.port_forward) |
| [hobnix/core#977](https://github.com/hobnix/core/issues/977) | Backlog | - | Epic: Build the web components on UI SDK behaviors (evaluate, then migrate) |

### 0.1 â€” Trustworthy Foundation

73 issues, 60 done.

| Issue | Status | Priority | Title |
| --- | --- | --- | --- |
| [hobnix/core#128](https://github.com/hobnix/core/issues/128) | In Progress | P0 | Epic: Unified Job System |
| [hobnix/core#139](https://github.com/hobnix/core/issues/139) | In Progress | P0 | Epic: Event Architecture |
| [hobnix/core#147](https://github.com/hobnix/core/issues/147) | In Progress | P0 | Epic: Reactive Live-state |
| [hobnix/core#159](https://github.com/hobnix/core/issues/159) | In Progress | P0 | Epic: Reliability and Recovery |
| [hobnix/core#163](https://github.com/hobnix/core/issues/163) | In Progress | P0 | Rebuild rehearsal in a VM from backup disk and passphrase (TODO A5) |
| [hobnix/core#430](https://github.com/hobnix/core/issues/430) | In Progress | - | Test-lab: run the install, update and restore checks in an Incus VM on the server |
| [hobnix/core#520](https://github.com/hobnix/core/issues/520) | In Progress | - | Release the core from GitHub in 0.1 (bring the release workflow of #515 to develop, prove it with a beta tag) |
| [hobnix/core#523](https://github.com/hobnix/core/issues/523) | In Progress | - | CI check: a package that changed since the last tag must have a raised version |
| [hobnix/core#534](https://github.com/hobnix/core/issues/534) | In Progress | - | VM and domain controller restore: missing guide steps, --tag host, wrong messages |
| [hobnix/core#161](https://github.com/hobnix/core/issues/161) | Ready | P0 | Run the auto-rollback on the real server and record the result |
| [hobnix/core#522](https://github.com/hobnix/core/issues/522) | Ready | - | Release the package repositories from GitHub (shared workflow for recipes, extensions, capabilities) |
| [hobnix/core#846](https://github.com/hobnix/core/issues/846) | Backlog | - | Flaky CI tests: job-step-live and dialogues (Broken pipe) |
| [hobnix/core#900](https://github.com/hobnix/core/issues/900) | Backlog | - | Error codes: stable named codes in one catalogue (ADR 0028) |

Done: [hobnix/core#121](https://github.com/hobnix/core/issues/121), [hobnix/core#122](https://github.com/hobnix/core/issues/122), [hobnix/core#123](https://github.com/hobnix/core/issues/123), [hobnix/core#124](https://github.com/hobnix/core/issues/124), [hobnix/core#125](https://github.com/hobnix/core/issues/125), [hobnix/core#126](https://github.com/hobnix/core/issues/126), [hobnix/core#127](https://github.com/hobnix/core/issues/127), [hobnix/core#129](https://github.com/hobnix/core/issues/129), [hobnix/core#131](https://github.com/hobnix/core/issues/131), [hobnix/core#133](https://github.com/hobnix/core/issues/133), [hobnix/core#135](https://github.com/hobnix/core/issues/135), [hobnix/core#137](https://github.com/hobnix/core/issues/137), [hobnix/core#141](https://github.com/hobnix/core/issues/141), [hobnix/core#143](https://github.com/hobnix/core/issues/143), [hobnix/core#145](https://github.com/hobnix/core/issues/145), [hobnix/core#149](https://github.com/hobnix/core/issues/149), [hobnix/core#151](https://github.com/hobnix/core/issues/151), [hobnix/core#153](https://github.com/hobnix/core/issues/153), [hobnix/core#155](https://github.com/hobnix/core/issues/155), [hobnix/core#157](https://github.com/hobnix/core/issues/157), [hobnix/core#165](https://github.com/hobnix/core/issues/165), [hobnix/core#167](https://github.com/hobnix/core/issues/167), [hobnix/core#169](https://github.com/hobnix/core/issues/169), [hobnix/core#171](https://github.com/hobnix/core/issues/171), [hobnix/core#252](https://github.com/hobnix/core/issues/252), [hobnix/core#253](https://github.com/hobnix/core/issues/253), [hobnix/core#286](https://github.com/hobnix/core/issues/286), [hobnix/core#288](https://github.com/hobnix/core/issues/288), [hobnix/core#289](https://github.com/hobnix/core/issues/289), [hobnix/core#290](https://github.com/hobnix/core/issues/290), [hobnix/core#291](https://github.com/hobnix/core/issues/291), [hobnix/core#292](https://github.com/hobnix/core/issues/292), [hobnix/core#293](https://github.com/hobnix/core/issues/293), [hobnix/core#294](https://github.com/hobnix/core/issues/294), [hobnix/core#295](https://github.com/hobnix/core/issues/295), [hobnix/core#296](https://github.com/hobnix/core/issues/296), [hobnix/core#297](https://github.com/hobnix/core/issues/297), [hobnix/core#298](https://github.com/hobnix/core/issues/298), [hobnix/core#322](https://github.com/hobnix/core/issues/322), [hobnix/core#323](https://github.com/hobnix/core/issues/323), [hobnix/core#324](https://github.com/hobnix/core/issues/324), [hobnix/core#385](https://github.com/hobnix/core/issues/385), [hobnix/core#386](https://github.com/hobnix/core/issues/386), [hobnix/core#387](https://github.com/hobnix/core/issues/387), [hobnix/core#388](https://github.com/hobnix/core/issues/388), [hobnix/core#389](https://github.com/hobnix/core/issues/389), [hobnix/core#390](https://github.com/hobnix/core/issues/390), [hobnix/core#391](https://github.com/hobnix/core/issues/391), [hobnix/core#392](https://github.com/hobnix/core/issues/392), [hobnix/core#393](https://github.com/hobnix/core/issues/393), [hobnix/core#396](https://github.com/hobnix/core/issues/396), [hobnix/core#397](https://github.com/hobnix/core/issues/397), [hobnix/core#398](https://github.com/hobnix/core/issues/398), [hobnix/core#399](https://github.com/hobnix/core/issues/399), [hobnix/core#414](https://github.com/hobnix/core/issues/414), [hobnix/core#415](https://github.com/hobnix/core/issues/415), [hobnix/core#417](https://github.com/hobnix/core/issues/417), [hobnix/core#521](https://github.com/hobnix/core/issues/521), [hobnix/core#567](https://github.com/hobnix/core/issues/567), [hobnix/core#607](https://github.com/hobnix/core/issues/607)

### 0.2 â€” Safe Updates

14 issues, 13 done.

| Issue | Status | Priority | Title |
| --- | --- | --- | --- |
| [hobnix/core#439](https://github.com/hobnix/core/issues/439) | Blocked | - | CI: test develop after each merge, faster quick tests, required checks |

Done: [hobnix/core#185](https://github.com/hobnix/core/issues/185), [hobnix/core#219](https://github.com/hobnix/core/issues/219), [hobnix/core#231](https://github.com/hobnix/core/issues/231), [hobnix/core#233](https://github.com/hobnix/core/issues/233), [hobnix/core#254](https://github.com/hobnix/core/issues/254), [hobnix/core#432](https://github.com/hobnix/core/issues/432), [hobnix/core#433](https://github.com/hobnix/core/issues/433), [hobnix/core#435](https://github.com/hobnix/core/issues/435), [hobnix/core#436](https://github.com/hobnix/core/issues/436), [hobnix/core#437](https://github.com/hobnix/core/issues/437), [hobnix/core#438](https://github.com/hobnix/core/issues/438), [hobnix/core#458](https://github.com/hobnix/core/issues/458), [hobnix/core#464](https://github.com/hobnix/core/issues/464)

### 0.2.1 â€” Faster test-lab

1 issues, 0 done.

| Issue | Status | Priority | Title |
| --- | --- | --- | --- |
| [hobnix/core#712](https://github.com/hobnix/core/issues/712) | In Progress | - | Test-lab: a faster run that does not grow with every roadmap step |

### 0.3 â€” Foundations

9 issues, 8 done.

| Issue | Status | Priority | Title |
| --- | --- | --- | --- |
| [hobnix/core#420](https://github.com/hobnix/core/issues/420) | Backlog | - | Notifications: run channels, routing and the web page on a server; choose the next providers |

Done: [hobnix/core#423](https://github.com/hobnix/core/issues/423), [hobnix/core#431](https://github.com/hobnix/core/issues/431), [hobnix/core#442](https://github.com/hobnix/core/issues/442), [hobnix/core#443](https://github.com/hobnix/core/issues/443), [hobnix/core#444](https://github.com/hobnix/core/issues/444), [hobnix/core#482](https://github.com/hobnix/core/issues/482), [hobnix/core#491](https://github.com/hobnix/core/issues/491), [hobnix/core#560](https://github.com/hobnix/core/issues/560)

### 0.4 â€” Install and Onboarding

14 issues, 11 done.

| Issue | Status | Priority | Title |
| --- | --- | --- | --- |
| [hobnix/core#173](https://github.com/hobnix/core/issues/173) | In Progress | P0 | Epic: Installation and Onboarding |
| [hobnix/core#175](https://github.com/hobnix/core/issues/175) | Backlog | P0 | Boot the ISO on real hardware or a VM, record what breaks |
| [hobnix/core#459](https://github.com/hobnix/core/issues/459) | Backlog | - | Epic: Works on a machine that is not the author's |

Done: [hobnix/core#179](https://github.com/hobnix/core/issues/179), [hobnix/core#181](https://github.com/hobnix/core/issues/181), [hobnix/core#183](https://github.com/hobnix/core/issues/183), [hobnix/core#573](https://github.com/hobnix/core/issues/573), [hobnix/core#574](https://github.com/hobnix/core/issues/574), [hobnix/core#575](https://github.com/hobnix/core/issues/575), [hobnix/core#576](https://github.com/hobnix/core/issues/576), [hobnix/core#577](https://github.com/hobnix/core/issues/577), [hobnix/core#580](https://github.com/hobnix/core/issues/580), [hobnix/core#581](https://github.com/hobnix/core/issues/581), [hobnix/core#596](https://github.com/hobnix/core/issues/596)

### 0.5 â€” Capabilities Repository

7 issues, 7 done.

Done: [hobnix/core#177](https://github.com/hobnix/core/issues/177), [hobnix/core#221](https://github.com/hobnix/core/issues/221), [hobnix/core#224](https://github.com/hobnix/core/issues/224), [hobnix/core#228](https://github.com/hobnix/core/issues/228), [hobnix/core#229](https://github.com/hobnix/core/issues/229), [hobnix/core#235](https://github.com/hobnix/core/issues/235), [hobnix/core#615](https://github.com/hobnix/core/issues/615)

### 0.6 â€” App Lifecycle

22 issues, 18 done.

| Issue | Status | Priority | Title |
| --- | --- | --- | --- |
| [hobnix/core#187](https://github.com/hobnix/core/issues/187) | In Progress | P0 | Epic: Application Lifecycle |
| [hobnix/core#613](https://github.com/hobnix/core/issues/613) | In Progress | - | Interactive recipe: the wizard form's address is asked again in the dialog; a run on an existing app cannot ask again |
| [hobnix/core#899](https://github.com/hobnix/core/issues/899) | In Review | - | Apply of a Docker app fails with "exit 127" when its images are not downloaded yet |
| [hobnix/core#850](https://github.com/hobnix/core/issues/850) | Backlog | - | Install dialog warns "the server is rebuilt" for an app that does not rebuild (ntfy) |

Done: [hobnix/core#237](https://github.com/hobnix/core/issues/237), [hobnix/core#238](https://github.com/hobnix/core/issues/238), [hobnix/core#240](https://github.com/hobnix/core/issues/240), [hobnix/core#257](https://github.com/hobnix/core/issues/257), [hobnix/core#263](https://github.com/hobnix/core/issues/263), [hobnix/core#264](https://github.com/hobnix/core/issues/264), [hobnix/core#265](https://github.com/hobnix/core/issues/265), [hobnix/core#266](https://github.com/hobnix/core/issues/266), [hobnix/core#267](https://github.com/hobnix/core/issues/267), [hobnix/core#465](https://github.com/hobnix/core/issues/465), [hobnix/core#466](https://github.com/hobnix/core/issues/466), [hobnix/core#467](https://github.com/hobnix/core/issues/467), [hobnix/core#468](https://github.com/hobnix/core/issues/468), [hobnix/core#469](https://github.com/hobnix/core/issues/469), [hobnix/core#470](https://github.com/hobnix/core/issues/470), [hobnix/core#471](https://github.com/hobnix/core/issues/471), [hobnix/core#612](https://github.com/hobnix/core/issues/612), [hobnix/core#614](https://github.com/hobnix/core/issues/614)

### 0.7 â€” Storage and NAS

10 issues, 3 done.

| Issue | Status | Priority | Title |
| --- | --- | --- | --- |
| [hobnix/core#189](https://github.com/hobnix/core/issues/189) | In Progress | P0 | Epic: Storage Management |
| [hobnix/core#418](https://github.com/hobnix/core/issues/418) | In Progress | - | Backup target outside the house (cloud or another server) |
| [hobnix/core#419](https://github.com/hobnix/core/issues/419) | In Progress | - | Capacity alerts: further automatic mitigation levels |
| [hobnix/core#425](https://github.com/hobnix/core/issues/425) | In Progress | - | File manager: run the write checks in a VM, then switch `fileManagerWrite` on |
| [hobnix/core#460](https://github.com/hobnix/core/issues/460) | In Progress | - | Take over the disks of an Unraid server in place |
| [hobnix/core#527](https://github.com/hobnix/core/issues/527) | In Progress | - | Back up only chosen parts of a container (include and exclude paths, like a .gitignore) |
| [hobnix/core#699](https://github.com/hobnix/core/issues/699) | Backlog | - | hs pool bulk add as a job leaves /bulk unmounted (mergerfs ends with the job unit) |

Done: [hobnix/core#255](https://github.com/hobnix/core/issues/255), [hobnix/core#426](https://github.com/hobnix/core/issues/426), [hobnix/core#463](https://github.com/hobnix/core/issues/463)

### 0.8 â€” Extensions and Access

11 issues, 0 done.

| Issue | Status | Priority | Title |
| --- | --- | --- | --- |
| [hobnix/core#197](https://github.com/hobnix/core/issues/197) | In Progress | P1 | Epic: Extension Protocol and SDK |
| [hobnix/core#239](https://github.com/hobnix/core/issues/239) | In Progress | P1 | Enforce extension permissions instead of only declaring them |
| [hobnix/core#313](https://github.com/hobnix/core/issues/313) | In Progress | - | Packages declare the events they provide |
| [hobnix/core#434](https://github.com/hobnix/core/issues/434) | In Progress | - | Roles and API tokens: build what ADR 0012 decides |
| [hobnix/core#462](https://github.com/hobnix/core/issues/462) | Backlog | - | Two-factor login and single sign-on for the web interface |
| [hobnix/core#926](https://github.com/hobnix/core/issues/926) | - | - | Manifest block [integrations.media] for media apps |
| [hobnix/core#927](https://github.com/hobnix/core/issues/927) | - | - | Event retention classes (ephemeral, audit, metric) and a rollup helper for extensions |
| [hobnix/core#944](https://github.com/hobnix/core/issues/944) | - | - | Security: tokens may reach rows that outlive the token (ssh-key, pkg, config, system) |
| [hobnix/core#945](https://github.com/hobnix/core/issues/945) | - | - | Security: a domain session keeps its role for up to 12 hours |
| [hobnix/core#946](https://github.com/hobnix/core/issues/946) | - | - | Security: viewer can list file names of sensitive shares and search backups |
| [hobnix/core#947](https://github.com/hobnix/core/issues/947) | - | - | Security: extension confinement leaves secrets readable; no deny list for fs.write |

### 0.8.5 â€” Web Design

8 issues, 8 done.

Done: [hobnix/core#768](https://github.com/hobnix/core/issues/768), [hobnix/core#769](https://github.com/hobnix/core/issues/769), [hobnix/core#770](https://github.com/hobnix/core/issues/770), [hobnix/core#771](https://github.com/hobnix/core/issues/771), [hobnix/core#772](https://github.com/hobnix/core/issues/772), [hobnix/core#773](https://github.com/hobnix/core/issues/773), [hobnix/core#774](https://github.com/hobnix/core/issues/774), [hobnix/core#775](https://github.com/hobnix/core/issues/775)

### 0.9 â€” Web Components

14 issues, 10 done.

| Issue | Status | Priority | Title |
| --- | --- | --- | --- |
| [hobnix/core#191](https://github.com/hobnix/core/issues/191) | In Progress | P1 | Epic: Component Library |
| [hobnix/core#450](https://github.com/hobnix/core/issues/450) | In Progress | - | Web: move the pages to the shared components, group by group |
| [hobnix/core#193](https://github.com/hobnix/core/issues/193) | Backlog | P1 | Epic: Storybook and Design System |
| [hobnix/core#879](https://github.com/hobnix/core/issues/879) | Backlog | - | Web: Storybook set up in web/ (first stories) |

Done: [hobnix/core#445](https://github.com/hobnix/core/issues/445), [hobnix/core#446](https://github.com/hobnix/core/issues/446), [hobnix/core#447](https://github.com/hobnix/core/issues/447), [hobnix/core#448](https://github.com/hobnix/core/issues/448), [hobnix/core#449](https://github.com/hobnix/core/issues/449), [hobnix/core#461](https://github.com/hobnix/core/issues/461), [hobnix/core#782](https://github.com/hobnix/core/issues/782), [hobnix/core#783](https://github.com/hobnix/core/issues/783), [hobnix/core#784](https://github.com/hobnix/core/issues/784), [hobnix/core#785](https://github.com/hobnix/core/issues/785)

### 0.10 â€” Live Interface

21 issues, 0 done.

| Issue | Status | Priority | Title |
| --- | --- | --- | --- |
| [hobnix/core#483](https://github.com/hobnix/core/issues/483) | Testing | - | An action shows at once: rows take their pending state from the job event |
| [hobnix/core#952](https://github.com/hobnix/core/issues/952) | Testing | - | SnapRAID: per-share skipped folders and removal limits for the parity sync |
| [hobnix/core#480](https://github.com/hobnix/core/issues/480) | Backlog | - | Epic: The interface follows events, it does not poll |
| [hobnix/core#481](https://github.com/hobnix/core/issues/481) | Backlog | - | Live state on by default, one mode, one store (decide: Redis or the state database) |
| [hobnix/core#484](https://github.com/hobnix/core/issues/484) | Backlog | - | More event sources: disks plugged and pulled (udev), units that start, stop or fail (systemd) |
| [hobnix/core#485](https://github.com/hobnix/core/issues/485) | Backlog | - | End-to-end test: an action updates the open page without a reload, within seconds |
| [hobnix/core#486](https://github.com/hobnix/core/issues/486) | Backlog | - | Measure the delay from "something changed" to "the browser shows it" |
| [hobnix/core#559](https://github.com/hobnix/core/issues/559) | Backlog | - | Live state: named events instead of broad wake-up groups |
| [hobnix/core#561](https://github.com/hobnix/core/issues/561) | Backlog | - | Live state: collector writes documents to the state database |
| [hobnix/core#562](https://github.com/hobnix/core/issues/562) | Backlog | - | Live state: web reads topics and /api/events from the database only |
| [hobnix/core#563](https://github.com/hobnix/core/issues/563) | Backlog | - | Live state: remove the liveState option and the Redis service |
| [hobnix/core#564](https://github.com/hobnix/core/issues/564) | Backlog | - | Live state: one status on the Data page and in hs sys live status |
| [hobnix/core#565](https://github.com/hobnix/core/issues/565) | Backlog | - | Live state: rewrite docs for the state database |
| [hobnix/core#566](https://github.com/hobnix/core/issues/566) | Backlog | - | Live state: real-server check, a terminal change shows in the open page |
| [hobnix/core#617](https://github.com/hobnix/core/issues/617) | Backlog | - | Follow-ups of the 0.1 acceptance audit: job records, event kinds, Events page |
| [hobnix/core#619](https://github.com/hobnix/core/issues/619) | Backlog | - | Acknowledge a health problem (quiet until it resolves and fails again) and a notification inbox |
| [hobnix/core#896](https://github.com/hobnix/core/issues/896) | Backlog | - | Jobs: plan dialog closes on Start, toasts report the job; Docker start/stop/restart as jobs |
| [hobnix/core#965](https://github.com/hobnix/core/issues/965) | - | - | Role-gate every change button: viewer still sees enabled buttons (disk add and others) |
| [hobnix/core#971](https://github.com/hobnix/core/issues/971) | - | - | Events timeline has no card or background, hard to read |
| [hobnix/core#972](https://github.com/hobnix/core/issues/972) | - | - | App install wizard shows step 1 while the job is at the last question, and the question gives no toast |
| [hobnix/core#973](https://github.com/hobnix/core/issues/973) | - | - | Jobs page: list and detail side by side (about 60/40), selection stays visible without scrolling |

### 0.10.1 â€” Network Map

9 issues, 0 done.

| Issue | Status | Priority | Title |
| --- | --- | --- | --- |
| [hobnix/core#870](https://github.com/hobnix/core/issues/870) | Backlog | - | Epic: Network map of this server |
| [hobnix/core#871](https://github.com/hobnix/core/issues/871) | Backlog | - | Web: UI SDK spike (pinned beta, one component, story) |
| [hobnix/core#872](https://github.com/hobnix/core/issues/872) | Backlog | - | Backend: hs sys netmap (graph document) |
| [hobnix/core#873](https://github.com/hobnix/core/issues/873) | Backlog | - | Backend: counters stream for the map (sampled only while a page is open) |
| [hobnix/core#874](https://github.com/hobnix/core/issues/874) | Backlog | - | Web: layout function for the map (graph in, positions out) |
| [hobnix/core#875](https://github.com/hobnix/core/issues/875) | Backlog | - | Web: draw the map (SVG nodes, canvas traffic dots) |
| [hobnix/core#876](https://github.com/hobnix/core/issues/876) | Backlog | - | Web: map without a mouse (roving focus, detail popover, table view) |
| [hobnix/core#877](https://github.com/hobnix/core/issues/877) | Backlog | - | Web: network map page and demo-mode data |
| [hobnix/core#878](https://github.com/hobnix/core/issues/878) | Backlog | - | Test and docs: network map |

### 0.11 â€” Navigation and Pages

10 issues, 0 done.

| Issue | Status | Priority | Title |
| --- | --- | --- | --- |
| [hobnix/core#427](https://github.com/hobnix/core/issues/427) | Backlog | - | Mobile-friendly web interface and a read-only status page |
| [hobnix/core#451](https://github.com/hobnix/core/issues/451) | Backlog | - | Epic: Navigation and page structure |
| [hobnix/core#452](https://github.com/hobnix/core/issues/452) | Backlog | - | Web: regroup the tree (fewer groups, only places) |
| [hobnix/core#453](https://github.com/hobnix/core/issues/453) | Backlog | - | Web: a page per object (disk, pool, share, instance, user) instead of a drawer with tabs |
| [hobnix/core#454](https://github.com/hobnix/core/issues/454) | Backlog | - | Web: quick look as an overlay, so selecting a row never moves the list |
| [hobnix/core#455](https://github.com/hobnix/core/issues/455) | Backlog | - | Web: the selected row and tab live in the address |
| [hobnix/core#456](https://github.com/hobnix/core/issues/456) | Backlog | - | Web: pools come from data, not from fixed names |
| [hobnix/core#457](https://github.com/hobnix/core/issues/457) | Backlog | - | Web: group pages that show the state of the group, one or two main actions plus a More menu |
| [hobnix/core#487](https://github.com/hobnix/core/issues/487) | Backlog | - | Accessibility: the whole interface by keyboard and with a screen reader |
| [hobnix/core#776](https://github.com/hobnix/core/issues/776) | Backlog | - | Web design: thin slice, the disk page |

### 0.12 â€” Package Pages

8 issues, 0 done.

| Issue | Status | Priority | Title |
| --- | --- | --- | --- |
| [hobnix/core#195](https://github.com/hobnix/core/issues/195) | Backlog | P1 | Epic: Declarative WebUI |
| [hobnix/core#424](https://github.com/hobnix/core/issues/424) | Backlog | - | Recipes: status panel and allowlisted actions from the manifest `[web]` section |
| [hobnix/core#472](https://github.com/hobnix/core/issues/472) | Backlog | - | Slots: the fixed places where a package may add to the interface |
| [hobnix/core#473](https://github.com/hobnix/core/issues/473) | Backlog | - | The block list is the component library: a registry with schemas, and the blocks that are missing |
| [hobnix/core#488](https://github.com/hobnix/core/issues/488) | Backlog | - | Error messages: what happened, why, and the next step, with a stable code |
| [hobnix/core#790](https://github.com/hobnix/core/issues/790) | Backlog | - | Packages place their pages: group, order, tabs, template and card state in [web.page] |
| [hobnix/core#924](https://github.com/hobnix/core/issues/924) | - | - | ext-game-lobbies: lobbies card, worlds and console tab, wake link |
| [hobnix/core#928](https://github.com/hobnix/core/issues/928) | - | - | ext-media-hub: media statistics, poster trigger and storage suggestions |

### 0.13 â€” Package Registry

2 issues, 0 done.

| Issue | Status | Priority | Title |
| --- | --- | --- | --- |
| [hobnix/core#217](https://github.com/hobnix/core/issues/217) | In Progress | P0 | Epic: Capabilities repository and channels |
| [hobnix/core#225](https://github.com/hobnix/core/issues/225) | Backlog | P0 | Create hobnix/capabilities, move the first optional capability as a pilot |

### 0.14 â€” Marketplace

12 issues, 0 done.

| Issue | Status | Priority | Title |
| --- | --- | --- | --- |
| [hobnix/core#205](https://github.com/hobnix/core/issues/205) | Backlog | P2 | Epic: Marketplace and Ecosystem |
| [hobnix/core#269](https://github.com/hobnix/core/issues/269) | Backlog | - | Import Unraid templates and Proxmox vzdump archives |
| [hobnix/core#474](https://github.com/hobnix/core/issues/474) | Backlog | - | Marketplace as a store: cards, categories, Installed and Updates, a page per package |
| [hobnix/core#475](https://github.com/hobnix/core/issues/475) | Backlog | - | The package index refreshes by itself |
| [hobnix/core#476](https://github.com/hobnix/core/issues/476) | Backlog | - | One place for updates: the system, apps and packages |
| [hobnix/core#477](https://github.com/hobnix/core/issues/477) | Backlog | - | Trust shown plainly: official or community, and a "tested on a real server" date |
| [hobnix/core#478](https://github.com/hobnix/core/issues/478) | Backlog | - | A page for every installed app, built from its manifest |
| [hobnix/core#793](https://github.com/hobnix/core/issues/793) | Backlog | - | Marketplace: a "fits this server" check from the package's declared needs |
| [hobnix/core#923](https://github.com/hobnix/core/issues/923) | - | - | Game recipes: gold-standard set and a generic custom-game-server |
| [hobnix/core#925](https://github.com/hobnix/core/issues/925) | - | - | hs pkg import-egg: turn a Pelican/Pterodactyl egg into a recipe draft |
| [hobnix/core#933](https://github.com/hobnix/core/issues/933) | - | - | Package identity <repo>/<package>: official shorthand, scoped updates, shadowing warning |
| [hobnix/core#934](https://github.com/hobnix/core/issues/934) | - | - | Exclusive capability slots: conflict check and replace flow at install |

### 0.15 â€” Translations

4 issues, 0 done.

| Issue | Status | Priority | Title |
| --- | --- | --- | --- |
| [hobnix/core#490](https://github.com/hobnix/core/issues/490) | Backlog | - | Epic: Translations (English is the base, the web interface is translated, German first) |
| [hobnix/core#492](https://github.com/hobnix/core/issues/492) | Backlog | - | Web: one catalog file per language, English as the base, a check that nothing is missing |
| [hobnix/core#493](https://github.com/hobnix/core/issues/493) | Backlog | - | Web: translate the page bodies to German, completely |
| [hobnix/core#494](https://github.com/hobnix/core/issues/494) | Backlog | - | Packages: titles and web texts per language in the manifest, no shell catalogs |

### 0.16 â€” Virtualization

8 issues, 2 done.

| Issue | Status | Priority | Title |
| --- | --- | --- | --- |
| [hobnix/core#199](https://github.com/hobnix/core/issues/199) | Backlog | P1 | Epic: Incus and VM Management |
| [hobnix/core#260](https://github.com/hobnix/core/issues/260) | Backlog | - | VM hardware step: GPU and PCIe passthrough, network bridge |
| [hobnix/core#261](https://github.com/hobnix/core/issues/261) | Backlog | - | Graphical VM console (VNC or SPICE) next to the serial console |
| [hobnix/core#262](https://github.com/hobnix/core/issues/262) | Backlog | - | Hobnix-in-Hobnix test harness: nested instances from the ISO |
| [hobnix/core#929](https://github.com/hobnix/core/issues/929) | - | - | hs twin: clone a server's configuration into a local VM for rehearsal |
| [hobnix/core#930](https://github.com/hobnix/core/issues/930) | - | - | Test-lab fault injection: broken unit, bad route, degraded disk |

Done: [hobnix/core#258](https://github.com/hobnix/core/issues/258), [hobnix/core#259](https://github.com/hobnix/core/issues/259)

### 0.17 â€” Networking and Multi-node

7 issues, 1 done.

| Issue | Status | Priority | Title |
| --- | --- | --- | --- |
| [hobnix/core#421](https://github.com/hobnix/core/issues/421) | Backlog | - | Node: a remote server owned by someone else as a read-only node |
| [hobnix/core#422](https://github.com/hobnix/core/issues/422) | Backlog | - | Edge role: rehearse on a VM or a spare VPS |
| [hobnix/core#918](https://github.com/hobnix/core/issues/918) | - | - | Capability interface ingress.port_forward and overridable [[ports]] per instance |
| [hobnix/core#919](https://github.com/hobnix/core/issues/919) | - | - | router-unifi: port forwards on a UniFi gateway as an ingress.port_forward provider |
| [hobnix/core#921](https://github.com/hobnix/core/issues/921) | - | - | edge-ports: VPS edge node with protocol-aware stubs and wake events |
| [hobnix/core#922](https://github.com/hobnix/core/issues/922) | - | - | Demand-driven hibernation: idle timeout, wake on connect, snapshot before restart |

Done: [hobnix/core#256](https://github.com/hobnix/core/issues/256)

### 1.0 â€” Stable Ecosystem

7 issues, 0 done.

| Issue | Status | Priority | Title |
| --- | --- | --- | --- |
| [hobnix/core#268](https://github.com/hobnix/core/issues/268) | Backlog | - | WebUI package builder: create, edit and package from the browser |
| [hobnix/core#479](https://github.com/hobnix/core/issues/479) | Backlog | - | Bundles: install several apps that belong together in one go |
| [hobnix/core#489](https://github.com/hobnix/core/issues/489) | Backlog | - | A public website: landing page and the documentation outside the repository |
| [hobnix/core#495](https://github.com/hobnix/core/issues/495) | Backlog | - | Epic: Blueprints: pick what the server is for and get it set up in one run |
| [hobnix/core#917](https://github.com/hobnix/core/issues/917) | - | - | Epic: 1.0 showcase: game edge, media hub, PC twin, flight recorder |
| [hobnix/core#931](https://github.com/hobnix/core/issues/931) | - | - | Flight recorder: redacted diagnostic bundle and prefilled issue (capabilities/feedback) |
| [hobnix/core#932](https://github.com/hobnix/core/issues/932) | - | - | Flight recorder: authenticated submission and rollback post-mortem draft |

### No milestone

21 issues, 8 done.

| Issue | Status | Priority | Title |
| --- | --- | --- | --- |
| [hobnix/core#955](https://github.com/hobnix/core/issues/955) | Testing | - | Hardware test: 0.1 â€” Trustworthy Foundation |
| [hobnix/core#956](https://github.com/hobnix/core/issues/956) | Testing | - | Hardware test: 0.2 â€” Safe Updates |
| [hobnix/core#957](https://github.com/hobnix/core/issues/957) | Testing | - | Hardware test: 0.3 â€” Foundations |
| [hobnix/core#958](https://github.com/hobnix/core/issues/958) | Testing | - | Hardware test: 0.4 â€” Install and Onboarding |
| [hobnix/core#959](https://github.com/hobnix/core/issues/959) | Testing | - | Hardware test: 0.5 â€” Capabilities Repository |
| [hobnix/core#960](https://github.com/hobnix/core/issues/960) | Testing | - | Hardware test: 0.6 â€” App Lifecycle |
| [hobnix/core#961](https://github.com/hobnix/core/issues/961) | Testing | - | Hardware test: 0.7 â€” Storage and NAS |
| [hobnix/core#962](https://github.com/hobnix/core/issues/962) | Testing | - | Hardware test: 0.9 â€” Web Components |
| [hobnix/core#1047](https://github.com/hobnix/core/issues/1047) | Testing | - | Hardware test: 0.10.1 â€” Network Map |
| [hobnix/core#1062](https://github.com/hobnix/core/issues/1062) | Testing | - | Hardware test: 0.11 â€” Navigation and Pages |
| [hobnix/core#1063](https://github.com/hobnix/core/issues/1063) | Testing | - | Hardware test: 0.12 â€” Package Pages |
| [hobnix/core#989](https://github.com/hobnix/core/issues/989) | - | - | Hardware test: 0.8 â€” Extensions and Access |
| [hobnix/core#990](https://github.com/hobnix/core/issues/990) | - | - | Hardware test: 0.10 â€” Live Interface |

Done: [hobnix/core#209](https://github.com/hobnix/core/issues/209), [hobnix/core#211](https://github.com/hobnix/core/issues/211), [hobnix/core#213](https://github.com/hobnix/core/issues/213), [hobnix/core#216](https://github.com/hobnix/core/issues/216), [hobnix/core#270](https://github.com/hobnix/core/issues/270), [hobnix/core#315](https://github.com/hobnix/core/issues/315), [hobnix/core#316](https://github.com/hobnix/core/issues/316), [hobnix/core#317](https://github.com/hobnix/core/issues/317)

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
