# Documentation

The same tree is the page Docs of the web interface (`hs docs build`); it comes from [`categories.tsv`](categories.tsv). A new file must be
listed there and below, or `tests/docs.sh` complains. Guides follow [GUIDE-TEMPLATE](GUIDE-TEMPLATE.md).

## Guides

| Guide | What it covers |
| --- | --- |
| [Install](install.md) | From an empty machine to a running server, first login, first-run checklist |
| [Containers and apps](containers-and-apps.md) | Containers and VMs, fixed addresses, snapshots, recipes and packages |
| [Users and shares](users-and-shares.md) | The domain, users and groups, shares and their permissions |
| [Storage and disks](storage-and-disks.md) | ZFS and SnapRAID pools, adding and replacing disks, disk health, moving from Unraid |
| [Disk failures](disk-failures.md) | What to check and do, case by case, when a disk or a pool fails |
| [Encryption and vault](encryption-and-vault.md) | One passphrase, the vault, encrypted disks, unlocking |
| [Backup and recovery](backup-and-recovery.md) | Backups, restoring, snapshots, rebuilding a server |
| [Web interface](web-interface.md) | Turning it on, signing in, pages, terminal, appearance |
| [Network map](network-map.md) | The map of the server, its bridges and instances, with live traffic |
| [Extensions](extensions.md) | Extension commands and services, permissions and what is enforced, package events |
| [Operations](operations.md) | Health alerts, updates, UPS, remote access, the gateway |

The command reference is generated from the command list (`hs help`, or the page *All commands*).

## Apps and extensions

Every package brings its own guide as `guide.md` in its folder (`packages/<name>/`, `capabilities/<name>/`, or the package's repository). The
Docs page shows them under *Apps* and *Extensions*.

## Contributing

| Document | What it is |
| --- | --- |
| [dev-environment](dev-environment.md) | Running tests, the WSL and VM tiers, the agent workflow |
| [GUIDE-TEMPLATE](GUIDE-TEMPLATE.md) | How a guide is written: shape, rules, the glossary |
| [PLAN-modular-core](PLAN-modular-core.md) | The option schema, capabilities and roles |
| [extensions-sdk](extensions-sdk.md) | Write an extension command in shell, Python, Go or Rust: the protocol, the helpers, the examples |
| [PLAN-extensions](PLAN-extensions.md) | Extension packages: commands and web pages |
| [PLAN-live-interface](PLAN-live-interface.md) | Milestone 0.10: the interface follows events, pending rows, delay measured, acknowledge |
| [PLAN-navigation](PLAN-navigation.md) | Milestone 0.11: navigation and pages, decisions D1 to D12 |
| [PLAN-package-pages](PLAN-package-pages.md) | Milestone 0.12 Package Pages: declarative web pages for packages (plan, nothing built) |
| [PLAN-packages](PLAN-packages.md) | Recipes and extensions as packages, repositories, signed releases |
| [PLAN-registry](PLAN-registry.md) | Milestone 0.13: a signed package index with one version per package, core as framework, names, blueprints (plan, nothing built) |
| [PLAN-package-names](PLAN-package-names.md) | Every capability, extension and recipe with its proposed name, for the retouch pass (draft) |
| [PLAN-network-map](PLAN-network-map.md) | A map of this server and its network, the pilot for the UI SDK (plan, nothing built) |
| [Package-API](Package-API.md) | What package.toml may say: the app contract and store fields, by API level |
| [PLAN-capabilities-on-machine](PLAN-capabilities-on-machine.md) | Derived files of an installed capability package |
| [PLAN-recipe-orchestrator](PLAN-recipe-orchestrator.md) | Interactive recipe runs: the orchestrator and its API contract |
| [PLAN-first-run-wizard](PLAN-first-run-wizard.md) | From the ISO to the first dashboard: network, disks, one-time code |
| [PLAN-web-backend](PLAN-web-backend.md) | The web interface backend |
| [THREAT-MODEL-web](THREAT-MODEL-web.md) | Who can reach the web service, what each sign-in can start, protections and open findings |
| [PLAN-disk-health](PLAN-disk-health.md) | Daily SMART baseline, and a disk and pool checklist |
| [PLAN-hardware-runbook](PLAN-hardware-runbook.md) | Runbook for four checks only the owner can run: auto-rollback, rebuild rehearsal, drill report, installer ISO (none run yet) |
| [PLAN-events](PLAN-events.md) | Event sources, consumers and delivery (audit #141 for the event architecture) |
| [events](events.md) | The event catalogue: kind names, levels, payload rules |
| [errors](errors.md) | The error code catalogue: stable names a plan or start can give |
| [notify-rules](notify-rules.md) | Which events become push messages: the rules table, mute a kind, Matrix cards |
| [PLAN-jobs](PLAN-jobs.md) | Job system audit: which commands run as jobs, what a job record holds |
| [PLAN-web-cache](PLAN-web-cache.md) | Hot state for the web interface (collector, live updates; the Redis parts are superseded by ADR 0026) |
| [PLAN-channels](PLAN-channels.md) | Update channels Stable, Beta, Edge on top of develop and main |
| [PLAN-portable-install](PLAN-portable-install.md) | Audit of fixed names and assumptions that break on another machine, options for pools, users and single-disk installs |
| [PLAN-capabilities-repo](PLAN-capabilities-repo.md) | Design for hobnix/capabilities: optional capabilities as packages, pure evaluation, channels, pilot and steps |
| [PLAN-app-lifecycle](PLAN-app-lifecycle.md) | Design for milestone 0.6: one lifecycle for apps and packages, one Install job, app contract, store fields, update policy |
| [PLAN-storage-nas](PLAN-storage-nas.md) | Design for milestone 0.7: file manager write and trash, spin-down, Unraid takeover, partial container backup, off-site copy, further capacity levels |
| [PLAN-extensions-access](PLAN-extensions-access.md) | Design for milestone 0.8: extension protocol and SDK, enforced permissions, package events, roles and API tokens, two-factor login and single sign-on |
| [RELEASE-PROCESS](RELEASE-PROCESS.md) | develop, release branch, main, tags, hotfixes, the milestone branch, ruleset proposals |
| [RELEASE-0.1-checklist](RELEASE-0.1-checklist.md) | The steps to release 0.1.0, what CI and the ISO need, blockers found |
| [RELEASE-NOTES-0.1](RELEASE-NOTES-0.1.md) | Draft release notes of 0.1.0, with the hardware-UNVERIFIED parts |
| [RELEASE-0.2-checklist](RELEASE-0.2-checklist.md) | The steps to release 0.2.0, what the test-lab has and has not passed |
| [RELEASE-NOTES-0.2](RELEASE-NOTES-0.2.md) | Draft release notes of 0.2.0, with what is not verified |
| [RELEASE-NOTES-0.3](RELEASE-NOTES-0.3.md) | Draft release notes of 0.3.0, with what is not verified |
| [RELEASE-NOTES-0.4](RELEASE-NOTES-0.4.md) | Draft release notes of 0.4.0, with what is not verified |
| [RELEASE-NOTES-0.5](RELEASE-NOTES-0.5.md) | Draft release notes of 0.5.0, with what is not verified |
| [RELEASE-NOTES-0.6](RELEASE-NOTES-0.6.md) | Draft release notes of 0.6.0, with what is not verified |
| [RELEASE-NOTES-0.7](RELEASE-NOTES-0.7.md) | Draft release notes of 0.7.0, with what is not verified |
| [RELEASE-NOTES-0.8](RELEASE-NOTES-0.8.md) | Draft release notes of 0.8.0, with what is not verified |
| [RELEASE-NOTES-0.9](RELEASE-NOTES-0.9.md) | Draft release notes of 0.9.0, with what is not verified |
| [RELEASE-NOTES-0.10](RELEASE-NOTES-0.10.md) | Draft release notes of 0.10.0, with what is not verified |
| [RELEASE-NOTES-0.11](RELEASE-NOTES-0.11.md) | Draft release notes of 0.11.0, with what is not verified |
| [RELEASE-NOTES-0.12](RELEASE-NOTES-0.12.md) | Draft release notes of 0.12.0, with what is not verified |
| [PLAN-docker-instances](PLAN-docker-instances.md) | Docker as a capability: locked instances, child apps, recipes with `runs` |
| [PLAN-web-design](PLAN-web-design.md) | Plan: handover of the web design (tokens, components, mockups, open points) |
| [PLAN-selfservice](PLAN-selfservice.md) | Self-service password change for domain users |
| [PLAN-web-auth](PLAN-web-auth.md) | Sign-in and sessions for the web interface |
| [PLAN-website](PLAN-website.md) | Public website: pages, build from the same Markdown, hosting options, release hookup, owner decisions |
| [roadmap](roadmap.md) | Milestones and open work, a snapshot of the GitHub project board |
| [Architecture decisions](adr/README.md) | Decision records (ADRs), starting with Rust behind the `hs sys` contract |
| [CLI-DESIGN](CLI-DESIGN.md) | The look of every `hs` command |
| [Entwicklungsnotizen](Entwicklungsnotizen.md) | Per-feature design notes (grouped by topic) |
