# 0027: Package lifecycle states (one vocabulary for every kind)

Status: Accepted (2026-11-16)
Issue: hobnix/server#467 (milestone 0.6 App Lifecycle, docs/PLAN-app-lifecycle.md Q1, D1 to D3)

Nothing here was run on a server. The read is built (`hs sys pkg states`, `hs sys apps list`) and tested on fixtures.

## Context

Each kind had its own words: a recipe `installed|partly|not installed|parked|unknown` (`hs sys recipes list`), an extension or capability `on|off`
(`hs sys parts list`) plus `hs sys parts pending`, a market row `new|current|update|waits|orphan` (`hs sys pkg market`). The web interface mixed
them by position. Milestones 0.11 and 0.13 read the same words, so they are decided once.

## Decision

**Four stages**, in a line, for every kind: `available`, `installed`, `on`, `running`. **Flags** do not change the stage: `update`, `waits`,
`orphan`, `pending`, `failed`, `unhealthy`, `stopped`. Output is a comma list, `-` for none, in that order.

| Stage | recipe | extension | capability |
| --- | --- | --- | --- |
| `available` | in the market, no copy here | in the market, no copy here | in the market, no copy here |
| `installed` | the copy is here (current/ or this tree) and no instance exists | copy there, parts list `off` | copy there, parts list `off` |
| `on` | at least one of its instances exists (recipes list `installed` or `partly`) | parts list `on` and a rebuild is pending | parts list `on` and a rebuild is pending |
| `running` | all existing instances are running (incus) | parts list `on` and not pending | parts list `on` and not pending |

- `set up` (the answers `recipe-<ct>.conf` exist, no instance yet) is a recipe sub-state between `installed` and `on`. It is **not** a fifth stage:
  the output stays four words; `set up` is only a word for text and dialogs.
- A recipe with an instance that is stopped stays `on` and gets the flag `stopped`. Without a container list (incus does not answer) a recipe is
  never `running`. `parked` and `unknown` recipes get their stage from the rest and no flag.
- `update`, `waits`, `orphan` come from the market state of the same name. `pending` is a name in `sys parts pending`. `failed` and `unhealthy`
  are reserved for the install job (Q3) and the app contract (Q4); nothing sets them yet.
- A package of this tree that is not in the market (built in) is listed with repo, available and installed `-`; its stage comes from the parts or
  the recipes list.

## The read

`hs sys pkg states` (`scripts/pkg.sh --states`, merge in `scripts/pkg_states.py`): tab separated, empty field `-`, sorted by name,
`name, kind, stage, flags, repo, available, installed, instances, title`. `hs sys apps list` is its recipe rows. `sys pkg market` and
`sys recipes list` keep their shape (tests/pkg.sh compares them with golden files).

## Verbs

The interface uses the same verbs for every kind: **Install** (`available` towards `on`), **Remove** (back to `available`, data stays), **Update**
(flag `update`). **Start/Stop** only for the instances of a recipe. **Turn off/on** (secondary) only for extension and capability.

## API stability

The stage and flag words are part of the machine-readable contract. Changing or removing a word, or the column order, needs an API level bump
(`scripts/lib/api-level`) and one release in which the old shape is still served (deprecation). Adding a flag word at the end of the list or a
column at the end does not; readers must ignore flags they do not know.
