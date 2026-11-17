#!/usr/bin/env python3
"""Dry check of the test-lab stages (hobnix/server#712): every `hs ...` command line of every stage is checked against the real repository,
without a VM. Wrong assumptions inside a command line used to show only in a 20 to 40 minute run.

What is checked (all static, nothing runs):
  - the words of `hs ...` are a row of scripts/lib/registry.tsv (the longest match, like find_row in scripts/lib/hs.sh);
  - every `--flag` is listed in the script's `# args:` header line or is a `case` pattern of the script (a `rust:` row: its fallback script);
  - a `long` row typed on the console carries --foreground (or --dry-run), else the dispatcher asks a question (long_guard in hs.sh);
  - a `hs sys ...` row typed by hand sets HS_CALLER, else the dispatcher asks "Run it anyway?" (sys_guard in hs.sh);
  - a command that asks a question (its script calls confirm/ask) carries an answer: --yes, --confirm, --foreground, --dry-run or HS_*_YES=1;
  - `--disks` takes /dev/disk/by-id names: a value that is a variable must come from a capture that reads /dev/disk/by-id, not from `readlink -f`;
  - nothing uses `sudo -n` (adminuser types the sudo password).
A command whose output is piped, redirected or captured has no terminal on its standard output, so the dispatcher does not ask: that is
exempt from the long and sys checks (the same test as `[ -t 1 ]` in hs.sh).

  python3 scripts/dev/nested_check.py [stage ...]     exit 0: nothing found, 1: problems (one per line), 2: usage
"""

import os
import re
import shlex
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

SEPARATORS = {";", ";;", "&&", "||", "|", "&", "(", ")", "|&"}
KEYWORDS = {"do", "then", "else", "elif", "if", "while", "until", "!", "time", "exec", "command", "{", "}"}
ANSWERS = {"--yes", "-y", "--confirm", "--foreground", "--dry-run", "-h", "--help"}
ASK_CALLS = re.compile(r"^\s*(?:if\s+|!\s+|\w+=\$\(\s*)?(confirm|confirm_name|ask|ask_secret|ask_choice|choose)\b", re.M)


# ---------------------------------------------------------------- the registry
def load_registry(root=ROOT):
    """[(kind, [words], script, flags)] from scripts/lib/registry.tsv."""
    rows = []
    with open(os.path.join(root, "scripts", "lib", "registry.tsv"), encoding="utf-8") as f:
        for line in f:
            if line.startswith("#") or not line.strip():
                continue
            c = line.rstrip("\n").split("\t")
            if len(c) < 6:
                continue
            rows.append((c[0], c[1].split(), c[2], c[6] if len(c) > 6 else ""))
    return rows


def find_row(rows, words):
    """The longest row whose words match the start of `words` (a <value> word matches anything), as find_row in scripts/lib/hs.sh."""
    best = None
    for kind, path, script, flags in rows:
        if len(path) > len(words) or (best and len(path) <= len(best[1])):
            continue
        if all(p.startswith("<") or p == words[i] for i, p in enumerate(path)):
            best = (kind, path, script, flags)
    return best


def doc_script(script, flags):
    if script.startswith("rust:"):
        m = re.search(r"fallback:([^,]+)", flags)
        return m.group(1) if m else None
    return script


_script_cache = {}


def script_info(root, script):
    """(text, flags the header names, set of case-pattern flags) of a script, cached."""
    key = (root, script)
    if key not in _script_cache:
        try:
            with open(os.path.join(root, "scripts", script), encoding="utf-8", errors="replace") as f:
                text = f.read()
        except OSError:
            _script_cache[key] = ("", set(), set())
            return _script_cache[key]
        m = re.search(r"^# args:(.*)$", text, re.M)
        header = set(re.findall(r"--[A-Za-z][\w-]*", m.group(1))) if m else set()
        patterns = set()
        for line in text.splitlines():
            s = line.strip()
            if s.startswith("#") or ")" not in s:
                continue
            head = s.split(")", 1)[0]
            patterns.update(re.findall(r"(?:^|[|\s(])(--[A-Za-z][\w-]*)(?=$|[|\s=)])", head))
        _script_cache[key] = (text, header, patterns)
    return _script_cache[key]


# ---------------------------------------------------------------- one command line
def hs_calls(text):
    """The `hs ...` calls of a shell line: [{'words': [...], 'env': [...], 'sudo_n': bool, 'tty_free': bool}]. Raises ValueError when
    the line cannot be split (an unbalanced quote)."""
    lex = shlex.shlex(text, posix=True, punctuation_chars=True)
    lex.whitespace_split = True
    toks = list(lex)
    calls, seg, captured = [], [], []   # captured: a stack, True for the inside of $( )

    def flush(sep):
        if not seg:
            return
        piped = sep in ("|", "|&")
        redirected = any(t in (">", ">>") and i > 0 and seg[i - 1] != "2" for i, t in enumerate(seg))
        free = piped or redirected or any(captured)
        words, env, i = [], [], 0
        while i < len(seg) and (seg[i] in KEYWORDS or re.match(r"^[A-Za-z_]\w*=", seg[i]) or seg[i] == "sudo"):
            if seg[i] == "sudo":   # sudo and its options
                i += 1
                while i < len(seg) and seg[i].startswith("-"):
                    i += 1
                continue
            if "=" in seg[i] and seg[i] not in KEYWORDS:
                env.append(seg[i])
            i += 1
        if i < len(seg) and seg[i] == "hs":
            for t in seg[i + 1:]:
                if t in (">", ">>", "<", ">&", "<<") or t.startswith(">") or t.startswith("<"):
                    break
                words.append(t)
            calls.append({"words": words, "env": env, "tty_free": free})

    for t in toks:
        if t in SEPARATORS:
            if t == "(":
                captured.append(bool(seg) and seg[-1].endswith("$"))
                seg.clear()
                continue
            if t == ")":
                flush(t)
                seg.clear()
                if captured:
                    captured.pop()
                continue
            flush(t)
            seg.clear()
        else:
            seg.append(t)
    flush(";")
    return calls


def check_call(root, rows, call, var_src, where):
    """The problems of one hs call."""
    out = []
    words = call["words"]
    row = find_row(rows, words)
    cmd = "hs " + " ".join(words)
    if not row:
        return ["%s: no registry row for `%s`" % (where, cmd)]
    kind, path, script, flags = row
    n = len(path)
    typed = words[n:]
    flagset = set(flags.split(","))
    fg_args = [t.split("=")[0] for t in typed if t.startswith("-")]
    ds = doc_script(script, flags)
    if ds:
        text, header, patterns = script_info(root, ds)
        known = header | patterns | {"-h", "--help"}
        for fl in fg_args:
            if fl == "--foreground" and "long" in flagset:
                continue   # the dispatcher takes it (long_guard)
            if fl.startswith("--") and fl not in known:
                out.append("%s: `%s`: %s is not a flag of %s (# args: names %s)" % (where, cmd, fl, ds, " ".join(sorted(header)) or "none"))
    else:
        text = ""
    answered = any(a in ANSWERS for a in fg_args) or any(re.match(r"^HS_\w*YES=1?$|^HS_\w*YES=", e) for e in call["env"])
    has_caller = any(e.startswith("HS_CALLER=") for e in call["env"])
    free = call["tty_free"]
    if "long" in flagset and not free and not answered:
        out.append("%s: `%s` is a long command: on the console it asks for a background job; add --foreground" % (where, cmd))
    if kind == "sys" and not free and not has_caller:
        out.append("%s: `%s` is a system command: typed by hand it asks \"Run it anyway?\"; set HS_CALLER=test" % (where, cmd))
    # asks a question: a changing user command of a script that calls confirm/ask, without an answer
    if kind == "user" and "changes" in flagset and "long" not in flagset and text and ASK_CALLS.search(text) and not answered and not has_caller:
        if "--yes" in (known if ds else set()) or "--confirm" in (known if ds else set()):
            out.append("%s: `%s` may ask a question on the terminal: add --yes (or --confirm <name>)" % (where, cmd))
    # --disks: by-id names
    for i, t in enumerate(typed):
        if t == "--disks" and i + 1 < len(typed):
            for part in typed[i + 1].split(","):
                m = re.fullmatch(r"@@(\w+)@@", part)
                if m:
                    src = var_src.get(m.group(1), "")
                    if "by-id" not in src or "readlink" in src:
                        out.append("%s: `%s`: --disks %s must be a /dev/disk/by-id name (the variable comes from `%s`)" % (where, cmd, part, src or "nowhere"))
                elif re.match(r"^/dev/(sd|vd|nvme|hd)", part):
                    out.append("%s: `%s`: --disks takes /dev/disk/by-id names, not %s" % (where, cmd, part))
    return out


# ---------------------------------------------------------------- the stages
def fill(text):
    """{var} placeholders become @@var@@ (one word, so the shell split keeps them together)."""
    return re.sub(r"\{(\w+)\}", r"@@\1@@", text)


def check_steps(steps, rows=None, root=ROOT, name="stage"):
    rows = rows if rows is not None else load_registry(root)
    out, var_src = [], {}
    for i, s in enumerate(steps, 1):
        kind = s.get("kind")
        if kind not in ("run", "run_var", "capture", "send", "send_var"):
            continue
        where = "%s step %d (%s)" % (name, i, s.get("what") or kind)
        text = s["text"]
        if re.search(r"\bsudo\s+(?:-\w*\s+)*-\w*n\w*\b|\bsudo\s+--non-interactive\b", text):
            out.append("%s: sudo -n: adminuser has to type the password for sudo" % where)
        try:
            calls = hs_calls(fill(text))
        except ValueError as e:
            out.append("%s: cannot split the command line (%s)" % (where, e))
            calls = []
        for c in calls:
            out += check_call(root, rows, c, var_src, where)
        if kind == "capture" and s.get("var"):
            var_src[s["var"]] = text
    return out


def scenarios():
    """(name, steps) of every stage, with the variants that change the steps (a pool disk set or not, an app or not)."""
    import nested_lib as n
    disks = {k: "<disk-%s>" % k for k in ("backup", "pool1", "pool2", "fast1", "fast2")}
    base = {"password": "<password>", "pubkey": "<pubkey>", "backup_pass": "<backup-password>", "hostname": "nested-test", "disks": disks}
    for stage in n.STAGES:
        yield stage, n.build_scenario(stage, dict(base))
        if stage in ("rollback", "upgrade"):
            yield stage + " (variant)", n.build_scenario(stage, dict(base, disks={}, app="demo-app", candidate="feature/x"))


def check_all(root=ROOT, only=None):
    rows = load_registry(root)
    out = []
    for name, steps in scenarios():
        if only and name.split()[0] not in only:
            continue
        out += check_steps(steps, rows, root, name)
    return out


def main(argv):
    import nested_lib as n
    only = set(argv)
    if only - set(n.STAGES):
        print("unknown stage: %s (stages: %s)" % (" ".join(sorted(only - set(n.STAGES))), " ".join(n.STAGES)), file=sys.stderr)
        return 2
    problems = check_all(ROOT, only)
    for p in problems:
        print(p)
    print("nested_check: %s" % ("%d problem(s)" % len(problems) if problems else "every stage command line fits the repository"))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
