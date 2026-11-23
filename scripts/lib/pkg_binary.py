"""The compiled program of a package: `[[binary]]` in package.toml (hobnix/core#1138, owner decision in #1129). Python stdlib only, no CLI.

  [[binary]]
  path   = "bin/media-svc"                 a regular file inside the package folder: relative, no "..", no symlink
  sha256 = "<64 hex>"                      the hash of that file; checked by validate and repo-check, and again on the installed copy
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

TARGETS = ("x86_64-unknown-linux-musl",)
HOST_ARCHS = ("x86_64", "amd64")
KEYS = {"path", "sha256", "bin", "target"}
SHA = re.compile(r"^[0-9a-f]{64}$")
BIN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")
PATH = re.compile(r"^[A-Za-z0-9._/-]+$")


def host_arch():
    return os.environ.get("HS_UNAME_M") or platform.machine()


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
    return bool(PATH.match(p)) and not p.startswith("/") and not any(x in ("", ".", "..") for x in parts)


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
    """The set of words commands.tsv rows (column 3) and [service] exec of this package use to name a program."""
    out = set()
    sv = m.get("service")
    if isinstance(sv, dict) and isinstance(sv.get("exec"), str):
        out.add(sv["exec"])
    try:
        with open(os.path.join(folder, "commands.tsv"), encoding="utf-8") as f:
            for line in f.read().splitlines():
                c = line.split("\t")
                if not line.startswith("#") and len(c) >= 3:
                    out.add(c[2].strip())
    except OSError:
        pass
    return out


def problems(m, folder=None):
    """[(code, text)]. `folder` None = a draft that is not on disk: only the shape is checked."""
    if "binary" not in m:
        return []
    b = m["binary"]
    if not isinstance(b, list) or not b or not all(isinstance(t, dict) for t in b):
        return [("binary.shape", "binary must be a list of tables: [[binary]] with path, sha256, bin and target")]
    out, paths, names = [], set(), set()
    refs = referenced(folder, m) if folder else None
    for i, t in tables(m):
        w = "[[binary]] %d" % i
        for k in sorted(set(t) - KEYS):
            out.append(("binary.shape", "%s: unknown key %s (allowed: path, sha256, bin, target)" % (w, k)))
        for k in ("path", "sha256", "target"):
            if not isinstance(t.get(k), str) or not t.get(k):
                out.append(("binary.shape", "%s: %s is missing (a text)" % (w, k)))
        p = t.get("path") if isinstance(t.get("path"), str) else ""
        name = t.get("bin", os.path.basename(p))
        if not isinstance(name, str) or not BIN.match(name):
            out.append(("binary.shape", "%s: bin %r is not a program name (letters, digits, . _ -)" % (w, name)))
            name = ""
        if isinstance(t.get("sha256"), str) and t["sha256"] and not SHA.match(t["sha256"]):
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
        bad = _inside(folder, p)
        if bad:
            out.append((bad[0], "%s: %s" % (w, bad[1])))
            continue
        if "@/" + p not in refs:
            out.append(("binary.unreferenced", "%s: no row of commands.tsv and no [service] exec refers to @/%s" % (w, p)))
        want = t.get("sha256")
        if isinstance(want, str) and SHA.match(want) and sha256_of(os.path.join(folder, p)) != want:
            out.append(("binary.hash", "%s: the sha256 of %s is not the one in package.toml" % (w, p)))
    return out


def manifest_problems(m, folder=None):
    return ["%s: %s" % c for c in problems(m, folder)]


def install_problems(m, folder):
    """[(code, text)] for the staged copy of an install or update: the server architecture first, then shape, path and hash of every program,
    then the executable bit. Empty for a package without [[binary]]."""
    if "binary" not in m:
        return []
    arch = host_arch()
    if arch not in HOST_ARCHS:
        return [("binary.arch", "this package ships a compiled program for x86_64 and this server is %s; it was not installed" % arch)]
    out = problems(m, folder)
    if out:
        return out
    for i, t in tables(m):
        if not os.stat(os.path.join(folder, t["path"])).st_mode & stat.S_IXUSR:
            out.append(("binary.exec", "[[binary]] %d: %s is not executable" % (i, t["path"])))
    return out
