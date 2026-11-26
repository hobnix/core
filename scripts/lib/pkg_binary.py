"""The compiled program of a package: `[[binary]]` in package.toml (hobnix/core#1138, owner decision in #1129). Python stdlib only, no CLI.

  [[binary]]
  path   = "bin/media-svc"                 a regular file inside the package folder: relative, no "..", no symlink
  sha256 = "<64 hex>"                      the hash of that file; checked by validate and repo-check, and again on the installed copy.
                                           Empty with no file = "not built yet" (hobnix/extensions: feature branches and develop; the release
                                           preparation builds the program and writes the hash). That state passes validate and repo-check, but
                                           repo-check --release and install and update refuse it (binary.unbuilt)
  bin    = "media-svc"                     the name of the program (default: the file name of path)
  target = "x86_64-unknown-linux-musl"     the only target there is for now

A commands.tsv row (column 3) or `[service] exec` refers to the program as `@/<path>`; a table nothing refers to is an error. Unknown keys are
refused. The server must be x86_64 (HS_UNAME_M overrides the machine name for tests) or install and update refuse the package, instead of a
service that fails to start.

Every problem is (code, text); the codes are in scripts/lib/error-codes.tsv. manifest_problems() -> ["code: text"], the shape of the other
checks. install_problems(m, folder) is what hs pkg install and update run on the staged copy before it replaces the old one.
"""
import hashlib
import os
import platform
import re
import stat
import tomllib

# the SDK crates (docs/PLAN-package-sdk.md); hobnix-ext-sdk is the deprecated re-export of 0.14
SDK = ("hobnix-pkg", "hobnix-pkg-command", "hobnix-pkg-service", "hobnix-ext-sdk")
SDK_URLS = ("https://github.com/hobnix/core", "https://github.com/hobnix/core.git")
SDK_TAG = re.compile(r"v[0-9]+\.[0-9]+\.[0-9]+(-(beta|rc)\.[0-9]+)?")
TARGETS = ("x86_64-unknown-linux-musl",)
HOST_ARCHS = ("x86_64", "amd64")
KEYS = {"path", "sha256", "bin", "target"}
SHA = re.compile(r"[0-9a-f]{64}")             # all three are used with fullmatch: "$" would let a trailing newline through
BIN = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}")
PATH = re.compile(r"[A-Za-z0-9._/-]+")
# the marker in front of the commands.tsv rows that the SDK's command macro builds into a program (TABLE_START, rust/hobnix-pkg-command/src/table.rs)
TABLE_START = b"\0hobnix-commands-tsv-1\0"
MAGIC = (b"\x7fELF", b"MZ", b"\xfe\xed\xfa\xce", b"\xfe\xed\xfa\xcf", b"\xce\xfa\xed\xfe", b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe")


def host_arch():
    """`uname -m`. HS_UNAME_M replaces it only when HS_TESTING=1 is set too (tests/pkg-binary.sh): the installer's plain environment cannot."""
    if os.environ.get("HS_TESTING") == "1" and os.environ.get("HS_UNAME_M"):
        return os.environ["HS_UNAME_M"]
    return platform.machine()


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def tables(m):
    """[(number, dict)] of the [[binary]] tables; a non-list or a non-table is skipped (problems() reports it)."""
    b = m.get("binary", [])
    return [(i, t) for i, t in enumerate(b, 1) if isinstance(t, dict)] if isinstance(b, list) else []


def path_ok(p):
    parts = p.split("/") if isinstance(p, str) else [""]
    return bool(PATH.fullmatch(p)) and not p.startswith("/") and not any(x in ("", ".", "..") for x in parts)


def _inside(folder, p):
    """None when folder/p is a regular file with no symlink on the way, else (code, text)."""
    cur = folder
    for part in p.split("/"):
        cur = os.path.join(cur, part)
        try:
            st = os.lstat(cur)
        except OSError:
            return ("binary.missing", "path %s: there is no such file in the package" % p)
        if stat.S_ISLNK(st.st_mode):
            return ("binary.path", "path %s goes through a symbolic link (%s)" % (p, part))
    if not stat.S_ISREG(st.st_mode):
        return ("binary.path", "path %s is not a regular file" % p)
    return None


def referenced(folder, m):
    """[(word, how)] for what commands.tsv rows (column 3) and [service] exec of this package name: how is "exec" (a service), "proto" (a row
    with the flag proto: ext_proto.py runs the program itself) or "bash" (any other row: hs.sh starts it as `bash <file>`)."""
    out = []
    sv = m.get("service")
    if isinstance(sv, dict) and isinstance(sv.get("exec"), str):
        out.append((sv["exec"], "exec"))
    try:
        with open(os.path.join(folder, "commands.tsv"), encoding="utf-8") as f:
            for line in f.read().splitlines():
                c = line.split("	")
                if not line.startswith("#") and len(c) >= 3:
                    flags = [x.strip() for x in c[6].split(",")] if len(c) >= 7 else []
                    out.append((c[2].strip(), "proto" if "proto" in flags else "bash"))
    except OSError:
        pass
    return out


def undeclared(folder, refs, declared):
    """[(code, text)] for a program that runs unhashed: a file started through @/<file> that is not a [[binary]] and is a compiled program
    (ELF, PE, Mach-O magic), or, as a service exec that is no .py or .sh file, does not start with #! (a script)."""
    out = []
    for word, how in refs:
        if not word.startswith("@/") or word[2:] in declared or not path_ok(word[2:]):
            continue
        path = os.path.join(folder, word[2:])
        if os.path.islink(path) or not os.path.isfile(path):
            continue
        try:
            with open(path, "rb") as f:
                head = f.read(4)
        except OSError:
            continue
        if any(head.startswith(x) for x in MAGIC) or (how == "exec" and not word.endswith((".py", ".sh")) and not head.startswith(b"#!")):
            out.append(("binary.undeclared", "%s is a program, not a script, and no [[binary]] declares it (it would run without its sha256 checked)" % word))
    return out


def problems(m, folder=None, built=False):
    """[(code, text)]. `folder` None = a draft that is not on disk: only the shape is checked. `built` = the program must be there and match
    (install, update, repo-check --release); else an empty sha256 with no file is allowed ("not built yet")."""
    refs = referenced(folder, m) if folder else []
    if "binary" not in m:
        return undeclared(folder, refs, set()) if folder else []
    b = m["binary"]
    if not isinstance(b, list) or not b or not all(isinstance(t, dict) for t in b):
        return [("binary.shape", "binary must be a list of tables: [[binary]] with path, sha256, bin and target")]
    out, paths, names = [], set(), set()
    for i, t in tables(m):
        w = "[[binary]] %d" % i
        for k in sorted(set(t) - KEYS):
            out.append(("binary.shape", "%s: unknown key %s (allowed: path, sha256, bin, target)" % (w, k)))
        for k in ("path", "sha256", "target"):
            if not isinstance(t.get(k), str) or (k != "sha256" and not t.get(k)):
                out.append(("binary.shape", "%s: %s is missing (a text%s)" % (w, k, "; empty until it is built" if k == "sha256" else "")))
        p = t.get("path") if isinstance(t.get("path"), str) else ""
        name = t.get("bin", os.path.basename(p))
        if not isinstance(name, str) or not BIN.fullmatch(name):
            out.append(("binary.shape", "%s: bin %r is not a program name (letters, digits, . _ -)" % (w, name)))
            name = ""
        if isinstance(t.get("sha256"), str) and t["sha256"] and not SHA.fullmatch(t["sha256"]):
            out.append(("binary.shape", "%s: sha256 must be 64 lower case hex digits" % w))
        if isinstance(t.get("target"), str) and t["target"] and t["target"] not in TARGETS:
            out.append(("binary.target", "%s: target %r is not supported (only %s)" % (w, t["target"], ", ".join(TARGETS))))
        if name and name in names:
            out.append(("binary.duplicate", "%s: bin %s is listed twice" % (w, name)))
        names.add(name)
        if not p:
            continue
        if not path_ok(p):
            out.append(("binary.path", "%s: path %r must be a relative file name inside the package (no .., no leading /, no . part)" % (w, p)))
            continue
        if p in paths:
            out.append(("binary.duplicate", "%s: path %s is listed twice" % (w, p)))
        paths.add(p)
        if not folder:
            continue
        hows = [h for word, h in refs if word == "@/" + p]
        if not hows:
            out.append(("binary.unreferenced", "%s: no row of commands.tsv and no [service] exec refers to @/%s" % (w, p)))
        elif "bash" in hows:
            out.append(("binary.runner", "%s: a row of commands.tsv without the flag proto starts @/%s with bash; give the row the flag proto or use [service] exec" % (w, p)))
        want = t.get("sha256") if isinstance(t.get("sha256"), str) else None
        bad = _inside(folder, p)
        if want == "":
            if bad and bad[0] == "binary.missing":
                if built:
                    out.append(("binary.unbuilt", "%s: %s is not built yet (no file, empty sha256)" % (w, p)))
            elif bad:
                out.append((bad[0], "%s: %s" % (w, bad[1])))
            else:
                out.append(("binary.hash", "%s: %s is there but sha256 is empty" % (w, p)))
        elif bad:
            out.append((bad[0], "%s: %s" % (w, bad[1])))
        elif want and SHA.fullmatch(want) and sha256_of(os.path.join(folder, p)) != want:
            out.append(("binary.hash", "%s: the sha256 of %s is not the one in package.toml" % (w, p)))
        if not bad:
            out += drift(folder, p, w)
    return out + (undeclared(folder, refs, paths) if folder else [])


def built_rows(path):
    """The commands.tsv rows that the SDK's command macro built into the program at `path` (between TABLE_START and a NUL byte), or None
    for a program without them (rows written by hand)."""
    try:
        with open(path, "rb") as f:
            data = f.read()
    except OSError:
        return None
    start = data.find(TABLE_START)
    end = data.find(b"\0", start + len(TABLE_START)) if start >= 0 else -1
    if end < 0:
        return None
    try:
        return data[start + len(TABLE_START):end].decode("utf-8").splitlines()
    except UnicodeDecodeError:
        return None


def drift(folder, p, w):
    """[(code, text)]: the rows of commands.tsv that start @/<p> differ from the rows built into the program (#1263). The program is read,
    never run. No rows built in: nothing to compare."""
    built = built_rows(os.path.join(folder, p))
    if built is None:
        return []
    try:
        with open(os.path.join(folder, "commands.tsv"), encoding="utf-8") as f:
            lines = f.read().splitlines()
    except OSError:
        lines = []
    rows = [l for l in lines if not l.startswith("#") and l.split("\t")[2:3] == ["@/" + p]]
    if rows == built:
        return []
    pairs = [(a, b) for a, b in zip(rows + ["-"] * len(built), built + ["-"] * len(rows)) if a != b]
    have, want = pairs[0] if pairs else ("-", "-")
    return [("binary.drift", "%s: the rows of commands.tsv for @/%s differ from the ones built into the program (the command macro of the SDK): "
             "commands.tsv has %r, the program %r; write the rows of Commands::tsv() into commands.tsv" % (w, p, have, want))]


def manifest_problems(m, folder=None, built=False):
    return ["%s: %s" % c for c in problems(m, folder, built)]


def _dependency_tables(doc):
    """Every table of a Cargo.toml that may name a dependency, as (label, table)."""
    kinds = ("dependencies", "dev-dependencies", "build-dependencies")
    out = [(k, doc.get(k)) for k in kinds]
    out.append(("workspace.dependencies", (doc.get("workspace") or {}).get("dependencies")))
    for cfg, t in (doc.get("target") or {}).items():
        out += [("target.%s.%s" % (cfg, k), t.get(k)) for k in kinds if isinstance(t, dict)]
    for src, t in (doc.get("patch") or {}).items():
        out.append(("patch.%s" % src, t))
    return [(label, t) for label, t in out if isinstance(t, dict)]


def sdk_pin_problems(folder):
    """[(code, text)] of a release (ADR 0031): the crate in the package folder takes the SDK from the core by a release tag. A rev, a
    branch, a path, another source or a [patch] is for develop only. No Cargo.toml = nothing to check. No network: whether the tag exists is
    cargo's to find out when the release preparation builds with --locked."""
    path = os.path.join(folder, "Cargo.toml")
    if not os.path.isfile(path):
        return []
    try:
        with open(path, "rb") as f:
            doc = tomllib.load(f)
    except (OSError, tomllib.TOMLDecodeError):
        return [("binary.sdk-pin", "Cargo.toml cannot be read")]
    out = []
    for label, table in _dependency_tables(doc):
        for key, dep in table.items():
            name = dep.get("package", key) if isinstance(dep, dict) else key
            if name not in SDK or (isinstance(dep, dict) and dep.get("workspace") is True):
                continue
            ok = (not label.startswith("patch.") and isinstance(dep, dict) and str(dep.get("git", "")) in SDK_URLS
                  and SDK_TAG.fullmatch(str(dep.get("tag", ""))) and not {"rev", "branch", "path"} & set(dep))
            if not ok:
                out.append(("binary.sdk-pin", "Cargo.toml [%s]: a release takes %s from %s by tag = \"vX.Y.Z\" (a core release tag, or a beta tag vX.Y.Z-beta.N; a rev, "
                            "branch, path or patch is for develop only)" % (label, name, SDK_URLS[0])))
    return out


def install_problems(m, folder):
    """[(code, text)] for the staged copy of an install or update: the server architecture first, then shape, path and hash of every program,
    then the executable bit. A package without [[binary]] still gets the `undeclared` check: no program runs unhashed."""
    arch = host_arch()
    if "binary" in m and arch not in HOST_ARCHS:
        return [("binary.arch", "this package ships a compiled program for x86_64 and this server is %s; it was not installed" % arch)]
    out = problems(m, folder, True)
    if out:
        return out
    for i, t in tables(m):
        if not os.stat(os.path.join(folder, t["path"])).st_mode & stat.S_IXUSR:
            out.append(("binary.exec", "[[binary]] %d: %s is not executable" % (i, t["path"])))
    return out
