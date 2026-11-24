#!/usr/bin/env python3
"""The package index (docs/PLAN-registry.md "The index", hobnix/core#1069). Python stdlib; Pillow only to resize assets.

One `index.json` per package repository, built from package.toml and assets/ by CI, signed by CI, read by servers.

  pkg_index.py tree <folder>                                       the tree hash of a package folder (sha256:<hex>)
  pkg_index.py build <repo checkout> --repo <id> --out <dir> [--serial N | --prev <index.json>] [--commit SHA] [--ttl-days 14]
                                                                   [--now <ISO>] [--skip-assets]    write <dir>/index.json and <dir>/assets/
  pkg_index.py validate <index.json> [--now <ISO>]                 the schema; exit 1 on a problem (an expired index is only a warning)
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
import json
import os
import re
import subprocess
import sys
import tomllib
from datetime import datetime, timedelta, timezone

FORMAT = 1
NAMESPACE = "hobnix-index"
KINDS = ("recipe", "extension", "capability", "blueprint")
NAME = re.compile(r"^[a-z][a-z0-9-]{0,40}$")
REPO = re.compile(r"^[a-z][a-z0-9-]{0,40}$")
SEMVER = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")
REQUIRES = re.compile(r"^>=\s*([1-9]\d*)$")
COMMIT = re.compile(r"^[0-9a-f]{40}$")
TREE = re.compile(r"^sha256:[0-9a-f]{64}$")
ASSET = re.compile(r"^assets/[0-9a-f]{16}\.webp$")
TIME = re.compile(r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$")
SUBDIRS = ("packages", "recipes", "extensions", "capabilities", "blueprints")
LIMITS = {"icon": (256, 256), "background": (1280, 720), "screenshot": (1280, 1280)}   # the largest size, kept in proportion
MAX_SOURCE = 5 * 1024 * 1024
MAX_SCREENSHOTS = 8
IMAGE_EXT = (".png", ".jpg", ".jpeg", ".webp")
META_TEXT = ("title", "title_de", "author", "license", "homepage", "changes")


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


def entry_of(checkout, path, extra, commit, yanked, assets_dir):
    if not re.match(r"^[A-Za-z0-9._/-]+$", path) or ".." in path.split("/"):
        raise Problem(f"path {path!r} is not allowed")
    folder = os.path.join(checkout, path)
    try:
        with open(os.path.join(folder, "package.toml"), "rb") as f:
            m = tomllib.load(f)
    except (OSError, tomllib.TOMLDecodeError) as e:
        raise Problem(f"{path}/package.toml: {e}")
    name, version = str(m.get("name")), str(m.get("version"))
    raw = m.get("meta", {}) if isinstance(m.get("meta"), dict) else {}
    meta = {"title": m.get("title", "")}
    for k in META_TEXT[1:]:
        if raw.get(k) or m.get(k):
            meta[k] = raw.get(k) or m.get(k)
    meta["tags"] = [str(x) for x in raw.get("tags", [])]
    needs = list(m.get("needs", [])) if m.get("kind") == "recipe" else []
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
    if m.get("renamed_from"):
        e["renamed_from"] = list(m["renamed_from"])
    return name, e


def build(checkout, repo, out, serial=None, prev=None, commit=None, ttl_days=14, now=None, assets=True):
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
        pk[name] = e
    doc = {"format": FORMAT, "serial": serial, "generated": stamp(t), "expires": stamp(t + timedelta(days=ttl_days)), "repo": repo, "packages": pk}
    bad = validate(doc)
    if bad:
        raise Problem("; ".join(bad))
    with open(os.path.join(out, "index.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(doc, f, indent=1, sort_keys=True, ensure_ascii=False)
        f.write("\n")
    return doc


def validate(doc, now=None, warnings=None):
    """[text] for an index document. Unknown fields are ignored (a client reads every format it knows)."""
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
        m = e.get("meta")
        if not isinstance(m, dict):
            w("meta is not an object")
            continue
        if not m.get("title"):
            w("meta.title missing")
        for k in META_TEXT[1:]:
            if k in m and not isinstance(m[k], str):
                w(f"meta.{k} is not text")
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
                        int(opt("--ttl-days", 14)), opt("--now"), "--skip-assets" not in rest)
            print(f"serial\t{doc['serial']}\npackages\t{len(doc['packages'])}\nexpires\t{doc['expires']}")
        elif cmd == "validate" and pos:
            with open(pos[0], encoding="utf-8") as f:
                warns = []
                bad = validate(json.load(f), opt("--now"), warns)
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
            bad = validate(doc, opt("--now"), warns)
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
        print(f"error\t{e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(run(sys.argv[1:]))
