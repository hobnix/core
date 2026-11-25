#!/usr/bin/env python3
"""Writes `[meta] changes` of one package.toml from the titles of the merged pull requests that touched it (prepare-release.sh, hobnix/core#1248).

    python3 -I release-changes.py <package.toml> < pulls.jsonl

stdin: one JSON object per line, {"number": 12, "title": "..."} (the same pull request may come several times: a PR touches several commits).
Pull request titles are written by contributors, so they are untrusted text: control, format and line-separator characters (newline, U+2028,
U+0085, ESC ...) become a space, markdown and `@` are dropped (the release pull request must not ping anybody or render links), every title is
cut at TITLE_MAX, at most MAX_TITLES are listed, the whole text stays within TOTAL_MAX. The value is one single-line TOML basic string; the result
is parsed again and must differ from the old file in `[meta] changes` only, or the file is left as it was. No title, nothing written (exit 0).
Titles never travel in argv or the environment. Exit 0 = ok (stdout: "written" or "kept"), 1 = refused."""
import json
import re
import sys
import tomllib
import unicodedata

TITLE_MAX = 100
MAX_TITLES = 15
TOTAL_MAX = 1000
DROP = re.compile(r"[@`*\[\]<>#|~\\{}]")
SKIP = re.compile(r"^prepare release\b", re.I)


def clean(title):
    out = "".join(" " if unicodedata.category(c)[0] in "CZ" or c.isspace() else c for c in title)
    out = DROP.sub("", out)
    out = re.sub(r" +", " ", out).strip(" -+!>")
    if len(out) > TITLE_MAX:
        out = out[:TITLE_MAX - 3].rstrip() + "..."
    return out


def text_of(lines):
    seen, titles = set(), []
    for line in lines[:100000]:
        try:
            o = json.loads(line)
        except ValueError:
            continue
        n, t = (o.get("number"), o.get("title")) if isinstance(o, dict) else (None, None)
        if isinstance(n, bool) or not isinstance(n, int) or not isinstance(t, str) or n in seen:
            continue
        seen.add(n)
        c = clean(t[:2000])
        if c and not SKIP.match(c):
            titles.append((n, c))
    titles.sort()
    shown, total = [], 0
    for _, c in titles[:MAX_TITLES]:
        if total + len(c) + 2 > TOTAL_MAX - 20:
            break
        shown.append(c)
        total += len(c) + 2
    rest = len(titles) - len(shown)
    return "; ".join(shown) + (f"; and {rest} more" if rest else "") if shown else ""


def put(src, value):
    """src with `[meta] changes = <value>` set; a multi-line old value is replaced whole."""
    line = "changes = " + json.dumps(value, ensure_ascii=False)
    rows = src.split("\n")
    meta = next((i for i, r in enumerate(rows) if re.fullmatch(r"\[meta\][ \t]*(#.*)?", r)), None)
    if meta is None:
        return src.rstrip("\n") + "\n\n[meta]\n" + line + "\n"
    end = next((i for i in range(meta + 1, len(rows)) if rows[i].startswith("[")), len(rows))
    i = next((i for i in range(meta + 1, end) if re.match(r"changes[ \t]*=", rows[i])), None)
    if i is None:
        rows.insert(meta + 1, line)
    else:
        j = i + 1
        for q in ('"""', "'''"):
            if re.match(r"changes[ \t]*=[ \t]*" + q, rows[i]) and rows[i].count(q) < 2:
                while j < len(rows) and q not in rows[j]:
                    j += 1
                j += 1
        rows[i:j] = [line]
    return "\n".join(rows)


def main(argv):
    if len(argv) != 2:
        print("usage: release-changes.py <package.toml> < pulls.jsonl", file=sys.stderr)
        return 1
    value = text_of(sys.stdin.read().split("\n"))
    if not value:
        print("kept")
        return 0
    with open(argv[1], encoding="utf-8", newline="") as f:
        old = f.read()
    try:
        before = tomllib.loads(old)
        new = put(old, value)
        after = tomllib.loads(new)
    except (tomllib.TOMLDecodeError, UnicodeError) as e:
        print(f"{argv[1]}: {e}", file=sys.stderr)
        return 1
    want = json.loads(json.dumps(before))
    want.setdefault("meta", {})["changes"] = value
    if json.loads(json.dumps(after)) != want:
        print(f"{argv[1]}: the new text would change more than [meta] changes: left as it was", file=sys.stderr)
        return 1
    if new != old:
        with open(argv[1], "w", encoding="utf-8", newline="") as f:
            f.write(new)
    print("written")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
