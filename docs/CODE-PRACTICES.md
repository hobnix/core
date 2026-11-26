# Code practices

Contributor document, not a guide. It applies to the core, to `hobnix/official` (recipes, capabilities, extensions) and to every new package we write. Agents load it through `.claude/rules/code-practices.md`, so generated code follows the same rules as written code. Third-party packages are invited to follow it; nothing here is required of them except what `hs pkg validate` checks.

Why this exists: the code base is read far more often than it is written, by people and by agents. Code that is easy to read is easy to review, to change and to trust. Where a rule can be checked by a tool, the tool enforces it (CI); where it cannot, review does.

## Principles

1. **Readable first.** Choose the version a new contributor understands in one pass. A clever shortcut that saves three lines and costs a minute of thought is a loss.
2. **Names carry the meaning.** A name says what a thing is or does in the language of the domain (pool, disk, instance, share, job), not how it is stored. Prefer `failed_disks` over `fd`, `parse_job_record` over `process`. No abbreviations except the ones in the glossary of docs/GUIDE-TEMPLATE.md and the usual short names for loops (`i`, `n`) over a few lines.
3. **One thing per function, one reason per module.** If a function needs "and" in its description, split it. If a file mixes parsing, decisions and output, split it along those lines (ADR 0001 decision 3: service layer in `hobnix-core`, text in `hobnix-cli`).
4. **Comments explain why, not what.** The code says what. A comment gives the reason, the constraint or the incident behind a decision ("a failing `zpool status` must not hide the disk list, #123"). Delete a comment that repeats the code; fix the code if it needs a comment to be understood.
5. **Make wrong states hard to write.** Use types for what the compiler can check: an enum instead of a string with four allowed values, a `Secret` instead of a `String`, a `PoolName` where a bare string would let a disk name slip in.
6. **Fail loudly, early and with context.** An error says what was tried, on which object, and what the user can do. No silent fallbacks that hide a broken state.
7. **Small diffs, tested behaviour.** A change carries its test. A move to Rust carries the characterization test of ADR 0001.

## Rust

CI already runs `cargo fmt --check`, `cargo clippy --locked --all-targets -- -D warnings` and `cargo test --locked` (ci.yml). The lints below are **run**: the workspace sets them once in `rust/Cargo.toml` (`[workspace.lints]`) and every crate inherits them (`[lints] workspace = true`). Code that breaks a lint gets a targeted `#[allow]` with a reason, or is fixed. Tests may use `unwrap`, `expect` and `panic` (`rust/clippy.toml`; the files of `tests/` carry an `allow` of their own); the CLI crate and the SDK's `die` write to the terminal on purpose.

- **Format and lint:** `rustfmt` defaults; clippy at its default level plus `clippy::unwrap_used`, `clippy::expect_used`, `clippy::panic`, `clippy::todo`, `clippy::dbg_macro` and `clippy::print_stdout` / `print_stderr` as warnings that CI's `-D warnings` turns into errors. `unsafe_code = "forbid"` for every crate (workspace lint); an exception needs its own review and a `// SAFETY:` comment.
- **Errors:** a library crate returns a typed error (`hobnix_core::Error`: `Refused`, `Missing`, `Failed`; ADR 0001 "Errors and logs"). A binary maps it to the exit code and the one stderr line `hobnix: <message>`. No `unwrap`, `expect` or indexing that can panic outside tests; a `expect` is allowed only for a condition the code has just made true, with the reason in its message.
- **Names:** types `UpperCamelCase`, functions and variables `snake_case` in full words, constants `UPPER_SNAKE`. Boolean names read as a question (`is_encrypted`, `has_spare`). A function that returns a `Result` is named for what it does, not `try_`.
- **Size:** a function fits on one screen (about 40 lines); a file about 400 lines. Above that, split. Nested `match` or `if let` deeper than three levels is a sign to extract a function or return early.
- **Modules and visibility:** everything is private until another module needs it. A public item of a library crate has a doc comment with one sentence on what it is and, where it is not obvious, what it expects and what it returns on error.
- **Dependencies:** each one is a cost (Nix builds without network, a locked `Cargo.lock`, review time). A new crate needs a sentence in the pull request: what it replaces, how large it is, how it is maintained. `serde` and `serde_json` are accepted (ADR 0001 "Job store"); the rest of `hobnix-core` stays on `std` until a record says otherwise. A dependency with its own large tree needs the owner's decision.
- **Output and logs:** no `println!` in library code. The CLI writes only the contract lines. Diagnostics go through `hobnix_core::log` (single lines, syslog priority prefix). A secret never appears in a log, an error or a `Debug` print; use `Secret` (ADR 0001).
- **Time, files and the system** sit behind a small trait (`Host`, `System`) so tests use a fake. No test needs root for logic.
- **Tests:** unit tests next to the code for logic; `tests/*.sh` and the `t` runner for behaviour at the `hs` boundary. Test names state the behaviour (`refuses_removal_without_confirm_name`), not the function.
- **Public contracts** (`hs sys` lines, JSON Lines of the package protocol, `registry.tsv`) are never changed to make code nicer. Change the code behind them.

## Shell

Shell stays for glue (ADR 0001 "Stays"; docs/PLAN-rust.md for the list). Practices:

- **Checked by tools:** `bash -n` for every script (pre-commit routine) and `shellcheck -S error` in CI (changed files on a pull request, all files otherwise). Also run on the changed files of a pull request: `shellcheck` at warning level as a ratchet (`scripts/dev/shellcheck-ratchet.sh`, baseline `tests/shellcheck-ratchet.tsv`: a file may not have more findings than listed, a new file none; fewer findings: lower the number with `--update`), and `shfmt -d -i 2 -ci` for layout (reports only, not blocking yet). To adopt: make the `shfmt` step blocking once the flags are checked on a runner; the existing scripts are not reformatted in one go.
- `set -euo pipefail`, quoted expansions, `local` for function variables, `readonly` for constants, no backticks, no `eval`.
- **Names:** variables and functions in full lower-case words (`pool_name`, `list_disks`); environment variables the interface depends on keep their `HS_` names. One function does one thing; a function over about 40 lines is a candidate for a helper or for Rust.
- **Output** only through `scripts/lib/ui.sh`; machine-readable lines never change shape (CLAUDE.md, `.claude/rules/shell.md`).
- **Size limit:** a script over about 300 lines that parses structured data (JSON, `zfs` or `incus` output) or keeps state moves to Rust when it is next changed, if the ADR 0001 checklist allows it. A pipeline of other tools stays shell.
- **Secrets** only through `scripts/lib/secret.sh`, never argv or the environment.

## Python

Python is being retired (docs/PLAN-rust.md). Until a program is replaced: fix bugs, add no new Python program and no new feature to a Python program that ADR 0001 would move, keep the standard library only, add type hints to anything you touch.

## Packages (recipes, capabilities, extensions)

The same practices apply to `hobnix/official`:

- Prefer the package SDK (docs/PLAN-package-sdk.md) over hand-written protocol code, `commands.tsv` rows or manifest boilerplate.
- A recipe stays declarative where it can: the manifest says what; code appears only where logic is needed. A recipe ends with `docs_hint`.
- A package that is not Rust may be bash (small glue) or any language that speaks the protocol; it still follows naming, size, error and comment rules above.
- `hs pkg validate` and the package CI template are the enforced part; naming and readability are checked in review.

## Review checklist

A reviewer (human or the `reviewer` agent) asks, in this order:

1. Does it do what the spec says, and is the behaviour tested?
2. Could a contributor who has not seen it before follow it without asking? (names, size, comments)
3. Are errors specific, and is a wrong state impossible or refused?
4. Is a contract (line shape, protocol, registry) unchanged?
5. Is anything added that is not needed: a dependency, an option, a layer?

## Changing this document

A new rule is added when a review comment is written for the second time, and it names the tool that enforces it, or says that review does. A rule nobody checks is removed.
