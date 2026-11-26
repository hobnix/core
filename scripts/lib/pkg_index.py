#!/usr/bin/env python3
"""The package index (docs/PLAN-registry.md "The index", hobnix/core#1069). Python stdlib; Pillow only to resize assets.

One `index.json` per package repository, built from package.toml and assets/ by CI, signed by CI, read by servers.

  pkg_index.py tree <folder>                                       the tree hash of a package folder (sha256:<hex>)
  pkg_index.py build <repo checkout> --repo <id> --out <dir> [--serial N | --prev <index.json>] [--commit SHA] [--ttl-days 14]
                                                                   [--now <ISO>] [--skip-assets] [--history <git dir>]    write <dir>/index.json and <dir>/assets/
  pkg_index.py assemble <community checkout> --out <dir> [--pins-tip SHA] --official-index <file|url>
                                                                   hobnix/community: fetch every pinned commit of manifests/*.toml, check it against
                                                                   the manifest and policy.toml, write the pins commit (<dir>/pins.commit, pins.bundle,
                                                                   tree/ for `build`); `error<TAB>text` per problem, exit 1
  pkg_index.py diff <community checkout> [--base <checkout of the target branch>]
                                                                   what a pull request does, for a reviewer: per changed manifest the fields, version, permissions,
                                                                   command rows, web declaration, binary rows and a bounded text diff of the files; every pin is
                                                                   checked like `assemble` does (the base policy.toml is the rule); `error<TAB>text`, exit 1 when refused
  pkg_index.py pin <manifest> <commit>                             point a manifest at a commit: rewrites commit and tree, prints the tree hash
  pkg_index.py validate <index.json> [--now <ISO>]               the schema; exit 1 on a problem (an expired index is only a warning)
  pkg_index.py sign <index.json> --key-file <private key>          write <index.json>.sig (an SSH signature, namespace hobnix-index)
  pkg_index.py verify <index.json> --signers <allowed_signers> [--prev <index.json>] [--now <ISO>]
                                                                   signature, schema, serial not below --prev; prints signer, serial, expires

Decisions (the plan names no scheme, these follow what the core already uses for release tags):
  signature   SSH signature (`ssh-keygen -Y sign`) over the exact bytes of index.json, namespace "hobnix-index", detached in index.json.sig. The
              trust list is an allowed_signers file (config/trusted-keys/<repo>.allowed_signers) whose line for this key says namespaces="hobnix-index".
  tree hash   sha256 over a listing of the folder (see tree_hash): independent of git, so a server computes the same from an archive of the commit.
  assets      icon.*, background.*, screenshots/* in the package's assets/ folder; resized, written as WebP, named by the sha256 of the result.
  key         the private key is only ever a FILE the caller names (--key-file); it is never read from argv or the environment.
"""
import hashlib
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import tomllib
from datetime import datetime, timedelta, timezone

FORMAT = 1
NAMESPACE = "hobnix-index"
KINDS = ("recipe", "extension", "capability", "blueprint")
NAME = re.compile(r"^[a-z][a-z0-9-]{0,40}$")
REPO = re.compile(r"^[a-z][a-z0-9-]{0,40}$")
SEMVER = re.compile(r"^(0|[1-9]\d{0,8})\.(0|[1-9]\d{0,8})\.(0|[1-9]\d{0,8})$")   # a part has at most 9 digits: int() of a longer one is a limit of Python and a way to break a build
REQUIRES = re.compile(r"^>=\s*([1-9]\d*)$")
COMMIT = re.compile(r"^[0-9a-f]{40}$")
TREE = re.compile(r"^sha256:[0-9a-f]{64}$")
ASSET = re.compile(r"^assets/[0-9a-f]{16}\.webp$")
BIN_SHA = re.compile(r"[0-9a-f]{64}")      # fullmatch only
TIME = re.compile(r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$")
SUBDIRS = ("packages", "recipes", "extensions", "capabilities", "blueprints")
LIMITS = {"icon": (256, 256), "background": (1280, 720), "screenshot": (1280, 1280)}   # the largest size, kept in proportion
MAX_SOURCE = 5 * 1024 * 1024
MAX_SCREENSHOTS = 8
IMAGE_EXT = (".png", ".jpg", ".jpeg", ".webp")
META_TEXT = ("title", "title_de", "author", "license", "homepage", "changes")
META_PROVENANCE = ("source", "source_commit")   # where a pinned (hobnix/community) package comes from; copied from index.toml, never from package.toml


class Problem(Exception):
    pass


def now_utc(text=None):
    if text:
        return datetime.strptime(text, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    return datetime.now(timezone.utc).replace(microsecond=0)


def stamp(d):
    return d.strftime("%Y-%m-%dT%H:%M:%SZ")


def tree_hash(folder):
    """sha256 of the listing `<mode> <size> <sha256 of content> <relative path>\\n`, files sorted by path bytes. mode is 755 for an executable
    file, else 644. A symlink or any other non-regular entry is refused: an archive of the commit must give the same listing everywhere."""
    lines = []
    for base, dirs, files in os.walk(folder):
        dirs[:] = sorted(d for d in dirs if d != ".git")
        for f in files:
            p = os.path.join(base, f)
            rel = os.path.relpath(p, folder).replace(os.sep, "/")
            if os.path.islink(p) or not os.path.isfile(p):
                raise Problem(f"{rel}: only regular files are allowed in a package")
            with open(p, "rb") as fh:
                data = fh.read()
            mode = "755" if os.access(p, os.X_OK) and os.name != "nt" else "644"
            lines.append((rel.encode(), f"{mode} {len(data)} {hashlib.sha256(data).hexdigest()} {rel}\n"))
    lines.sort()
    return "sha256:" + hashlib.sha256("".join(t for _, t in lines).encode()).hexdigest()


def discover(checkout):
    """[(path relative to the checkout, extra index.toml entry or {})] for every package folder of a repository."""
    idx = os.path.join(checkout, "index.toml")
    out = []
    if os.path.isfile(idx):
        with open(idx, "rb") as f:
            for name, e in sorted(tomllib.load(f).get("package", {}).items()):
                out.append((str(e.get("path", "")), e))
        return out
    for sub in SUBDIRS:
        d = os.path.join(checkout, sub)
        if os.path.isdir(d):
            for n in sorted(os.listdir(d)):
                if os.path.isfile(os.path.join(d, n, "package.toml")):
                    out.append((f"{sub}/{n}", {}))
    return out


def yanked_set(checkout):
    """{(name, version)} from yanked.toml: [[yanked]] name, version, reason. A bad version stays listed and is marked."""
    p = os.path.join(checkout, "yanked.toml")
    if not os.path.isfile(p):
        return {}
    with open(p, "rb") as f:
        return {(str(y.get("name")), str(y.get("version"))): str(y.get("reason", "")) for y in tomllib.load(f).get("yanked", [])}


def _pillow():
    try:
        from PIL import Image
        return Image
    except ImportError:
        raise Problem("assets need Pillow (pip install pillow); or build with --skip-assets")


def make_asset(src, kind, out_dir):
    """Resize one image to its limit, write WebP, name it by content hash; returns 'assets/<hash>.webp'."""
    if os.path.getsize(src) > MAX_SOURCE:
        raise Problem(f"{src}: larger than {MAX_SOURCE // 1048576} MB")
    Image = _pillow()
    try:
        im = Image.open(src)
        im.load()
    except Exception as e:
        raise Problem(f"{src}: not an image ({e})")
    im = im.convert("RGBA" if "A" in im.getbands() else "RGB")
    im.thumbnail(LIMITS[kind])
    tmp = os.path.join(out_dir, ".new.webp")
    im.save(tmp, "WEBP", quality=80, method=6)
    with open(tmp, "rb") as f:
        digest = hashlib.sha256(f.read()).hexdigest()[:16]
    final = os.path.join(out_dir, digest + ".webp")
    os.replace(tmp, final)
    return "assets/" + digest + ".webp"


def build_assets(folder, out_dir):
    d = os.path.join(folder, "assets")
    if not os.path.isdir(d):
        return {}
    os.makedirs(out_dir, exist_ok=True)
    got = {}
    for f in sorted(os.listdir(d)):
        stem, ext = os.path.splitext(f)
        p = os.path.join(d, f)
        if os.path.isfile(p) and ext.lower() in IMAGE_EXT and stem in ("icon", "background") and stem not in got:
            got[stem] = make_asset(p, stem, out_dir)
    shots = os.path.join(d, "screenshots")
    if os.path.isdir(shots):
        names = [f for f in sorted(os.listdir(shots)) if os.path.splitext(f)[1].lower() in IMAGE_EXT]
        if len(names) > MAX_SCREENSHOTS:
            raise Problem(f"more than {MAX_SCREENSHOTS} screenshots")
        got["screenshots"] = [make_asset(os.path.join(shots, f), "screenshot", out_dir) for f in names]
    return got


def binaries_of(folder, m):
    """The [[binary]] rows of a manifest as [{bin, target, sha256, size}]: informational (docs/PLAN-registry.md), read from the manifest and the
    file in the folder, nothing downloaded. A row that is not built yet (empty sha256) or not well formed is left out; size only when the file is there."""
    out = []
    rows = m.get("binary", [])
    for t in rows if isinstance(rows, list) else []:
        if not isinstance(t, dict) or not all(isinstance(t.get(k), str) for k in ("bin", "target", "sha256")) or not BIN_SHA.fullmatch(t["sha256"]):
            continue
        r = {"bin": t["bin"], "target": t["target"], "sha256": t["sha256"]}
        try:
            if isinstance(t.get("path"), str) and ".." not in t["path"].split("/") and not t["path"].startswith("/"):
                r["size"] = os.path.getsize(os.path.join(folder, t["path"]))
        except OSError:
            pass
        out.append(r)
    return out


def entry_of(checkout, path, extra, commit, yanked, assets_dir):
    if not re.match(r"^[A-Za-z0-9._/-]+$", path) or ".." in path.split("/"):
        raise Problem(f"path {path!r} is not allowed")
    folder = os.path.join(checkout, path)
    try:
        with open(os.path.join(folder, "package.toml"), "rb") as f:
            m = tomllib.load(f)
    except (OSError, tomllib.TOMLDecodeError, RecursionError, MemoryError) as e:
        raise Problem(f"{path}/package.toml: {e!r}"[:300])
    name, version = str(m.get("name")), str(m.get("version"))
    raw = m.get("meta", {}) if isinstance(m.get("meta"), dict) else {}
    meta = {"title": m.get("title", "")}
    for k in META_TEXT[1:]:
        if raw.get(k) or m.get(k):
            meta[k] = raw.get(k) or m.get(k)
    meta["tags"] = [str(x) for x in raw.get("tags", [])]
    for k in META_PROVENANCE:
        if isinstance(extra.get(k), str):
            meta[k] = extra[k]
    needs = list(m.get("needs", [])) if m.get("kind") == "recipe" else []
    if m.get("kind") == "blueprint":
        # the package list in order, so the marketplace shows it without the folder; `docker` stands for the [docker] table
        bp = m.get("blueprint", {}) if isinstance(m.get("blueprint"), dict) else {}
        needs = [str(x) for k in ("capabilities", "extensions", "recipes") for x in (bp.get(k) if isinstance(bp.get(k), list) else [])]
        needs += ["docker"] if isinstance(m.get("docker"), dict) else []
    needs += [x for x in m.get("requires", []) if x not in needs] if isinstance(m.get("requires"), list) else []
    assets = build_assets(folder, assets_dir) if assets_dir else {}
    meta["icon"] = assets.get("icon")
    meta["background"] = assets.get("background")
    meta["screenshots"] = assets.get("screenshots", [])
    e = {"kind": m.get("kind"), "version": version, "path": path, "commit": commit, "tree": tree_hash(folder),
         "requires_core": m.get("requires_core"), "yanked": (name, version) in yanked,
         "needs": needs, "core": extra.get("core") is True, "meta": meta}
    if (name, version) in yanked and yanked[(name, version)]:
        e["yanked_reason"] = yanked[(name, version)]
    bins = binaries_of(folder, m)
    if bins:
        e["binaries"] = bins
    if m.get("renamed_from"):
        e["renamed_from"] = list(m["renamed_from"])
    return name, e


HISTORY_COMMITS = 400      # first-parent commits that touched the package folder, newest first: more are never read
HISTORY_SECONDS = 90       # time limit of the whole walk of one package (hashing included)
HISTORY_VERSIONS = 10      # older versions in an entry
HISTORY_MAX_FILES = 5000
HISTORY_TEXT = 500         # characters of `changes` and `yanked_reason` in an older row
MAX_COMMIT_TIME = 253402300799   # 9999-12-31T23:59:59Z: a later committer date is nonsense and the commit is skipped
MAX_INDEX_BUILD = 10 * 1024 * 1024   # the client refuses 20 MiB (MAX_INDEX in pkg_repo.py); a build stays well below
HISTORY_MAX_BYTES = 1 << 30
ROW_KEYS = ("version", "date", "path", "commit", "tree", "requires_core", "yanked", "changes", "yanked_reason")


def _vkey(text):
    return tuple(int(x) for x in str(text).split("."))


def _git_dir_of(checkout):
    r = subprocess.run(["git", "-C", checkout, "rev-parse", "--absolute-git-dir"], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 and r.stdout.strip() else None


def _history_git(git_dir, args, end):
    """git on the repository under test with what is left of the walk's time (one deadline for all calls). Replace refs are never followed."""
    left = end - time.monotonic()
    if left <= 0:
        raise subprocess.TimeoutExpired("git", 0)
    return _git(git_dir, args, extra_env={"GIT_NO_REPLACE_OBJECTS": "1"}, timeout=left)


def _history_tree_hash(git_dir, commit, path, scratch, end):
    """tree_hash of the folder as it was in `commit`, or None when the folder is one tree_hash refuses (a link, a submodule, a odd name)."""
    got = _history_git(git_dir, ["rev-parse", "--verify", "-q", f"{commit}:{path}"], end)
    if got.returncode != 0:
        return None
    rows = _list_tree(git_dir, got.stdout.decode().strip(), max(end - time.monotonic(), 0.1))
    if not rows or len(rows) > HISTORY_MAX_FILES or sum(max(r[2], 0) for r in rows) > HISTORY_MAX_BYTES:
        return None
    for mode, _oid, size, rel in rows:
        if mode not in ("100644", "100755") or size < 0 or any(x in ("", ".", "..", ".git") for x in rel.split("/")):
            return None
    folder = os.path.join(scratch, "folder")
    _remove(folder)
    os.makedirs(folder)
    for mode, oid, _size, rel in rows:
        _blob_to_file(git_dir, oid, os.path.join(folder, *rel.split("/")), mode == "100755", max(end - time.monotonic(), 0.1))
    return tree_hash(folder)


def history_of(git_dir, tip, path, name, version, yanked, seconds=None):
    """(date, rows) of one package from the FIRST-PARENT history of `tip` (never from a previous index: that is downloaded without a signature
    check). date: the first commit of the walk that had `version` (None when none). rows: older versions, newest first, at most HISTORY_VERSIONS:
    the newest commit that had the version, its folder hashed with tree_hash. Only the current path is followed. A commit with a missing or
    invalid manifest and a folder tree_hash refuses is skipped. Old history never stops a build: ANY failure of one commit or one version skips
    it. One deadline (HISTORY_SECONDS) covers every git call of the walk, so a stalled git ends it within that time."""
    if not git_dir or not COMMIT.fullmatch(str(tip)) or not isinstance(version, str) or not SEMVER.fullmatch(version):
        return None, []
    end = time.monotonic() + (HISTORY_SECONDS if seconds is None else seconds)
    try:
        log = _history_git(git_dir, ["log", "--first-parent", "--no-renames", "--no-ext-diff", f"--max-count={HISTORY_COMMITS}",
                                     "--format=%H %ct", tip, "--", path], end)
    except Exception:
        return None, []
    if log.returncode != 0:
        return None, []
    newest, oldest = {}, {}
    for line in log.stdout.decode(errors="replace").splitlines():
        if time.monotonic() > end:
            break
        c, _, ct = line.partition(" ")
        if not COMMIT.fullmatch(c) or not ct.isdigit() or not 0 <= int(ct) <= MAX_COMMIT_TIME:
            continue
        try:
            blob = _history_git(git_dir, ["cat-file", "blob", f"{c}:{path}/package.toml"], end)
            if blob.returncode != 0 or len(blob.stdout) > 1 << 20:
                continue
            m = tomllib.loads(blob.stdout.decode())
            v = m.get("version")
            if m.get("name") != name or not isinstance(v, str) or not SEMVER.fullmatch(v) or not REQUIRES.match(str(m.get("requires_core", ""))):
                continue
        except Exception:      # a manifest that is not valid, too deep (RecursionError), too large (MemoryError) or a git that failed: skipped
            continue
        newest.setdefault(v, (c, m))
        oldest[v] = int(ct)
    day = lambda v: stamp(datetime.fromtimestamp(oldest[v], timezone.utc))
    rows = []
    with tempfile.TemporaryDirectory() as scratch:
        for v in sorted((v for v in newest if _vkey(v) < _vkey(version)), key=_vkey, reverse=True):
            if len(rows) >= HISTORY_VERSIONS or time.monotonic() > end:
                break
            c, m = newest[v]
            try:
                tree = _history_tree_hash(git_dir, c, path, scratch, end)
                if tree is None:
                    continue
                raw = m.get("meta", {}) if isinstance(m.get("meta"), dict) else {}
                row = {"version": v, "date": day(v), "path": path, "commit": c, "tree": tree, "requires_core": m["requires_core"],
                       "yanked": (name, v) in yanked}
                changes = raw.get("changes") or m.get("changes")
                if isinstance(changes, str):
                    row["changes"] = changes[:HISTORY_TEXT]
                if (name, v) in yanked and yanked[(name, v)]:
                    row["yanked_reason"] = yanked[(name, v)][:HISTORY_TEXT]
            except Exception:
                continue
            rows.append(row)
    try:
        date = day(version) if version in oldest else None
    except Exception:
        date = None
    return date, rows


def _row_problems(row, e):
    """[text] for one `versions` row of entry `e`."""
    if not isinstance(row, dict):
        return ["not an object"]
    out = []
    for k, rx in (("version", SEMVER), ("date", TIME), ("commit", COMMIT), ("tree", TREE), ("requires_core", REQUIRES)):
        if not isinstance(row.get(k), str) or not rx.match(row[k]):
            out.append(f"{k} is not valid")
    if row.get("path") != e.get("path"):
        out.append("path is not the path of the entry")
    if not isinstance(row.get("yanked"), bool):
        out.append("yanked is not true or false")
    for k in ("changes", "yanked_reason"):
        if k in row and (not isinstance(row[k], str) or len(row[k]) > HISTORY_TEXT):
            out.append(f"{k} is not text of at most {HISTORY_TEXT} characters")
    if not out and SEMVER.match(str(e.get("version", ""))) and _vkey(row["version"]) >= _vkey(e["version"]):
        out.append("version is not lower than the current one")
    return out


def clean_history(e):
    """The entry with `date` and `versions` reduced to what is well formed (a client: malformed rows and fields are left out, nothing is refused)."""
    e = dict(e)
    if "date" in e and not (isinstance(e["date"], str) and TIME.match(e["date"])):
        del e["date"]
    if "versions" in e:
        good, seen = [], set()
        for r in e["versions"] if isinstance(e["versions"], list) else []:
            if isinstance(r, dict) and not _row_problems(r, e) and r["version"] not in seen:
                seen.add(r["version"])
                good.append({k: v for k, v in r.items() if k in ROW_KEYS})
        e["versions"] = sorted(good, key=lambda r: _vkey(r["version"]), reverse=True)[:HISTORY_VERSIONS]
    return e


def build(checkout, repo, out, serial=None, prev=None, commit=None, ttl_days=14, now=None, assets=True, history=None):
    if not REPO.match(repo):
        raise Problem("repo id is not a lowercase word")
    if serial is None:
        serial = 1
        if prev:
            with open(prev, encoding="utf-8") as f:
                serial = int(json.load(f).get("serial", 0)) + 1
    if commit is None:
        commit = subprocess.run(["git", "-C", checkout, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
    t = now_utc(now)
    yanked = yanked_set(checkout)
    os.makedirs(out, exist_ok=True)
    pk = {}
    for path, extra in discover(checkout):
        name, e = entry_of(checkout, path, extra, commit, yanked, os.path.join(out, "assets") if assets else None)
        if name in pk:
            raise Problem(f"{name}: listed twice")
        date, rows = history_of(history or _git_dir_of(checkout), commit, path, name, e["version"], yanked)
        if date:
            e["date"] = date
        if rows:
            e["versions"] = rows
        pk[name] = e
    doc = {"format": FORMAT, "serial": serial, "generated": stamp(t), "expires": stamp(t + timedelta(days=ttl_days)), "repo": repo, "packages": pk}
    bad = validate(doc, strict=True)
    if bad:
        raise Problem("; ".join(bad))
    dump = lambda: json.dumps(doc, indent=1, sort_keys=True, ensure_ascii=False) + "\n"
    text = dump()
    while len(text.encode()) > MAX_INDEX_BUILD:     # older rows are the first to go (the one package with the most of them, its oldest row)
        heavy = max((n for n in pk if pk[n].get("versions")), key=lambda n: len(json.dumps(pk[n]["versions"])), default=None)
        if heavy is None:
            raise Problem(f"the index is larger than {MAX_INDEX_BUILD // 1048576} MiB even without older versions (a client refuses more than 20 MiB)")
        pk[heavy]["versions"].pop()
        if not pk[heavy]["versions"]:
            del pk[heavy]["versions"]
        text = dump()
    with open(os.path.join(out, "index.json"), "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    return doc


def validate(doc, now=None, warnings=None, strict=False):
    """[text] for an index document. Unknown fields are ignored (a client reads every format it knows). `binaries` is informational and nothing
    trusts it: only strict (the builder side, CI) checks its shape; a client calls without strict and ignores a malformed field."""
    out = []
    bad = out.append
    if not isinstance(doc, dict):
        return ["the index is not an object"]
    if doc.get("format") != FORMAT:
        bad(f"format {doc.get('format')!r} is not one this core reads ({FORMAT})")
        return out
    s = doc.get("serial")
    if not isinstance(s, int) or isinstance(s, bool) or s < 0:
        bad("serial is not a non-negative integer")
    for k in ("generated", "expires"):
        if not TIME.match(str(doc.get(k, ""))):
            bad(f"{k} is not a UTC time like 2026-11-22T04:00:00Z")
    if not out and doc["expires"] <= doc["generated"]:
        bad("expires is not after generated")
    if not REPO.match(str(doc.get("repo", ""))):
        bad("repo is not a lowercase word")
    elif doc["repo"] in ("core", "local"):
        bad(f"repo {doc['repo']} is a reserved name")
    if warnings is not None and not out and now_utc(now) > now_utc(doc["expires"]):
        warnings.append("the index has expired")
    pk = doc.get("packages")
    if not isinstance(pk, dict):
        bad("packages is not an object")
        return out
    for n, e in sorted(pk.items()):
        w = lambda t, n=n: bad(f"{n}: {t}")
        if not NAME.match(n):
            w("name is not a lowercase word")
        if not isinstance(e, dict):
            w("entry is not an object")
            continue
        if e.get("kind") not in KINDS:
            w("kind is not one of " + ", ".join(KINDS))
        if not SEMVER.match(str(e.get("version", ""))):
            w("version is not semver")
        if not COMMIT.match(str(e.get("commit", ""))):
            w("commit is not a 40-digit hex id")
        if not TREE.match(str(e.get("tree", ""))):
            w("tree is not sha256:<64 hex>")
        if not REQUIRES.match(str(e.get("requires_core", ""))):
            w('requires_core must look like ">=13"')
        p = str(e.get("path", ""))
        if not re.match(r"^[A-Za-z0-9._/-]+$", p) or ".." in p.split("/") or p.startswith("/"):
            w("path is not allowed")
        for k in ("yanked", "core"):
            if not isinstance(e.get(k), bool):
                w(f"{k} is not true or false")
        if not isinstance(e.get("needs"), list) or not all(isinstance(x, str) for x in e["needs"]):
            w("needs is not a list of names")
        if strict and "binaries" in e:
            b = e["binaries"]
            if not isinstance(b, list) or not all(
                    isinstance(x, dict) and isinstance(x.get("bin"), str) and isinstance(x.get("target"), str)
                    and isinstance(x.get("sha256"), str) and BIN_SHA.fullmatch(x["sha256"])
                    and (x.get("size") is None or (isinstance(x["size"], int) and not isinstance(x["size"], bool) and x["size"] >= 0)) for x in b):
                w("binaries is not a list of {bin, target, sha256 (64 hex), size}")
        if strict and "date" in e and not (isinstance(e["date"], str) and TIME.match(e["date"])):
            w("date is not a UTC time like 2026-11-22T04:00:00Z")
        if strict and "versions" in e:
            vs = e["versions"]
            if not isinstance(vs, list) or len(vs) > HISTORY_VERSIONS:
                w(f"versions is not a list of at most {HISTORY_VERSIONS} rows")
            else:
                for i, r in enumerate(vs):
                    for t in _row_problems(r, e):
                        w(f"versions[{i}]: {t}")
                keys = [_vkey(r["version"]) for r in vs if isinstance(r, dict) and SEMVER.match(str(r.get("version", "")))]
                if any(a <= b for a, b in zip(keys, keys[1:])):
                    w("versions are not newest first, one row per version")
        m = e.get("meta")
        if not isinstance(m, dict):
            w("meta is not an object")
            continue
        if not m.get("title"):
            w("meta.title missing")
        for k in META_TEXT[1:] + META_PROVENANCE:
            if k in m and not isinstance(m[k], str):
                w(f"meta.{k} is not text")
        if strict and "source_commit" in m and not COMMIT.fullmatch(str(m["source_commit"])):
            w("meta.source_commit is not a 40-digit hex id")
        if not isinstance(m.get("tags", []), list):
            w("meta.tags is not a list")
        for k in ("icon", "background"):
            if m.get(k) is not None and not ASSET.match(str(m[k])):
                w(f"meta.{k} is not assets/<hash>.webp")
        shots = m.get("screenshots", [])
        if not isinstance(shots, list) or not all(ASSET.match(str(x)) for x in shots):
            w("meta.screenshots is not a list of assets/<hash>.webp")
    return out


def check_serial(new, old):
    """None, or the reason a client refuses `new`: a lower serial than the index it has (no rollback to an old index)."""
    if new["serial"] < old["serial"]:
        return f"serial {new['serial']} is below the one already seen ({old['serial']})"
    if new["serial"] == old["serial"] and new != old:
        return f"serial {new['serial']} was already used for a different index"
    return None


def sign(index, key_file):
    if not os.path.isfile(key_file):
        raise Problem("the key file does not exist")
    sig = index + ".sig"
    if os.path.exists(sig):
        os.remove(sig)
    r = subprocess.run(["ssh-keygen", "-Y", "sign", "-q", "-f", key_file, "-n", NAMESPACE, index], capture_output=True, text=True)
    if r.returncode != 0 or not os.path.isfile(sig):
        raise Problem("signing failed: " + r.stderr.strip()[:200])
    return sig


def verify_signature(index, signers):
    """The signer's identity, or Problem. The signature is checked over the bytes of the file, before anything in it is trusted."""
    sig = index + ".sig"
    if not os.path.isfile(sig):
        raise Problem("no signature file (index.json.sig)")
    with open(index, "rb") as f:
        data = f.read()
    r = subprocess.run(["ssh-keygen", "-Y", "find-principals", "-f", signers, "-s", sig], capture_output=True, text=True)
    who = r.stdout.split()
    if r.returncode != 0 or not who:
        raise Problem("the signer is not in the trusted keys")
    for w in who:
        v = subprocess.run(["ssh-keygen", "-Y", "verify", "-f", signers, "-I", w, "-n", NAMESPACE, "-s", sig], input=data, capture_output=True)
        if v.returncode == 0:
            return w
    raise Problem("the signature does not match the index")


# ---- hobnix/community: pin-only manifests (docs/PLAN-registry.md, hobnix/core#1076) ----
# A manifest in manifests/<name>.toml pins a commit and a tree hash of a package in the author's repository. `assemble` fetches each pin,
# refuses what the reviewed manifest does not say, and writes the trees into one git commit (the CI-written `pins` branch). The index is then
# built from that commit like any other repository, so the client needs nothing new. Nothing in a pinned package is run here.

RESERVED_NAMES = ("official", "community", "core", "local")
MANIFEST_KEYS = ("name", "kind", "source", "commit", "path", "tree", "license", "maintainers", "status")
SOURCE_URL = re.compile(r"^https://([a-z0-9][a-z0-9.-]*)/[A-Za-z0-9._~-]+(/[A-Za-z0-9._~-]+)+$")
LICENCE_FILES = ("LICENSE", "LICENSE.md", "COPYING")
CI_ENV = {"GIT_AUTHOR_NAME": "hobnix-community-ci", "GIT_AUTHOR_EMAIL": "noreply@hobnix.invalid",
          "GIT_COMMITTER_NAME": "hobnix-community-ci", "GIT_COMMITTER_EMAIL": "noreply@hobnix.invalid",
          "GIT_NO_LAZY_FETCH": "1"}   # a blob the partial fetch left out is never fetched behind our back (git 2.44+; older git ignores it)
GIT_TIMEOUT = 300
OMITTED = 1 << 40        # the size of a blob the partial fetch did not bring


def _load_pkg_binary():
    spec = importlib.util.spec_from_file_location("pkg_binary", os.path.join(os.path.dirname(os.path.abspath(__file__)), "pkg_binary.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def load_policy(checkout: str) -> dict:
    """policy.toml of a community checkout: licences, hosts, kinds and the size caps. A missing or broken file stops the run."""
    try:
        with open(os.path.join(checkout, "policy.toml"), "rb") as f:
            policy = tomllib.load(f)
    except (OSError, tomllib.TOMLDecodeError) as e:
        raise Problem(f"policy.toml: {e}")
    for k in ("licences", "hosts", "kinds"):
        if not isinstance(policy.get(k), list) or not all(isinstance(x, str) for x in policy[k]):
            raise Problem(f"policy.toml: {k} is not a list of text")
    for k in ("max_folder_bytes", "max_file_bytes", "max_files", "max_binary_bytes"):
        if not isinstance(policy.get(k), int) or isinstance(policy.get(k), bool) or policy[k] < 1:
            raise Problem(f"policy.toml: {k} is not a positive number")
    return policy


def source_problem(source: object, policy: dict, allow_local: bool = False) -> str | None:
    """None, or why a source address is refused: https only, no login, no port, the host on the allow-list."""
    if not isinstance(source, str):
        return "source is not text"
    if allow_local and (source.startswith("file://") or source.startswith("/")):
        return None
    m = SOURCE_URL.fullmatch(source)
    if not m:
        return "source must be an https address like https://github.com/<owner>/<repository> (no login, no port)"
    if m.group(1) not in policy["hosts"]:
        return f"source host {m.group(1)} is not allowed (allowed: {', '.join(policy['hosts'])})"
    return None


def manifest_problems(m: dict, file_name: str, policy: dict, allow_local: bool = False) -> list[str]:
    """Problems of one manifest: the fields, the name against the file name and the reserved words, kind, host, licence."""
    out = [f"unknown field {k}" for k in sorted(set(m) - set(MANIFEST_KEYS))]
    name = m.get("name")
    if not isinstance(name, str) or not NAME.fullmatch(name):
        out.append("name is not a lowercase word")
    elif name != os.path.splitext(os.path.basename(file_name))[0]:
        out.append(f"name {name} differs from the file name")
    elif name in RESERVED_NAMES:
        out.append(f"name {name} is reserved")
    if m.get("kind") not in policy["kinds"]:
        out.append("kind is not one of " + ", ".join(policy["kinds"]))
    bad = source_problem(m.get("source"), policy, allow_local)
    if bad:
        out.append(bad)
    if not COMMIT.fullmatch(str(m.get("commit", ""))):
        out.append("commit is not a 40-digit hex id")
    if not TREE.fullmatch(str(m.get("tree", ""))):
        out.append("tree is not sha256:<64 hex>")
    p = m.get("path")
    if not isinstance(p, str) or (p != "." and (not re.fullmatch(r"^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$", p) or ".." in p.split("/"))):
        out.append('path is not "." or a relative folder')
    if m.get("license") not in policy["licences"]:
        out.append(f"license {m.get('license')!r} is not on the list of policy.toml")
    who = m.get("maintainers")
    if not isinstance(who, list) or not who or not all(isinstance(x, str) and x for x in who):
        out.append("maintainers is not a list of names")
    if m.get("status") not in ("active", "suspended"):
        out.append("status is not active or suspended")
    return out


def _git(git_dir: str, args: list[str], local: bool = False, data: bytes | None = None, extra_env: dict | None = None, timeout: float | None = None) -> subprocess.CompletedProcess:
    argv, env = _git_command(git_dir, args, local, extra_env)
    return subprocess.run(argv, capture_output=True, input=data, env=env, timeout=min(timeout, GIT_TIMEOUT) if timeout else GIT_TIMEOUT)


def _git_command(git_dir: str, args: list[str], local: bool = False, extra_env: dict | None = None) -> tuple[list[str], dict]:
    """git on a bare directory: no prompt, no password, no hooks, no redirects, no submodules, no text conversion, a time limit, https only
    (file:// and paths only when `local`, for tests). Returns (argv, environment)."""
    env = dict(os.environ, GIT_TERMINAL_PROMPT="0", GIT_CONFIG_NOSYSTEM="1", **CI_ENV, **(extra_env or {}))
    config = ["protocol.allow=never", "protocol.https.allow=always", f"protocol.file.allow={'always' if local else 'never'}",
              "http.followRedirects=false", "http.lowSpeedLimit=1000", "http.lowSpeedTime=60", f"core.hooksPath={os.devnull}",
              "core.fsmonitor=false", "core.autocrlf=false", "submodule.recurse=false", "fetch.recurseSubmodules=false"]
    return ["git", *[x for c in config for x in ("-c", c)], "--git-dir", git_dir, *args], env


def _git_out(git_dir: str, args: list[str], what: str, local: bool = False, data: bytes | None = None, extra_env: dict | None = None, timeout: float | None = None) -> bytes:
    r = _git(git_dir, args, local, data, extra_env, timeout)
    if r.returncode != 0:
        raise Problem(f"{what}: {r.stderr.decode(errors='replace').strip()[:200]}")
    return r.stdout


def _git_text(git_dir: str, args: list[str], what: str, local: bool = False, data: bytes | None = None, extra_env: dict | None = None) -> str:
    return _git_out(git_dir, args, what, local, data, extra_env).decode().strip()


def _list_tree(git_dir: str, tree: str, timeout: float | None = None) -> list[tuple[str, str, int, str]]:
    """[(mode, blob id, size, path)] of every entry below a git tree: the SAME object set that is checked, copied and hashed. A gitlink has size -1."""
    rows = []
    for record in _git_out(git_dir, ["ls-tree", "-r", "-l", "-z", tree], "git ls-tree", timeout=timeout).split(b"\0"):
        if not record:
            continue
        head, _, raw_path = record.partition(b"\t")
        mode, _kind, oid, size = head.split()
        try:
            path = raw_path.decode("utf-8")
        except UnicodeDecodeError:
            raise Problem("a file name is not UTF-8")
        # `BAD`: the blob was left out by the size filter of the fetch (GIT_NO_LAZY_FETCH=1): larger than the limit, so the caps refuse it
        rows.append((mode.decode(), oid.decode(), -1 if size == b"-" else OMITTED if size == b"BAD" else int(size), path))
    return rows


def tree_problems(rows: list[tuple[str, str, int, str]], policy: dict) -> list[str]:
    """What a listing says before any file is read: only regular files, no .gitattributes or .gitmodules, file count and sizes within the caps
    (a file may be as large as a binary; the total as the folder plus one binary; the exact rules follow on the files themselves)."""
    out = []
    for mode, _oid, _size, path in rows:
        parts = path.split("/")
        if mode not in ("100644", "100755"):
            out.append(f"{path}: only regular files are allowed in a package (mode {mode})")
        if any(x in ("", ".", "..", ".git") for x in parts):
            out.append(f"{path}: this path is not allowed")
        if parts[-1] in (".gitattributes", ".gitmodules"):
            out.append(f"{path}: {parts[-1]} is not allowed")
    if len(rows) > policy["max_files"]:
        out.append(f"{len(rows)} files, the limit is {policy['max_files']}")
    for _mode, _oid, size, path in rows:
        if size > policy["max_binary_bytes"]:
            out.append(f"{path}: larger than {policy['max_binary_bytes']} bytes")
    if sum(max(r[2], 0) for r in rows) > policy["max_folder_bytes"] + policy["max_binary_bytes"]:
        out.append("the folder is far larger than the limit")
    return out


def _blob_to_file(git_dir: str, oid: str, dest: str, executable: bool, timeout: float | None = None) -> None:
    """Write one blob to a file without holding it in memory."""
    argv, env = _git_command(git_dir, ["cat-file", "blob", oid])
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    with open(dest, "wb") as out:
        done = subprocess.run(argv, stdout=out, stderr=subprocess.PIPE, env=env, timeout=min(timeout, GIT_TIMEOUT) if timeout else GIT_TIMEOUT)
    if done.returncode != 0:
        raise Problem(f"cannot read a file: {done.stderr.decode(errors='replace').strip()[:200]}")
    os.chmod(dest, 0o755 if executable else 0o644)


def materialise(source: str, commit: str, path: str, git_dir: str, folder: str, policy: dict, local: bool = False) -> str:
    """Fetch exactly `commit` into the bare repository `git_dir`, check the listing of the package folder's tree (links, submodules, git
    attribute files, caps) BEFORE reading a file, then write exactly those files into `folder`. Returns the git id of the tree."""
    if not os.path.isdir(git_dir):
        _git_text(git_dir, ["init", "--bare", "-q"], "git init")
    # --filter=blob:limit: a blob above the largest allowed file is not downloaded at all (the listing then names it too large); a server that
    # cannot filter ignores the option and sends everything, the caps are checked on the listing either way
    limit = f"--filter=blob:limit={policy['max_binary_bytes'] + 1}"
    # a filtered fetch needs a NAMED remote (git records it as the promisor; an address as name is refused). Reset on every call: the source was
    # checked by source_problem() and is only ever https, or a path in the tests
    _git_text(git_dir, ["config", "remote.pin.url", source], "git config")
    _git_text(git_dir, ["fetch", "--depth", "1", "--no-tags", "-q", limit, "pin", commit], f"cannot fetch {commit[:12]} from {source}", local)
    if _git_text(git_dir, ["rev-parse", "FETCH_HEAD^{commit}"], "fetch") != commit:
        raise Problem(f"{source} gave another commit than {commit}")
    spec = commit + "^{tree}" if path == "." else f"{commit}:{path}"
    got = _git(git_dir, ["rev-parse", "--verify", spec])
    if got.returncode != 0:
        raise Problem(f"folder {path} is not in commit {commit[:12]}")
    subtree = got.stdout.decode().strip()
    rows = _list_tree(git_dir, subtree)
    bad = tree_problems(rows, policy)
    if bad:
        raise Problem("; ".join(bad))
    os.makedirs(folder, exist_ok=True)
    for mode, oid, _size, rel in rows:
        _blob_to_file(git_dir, oid, os.path.join(folder, *rel.split("/")), mode == "100755")
    return subtree


def _is_binary(path: str) -> bool:
    with open(path, "rb") as f:
        return b"\0" in f.read(8000)


def folder_problems(folder: str, manifest: dict, policy: dict) -> list[str]:
    """What the reviewed manifest and policy.toml say about the fetched folder: package.toml against the manifest, no Nix, no .gitattributes,
    size caps, no binary file that is not a hashed [[binary]] row, a licence."""
    try:
        with open(os.path.join(folder, "package.toml"), "rb") as f:
            up = tomllib.load(f)
    except (OSError, tomllib.TOMLDecodeError) as e:
        return [f"package.toml: {e}"]
    out = [f"package.toml says {k} {up.get(k)!r}, the manifest {manifest.get(k)!r}" for k in ("name", "kind") if up.get(k) != manifest.get(k)]
    rows = up.get("binary") if isinstance(up.get("binary"), list) else []
    declared = {t["path"] for t in rows if isinstance(t, dict) and isinstance(t.get("path"), str)}
    out += [f"[[binary]]: {t}" for t in _load_pkg_binary().manifest_problems(up, folder, True)]
    total, count = 0, 0
    for base, _dirs, files in os.walk(folder):
        for f in sorted(files):
            p = os.path.join(base, f)
            rel = os.path.relpath(p, folder).replace(os.sep, "/")
            size = os.path.getsize(p)
            count += 1
            if f == ".gitattributes":
                out.append(f"{rel}: .gitattributes is not allowed")
            if f.endswith(".nix"):
                out.append(f"{rel}: Nix modules are not accepted from this repository")
            if rel in declared:
                if size > policy["max_binary_bytes"]:
                    out.append(f"{rel}: larger than {policy['max_binary_bytes']} bytes")
                continue
            total += size
            if size > policy["max_file_bytes"]:
                out.append(f"{rel}: larger than {policy['max_file_bytes']} bytes")
            is_image = rel.startswith("assets/") and os.path.splitext(f)[1].lower() in IMAGE_EXT
            if not is_image and _is_binary(p):
                out.append(f"{rel}: a binary file that is not a [[binary]] row with a sha256")
    if total > policy["max_folder_bytes"]:
        out.append(f"the folder is {total} bytes, the limit is {policy['max_folder_bytes']}")
    if count > policy["max_files"]:
        out.append(f"{count} files, the limit is {policy['max_files']}")
    meta = up.get("meta") if isinstance(up.get("meta"), dict) else {}
    if not any(os.path.isfile(os.path.join(folder, n)) for n in LICENCE_FILES) and meta.get("license") != manifest.get("license"):
        out.append("no LICENSE, LICENSE.md or COPYING file, and [meta] license is not the manifest's license")
    return out


def _version_key(text: object) -> tuple[int, ...]:
    return tuple(int(x) for x in str(text).split(".")) if SEMVER.fullmatch(str(text)) else (0, 0, 0)


def _index_toml(packages: dict[str, dict]) -> str:
    """The generated index.toml of the pins tree: the fields repo-check compares, copied from each upstream package.toml."""
    lines = ['publish = "index"', 'licences = "per-package"', ""]
    for name, e in sorted(packages.items()):
        lines.append(f"[package.{name}]")
        lines += [f"{k} = {json.dumps(v)}" for k, v in e.items() if v is not None]
        lines.append("")
    return "\n".join(lines)


def _pins_entry(m: dict, up: dict) -> dict:
    e = {"path": f"{m['kind']}s/{m['name']}", "version": up.get("version"), "kind": up.get("kind"), "requires_core": up.get("requires_core"),
         "core": False, "source": m["source"], "source_commit": m["commit"]}
    for k in ("icon", "category", "app_version", "audience"):
        e[k] = up.get(k)
    return e


def _official_names(location: str | None) -> set[str]:
    """Package names of the official index (a file or an https address). Required, and unreachable is a failure: the check fails closed."""
    if not location:
        raise Problem("--official-index is required (the CI check passes https://packages.hobnix.dev/official/index.json)")
    try:
        if location.startswith("https://"):
            import urllib.request
            with urllib.request.urlopen(location, timeout=20) as r:
                return set(json.load(r)["packages"])
        with open(location, encoding="utf-8") as f:
            return set(json.load(f)["packages"])
    except (OSError, ValueError, KeyError) as e:
        raise Problem(f"the official index could not be read ({e})")


def _previous_pin(git_dir: str, tip: str | None, prefix: str) -> tuple[str | None, str | None]:
    """(version, tree id) of a package in the previous pins commit, or (None, None)."""
    if not tip:
        return None, None
    got = _git(git_dir, ["show", f"{tip}:{prefix}/package.toml"])
    if got.returncode != 0:
        return None, None
    try:
        version = str(tomllib.loads(got.stdout.decode()).get("version"))
    except tomllib.TOMLDecodeError:
        return None, None
    return version, _git_text(git_dir, ["rev-parse", f"{tip}:{prefix}"], "rev-parse")


def _read_manifests(checkout: str, policy: dict, allow_local: bool) -> tuple[list[dict], list[str]]:
    folder = os.path.join(checkout, "manifests")
    found, out = [], []
    for fname in sorted(os.listdir(folder)) if os.path.isdir(folder) else []:
        if fname == ".gitkeep":
            continue
        try:
            with open(os.path.join(folder, fname), "rb") as f:
                m = tomllib.load(f)
        except (OSError, tomllib.TOMLDecodeError) as e:
            out.append(f"manifests/{fname}: {e}")
            continue
        bad = manifest_problems(m, fname, policy, allow_local) if fname.endswith(".toml") else ["only .toml files belong here"]
        out += [f"manifests/{fname}: {t}" for t in bad]
        if not bad:
            found.append(m)
    return found, out


def _check_pin(m: dict, git_dir: str, scratch: str, policy: dict, pins_tip: str | None, local: bool) -> tuple[str, dict, list[str]]:
    """Fetch one pin and check it: (git id of the folder, its upstream package.toml, problems)."""
    folder = os.path.join(scratch, m["name"])
    subtree = materialise(m["source"], m["commit"], m["path"], git_dir, folder, policy, local)
    found = folder_problems(folder, m, policy)
    actual = tree_hash(folder)
    if actual != m["tree"]:
        found.append(f"the tree hash of the fetched folder is {actual}, the manifest says {m['tree']}")
    with open(os.path.join(folder, "package.toml"), "rb") as f:
        up = tomllib.load(f)
    old_version, old_tree = _previous_pin(git_dir, pins_tip, f"{m['kind']}s/{m['name']}")
    if old_tree and old_tree != subtree and _version_key(up.get("version")) <= _version_key(old_version):
        found.append(f"version {up.get('version')} is not higher than {old_version} of the previous pin")
    return subtree, up, found


def _remove(path: str) -> None:
    if os.path.isdir(path):
        shutil.rmtree(path)
    elif os.path.exists(path):
        os.remove(path)


def assemble(checkout: str, out_dir: str, official_index: str | None = None, pins_tip: str | None = None,
             allow_local: bool = False) -> tuple[str | None, list[str]]:
    """Build the pins commit from the active manifests of `checkout`. Returns (commit id or None, problems); with problems nothing is committed.
    Writes out_dir/pins.git (the objects), out_dir/tree/ (the files, for `index build`), pins.commit and, when the tree changed, pins.bundle."""
    out_dir = os.path.abspath(out_dir)   # git changes into the work tree for checkout-index: every path handed to it must not depend on the cwd
    policy = load_policy(checkout)
    manifests, problems = _read_manifests(checkout, policy, allow_local)
    official = _official_names(official_index)
    git_dir, scratch, index_file = (os.path.join(out_dir, n) for n in ("pins.git", "folders", "pins.index"))
    os.makedirs(out_dir, exist_ok=True)
    for stale in (scratch, index_file, os.path.join(out_dir, "tree"), os.path.join(out_dir, "pins.bundle")):
        _remove(stale)
    if not os.path.isdir(git_dir):
        _git_text(git_dir, ["init", "--bare", "-q"], "git init")
    if pins_tip:
        _git_text(git_dir, ["fetch", "-q", checkout, pins_tip], f"cannot read the previous pins commit {pins_tip[:12]}", True)
    entries: dict[str, dict] = {}
    for m in manifests:
        if m["status"] != "active":
            continue
        if m["name"] in official:
            problems.append(f"{m['name']}: the name is taken by a package of the official index")
            continue
        try:
            subtree, up, found = _check_pin(m, git_dir, scratch, policy, pins_tip, allow_local)
        except (Problem, OSError, tomllib.TOMLDecodeError) as e:
            found = [str(e)]
        problems += [f"{m['name']}: {t}" for t in found]
        if not found:
            entries[m["name"]] = _pins_entry(m, up)
            _git_text(git_dir, ["read-tree", f"--prefix={m['kind']}s/{m['name']}/", subtree], "read-tree",
                      extra_env={"GIT_INDEX_FILE": index_file, "GIT_WORK_TREE": scratch})   # --prefix wants a work tree; read-tree without -u never writes to it
    if problems:
        return None, problems
    return _write_pins(git_dir, index_file, entries, pins_tip, out_dir), []


def _write_pins(git_dir: str, index_file: str, entries: dict[str, dict], pins_tip: str | None, out_dir: str) -> str:
    """Add the generated index.toml to the staged trees, commit (the previous tip when nothing changed), write the bundle and the files."""
    env = {"GIT_INDEX_FILE": index_file}
    blob = _git_text(git_dir, ["hash-object", "-w", "--stdin"], "hash-object", data=_index_toml(entries).encode())
    _git_text(git_dir, ["update-index", "--add", "--cacheinfo", f"100644,{blob},index.toml"], "update-index", extra_env=env)
    tree = _git_text(git_dir, ["write-tree"], "write-tree", extra_env=env)
    if pins_tip and _git_text(git_dir, ["rev-parse", f"{pins_tip}^{{tree}}"], "rev-parse") == tree:
        commit = pins_tip
    else:
        listing = "".join(f"{n} {e['source']} {e['source_commit']}\n" for n, e in sorted(entries.items()))
        commit = _git_text(git_dir, ["commit-tree", tree, *(["-p", pins_tip] if pins_tip else []), "-m", f"pins: {len(entries)} packages\n\n{listing}"], "commit-tree")
        _git_text(git_dir, ["update-ref", "refs/heads/pins", commit], "update-ref")
        _git_text(git_dir, ["bundle", "create", "-q", os.path.join(out_dir, "pins.bundle"), "refs/heads/pins", *([f"^{pins_tip}"] if pins_tip else [])], "git bundle")
    with open(os.path.join(out_dir, "pins.commit"), "w", encoding="utf-8", newline="\n") as f:
        f.write(commit + "\n")
    tree_dir = os.path.join(out_dir, "tree")
    os.makedirs(tree_dir)
    _git_text(git_dir, ["checkout-index", "-a"], "checkout-index", extra_env={**env, "GIT_WORK_TREE": tree_dir})   # the staged objects, nothing converted
    return commit


def pin(manifest_file: str, commit: str, allow_local: bool = False) -> str:
    """Point a manifest at `commit`: fetch it, compute the tree hash of the package folder, rewrite the commit and tree lines in place."""
    if not COMMIT.fullmatch(commit):
        raise Problem("commit is not a 40-digit hex id")
    policy = load_policy(os.path.dirname(os.path.dirname(os.path.abspath(manifest_file))))
    with open(manifest_file, "rb") as f:
        m = tomllib.load(f)
    bad = source_problem(m.get("source"), policy, allow_local)
    if bad or not isinstance(m.get("path"), str):
        raise Problem(bad or "path is missing")
    with tempfile.TemporaryDirectory() as work:
        materialise(m["source"], commit, m["path"], os.path.join(work, "git"), os.path.join(work, "folder"), policy, allow_local)
        tree = tree_hash(os.path.join(work, "folder"))
    with open(manifest_file, encoding="utf-8") as f:
        text = f.read()
    for key, value in (("commit", commit), ("tree", tree)):
        text, n = re.subn(rf'(?m)^{key}\s*=\s*"[^"\n]*"', f'{key} = "{value}"', text)
        if n != 1:
            raise Problem(f'{key} is not one line of the form {key} = "..."')
    with open(manifest_file, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    return tree


MAX_DIFF_LINES = 120       # per file
MAX_DIFF_TOTAL = 1500      # per run
MAX_DIFF_FILE = 256 * 1024
MANIFEST_FIELDS = ("kind", "source", "path", "commit", "tree", "license", "maintainers", "status")


def _clean(text: object, limit: int = 300) -> str:
    """Untrusted text made safe to print: control and format characters (escape sequences, bidi overrides) become \\xNN, long text is cut."""
    t = "".join(c if c.isprintable() else f"\\x{ord(c):02x}" for c in str(text))
    # the runner reads `##[warning]...` and `##vso[...]` as a command anywhere in a line (`::` only at a line start, see _quote): no `##` survives,
    # a single `#` (a shebang, a comment) stays readable
    t = t.replace("##", "#\\x23")
    return t if len(t) <= limit else t[:limit] + "..."


def _quote(text: object) -> str:
    """One line of untrusted text for the report: indented and marked, so a line can never start with `::` (a workflow command in the CI log)."""
    return "    | " + _clean(text)


def _files_of(folder: str) -> dict[str, tuple[bytes | None, bool, int]]:
    """{relative path: (content or None when large, executable, size)} of a folder that materialise() wrote (regular files only)."""
    out = {}
    for base, _dirs, names in os.walk(folder):
        for n in sorted(names):
            p = os.path.join(base, n)
            size = os.path.getsize(p)
            data = None
            if size <= MAX_DIFF_FILE:
                with open(p, "rb") as f:
                    data = f.read()
            out[os.path.relpath(p, folder).replace(os.sep, "/")] = (data, bool(os.stat(p).st_mode & 0o111), size)
    return out


def _is_script(rel: str, entry: tuple[bytes | None, bool, int]) -> bool:
    return entry[1] or rel.endswith((".sh", ".py", ".bash")) or (entry[0] or b"").startswith(b"#!")


def _toml_of(files: dict, name: str) -> dict:
    try:
        return tomllib.loads((files.get(name, (b"",))[0] or b"").decode())
    except (tomllib.TOMLDecodeError, UnicodeDecodeError):
        return {}


def _fetch_pin(m: dict, work: str, policy: dict, local: bool) -> tuple[dict | None, list[str]]:
    """One pin fetched and checked like assemble does: (its files, problems). Files is None when the pin could not be read."""
    folder = os.path.join(work, "folder")
    try:
        materialise(m["source"], m["commit"], m["path"], os.path.join(work, "git"), folder, policy, local)
        problems = folder_problems(folder, m, policy)
        actual = tree_hash(folder)
        if actual != m["tree"]:
            problems.append(f"the tree hash of the fetched folder is {actual}, the manifest says {m['tree']}")
        return _files_of(folder), problems
    except (Problem, OSError, tomllib.TOMLDecodeError, subprocess.TimeoutExpired) as e:
        return None, [str(e)]


def _list_changes(label: str, old: list, new: list) -> list[str]:
    old_s, new_s = set(map(str, old)), set(map(str, new))
    return [f"  {label}: +{_clean(x)}" for x in sorted(new_s - old_s)] + [f"  {label}: -{_clean(x)}" for x in sorted(old_s - new_s)]


def _content_diff(old: dict, new: dict, budget: list[int]) -> tuple[list[str], set[str]]:
    """The file list (added, removed, changed) and a bounded text diff of every changed file; the set names what the change touches."""
    import difflib
    out, touches = [], set()
    for rel in sorted(set(old) | set(new)):
        o, n = old.get(rel), new.get(rel)
        if o and n and o == n:
            continue
        state = "added" if not o else "removed" if not n else "changed"
        entry = n or o
        kind = "script" if _is_script(rel, entry) else "commands" if rel == "commands.tsv" else "manifest" if rel == "package.toml" else \
            "assets" if rel.startswith("assets/") else "other"
        touches.add(kind)
        out.append(f"  {state:<8}{entry[2]:>8} bytes  {_clean(rel)}" + ("  (executable)" if entry[1] else "") + (f"  [{kind}]" if kind in ("script", "commands") else ""))
        if o and n and o[1] != n[1]:
            out.append(f"    | mode: {'executable' if o[1] else 'plain'} -> {'executable' if n[1] else 'plain'}")
        if state == "removed":
            continue
        texts = []
        for side in (o, n):
            if side is None:
                texts.append([])
                continue
            try:
                texts.append(side[0].decode("utf-8").splitlines() if side[0] is not None else None)
            except UnicodeDecodeError:
                texts.append(None)
        if None in texts:
            digest = hashlib.sha256(n[0]).hexdigest()[:16] if n[0] is not None else "not computed (large file)"
            out.append(f"    | (binary, non-UTF-8 or large: no text diff, sha256 {digest})")
            continue
        shown = 0
        for line in difflib.unified_diff(texts[0], texts[1], "old", "new", lineterm="", n=1):
            if shown >= MAX_DIFF_LINES or budget[0] <= 0:
                out.append("    | ... diff cut here, read the pinned commit itself")
                break
            out.append(_quote(line))
            shown += 1
            budget[0] -= 1
    return out, touches


def community_diff(new_checkout: str, base_checkout: str | None = None, allow_local: bool = False) -> tuple[list[str], list[str]]:
    """What a pull request to hobnix/community does: for every manifest that differs from the base checkout, the manifest fields, then (the pinned
    commits fetched and checked like `assemble` does) version, permissions, command rows, web declaration, binary rows and a bounded text diff of
    the files. Returns (report lines, problems); a pin the check refuses is a problem. The base checkout's policy.toml is the rule (a pull request
    that edits policy.toml is not allowed to loosen its own check) and a change to it is reported."""
    policy = load_policy(base_checkout or new_checkout)
    report, problems = [], []
    new, bad = _read_manifests(new_checkout, policy, allow_local)
    problems += bad
    old = _read_manifests(base_checkout, policy, allow_local)[0] if base_checkout else []
    if base_checkout:
        try:
            texts = []
            for c in (base_checkout, new_checkout):
                with open(os.path.join(c, "policy.toml"), "rb") as f:
                    texts.append(f.read())
        except OSError:
            texts = [b"a", b"b"]
        if texts[0] != texts[1]:
            report.append("!! policy.toml differs from the base. The base policy was used for the checks below; a maintainer reads this change first.")
    old_by, new_by = {m["name"]: m for m in old}, {m["name"]: m for m in new}
    budget = [MAX_DIFF_TOTAL]
    for name in sorted(set(old_by) | set(new_by)):
        o, n = old_by.get(name), new_by.get(name)
        if o == n:
            continue
        verb = "added" if not o else "removed" if not n else "changed"
        report.append(f"== {_clean(name)}: manifest {verb}")
        if not n:
            report.append("  the package leaves the index at the next run")
            continue
        for k in MANIFEST_FIELDS:
            ov, nv = (o or {}).get(k), n.get(k)
            if o is None:
                report.append(f"  {k}: {_clean(nv)}")
            elif ov != nv:
                report.append(f"  {k}: {_clean(ov)} -> {_clean(nv)}" + ("   !! the SOURCE of the code changes" if k == "source" else ""))
        if n["status"] != "active":
            report.append("  not active: nothing is fetched or built")
            continue
        with tempfile.TemporaryDirectory() as new_work, tempfile.TemporaryDirectory() as old_work:
            files, found = _fetch_pin(n, new_work, policy, allow_local)
            problems += [f"{name}: {t}" for t in found]
            report += [f"  REFUSED: {_clean(t)}" for t in found]
            if files is None:
                continue
            before = None
            if o and o["status"] == "active" and (o["source"], o["commit"], o["path"]) != (n["source"], n["commit"], n["path"]):
                before, why = _fetch_pin(o, old_work, policy, allow_local)
                if before is None:
                    report.append(f"  the old pin cannot be read ({_clean(why[0])}): all files are shown as new")
            elif o and o["status"] == "active":
                before = files   # same pin, only the manifest text changed
            up, up_old = _toml_of(files, "package.toml"), _toml_of(before or {}, "package.toml")
            report.append(f"  version: {_clean(up_old.get('version', '-'))} -> {_clean(up.get('version', '-'))}" if before else f"  version: {_clean(up.get('version', '-'))}")
            wrong = [f"{k} is not a list" for k in ("permissions", "binary") if any(t.get(k) not in (None, []) and not isinstance(t.get(k), list) for t in (up, up_old))]
            if wrong:
                problems += [f"{name}: {t}" for t in wrong]
                report += [f"  REFUSED: {t}" for t in wrong]
                continue
            report += _list_changes("permissions", up_old.get("permissions") or [], up.get("permissions") or [])
            rows = lambda t: [f"{b.get('path')} {b.get('url')} {b.get('sha256')}" for b in t.get("binary") or [] if isinstance(b, dict)]
            report += _list_changes("[[binary]]", rows(up_old), rows(up))
            web_old, web_new = up_old.get("web") if isinstance(up_old.get("web"), dict) else {}, up.get("web") if isinstance(up.get("web"), dict) else {}
            report += [f"  web.{_clean(k)}: {'added' if k not in web_old else 'removed' if k not in web_new else 'changed'}"
                       for k in sorted(set(web_old) | set(web_new)) if web_old.get(k) != web_new.get(k)]
            rows_old = (before or {}).get("commands.tsv", (b"",))[0] or b""
            rows_new = files.get("commands.tsv", (b"",))[0] or b""
            report += _list_changes("command row", rows_old.decode(errors="replace").splitlines(), rows_new.decode(errors="replace").splitlines())
            lines, touches = _content_diff(before or {}, files, budget)
            report.append(f"  touches: {', '.join(sorted(touches)) or 'nothing in the folder'}")
            report += lines
    if not report:
        report.append("no manifest differs from the base")
    return report, problems


def run(argv):
    if not argv:
        print(__doc__)
        return 1
    cmd, rest = argv[0], argv[1:]

    def opt(name, default=None):
        return rest[rest.index(name) + 1] if name in rest and rest.index(name) + 1 < len(rest) else default
    pos = rest[:1] if rest and not rest[0].startswith("--") else []
    try:
        if cmd == "tree" and pos:
            print(tree_hash(pos[0]))
        elif cmd == "build" and pos and opt("--repo") and opt("--out"):
            doc = build(pos[0], opt("--repo"), opt("--out"), int(opt("--serial")) if opt("--serial") else None, opt("--prev"), opt("--commit"),
                        int(opt("--ttl-days", 14)), opt("--now"), "--skip-assets" not in rest, opt("--history"))
            print(f"serial\t{doc['serial']}\npackages\t{len(doc['packages'])}\nexpires\t{doc['expires']}")
        elif cmd == "assemble" and pos and opt("--out"):
            commit, bad = assemble(pos[0], opt("--out"), opt("--official-index"), opt("--pins-tip"), os.environ.get("HS_COMMUNITY_ALLOW_LOCAL") == "1")
            for t in bad:
                print(f"error\t{_clean(t)}", file=sys.stderr)
            if bad:
                return 1
            print(f"commit\t{commit}")
        elif cmd == "diff" and pos:
            report, bad = community_diff(pos[0], opt("--base"), os.environ.get("HS_COMMUNITY_ALLOW_LOCAL") == "1")
            for t in report:
                print(t)
            for t in bad:
                print(f"error\t{_clean(t)}", file=sys.stderr)
            return 1 if bad else 0
        elif cmd == "pin" and len(rest) == 2:
            print(pin(rest[0], rest[1], os.environ.get("HS_COMMUNITY_ALLOW_LOCAL") == "1"))
        elif cmd == "validate" and pos:
            with open(pos[0], encoding="utf-8") as f:
                warns = []
                bad = validate(json.load(f), opt("--now"), warns, True)
            for t in warns:
                print("warning: " + t, file=sys.stderr)
            for t in bad:
                print(t)
            return 1 if bad else 0
        elif cmd == "sign" and pos and opt("--key-file"):
            print(sign(pos[0], opt("--key-file")))
        elif cmd == "verify" and pos and opt("--signers"):
            who = verify_signature(pos[0], opt("--signers"))     # first: nothing in the file counts before this
            with open(pos[0], encoding="utf-8") as f:
                doc = json.load(f)
            warns = []
            bad = validate(doc, opt("--now"), warns, True)
            if bad:
                raise Problem("; ".join(bad))
            if opt("--prev"):
                with open(opt("--prev"), encoding="utf-8") as f:
                    why = check_serial(doc, json.load(f))
                if why:
                    raise Problem(why)
            for t in warns:
                print("warning: " + t, file=sys.stderr)
            print(f"signer\t{who}\nserial\t{doc['serial']}\nexpires\t{doc['expires']}")
        else:
            print(__doc__)
            return 2
    except (Problem, OSError, ValueError, json.JSONDecodeError) as e:
        print(f"error\t{_clean(e)}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(run(sys.argv[1:]))
