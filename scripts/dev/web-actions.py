#!/usr/bin/env python3
"""Action-row ratchet (#457, docs/PLAN-navigation.md step 6): no action row with more than three visible buttons.

  web-actions.py [--root DIR] [--baseline FILE] [--update] [--files]

An action row is a `{#snippet actions()}` block (PageHeader, Section, ...) or an element whose class is `actions`, `acts` or ends in
`-actions`. Visible buttons are the `<Button` tags in the row; a `<Menu` inside it is not counted. A file's number is its largest row.
--files prints `file<TAB>buttons` for the files over the limit; the baseline (tests/web-actions.tsv) holds exactly those.
Exit 1 if a file is over three and not in the baseline, rose above its baseline, or fell without the baseline being lowered.
--update rewrites the baseline from the tree (use it only to lower numbers).
"""
import argparse
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
LIMIT = 3
VOID = ("input", "br", "img", "hr")
TAG = re.compile(
    r"""<(/?)([a-zA-Z][\w.-]*)((?:"[^"]*"|'[^']*'|\{(?:[^{}]|\{[^{}]*\})*\}|[^>"'{])*)>"""
    r"""|\{(#snippet\s+\w+|/snippet)[^}]*\}""",
    re.S,
)
ROWCLASS = re.compile(r'class\s*=\s*"([^"]*)"')


def is_row_class(attrs):
    m = ROWCLASS.search(attrs)
    return bool(m) and any(t in ("actions", "acts") or t.endswith("-actions") for t in m.group(1).split())


def rows(text):
    """Yield the number of visible Button tags of each action row in text."""
    text = re.sub(r"<!--.*?-->", "", text, flags=re.S)
    for tag in ("script", "style"):
        text = re.sub(r"<%s\b.*?</%s>" % (tag, tag), "", text, flags=re.S)
    stack = []      # ("snip", row|None) / ("el", name, row|None) / ("menu", "Menu", None)
    live = []       # rows that are open
    for m in TAG.finditer(text):
        if m.group(4):
            if m.group(4) == "/snippet":
                while stack and stack[-1][0] != "snip":
                    stack.pop()
                if stack:
                    row = stack.pop()[1]
                    if row is not None:
                        live.remove(row)
                        yield row["n"]
            else:
                row = {"n": 0} if re.fullmatch(r"#snippet\s+actions", m.group(4)) else None
                if row is not None:
                    live.append(row)
                stack.append(("snip", row))
            continue
        closing, name, attrs = m.group(1) == "/", m.group(2), m.group(3)
        if closing:
            for i in range(len(stack) - 1, -1, -1):
                if stack[i][0] != "snip" and stack[i][1] == name:
                    for s in stack[i:]:
                        if s[0] == "snip":
                            continue
                        if s[2] is not None:
                            live.remove(s[2])
                            yield s[2]["n"]
                    del stack[i:]
                    break
            continue
        if name == "Button":
            if live and not any(s[0] == "menu" for s in stack):
                live[-1]["n"] += 1
            continue
        if name in VOID or attrs.rstrip().endswith("/"):
            continue
        row = {"n": 0} if is_row_class(attrs) else None
        if row is not None:
            live.append(row)
        stack.append(("menu" if name == "Menu" else "el", name, row))
    for row in live:
        yield row["n"]


def current(root):
    root = Path(root)
    out = {}
    for p in sorted(root.rglob("*.svelte")):
        n = max(rows(p.read_text(encoding="utf-8", errors="replace")), default=0)
        if n > LIMIT:
            out[p.relative_to(root).as_posix()] = n
    return out


def render(d):
    return "file\tbuttons\n" + "".join("%s\t%d\n" % (f, d[f]) for f in sorted(d))


def parse(text):
    d = {}
    for line in text.splitlines()[1:]:
        if line.strip():
            f, n = line.split("\t")
            d[f] = int(n)
    return d


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", default=str(REPO / "web" / "src"))
    ap.add_argument("--baseline", default=str(REPO / "tests" / "web-actions.tsv"))
    ap.add_argument("--update", action="store_true")
    ap.add_argument("--files", action="store_true")
    a = ap.parse_args()
    new = current(a.root)
    if a.files:
        sys.stdout.write(render(new))
        return 0
    base = Path(a.baseline)
    if a.update:
        base.write_text(render(new), encoding="utf-8", newline="\n")
        print("wrote %s" % base)
        return 0
    old = parse(base.read_text(encoding="utf-8")) if base.is_file() else {}
    bad = 0
    for f in sorted(set(old) | set(new)):
        n, b = new.get(f, 0), old.get(f, LIMIT)
        if n > b:
            print("web/src/%s: %d visible buttons in an action row > %d: keep at most %d visible, put the rest in a Menu" % (f, n, b, LIMIT))
            bad += 1
        elif n < b and f in old:
            print("web/src/%s: %d < %d: lower the number in tests/web-actions.tsv (python3 scripts/dev/web-actions.py --update)" % (f, n or LIMIT, b))
            bad += 1
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
