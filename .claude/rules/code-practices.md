---
paths:
  - "rust/**/*.rs"
  - "scripts/**/*.sh"
  - "packages/**/*"
  - "capabilities/**/*"
---

# Code practices

Loaded when you touch the files above (path-scoped rule). The full text is docs/CODE-PRACTICES.md; read it before you write new code in a language you have not touched this session.

- Readable first: names in full words from the domain (`failed_disks`, not `fd`), one thing per function (about 40 lines), one reason per module (about 400 lines), comments say why, never what.
- Rust: no `unwrap`/`expect`/panicking index outside tests, typed errors in libraries (`hobnix_core::Error`), `forbid(unsafe_code)`, no `println!` in library code, no new dependency without a reason in the pull request, a trait for the system so tests use a fake.
- Shell: `set -euo pipefail`, quoted expansions, output through `ui.sh`; a script over about 300 lines that parses structured data goes to Rust when touched (ADR 0001 checklist).
- No new Python program; fix bugs only (docs/PLAN-rust.md).
- Contracts (`hs sys` lines, package protocol, `registry.tsv`) never change for tidiness.
