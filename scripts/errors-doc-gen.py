#!/usr/bin/env python3
"""docs/errors.md, generated from scripts/lib/error-codes.tsv (ADR 0028), so the page cannot drift from the catalogue.

  errors-doc-gen.py write    rewrite the table between the BEGIN/END markers in docs/errors.md
  errors-doc-gen.py check    change nothing: exit 1 when the table is stale (tests/error-codes.sh)
  errors-doc-gen.py codes    print the codes of the catalogue, one per line

The text between the markers is generated: never edit it by hand. Python stdlib only.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TSV = os.path.join(ROOT, "scripts", "lib", "error-codes.tsv")
DOC = os.path.join(ROOT, "docs", "errors.md")
BEGIN = "<!-- BEGIN generated from scripts/lib/error-codes.tsv (python3 scripts/errors-doc-gen.py write) -->"
END = "<!-- END generated -->"
CODE_RE = re.compile(r"^[a-z][a-z0-9-]*(\.[a-z][a-z0-9-]*)?$")


def rows(path):
    out = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            c = line.split("\t")
            if len(c) != 5:
                raise SystemExit("error: %s: need 5 tab-separated columns: %s" % (path, line))
            if not CODE_RE.match(c[0]) or c[1] not in ("run", "script") or "" in c:
                raise SystemExit("error: %s: bad code, layer or empty field: %s" % (path, line))
            out.append(c)
    return out


def anchor(code):
    """The heading id of a code in docs/errors.md: lower case, the dot dropped (plan.changed -> planchanged), as a docs site makes it from the heading. The web links to it (web/src/ui/errornote.js)."""
    return code.replace(".", "")


def table(path):
    """One short section per code, so the web can link to errors#<anchor>."""
    out = []
    for code, layer, meaning, text, fix in rows(path):
        out.append("### %s\n\n%s.\n\n- Layer: %s\n- Text: %s\n- Fix: %s\n" % (
            code, meaning.rstrip("."), layer, text, "none" if fix == "-" else "`%s`" % fix))
    return "\n".join(out).rstrip("\n")


def main(argv):
    cmd = argv[1] if len(argv) > 1 else ""
    if cmd not in ("write", "check", "codes"):
        print(__doc__)
        return 2
    tsv = argv[argv.index("--tsv") + 1] if "--tsv" in argv else TSV
    if cmd == "codes":
        print("\n".join(r[0] for r in rows(tsv)))
        return 0
    with open(DOC, encoding="utf-8", newline="") as f:
        have = f.read()
    a = have.find(BEGIN)
    b = have.find(END, a) if a >= 0 else -1
    if a < 0 or b < 0:
        raise SystemExit("error: docs/errors.md has no BEGIN/END markers")
    want = have[:a] + BEGIN + "\n\n" + table(tsv) + "\n\n" + have[b:]
    if cmd == "write":
        with open(DOC, "w", encoding="utf-8", newline="\n") as f:
            f.write(want)
        return 0
    if have != want:
        print("docs/errors.md is stale: run python3 scripts/errors-doc-gen.py write", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
