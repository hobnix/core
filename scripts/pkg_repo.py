"""Package repositories for scripts/pkg.py (docs/PLAN-packages.md, "Repositories" and "Trust"). Standard library plus `git`.

A repository is a git repository with `index.toml` at its root and one folder per package. A RELEASE is a tag `v<semver>` signed with an SSH
key; only the newest tag whose signature verifies against the repository's allowed-signers file is ever used (never a branch). The index at
that tag says which package versions the release holds:

    [package.arr]
    version = "1.4.0"
    kind = "recipe"
    path = "recipes/arr"
    requires_core = ">=1"

State, all under <state>/packages (root-owned on the server):
    repos.toml            repositories added by a person (name, url, signers or unsigned)
    keys/<name>.signers   the allowed-signers file of an added repository
    repos/<name>/         the local clone (fetched with --tags)
    current/<name>/       the installed package (read-only copy of the folder at the tag; the loaders read this folder)
    previous/<name>@<commit>/   the one before, kept for a rollback until the next update
    installed.toml        version, repo, commit and tag of every applied package
    ../pkg-events/<name>.tsv   the events the package declares (written on install, removed with it)
The two default repositories come from config/package-repos.toml; their allowed signers from config/trusted-keys/<name>.allowed_signers.
"""
import io
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import tomllib

TAG = re.compile(r"^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")
BETA_TAG = re.compile(r"^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)-beta\.([1-9]\d*)$")


def tag_key(t):
    """semver order of a release tag: v1.4.0-beta.2 < v1.4.0"""
    m = TAG.match(t) or BETA_TAG.match(t)
    g = m.groups()
    return (int(g[0]), int(g[1]), int(g[2]), 1, 0) if len(g) == 3 else (int(g[0]), int(g[1]), int(g[2]), 0, int(g[3]))


def beta_allowed(state):
    """the setting updateChannel is beta or edge (docs/PLAN-channels.md: packages have no edge, edge counts as beta)"""
    d = os.environ.get("HS_SETTINGS_DIR") or os.path.join(os.path.dirname(state), "settings")
    try:
        with open(os.path.join(d, "updateChannel"), encoding="utf-8") as f:
            return f.read().strip() in ("beta", "edge")
    except OSError:
        return False
REPO_NAME = re.compile(r"^[a-z][a-z0-9-]{0,40}$")


class Refused(Exception):
    """a reason shown to the person, exit 1"""


def git(*args, cwd=None, input=None):
    r = subprocess.run(["git", *args], cwd=cwd, input=input, capture_output=True)
    if r.returncode != 0:
        raise Refused("git %s: %s" % (args[0], r.stderr.decode("utf-8", "replace").strip().splitlines()[-1:] or "failed"))
    return r.stdout


def git_ok(*args, cwd=None):
    return subprocess.run(["git", *args], cwd=cwd, capture_output=True).returncode == 0


class Repos:
    def __init__(self, pkg):
        self.pkg = pkg
        self.state = pkg.state_dir()

    # ── the list of repositories ──
    def defaults(self):
        f = os.path.join(self.pkg.root(), "config", "package-repos.toml")
        try:
            with open(f, "rb") as fh:
                return [dict(r, default=True) for r in tomllib.load(fh).get("repo", [])]
        except OSError:
            return []

    def added(self):
        try:
            with open(os.path.join(self.state, "repos.toml"), "rb") as fh:
                return [dict(r, default=False) for r in tomllib.load(fh).get("repo", [])]
        except (OSError, tomllib.TOMLDecodeError):
            return []

    def all(self):
        return {r["name"]: r for r in self.defaults() + self.added()}

    def signers(self, r):
        """path of the allowed-signers file, or None (unsigned repository)"""
        if r.get("unsigned"):
            return None
        if r.get("default"):
            return os.path.join(self.pkg.root(), "config", "trusted-keys", r["name"] + ".allowed_signers")
        return os.path.join(self.state, "keys", r["name"] + ".signers")

    def save_added(self, rows):
        os.makedirs(self.state, exist_ok=True)
        f = os.path.join(self.state, "repos.toml")
        with open(f + ".new", "w", encoding="utf-8") as o:
            for r in rows:
                o.write("[[repo]]\nname = %s\nurl = %s\n" % (self.pkg.q(r["name"]), self.pkg.q(r["url"])))
                if r.get("unsigned"):
                    o.write("unsigned = true\n")
                o.write("\n")
        os.replace(f + ".new", f)

    def add(self, name, url, key=None, unsigned=False):
        if not REPO_NAME.match(name):
            raise Refused("the repository name is a lowercase word")
        if name in self.all():
            raise Refused("a repository called %s exists already" % name)
        if not re.match(r"^(https://|ssh://|git@|file://|/|[A-Za-z]:[\/])", url):
            raise Refused("the address must be https://, ssh://, git@host:path or a local path")
        if bool(key) == bool(unsigned):
            raise Refused("give --key <allowed_signers file> (releases must be signed) or --unsigned")
        if key:
            with open(key, encoding="utf-8") as fh:
                text = fh.read()
            if not re.search(r"(ssh-ed25519|ssh-rsa|ecdsa-sha2-\S+|sk-\S+)\s+\S+", text):
                raise Refused("%s holds no SSH public key in allowed-signers format" % key)
            os.makedirs(os.path.join(self.state, "keys"), exist_ok=True)
            shutil.copyfile(key, os.path.join(self.state, "keys", name + ".signers"))
        self.save_added(self.added() + [{"name": name, "url": url, "unsigned": unsigned}])

    def remove(self, name):
        rows = self.added()
        if name not in [r["name"] for r in rows]:
            raise Refused("%s is not a repository that was added (the defaults stay)" % name)
        self.save_added([r for r in rows if r["name"] != name])
        shutil.rmtree(os.path.join(self.state, "repos", name), ignore_errors=True)
        try:
            os.remove(os.path.join(self.state, "keys", name + ".signers"))
        except OSError:
            pass

    # ── git: fetch and verify ──
    def clone_dir(self, name):
        return os.path.join(self.state, "repos", name)

    def fetch(self, r):
        d = self.clone_dir(r["name"])
        if os.path.isdir(os.path.join(d, ".git")) or os.path.isfile(os.path.join(d, "HEAD")):
            git("fetch", "--quiet", "--tags", "--force", "origin", cwd=d)
        else:
            os.makedirs(os.path.dirname(d), exist_ok=True)
            git("clone", "--quiet", "--no-checkout", "--", r["url"], d)
            git("fetch", "--quiet", "--tags", "--force", "origin", cwd=d)

    def tags(self, r):
        d = self.clone_dir(r["name"])
        if not os.path.isdir(d):
            return []
        out = git("tag", "--list", "v*", cwd=d).decode().split()
        beta = beta_allowed(self.state)
        return sorted((t for t in out if TAG.match(t) or (beta and BETA_TAG.match(t))), key=tag_key, reverse=True)

    def verified_tag(self, r):
        """the newest release tag whose signature verifies, as (tag, commit); Refused with the reason when there is none"""
        d = self.clone_dir(r["name"])
        sig = self.signers(r)
        tags = self.tags(r)
        if not tags:
            raise Refused("%s has no release tag (v1.2.3) yet" % r["name"])
        if sig is None:
            t = tags[0]
            return t, git("rev-list", "-n", "1", t, cwd=d).decode().strip()
        if not os.path.isfile(sig):
            raise Refused("%s: no trusted key (%s); the release cannot be verified" % (r["name"], os.path.basename(sig)))
        for t in tags:
            if git_ok("-c", "gpg.format=ssh", "-c", "gpg.ssh.allowedSignersFile=" + sig, "verify-tag", t, cwd=d):
                return t, git("rev-list", "-n", "1", t, cwd=d).decode().strip()
        raise Refused("%s: none of its %d release tags has a valid signature from a trusted key" % (r["name"], len(tags)))

    def index(self, r, tag):
        d = self.clone_dir(r["name"])
        try:
            return tomllib.loads(git("show", tag + ":index.toml", cwd=d).decode("utf-8")).get("package", {})
        except tomllib.TOMLDecodeError as e:
            raise Refused("%s: index.toml is not valid (%s)" % (r["name"], e))

    def fetch_all(self, only=None):
        """-> [(repo, tag, commit, error)] after fetching every repository (or one)"""
        out = []
        for name, r in self.all().items():
            if only and name != only:
                continue
            try:
                self.fetch(r)
                t, c = self.verified_tag(r)
                out.append((name, t, c, ""))
            except Refused as e:
                out.append((name, "", "", str(e)))
        return out

    def catalog(self):
        """{package name: [(repo, entry, tag, commit)]} from the cached clones, newest verified tag each"""
        cat = {}
        for name, r in self.all().items():
            try:
                t, c = self.verified_tag(r)
                for pname, entry in self.index(r, t).items():
                    cat.setdefault(pname, []).append((name, entry, t, c))
            except Refused:
                continue
        return cat

    # ── install ──
    def choose(self, name, repo=None):
        cat = self.catalog().get(name, [])
        if repo:
            cat = [c for c in cat if c[0] == repo]
        if not cat:
            raise Refused("no package %s in the repositories (hs pkg fetch updates them)" % name)
        if len(cat) > 1:
            raise Refused("%s is in %s: name one with --repo (a package name is never shadowed silently)" % (name, ", ".join(c[0] for c in cat)))
        if any(m.get("name") == name and "/current/" not in p.replace("\\", "/") for p, m in self.pkg.manifests()):
            raise Refused("%s is part of this installation already (a built-in package is not replaced by a repository)" % name)
        return cat[0]

    def extract(self, r, tag, path, dest):
        d = self.clone_dir(r["name"])
        if not re.match(r"^[A-Za-z0-9._/-]+$", path) or ".." in path.split("/"):
            raise Refused("%s: the path %r in index.toml is not allowed" % (r["name"], path))
        data = git("archive", "--format=tar", tag + ":" + path, cwd=d)
        os.makedirs(dest)
        with tarfile.open(fileobj=io.BytesIO(data)) as tf:
            for m in tf.getmembers():
                if not (m.isfile() or m.isdir()) or m.name.startswith("/") or ".." in m.name.split("/"):
                    raise Refused("%s: %s is a link or leaves the folder; refused" % (r["name"], m.name))
            tf.extractall(dest)
        for base, dirs, files in os.walk(dest):      # read-only: nothing a user can write is ever run as root
            for n in files:
                p = os.path.join(base, n)
                os.chmod(p, os.stat(p).st_mode & ~(stat.S_IWUSR | stat.S_IWGRP | stat.S_IWOTH))
        for base, dirs, files in os.walk(dest, topdown=False):
            os.chmod(base, os.stat(base).st_mode & ~(stat.S_IWGRP | stat.S_IWOTH))

    def check_entry(self, name, entry, repo):
        pkg = self.pkg
        path = str(entry.get("path", ""))
        if not re.match(r"^[A-Za-z0-9._/-]+$", path) or ".." in path.split("/"):
            raise Refused("%s: the path %r in index.toml is not allowed" % (repo, path))
        if not pkg.NAME.match(name):
            raise Refused("%s: not a package name" % name)
        rq = pkg.REQUIRES.match(str(entry.get("requires_core", "")))
        if not rq:
            raise Refused('%s: requires_core in the index must look like ">=1"' % name)
        if int(rq.group(1)) > pkg.api_level():
            raise Refused("%s needs core API level %s, this one has %d: hs update first" % (name, rq.group(1), pkg.api_level()))
        if not pkg.SEMVER.match(str(entry.get("version", ""))):
            raise Refused("%s: the version in the index is not semver" % name)

    def install(self, name, repo=None):
        r_name, entry, tag, commit = self.choose(name, repo)
        r = self.all()[r_name]
        self.check_entry(name, entry, r_name)
        cur = os.path.join(self.state, "current", name)
        tmp = os.path.join(self.state, "current", ".new-" + name)
        self.rm_quiet(tmp)
        os.makedirs(os.path.dirname(cur), exist_ok=True)
        self.extract(r, tag, entry["path"], tmp)
        with open(os.path.join(tmp, "package.toml"), "rb") as fh:
            m = tomllib.load(fh)
        if m.get("name") != name or m.get("version") != entry["version"]:
            self.rm_quiet(tmp)
            raise Refused("%s: package.toml (name %s, version %s) does not match the index (%s)" % (name, m.get("name"), m.get("version"), entry["version"]))
        rq = self.pkg.REQUIRES.match(str(m.get("requires_core", "")))
        if not rq or int(rq.group(1)) > self.pkg.api_level():
            self.rm_quiet(tmp)
            raise Refused("%s: package.toml says requires_core %r, this server has API level %d: hs update first" % (name, m.get("requires_core"), self.pkg.api_level()))
        for src, v in (("index.toml", entry.get("requires_nix_api")), ("package.toml", m.get("requires_nix_api"))):
            if v is None:
                continue
            if isinstance(v, bool) or not isinstance(v, int) or v < 1:
                self.rm_quiet(tmp)
                raise Refused("%s: requires_nix_api in %s must be a whole number from 1" % (name, src))
            if v > self.pkg.nix_api_level():
                self.rm_quiet(tmp)
                raise Refused("%s: %s says requires_nix_api %d, this core has Nix API level %d: hs update first" % (name, src, v, self.pkg.nix_api_level()))
        ev = self.pkg.pkg_events.manifest_problems(name, m.get("events", []))
        if ev:
            self.rm_quiet(tmp)
            raise Refused("%s: package.toml [[events]]: %s" % (name, ev[0]))
        pm = self.pkg.pkg_perms.manifest_problems(name, m, self.pkg.capability_toml(tmp))
        if pm:
            self.rm_quiet(tmp)
            raise Refused("%s: package.toml permissions: %s" % (name, pm[0]))
        vendored = m.get("kind") == "capability" and bool(m.get("module"))
        if vendored:
            # Nix code from outside the checkout: default repositories only, never a name of the core, only files of its own folder (docs/PLAN-capabilities-repo.md, Q2/Q3)
            problem = None
            if not r.get("default"):
                problem = "has a Nix module, which only the default repositories may ship (%s is an added repository)" % r_name
            elif os.path.isdir(os.path.join(self.pkg.root(), "capabilities", name)):
                problem = "has the name of a capability of the core, which a package does not replace"
            else:
                try:
                    self.pkg_vendor.nix_hashes(tmp)
                except self.pkg_vendor.Refused as e:
                    problem = str(e)
            if problem:
                self.rm_quiet(tmp)
                raise Refused("%s: %s" % (name, problem))
        old = self.pkg.installed().get(name, {})
        if os.path.isdir(cur):
            prev = os.path.join(self.state, "previous")
            os.makedirs(prev, exist_ok=True)
            for x in os.listdir(prev):
                if x.startswith(name + "@"):
                    self.rm(os.path.join(prev, x))
            os.rename(cur, os.path.join(prev, "%s@%s" % (name, old.get("commit", "unknown")[:12])))
            self.keep_previous(name, old, vendored)
        os.rename(tmp, cur)
        if m.get("kind") == "capability":
            if vendored:
                tree = git("rev-parse", "%s:%s" % (tag, entry["path"]), cwd=self.clone_dir(r_name)).decode().strip()
                self.pkg_vendor.vendor(cur, self.nixos_dir(), dict(repo=r_name, tag=tag, commit=commit, tree=tree))
            else:
                self.pkg_vendor.unvendor(name, self.nixos_dir())
        data = self.pkg.installed()
        data[name] = {"version": entry["version"], "repo": r_name, "commit": commit, "tag": tag}
        if "applied" in old:
            data[name]["applied"] = old["applied"]
        self.pkg.save_installed(data)
        try:
            self.pkg.pkg_events.write(name, m.get("events") or [])
        except OSError as e:
            print("%s: its events were not installed: %s" % (name, e), file=sys.stderr)
        self.last_permissions = self.pkg.pkg_perms.of(m)
        return entry["version"], r_name, tag

    def keep_previous(self, name, old, vendored):
        """An update replaced the copy: keep what a rollback needs besides previous/<name>@<commit>: the installed.toml entry, and for a
        vendored package the old lock as vendor/capabilities.lock.previous (docs/PLAN-capabilities-repo.md, Q6)."""
        prev = os.path.join(self.state, "previous")
        with open(os.path.join(prev, name + ".entry.json"), "w", encoding="utf-8") as f:
            json.dump(old, f)
        lock = self.pkg_vendor.lock_file(self.nixos_dir())
        if vendored and os.path.isfile(lock):
            shutil.copyfile(lock, lock + ".previous")

    def previous_copy(self, name):
        """-> (folder, entry dict) of the kept previous copy, or raises Refused"""
        prev = os.path.join(self.state, "previous")
        found = sorted(x for x in os.listdir(prev) if x.startswith(name + "@")) if os.path.isdir(prev) else []
        if not found:
            raise Refused("%s has no previous copy to put back" % name)
        try:
            with open(os.path.join(prev, name + ".entry.json"), encoding="utf-8") as f:
                entry = json.load(f)
        except (OSError, ValueError):
            entry = {}
        return os.path.join(prev, found[0]), entry

    def rollback_plan(self, name):
        """-> (from version, to version): what `rollback` would do"""
        folder, entry = self.previous_copy(name)
        have = self.pkg.installed().get(name, {})
        return have.get("version", "-"), entry.get("version") or self.manifest_version(folder)

    @staticmethod
    def manifest_version(folder):
        try:
            with open(os.path.join(folder, "package.toml"), "rb") as f:
                return str(tomllib.load(f).get("version", "-"))
        except (OSError, tomllib.TOMLDecodeError):
            return "-"

    def rollback(self, name):
        """Put the previous copy and the old lock back (the update broke the rebuild). The kept copy is consumed."""
        folder, entry = self.previous_copy(name)
        if not os.path.isdir(os.path.join(self.state, "current", name)):
            raise Refused("%s was not installed from a repository" % name)
        with open(os.path.join(folder, "package.toml"), "rb") as f:
            m = tomllib.load(f)
        cur = os.path.join(self.state, "current", name)
        self.rm(cur)
        os.rename(folder, cur)
        lock_path = self.pkg_vendor.lock_file(self.nixos_dir())
        if m.get("kind") == "capability" and m.get("module"):
            oldlock = {}
            try:
                with open(lock_path + ".previous", "rb") as f:
                    oldlock = tomllib.load(f).get(name, {})
            except (OSError, tomllib.TOMLDecodeError):
                pass
            self.pkg_vendor.vendor(cur, self.nixos_dir(), {k: oldlock.get(k) or entry.get(k) for k in ("repo", "tag", "commit", "tree")})
            try:
                os.remove(lock_path + ".previous")
            except OSError:
                pass
        data = self.pkg.installed()
        back = dict(entry) if entry.get("version") else {"version": m.get("version"), "repo": data.get(name, {}).get("repo", "")}
        if "applied" in data.get(name, {}) and "applied" not in back:
            back["applied"] = data[name]["applied"]
        data[name] = back
        self.pkg.save_installed(data)
        try:
            os.remove(os.path.join(self.state, "previous", name + ".entry.json"))
        except OSError:
            pass
        return back.get("version")

    def rollback_candidates(self):
        """[(name, version now, version before)] for every vendored package whose entry in the lock differs from vendor/capabilities.lock.previous."""
        lock = self.pkg_vendor.lock_file(self.nixos_dir())
        try:
            with open(lock + ".previous", "rb") as f:
                before = tomllib.load(f)
        except (OSError, tomllib.TOMLDecodeError):
            return []
        now = self.pkg_vendor.read_lock(self.nixos_dir())
        out = []
        for n in sorted(now):
            if n in before and now[n].get("commit") != before[n].get("commit"):
                try:
                    self.previous_copy(n)
                except Refused:
                    continue
                out.append((n, str(now[n].get("version", "-")), str(before[n].get("version", "-"))))
        return out

    def installed_permissions(self, name):
        """The permissions of the installed copy (None = not declared, or not installed)."""
        try:
            with open(os.path.join(self.state, "current", name, "package.toml"), "rb") as f:
                return self.pkg.pkg_perms.of(tomllib.load(f))
        except (OSError, tomllib.TOMLDecodeError):
            return None

    def new_permissions(self, name, commit):
        """The permissions the release `commit` declares: (declared list or None, the ones the installed copy lacks)."""
        r_name, entry, _, _ = self.choose_installed(name, self.recorded(name)["repo"])
        raw = git("show", "%s:%s/package.toml" % (commit, entry["path"]), cwd=self.clone_dir(r_name))
        new = self.pkg.pkg_perms.of(tomllib.loads(raw.decode("utf-8", "replace")))
        return new, self.pkg.pkg_perms.added(self.installed_permissions(name), new)

    @property
    def pkg_vendor(self):
        return self.pkg.pkg_vendor

    @staticmethod
    def nixos_dir():
        """The checkout that vendor/ lives in (HS_NIXOS_DIR, default /etc/nixos)."""
        return os.environ.get("HS_NIXOS_DIR", "/etc/nixos")

    @staticmethod
    def rm(path):
        def onerr(fn, p, _):
            os.chmod(p, stat.S_IRWXU)
            fn(p)
        shutil.rmtree(path, onerror=onerr)

    @classmethod
    def rm_quiet(cls, path):
        """Remove a folder if it exists; read-only files too (a refused install leaves one behind, and on Windows a plain rmtree keeps it)."""
        if os.path.lexists(path):
            cls.rm(path)

    def recorded(self, name):
        """installed.toml's entry for a package that sits in current/; an entry without repo (written by the old `hs recipe` record, which
        dropped repo, commit and tag) gets the repository that lists the package when exactly one does"""
        have = dict(self.pkg.installed().get(name, {}))
        if "repo" not in have and os.path.isdir(os.path.join(self.state, "current", name)):
            repos = [c[0] for c in self.catalog().get(name, [])]
            if len(repos) == 1:
                have["repo"] = repos[0]
        if "repo" not in have:
            raise Refused("%s was not installed from a repository" % name)
        return have

    def remove_package(self, name):
        data = self.pkg.installed()
        cur = os.path.join(self.state, "current", name)
        if not os.path.isdir(cur):
            raise Refused("%s was not installed from a repository" % name)
        self.rm(cur)
        self.pkg_vendor.unvendor(name, self.nixos_dir())
        self.pkg.pkg_events.remove(name)
        data.pop(name, None)
        self.pkg.save_installed(data)

    # ── update ──
    def diff(self, name):
        """-> (old commit, new tag, new commit, diff text) or None when the installed package is current"""
        have = self.recorded(name)
        r_name, entry, tag, commit = self.choose_installed(name, have["repo"])
        self.check_entry(name, entry, r_name)
        if commit == have.get("commit"):
            return None
        ev, hv, ht = self.pkg.semver_key(entry["version"]), self.pkg.semver_key(have["version"]), have.get("tag", "")
        # same version under a newer tag: a beta that became the release
        if not (ev > hv or (ev == hv and (TAG.match(ht) or BETA_TAG.match(ht)) and tag_key(tag) > tag_key(ht))):
            return None
        d = self.clone_dir(r_name)
        # no recorded commit (see recorded): show the whole new package against the empty tree
        old = have.get("commit") or "4b825dc642cb6eb9a060e54bf8d69288fbee4904"
        text = git("diff", "--stat", "-p", old, commit, "--", entry["path"], cwd=d).decode("utf-8", "replace")
        return old, tag, commit, text

    def choose_installed(self, name, repo):
        cat = [c for c in self.catalog().get(name, []) if c[0] == repo]
        if not cat:
            raise Refused("%s is not in %s any more" % (name, repo))
        return cat[0]


def run(pkg, cmd, rest):
    """the commands of pkg.py that need a repository; returns the exit code"""
    R = Repos(pkg)
    try:
        if cmd == "repo":
            sub = rest[0] if rest else "list"
            if sub == "list":
                for n, r in R.all().items():
                    print("\t".join([n, r["url"], "unsigned" if r.get("unsigned") else "signed", "default" if r.get("default") else "added"]))
            elif sub == "add":
                key = rest[rest.index("--key") + 1] if "--key" in rest else None
                R.add(rest[1], rest[2], key=key, unsigned="--unsigned" in rest)
            elif sub == "remove":
                R.remove(rest[1])
            else:
                raise Refused("repo list | add <name> <url> (--key <file> | --unsigned) | remove <name>")
        elif cmd == "fetch":
            bad = 0
            for name, tag, commit, err in R.fetch_all(rest[0] if rest else None):
                print("\t".join([name, tag or "-", commit[:12] or "-", err or "ok"]))
                bad += bool(err)
            return 1 if bad else 0
        elif cmd == "available":
            have = pkg.installed()
            for pname, rows in sorted(R.catalog().items()):
                for r_name, e, tag, _ in rows:
                    print("\t".join([r_name, pname, e.get("kind", "?"), str(e.get("version")), have.get(pname, {}).get("version", "-")]))
        elif cmd == "market":
            # everything a person can install, as data (hs sys pkg market): package, kind, repository, available version, installed version
            # (- = no copy in current/), state (new|current|update|waits|orphan), core (yes|no), audience, title. A package of a repository that
            # is gone (or no longer lists it) is an orphan: its copy stays until `hs pkg remove`.
            have = pkg.installed()
            cur = os.path.join(R.state, "current")
            seen = set()
            for pname, rows in sorted(R.catalog().items()):
                for r_name, e, tag, _ in rows:
                    ver = str(e.get("version"))
                    inst = "-"
                    if os.path.isdir(os.path.join(cur, pname)):
                        inst = str(have.get(pname, {}).get("version", "?"))
                    if inst == "-":
                        state = "new"
                    elif inst == ver:
                        state = "current"
                    else:
                        try:
                            state = "update" if pkg.semver_key(ver) > pkg.semver_key(inst) else "current"
                        except ValueError:
                            state = "update"
                    if state in ("new", "update") and pkg.waits_for(e):
                        state = "waits"   # a release whose needs this core does not meet: shown, not installable (hs update first)
                    seen.add(pname)
                    print("	".join([pname, e.get("kind", "?"), r_name, ver, inst, state, "yes" if e.get("core") else "no",
                                     e.get("audience", "generic"), (e.get("title") or "-").replace("	", " ")]))
            if os.path.isdir(cur):
                for pname in sorted(os.listdir(cur)):
                    if pname in seen or pname.startswith("."):
                        continue
                    print("	".join([pname, "?", have.get(pname, {}).get("repo", "-"), "-", str(have.get(pname, {}).get("version", "?")), "orphan", "no", "-", "-"]))
        elif cmd == "install" and rest and rest[0] == "--core":
            # the packages the core refers to by name (`core = true` in the index) and the ones applied here: fetch what is neither built in nor installed yet
            bad = 0
            for name, tag, commit, err in R.fetch_all():
                bad += bool(err)
                if err:
                    print("%s: %s" % (name, err), file=sys.stderr)
            # wanted: the core packages and every recipe already applied on this server (installed.toml also holds the versions `hs recipe`
            # recorded before packages came from a repository); there: its folder in current/ or a built-in one
            applied = pkg.installed()
            builtin = {m.get("name") for p, m in pkg.manifests() if "/current/" not in p.replace("\\", "/")}
            for pname, rows in sorted(R.catalog().items()):
                there = os.path.isdir(os.path.join(R.state, "current", pname)) or pname in builtin
                if there or not (rows[0][1].get("core") or pname in applied):
                    continue
                try:
                    v, r_name, tag = R.install(pname, rows[0][0])
                    print("%s %s from %s (%s)" % (pname, v, r_name, tag))
                except Refused as e:
                    bad += 1
                    print("%s: %s" % (pname, e), file=sys.stderr)
            return 1 if bad else 0
        elif cmd == "install":
            repo = rest[rest.index("--repo") + 1] if "--repo" in rest else None
            v, r_name, tag = R.install(rest[0], repo)
            print("%s %s from %s (%s)" % (rest[0], v, r_name, tag))
            print("permissions it declares (not enforced, it runs as root): %s" % pkg.pkg_perms.describe(R.last_permissions))
        elif cmd == "update":
            res = R.diff(rest[0])
            if res is None:
                print("current")
                return 0
            old, tag, commit, text = res
            print(text)
            new, fresh = R.new_permissions(rest[0], commit)
            print("permissions it declares (not enforced, it runs as root): %s" % pkg.pkg_perms.describe(new))
            if fresh:
                print("NEW permissions compared with the installed version: %s" % ", ".join(fresh))
                if "--accept-permissions" not in rest:
                    if not sys.stdin.isatty():
                        raise Refused("this update asks for new permissions: read them above and run again with --accept-permissions")
                    if input("Type the package name %s to accept them: " % rest[0]).strip() != rest[0]:
                        raise Refused("not installed: the new permissions were not accepted")
            if "--yes" not in rest and not (fresh and sys.stdin.isatty()):
                if not sys.stdin.isatty():
                    raise Refused("an update changes code that runs as root: read the diff above and run again with --yes")
                if input("Install %s? [y/N] " % tag).strip().lower() not in ("y", "yes"):
                    raise Refused("not installed")
            v, r_name, tag = R.install(rest[0], R.recorded(rest[0])["repo"])
            print("%s %s from %s (%s)" % (rest[0], v, r_name, tag))
        elif cmd == "rollback":
            # rollback <name> --plan: "name TAB from TAB to" | rollback <name>: put the previous copy and lock back (the caller asked first)
            if "--plan" in rest:
                a, b = R.rollback_plan(rest[0])
                print("\t".join([rest[0], a, b]))
            else:
                print("%s %s" % (rest[0], R.rollback(rest[0])))
        elif cmd == "rollback-candidates":
            # the vendored packages whose lock line differs from the kept old lock: name TAB now TAB before
            for n, a, b in R.rollback_candidates():
                print("\t".join([n, a, b]))
        elif cmd == "remove":
            R.remove_package(rest[0])
        else:
            return 2
    except Refused as e:
        print(str(e), file=sys.stderr)
        return 1
    except IndexError:
        print("missing argument", file=sys.stderr)
        return 1
    return 0
