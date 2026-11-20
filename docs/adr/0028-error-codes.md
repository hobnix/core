# 0028: Error codes: stable named codes in one catalogue, exit numbers stay 0/1/other

Status: Accepted (2026-11-20, owner)
Issue: hobnix/server#900 (milestone 0.1 Trustworthy Foundation, epic #159 Reliability and Recovery)

Nothing here was built or run on a server.

The build is issue #488 in milestone 0.12.

## Context

A plan or start of a change (`hs sys <area> plan|start ...`, scripts/*-change.sh) tells the web interface what went wrong in two ways: a
`reason` line with English text, and the exit number. Neither is good for a program to act on:

- **Exit numbers are not ours.** The shell and the tools already use them: 124 is a timeout (`timeout`), 126 and 127 are "cannot run" and
  "not found", 128+n is a signal (130, 137, 143), 141 is a broken pipe (SIGPIPE). Any command a script calls can return one of them, and there
  are only 256 with no names.
- **They have already misled us.** The web server turned a `subprocess.TimeoutExpired` into exit 127 with no output, so a slow `docker compose
  up -d` showed "The server could not do this (exit 127)", which reads as "command not found" (#899, fixed: a timeout is 124 now and says so).
- **The web interface matches on English text.** PlanDialog looks for "changed meanwhile" in the reason to offer a reload. A reworded sentence
  breaks a button without any test noticing.
- **The same problem has many sentences.** About 600 `refuse` calls in the change scripts write their own text for things such as "the vault is
  closed", "Docker is not on", "no such app". The interface cannot offer the same fix button for all of them.

ADR 0025 already decided that web-visible sentences get a dotted `code` beside the English text (`disk.full`) when the web needs them, for
translation. This record uses that vocabulary for errors and decides where the codes live and who may emit them.

## Decision

1. **A `code` line beside `reason`.** A plan or start that refuses or fails may print `code<TAB><name>` next to `status` and `reason`. Parsers
   ignore unknown keys (web-serve.py `parse_change`), so this adds to the contract and changes no existing line (ADR 0006 rule 4). The English
   `reason` stays, required, and is what the terminal shows; the code is for programs.
2. **Names, not numbers.** A code is `<area>.<what>` in lower case with `-`, the same shape as ADR 0025 (`vault.locked`, `docker.off`,
   `app.unknown`, `run.timeout`). A code never changes meaning; a rename keeps the old name as an alias for one release.
3. **Exit numbers stay three meanings.** 0 = ok or done, 1 = refused (a `status` line says why), anything else = the run broke. No script picks
   a new exit number to carry meaning.
4. **One catalogue.** `scripts/lib/error-codes.tsv`: `code<TAB>layer<TAB>meaning<TAB>text<TAB>fix` (`-` for none). `layer` is `run` or
   `script`. `text` is the default English sentence, `fix` an `hs` command or a page path, or `-`. A table in docs/errors.md is generated from it
   (`scripts/errors-doc-gen.py write`, like docs/events.md from event-kinds.tsv). A test fails when a script prints a code that is not in the
   catalogue, or when the docs table is stale.
5. **Two layers.**
   - **run**: set by the web server when the script gave no status line: `run.timeout` (the time limit passed), `run.not-found` (the command
     could not be started), `run.killed` (ended by a signal), `run.no-status` (ended without a status line). The web server adds `code` to the
     answer; the reason text comes from the catalogue.
   - **script**: set by a change script through one helper in scripts/lib/ui.sh, `refuse_code <code> [<reason>]`, which prints `status`,
     `reason` (the given text, else the catalogue text) and `code`. A plain `refuse "<text>"` stays allowed and means code `refused`.
6. **The web interface acts on the code, never on the text.** PlanDialog takes the fix button, a "run as job" or a "reload" offer from the
   code; for a code it does not know it shows the reason as today. The "changed meanwhile" text match goes when its code exists.
7. **Convert by use.** No sweep of all `refuse` calls. First the run layer, then the refusals the web interface acts on or shows most often
   (vault closed, Docker off, app unknown, name not valid, changed meanwhile, busy). A new refusal the web needs to act on gets a code.

## Consequences

- One place answers "what can go wrong and what does the user do about it", and the docs page follows from it.
- Codes are an API contract: a rename needs the alias step, and the catalogue test keeps scripts and docs in step.
- Reasons stay English text for the terminal and for codes the web does not know, so an old web interface and a new script still work together.
- Translation (ADR 0025) can key the web text on the same code later; this record does not decide the translation.
- Jobs: a failed background job's `job.failed` event and job record can carry the same code later (ADR 0005, ADR 0018); not part of this step.

## Not decided here

- Codes for `reads` (they answer 502 with an `error` text today); same catalogue, later.
- Codes in `hs` terminal output (never shown; the terminal keeps the English sentence).
