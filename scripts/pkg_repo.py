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
A repository that has an `index` address (docs/PLAN-registry.md) is read the other way: the signed index.json (and index.json.sig beside it) is
fetched, verified against the allowed signers (namespace hobnix-index), checked for serial (never lower than the one kept) and kept in
    index/<name>/live/index.json (+ .sig)   the last accepted index (as one pair; .old while a swap is interrupted); the version of a package is the one in it, not a release tag
    index/<name>/serial   the serial floor (serial and sha256), written before the swap and never removed by it; .lock = the fetch lock
    index-cache/<name>/   the package folders of the index commits whose tree hash was checked (read by the web without git or hashing again)
The commit of an entry is fetched into repos/<name>/ (by `hs pkg fetch`; a read never runs git clone or fetch) and its tree is checked against the entry's `tree` hash before anything is installed.
A repository without `index` keeps the signed release tags. The tag shown for an index package is `v<version>-<8 hex of the commit><8 hex of the tree hash>` (the shape stays).
The two default repositories come from config/package-repos.toml; their allowed signers from config/trusted-keys/<name>.allowed_signers.
"""
import atexit
import contextlib
import hashlib
import importlib.util
import io
import json
import os
import re
import shutil
import stat
import signal
import subprocess
import sys
import tarfile
import tempfile
import time
import tomllib
import urllib.request
from datetime import timedelta

try:
    import fcntl
except ImportError:         # Windows (development only): no lock
    fcntl = None

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
MAX_INDEX = 20 * 1024 * 1024
CACHE_KEEP_SECONDS = 600   # prune leaves a cached folder alone that was created or read this recently
GIT_TIMEOUT = 180          # seconds for one git call (as HS_INSTALL_FETCH_TIMEOUT in scripts/lib/checkout.sh)
# The longest a fetch holds the lock: the index (two loads of 30 s at most) + clone + fetch (2 x GIT_TIMEOUT) + all fetches of commits by id together
# (one more GIT_TIMEOUT, see fetch_index) = 3 x GIT_TIMEOUT + 60 s. A fetch or install that waits for the lock waits that long (HS_PKG_LOCK_WAIT sets it).
LOCK_FACTOR = 3
GRACE_DAYS = 7          # an expired index keeps working; the warning starts this long after `expires`
EMPTY_TREE = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"


def clean_text(s, keep_ws=False):
    """The one place a text that may come from a package is made safe to print: C0 (tab and newline kept with keep_ws), DEL, C1 (U+0085)
    and the line and paragraph separators U+2028/U+2029 become ?. Every refusal passes through it (Refused), so install, update and
    install --core show the same text."""
    return re.sub("[\\x00-\\x08\\x0b-\\x1f\\x7f-\\x9f\\u2028\\u2029" + ("" if keep_ws else "\\t\\n") + "]", "?", str(s))


class Refused(Exception):
    """a reason shown to the person, exit 1; `code` (scripts/lib/error-codes.tsv) is printed as a machine line after it"""

    def __init__(self, text, code=None):
        super().__init__(clean_text(text, True))
        self.code = code


def git_limit():
    try:
        return float(os.environ.get("HS_PKG_GIT_TIMEOUT") or GIT_TIMEOUT)
    except ValueError:
        return GIT_TIMEOUT


def ssh_configured():
    """the person set core.sshCommand in a git configuration: ours is not put over it"""
    if not hasattr(ssh_configured, "v"):
        r = subprocess.run(["git", "config", "--get", "core.sshCommand"], capture_output=True)
        ssh_configured.v = r.returncode == 0 and bool(r.stdout.strip())
    return ssh_configured.v


def git_run(args, cwd=None, input=None, limit=None):
    """run git without a terminal prompt (like scripts/lib/checkout.sh) and with a time limit (HS_PKG_GIT_TIMEOUT, default 180 s): a stalled remote
    is killed with its helpers, so a lock held around it is always released. -> CompletedProcess; Refused on a timeout"""
    env = dict(os.environ, GIT_TERMINAL_PROMPT="0", GIT_ASKPASS="true")
    # a fetch that outlives its caller (the caller was killed) ends by itself: it is its own session, so no signal of the caller reaches it
    env.setdefault("GIT_HTTP_LOW_SPEED_LIMIT", "1000")
    env.setdefault("GIT_HTTP_LOW_SPEED_TIME", "60")
    if "GIT_SSH_COMMAND" not in env and "GIT_SSH" not in env and not ssh_configured():
        env["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes -o ConnectTimeout=30 -o ServerAliveInterval=15 -o ServerAliveCountMax=4"
    limit = git_limit() if limit is None else limit
    p = subprocess.Popen(["git", *args], cwd=cwd, env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                         start_new_session=hasattr(os, "killpg"))
    try:
        out, err = p.communicate(input, timeout=limit)
    except subprocess.TimeoutExpired:
        try:
            if hasattr(os, "killpg"):
                os.killpg(p.pid, signal.SIGKILL)
            else:
                p.kill()
        except OSError:
            p.kill()
        p.communicate()
        raise Refused("git %s timed out after %d s (the remote does not answer)" % (args[0], limit))
    return subprocess.CompletedProcess(p.args, p.returncode, out, err)


def git(*args, cwd=None, input=None):
    r = git_run(args, cwd=cwd, input=input)
    if r.returncode != 0:
        raise Refused("git %s: %s" % (args[0], r.stderr.decode("utf-8", "replace").strip().splitlines()[-1:] or "failed"))
    return r.stdout


def git_ok(*args, cwd=None, limit=None):
    try:
        return git_run(args, cwd=cwd, limit=limit).returncode == 0
    except Refused:
        return False


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
                if r.get("index"):
                    o.write("index = %s\n" % self.pkg.q(r["index"]))
                o.write("\n")
        os.replace(f + ".new", f)

    def add(self, name, url, key=None, unsigned=False, index=None):
        if not REPO_NAME.match(name):
            raise Refused("the repository name is a lowercase word")
        if name in self.all():
            raise Refused("a repository called %s exists already" % name)
        for d in self.defaults():
            if name in (d.get("replaces") or []):
                raise Refused("the name %s belongs to the default repository %s, which took over the old repository of that name: pick another name" % (name, d["name"]))
        if not re.match(r"^(https://|ssh://|git@|file://|/|[A-Za-z]:[\/])", url):
            raise Refused("the address must be https://, ssh://, git@host:path or a local path")
        if index and not re.match(r"^(https://|file://|/|[A-Za-z]:[\/])", index):
            raise Refused("the index address must be https:// or a local path")
        if key and not os.path.isfile(key):
            raise Refused("the key file %s does not exist" % key)
        if index and not unsigned and key:
            try:
                with open(key, encoding="utf-8") as fh:
                    has_ns = re.search(r'namespaces="[^"]*\bhobnix-index\b', fh.read())
            except (OSError, ValueError) as e:
                raise Refused("the key file %s cannot be read: %s" % (key, e))
            if not has_ns:
                raise Refused('the key file has no line with namespaces="hobnix-index": a key that signs git tags does not sign indexes')
        if index and unsigned:
            raise Refused("a signed index needs --key <allowed_signers file>, not --unsigned")
        if bool(key) == bool(unsigned):
            raise Refused("give --key <allowed_signers file> (releases must be signed) or --unsigned")
        if key:
            try:
                with open(key, encoding="utf-8") as fh:
                    text = fh.read()
            except (OSError, ValueError) as e:
                raise Refused("the key file %s cannot be read: %s" % (key, e))
            if not re.search(r"(ssh-ed25519|ssh-rsa|ecdsa-sha2-\S+|sk-\S+)\s+\S+", text):
                raise Refused("%s holds no SSH public key in allowed-signers format" % key)
            os.makedirs(os.path.join(self.state, "keys"), exist_ok=True)
            shutil.copyfile(key, os.path.join(self.state, "keys", name + ".signers"))
        self.save_added(self.added() + [dict(name=name, url=url, unsigned=unsigned, **({"index": index} if index else {}))])

    def remove(self, name):
        rows = self.added()
        if name not in [r["name"] for r in rows]:
            raise Refused("%s is not a repository that was added (the defaults stay)" % name)
        self.save_added([r for r in rows if r["name"] != name])
        shutil.rmtree(os.path.join(self.state, "repos", name), ignore_errors=True)
        shutil.rmtree(os.path.join(self.state, "index", name), ignore_errors=True)
        self.rm_quiet(os.path.join(self.state, "index-cache", name))
        try:
            os.remove(os.path.join(self.state, "keys", name + ".signers"))
        except OSError:
            pass

    # ── git: fetch and verify ──
    def clone_dir(self, name):
        return os.path.join(self.state, "repos", name)

    def fetch(self, r):
        d = self.clone_dir(r["name"])
        if os.path.isdir(d) and os.path.isdir(os.path.join(d, ".git")) or os.path.isfile(os.path.join(d, "HEAD")):
            # a clone of another address (a repository of that name was removed and the name is used again): never reused
            have = git_run(["config", "--get", "remote.origin.url"], cwd=d).stdout
            have = have.decode("utf-8", "replace").strip() if isinstance(have, bytes) else str(have).strip()
            if have != r["url"]:
                shutil.rmtree(d, ignore_errors=True)
        if os.path.isdir(os.path.join(d, ".git")) or os.path.isfile(os.path.join(d, "HEAD")):
            git("fetch", "--quiet", "--tags", "--force", "origin", cwd=d)
        else:
            os.makedirs(os.path.dirname(d), exist_ok=True)
            git("clone", "--quiet", "--no-checkout", "--", r["url"], d)
            git("fetch", "--quiet", "--tags", "--force", "origin", cwd=d)

    # ── the signed index (docs/PLAN-registry.md) ──
    @property
    def pkg_index(self):
        if not hasattr(self, "_pi"):
            spec = importlib.util.spec_from_file_location("pkg_index", os.path.join(self.pkg.HERE, "lib", "pkg_index.py"))
            self._pi = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(self._pi)
        return self._pi

    def index_dir(self, name):
        return os.path.join(self.state, "index", name)

    def live_dir(self, name):
        """the folder holding the accepted index.json and its .sig as one pair; after a crash in the swap the kept old pair is still readable"""
        d = self.index_dir(name)
        live, old = os.path.join(d, "live"), os.path.join(d, ".old")
        return live if os.path.isdir(live) or not os.path.isdir(old) else old

    @staticmethod
    def load_from(src, dest):
        """copy an https:// address or a local path to dest (at most MAX_INDEX bytes)"""
        if src.startswith("https://"):
            try:
                with urllib.request.urlopen(urllib.request.Request(src, headers={"User-Agent": "hs-pkg"}), timeout=30) as resp:
                    data = resp.read(MAX_INDEX + 1)
            except (OSError, ValueError) as e:
                raise Refused("could not fetch %s: %s" % (src, e))
        else:
            try:
                with open(src[7:] if src.startswith("file://") else src, "rb") as f:
                    data = f.read(MAX_INDEX + 1)
            except OSError as e:
                raise Refused("could not read %s: %s" % (src, e))
        if len(data) > MAX_INDEX:
            raise Refused("%s is larger than %d MB" % (src, MAX_INDEX // 1048576))
        with open(dest, "wb") as o:
            o.write(data)

    def signers_file(self, r):
        sig = self.signers(r)
        if sig is None or not os.path.isfile(sig):
            raise Refused("%s: no trusted key (%s); the index cannot be verified" % (r["name"], os.path.basename(sig or "--key")))
        return sig

    def checked_index(self, r, path):
        """the document of the index at `path` after its signature (first) and its schema; Refused with the reason"""
        pi = self.pkg_index
        try:
            pi.verify_signature(path, self.signers_file(r))
            with open(path, encoding="utf-8") as f:
                doc = json.load(f)
        except (pi.Problem, OSError, ValueError) as e:
            raise Refused("%s: the index is refused: %s" % (r["name"], e))
        bad = pi.validate(doc)
        if bad:
            raise Refused("%s: the index is refused: %s" % (r["name"], "; ".join(bad[:3])))
        if doc.get("repo") != r["name"]:      # another repository's signed index served under this address (the same CI key may sign both)
            raise Refused("%s: the index is refused: it is the index of %r, not of %s (add the repository under the name its index has)" % (r["name"], doc.get("repo"), r["name"]))
        return doc

    def floor_file(self, name):
        return os.path.join(self.index_dir(name), "serial")

    def read_floor(self, name):
        """(serial, sha256 of that index.json) kept in the separate floor file; None when there is none; False when the file is damaged"""
        try:
            with open(self.floor_file(name), encoding="utf-8") as f:
                s, h = f.read().split()
            return int(s), h
        except FileNotFoundError:
            return None
        except (OSError, ValueError):
            return False

    def write_floor(self, name, doc, path):
        """the serial floor, written (and synced) before the swap and never removed by it: a crash in the swap cannot lose it"""
        with open(path, "rb") as f:
            digest = hashlib.sha256(f.read()).hexdigest()
        ff = self.floor_file(name)
        with open(ff + ".new", "w", encoding="utf-8") as o:
            o.write("%d %s\n" % (doc["serial"], digest))
            o.flush()
            os.fsync(o.fileno())
        os.replace(ff + ".new", ff)

    @contextlib.contextmanager
    def locked(self, name):
        """the one lock of a repository (index/<name>/.lock) around everything that may write the index or run git clone/fetch. Waits at most
        HS_PKG_LOCK_WAIT seconds, then Refused "another pkg fetch is running"; flock is released when the process ends. Re-entrant in this process."""
        held = self.__dict__.setdefault("_held", set())
        if name in held:
            yield
            return
        os.makedirs(self.index_dir(name), exist_ok=True)
        f = open(os.path.join(self.index_dir(name), ".lock"), "w")
        try:
            if fcntl:
                try:
                    wait = float(os.environ.get("HS_PKG_LOCK_WAIT") or LOCK_FACTOR * git_limit() + 60)
                except ValueError:
                    wait = LOCK_FACTOR * git_limit() + 60
                end = time.monotonic() + wait
                while True:
                    try:
                        fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
                        break
                    except OSError:
                        if time.monotonic() >= end:
                            raise Refused("%s: another pkg fetch is running (waited %d s); try again in a minute" % (name, wait))
                        time.sleep(0.2)
            held.add(name)
            try:
                yield
            finally:
                held.discard(name)
        finally:
            f.close()

    def fetch_index(self, r):
        """fetch index.json and its signature, keep them only when signature, schema and serial are right; returns the document"""
        name = r["name"]
        with self.locked(name):
            doc = self.fetch_index_locked(r)
            self.fetch(r)       # once per run: the clone and the commits the index names, so reads of the web never run git clone or fetch
            d = self.clone_dir(name)
            missing = {}
            end = time.monotonic() + git_limit()        # all fetches by id together: the lock is held for a known time at most
            for pname, e in doc["packages"].items():
                sha = e["commit"]
                if git_ok("cat-file", "-e", sha + "^{commit}", cwd=d):
                    continue
                left = end - time.monotonic()
                if left > 0:    # a commit no branch or tag reaches any more is fetched by its id
                    git_ok("fetch", "--quiet", "origin", sha, cwd=d, limit=left)
                if not git_ok("cat-file", "-e", sha + "^{commit}", cwd=d):
                    missing[pname] = [sha, "the commit %s cannot be fetched from %s%s" % (sha[:12], r["url"], "" if left > 0 else " (time used up; the next fetch tries again)")]
            self.write_unfetchable(name, missing)
            for pname, (sha, why) in sorted(missing.items()):
                print("warning: %s: %s is not available: %s" % (name, pname, why), file=sys.stderr)
            return doc

    def unfetchable_file(self, name):
        return os.path.join(self.index_dir(name), "unfetchable.json")

    def unfetchable(self, name):
        """{package: [commit, reason]} of the packages whose pinned commit the last fetch could not get (they are not available)"""
        try:
            with open(self.unfetchable_file(name), encoding="utf-8") as f:
                d = json.load(f)
            return d if isinstance(d, dict) else {}
        except (OSError, ValueError):
            return {}

    def write_unfetchable(self, name, missing):
        f = self.unfetchable_file(name)
        try:
            if not missing:
                self.rm_quiet(f)
                return
            with open(f + ".new", "w", encoding="utf-8") as o:
                json.dump(missing, o)
            os.replace(f + ".new", f)
        except OSError:
            pass

    def fetch_index_locked(self, r):
        pi = self.pkg_index
        name = r["name"]
        d = self.index_dir(name)
        new = os.path.join(d, ".new")
        self.rm_quiet(new)
        os.makedirs(new)
        try:
            self.load_from(r["index"], os.path.join(new, "index.json"))
            self.load_from(r["index"] + ".sig", os.path.join(new, "index.json.sig"))
            doc = self.checked_index(r, os.path.join(new, "index.json"))
            try:
                with open(os.path.join(self.live_dir(name), "index.json"), encoding="utf-8") as f:
                    old = json.load(f)
            except (OSError, ValueError):
                old = None
            why = pi.check_serial(doc, old) if old else None
            floor = self.read_floor(name)
            if floor is False:      # fail closed: without a readable floor and a kept pair an older signed index could not be told apart
                if old is None:
                    raise Refused("%s: the serial floor file %s is damaged and no kept index remains to check against; nothing was changed. "
                                  "Delete that file by hand (rm %s) to accept the current index as the first one; this works for the default repositories too" % (name, self.floor_file(name), self.floor_file(name)))
                floor = None
            if not why and floor:       # the floor outlives the pair: with live and .old gone an older signed index is still refused
                with open(os.path.join(new, "index.json"), "rb") as f:
                    digest = hashlib.sha256(f.read()).hexdigest()
                if doc["serial"] < floor[0]:
                    why = "serial %d is below the one already seen (%d)" % (doc["serial"], floor[0])
                elif doc["serial"] == floor[0] and digest != floor[1]:
                    why = "serial %d was already used for a different index" % doc["serial"]
            if why:
                raise Refused("%s: the index is refused: %s (no rollback to an older index)" % (name, why))
            try:
                self.write_floor(name, doc, os.path.join(new, "index.json"))
            except OSError as e:
                raise Refused("%s: the serial floor cannot be written (%s); nothing was changed" % (name, e))
            live, prev = os.path.join(d, "live"), os.path.join(d, ".old")
            if os.path.isdir(live):
                self.rm_quiet(prev)
                os.rename(live, prev)       # a crash here leaves .old, which live_dir still reads
            os.rename(new, live)            # .old is not removed before live exists again: it may be the only kept pair
            self.rm_quiet(prev)
        finally:
            self.rm_quiet(new)
        self._idx = {}
        self.prune_cache(name, doc)
        if pi.now_utc() > pi.now_utc(doc["expires"]) + timedelta(days=GRACE_DAYS):
            print("warning: the index of %s expired on %s" % (name, doc["expires"]), file=sys.stderr)
        return doc

    def read_index(self, r):
        """the kept index of a repository, its signature checked again; Refused when there is none or it does not verify"""
        memo = self.__dict__.setdefault("_idx", {})
        if r["name"] not in memo:
            path = os.path.join(self.live_dir(r["name"]), "index.json")
            if not os.path.isfile(path):
                raise Refused("%s: no index yet (hs pkg fetch)" % r["name"])
            memo[r["name"]] = self.checked_index(r, path)
        return memo[r["name"]]

    @staticmethod
    def index_tag(entry):
        """v<version>-<8 of the commit><8 of the tree hash>: a plan made for this tag is only ever installed as these files (the tag shape of the web job allows it)"""
        return "v%s-%s%s" % (entry["version"], entry["commit"][:8], entry["tree"][7:15])

    def index_entries(self, r, with_unavailable=False):
        """{package: entry} of an index repository: the index entry plus what the rest of the code reads from a release entry. A package whose
        commit could not be fetched is left out, or (with_unavailable) kept with `_unavailable` = the reason: never offered, but still known"""
        out = {}
        bad = self.unfetchable(r["name"])
        for n, e in self.read_index(r)["packages"].items():
            extra = {}
            if n in bad and bad[n][0] == e["commit"]:
                if not with_unavailable:
                    continue
                extra = {"_unavailable": "its commit could not be fetched: %s" % bad[n][1]}
            out[n] = dict(e, _index=True, title=(e.get("meta") or {}).get("title", ""), **extra)
        return out

    def ensure_commit(self, r, sha, fetch=True):
        """the pinned commit is in the clone (fetched when it is not, unless fetch=False: a read of the web never runs git clone or fetch); Refused otherwise"""
        d = self.clone_dir(r["name"])
        have = lambda: os.path.isdir(d) and git_ok("cat-file", "-e", sha + "^{commit}", cwd=d)
        if have():
            return
        if not fetch:
            raise Refused("%s: the commit %s is not in the local clone yet (hs pkg fetch)" % (r["name"], sha[:12]))
        with self.locked(r["name"]):        # no second git fetch beside a running pkg fetch ("cannot lock ref")
            if have():
                return
            self.fetch(r)
            if not have():
                git_ok("fetch", "--quiet", "origin", sha, cwd=d)
            if not have():
                raise Refused("%s: the commit %s of the index is not in the repository" % (r["name"], sha[:12]))

    def verified_dir(self, r_name, entry):
        """a temporary folder with the package at the pinned commit, tree hash checked (for reading files before an install)"""
        memo = self.__dict__.setdefault("_vd", {})
        key = (r_name, entry["commit"], entry["path"])
        if key not in memo:
            r = self.all()[r_name]
            cached = self.cache_path(r_name, entry)
            if self.cache_valid(cached, entry):
                memo[key] = os.path.join(cached, "pkg")
                return memo[key]
            self.ensure_commit(r, entry["commit"], fetch=False)
            try:        # beside the cache so the finished folder is renamed into place
                os.makedirs(os.path.dirname(cached), exist_ok=True)
                tmp = tempfile.mkdtemp(prefix=".tmp-", dir=os.path.dirname(cached))
            except OSError:
                tmp = tempfile.mkdtemp(prefix="hs-pkg-")
            atexit.register(self.rm_quiet, tmp)
            self.extract(r, entry["commit"], entry["path"], os.path.join(tmp, "pkg"), entry["tree"])
            memo[key] = os.path.join(tmp, "pkg")
            self.cache_store(cached, tmp, entry)
            if os.path.isdir(os.path.join(cached, "pkg")):
                memo[key] = os.path.join(cached, "pkg")
        return memo[key]

    # the checked folders of the index packages, kept per commit: a read of the web does not archive and hash every capability again.
    # The folder is only written after its tree hash matched the signed index; the marker holds that hash, a different entry is never served from it.
    def cache_path(self, r_name, entry):
        return os.path.join(self.state, "index-cache", r_name, "%s-%s" % (entry["commit"], hashlib.sha256(entry["path"].encode()).hexdigest()[:12]))

    @staticmethod
    def cache_valid(path, entry):
        try:
            with open(os.path.join(path, "tree"), encoding="utf-8") as f:
                ok = f.read().strip() == entry["tree"] and os.path.isdir(os.path.join(path, "pkg"))
            if ok:
                os.utime(path)      # used now: prune keeps it
            return ok
        except OSError:
            return False

    def cache_store(self, cached, tmp, entry):
        """move the checked folder `tmp`/pkg to `cached` (atomic rename); a state folder that cannot be written just means no cache"""
        try:
            with open(os.path.join(tmp, "tree"), "w", encoding="utf-8") as f:
                f.write(entry["tree"] + "\n")
            os.makedirs(os.path.dirname(cached), exist_ok=True)
            if self.cache_valid(cached, entry):     # another read was first: its folder may be in use, keep it
                return
            self.rm_quiet(cached)
            os.rename(tmp, cached)
        except OSError:
            pass

    def prune_cache(self, name, doc):
        """drop the cached folders of commits the accepted index no longer names"""
        d = os.path.join(self.state, "index-cache", name)
        if not os.path.isdir(d):
            return
        keep = {"%s-%s" % (e["commit"], hashlib.sha256(e["path"].encode()).hexdigest()[:12]) for e in doc["packages"].values()}
        now = time.time()
        for n in os.listdir(d):
            p = os.path.join(d, n)
            try:
                recent = now - os.stat(p).st_mtime < CACHE_KEEP_SECONDS     # created or read a moment ago: a running read may be using it
            except OSError:
                continue
            if n not in keep and not recent:
                self.rm_quiet(p)

    def read_at(self, r_name, entry, ref, rel):
        """bytes of <package folder>/<rel> at `ref`; for an index package the folder of the pinned commit after its tree hash was checked"""
        if not rel or rel.startswith("/") or "\\" in rel or ".." in rel.split("/") or re.match(r"^[A-Za-z]:", rel):
            raise Refused("%s: %r is outside the package folder" % (r_name, rel))
        if not entry.get("_index"):
            return git("show", "%s:%s/%s" % (ref, entry["path"], rel), cwd=self.clone_dir(r_name))
        base = os.path.realpath(self.verified_dir(r_name, entry))
        full = os.path.realpath(os.path.join(base, rel))
        if os.path.commonpath([base, full]) != base:
            raise Refused("%s: %r is outside the package folder" % (r_name, rel))
        try:
            with open(full, "rb") as f:
                return f.read()
        except OSError:
            raise Refused("%s: %s is not in the package" % (r_name, rel))

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
        if r.get("index"):      # the version comes from the index: "serial-N" stands for the release, the commit is per package
            return "serial-%d" % self.read_index(r)["serial"], ""
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
                if r.get("index"):
                    self.fetch_index(r)
                else:
                    self.fetch(r)
                t, c = self.verified_tag(r)
                out.append((name, t, c, ""))
            except Refused as e:
                out.append((name, "", "", str(e)))
        return out

    def catalog(self, with_unavailable=False):
        """{package name: [(repo, entry, tag, commit)]} from the cached clones, newest verified tag each; with_unavailable also lists the
        packages whose commit could not be fetched (entry["_unavailable"] = why): for what must know an installed copy, never for an offer"""
        cat = {}
        for name, r in self.all().items():
            try:
                if r.get("index"):
                    for pname, entry in self.index_entries(r, with_unavailable).items():
                        cat.setdefault(pname, []).append((name, entry, self.index_tag(entry), entry["commit"]))
                    continue
                t, c = self.verified_tag(r)
                for pname, entry in self.index(r, t).items():
                    cat.setdefault(pname, []).append((name, entry, t, c))
            except Refused:
                continue
        return cat

    # ── migration of installed packages to the repository that replaced theirs ──
    def listed(self, r):
        """{package: entry} that a default repository lists (unavailable ones too), or None while its index/tags were never fetched"""
        try:
            if r.get("index"):
                return self.index_entries(r, True)
            t, _ = self.verified_tag(r)
            return self.index(r, t)
        except (Refused, OSError, KeyError, TypeError, AttributeError):
            return None

    def migrate(self, apply=True):
        """Installed packages whose repository has no row any more move to the ONE default row that names it in `replaces = [...]` and lists the
        package. -> [(kind, package, old, new)], sorted by package:
          migrated  repo is now `new` (installed.toml and the repo of its vendor lock line; version, commit, tag, applied stay: nothing is
                    downgraded when the server is newer than the index, nothing is installed or removed)
          unmoved   the row that replaced the repository does not list it: stays installed as it is, gets no updates (new = -)
          waits     the replacing row has no verified index yet (first fetch failed): nothing changes (new = the row)
        Never moved: a package of a repository that is gone and that no default row replaces (a removed ADDED repository must not gain the
        trust of a default one). Several rows may replace one repository (a revert): the one that lists the package wins, none or several -> unmoved or
        ambiguous (kept, a note). Idempotent: a migrated entry has a row. Revert: a commit that restores the old rows
        and sets `replaces = ["official"]` on both maps the packages back by the same rule. apply=False only plans."""
        rows = self.all()
        defaults = [r for r in self.defaults() if isinstance(r.get("replaces"), list)]
        first = self.pkg.installed()
        listing, out = {}, []
        for n in sorted(first):
            e = first[n]
            old = e.get("repo") if isinstance(e, dict) else None
            if not isinstance(old, str) or not old or old in rows:
                continue
            target = [r for r in defaults if old in r["replaces"]]
            if not target:
                continue
            for r in target:
                if r["name"] not in listing:
                    listing[r["name"]] = self.listed(r)
            # a revert restores several rows that all name the same replacing row: the one whose index lists the package is the new home
            hits = [r["name"] for r in target if listing[r["name"]] is not None and n in listing[r["name"]]]
            if len(hits) == 1:
                out.append(("migrated", n, old, hits[0]))
            elif len(hits) > 1:
                out.append(("ambiguous", n, old, ",".join(hits)))
            elif any(listing[r["name"]] is None for r in target):
                out.append(("waits", n, old, next(r["name"] for r in target if listing[r["name"]] is None)))
            else:
                out.append(("unmoved", n, old, "-"))
        moved = {n: (old, new) for k, n, old, new in out if k == "migrated"}
        if apply:
            have = self.pkg.installed()          # re-read right before writing: a beside-running install is not lost
            if first and not have:
                raise Refused("installed.toml could not be read again: nothing was migrated")
            if not all(isinstance(v, dict) for v in have.values()):
                raise Refused("installed.toml has an entry that is not a table: nothing was migrated")
            for n, (old, new) in list(moved.items()):
                if have.get(n, {}).get("repo") != old:
                    del moved[n]
            # the lock first, installed.toml second: a run that dies in between is finished by the next one (the lock heals on every run
            # from installed.toml, which still says `old` and is migrated again)
            vend = self.pkg.pkg_vendor
            lock = vend.read_lock(self.nixos_dir())
            hit = False
            for n, e in lock.items():
                if not isinstance(e, dict):
                    continue
                want = moved[n][1] if n in moved else have.get(n, {}).get("repo")
                if isinstance(want, str) and want in rows and e.get("repo") != want:
                    e["repo"] = want
                    hit = True
            if hit:
                vend.write_lock(self.nixos_dir(), lock)
            if moved:
                for n, (old, new) in moved.items():
                    have[n]["repo"] = new
                self.pkg.save_installed(have)    # temp file + rename
        return out

    # ── install ──
    def choose(self, name, repo=None):
        cat = self.catalog().get(name, [])
        if repo:
            cat = [c for c in cat if c[0] == repo]
        if not cat:
            for rn in self.all():
                if (not repo or rn == repo) and name in self.unfetchable(rn):
                    raise Refused("%s is not available: %s" % (name, self.unfetchable(rn)[name][1]))
            raise Refused("no package %s in the repositories (hs pkg fetch updates them)" % name)
        if len(cat) > 1:
            raise Refused("%s is in %s: name one with --repo (a package name is never shadowed silently)" % (name, ", ".join(c[0] for c in cat)))
        if any(m.get("name") == name and "/current/" not in p.replace("\\", "/") for p, m in self.pkg.manifests()):
            raise Refused("%s is part of this installation already (a built-in package is not replaced by a repository)" % name)
        if cat[0][1].get("yanked"):
            raise Refused(self.yanked_text(name, cat[0][1]) + ": it is not installed")
        return cat[0]

    @staticmethod
    def yanked_text(name, entry):
        why = entry.get("yanked_reason")
        return "%s %s was withdrawn (yanked)%s" % (name, entry.get("version"), ": " + why if why else "")

    def extract(self, r, tag, path, dest, tree=None):
        """the folder `path` of `tag` (a tag, or a commit for an index package) into dest; `tree` = the hash the signed index names: checked before use"""
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
        if tree:
            try:
                got = self.pkg_index.tree_hash(dest)
            except self.pkg_index.Problem as e:
                self.rm_quiet(dest)
                raise Refused("%s: %s" % (r["name"], e))
            if got != tree:
                self.rm_quiet(dest)
                raise Refused("%s: the files at the pinned commit do not match the tree hash in the signed index (%s, expected %s); nothing was installed" % (r["name"], got[:19], tree[:19]))
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

    def install(self, name, repo=None, want_tag=None):
        r_name, entry, tag, commit = self.choose(name, repo)
        if entry.get("kind") == "blueprint":
            raise Refused("%s is a blueprint: hs blueprint apply %s" % (name, name), "pkg.blueprint")
        if want_tag and tag != want_tag:
            # the person saw the plan of one release (docs/PLAN-app-lifecycle.md D4): a newer or different verified tag is not installed behind their back
            raise Refused("%s: the plan was made for %s but the newest verified release is %s now: read the plan again" % (name, want_tag, tag))
        r = self.all()[r_name]
        self.check_entry(name, entry, r_name)
        cur = os.path.join(self.state, "current", name)
        tmp = os.path.join(self.state, "current", ".new-" + name)
        self.rm_quiet(tmp)
        os.makedirs(os.path.dirname(cur), exist_ok=True)
        indexed = bool(entry.get("_index"))
        ref = commit if indexed else tag
        if indexed:
            self.ensure_commit(r, commit)
        self.extract(r, ref, entry["path"], tmp, entry["tree"] if indexed else None)
        with open(os.path.join(tmp, "package.toml"), "rb") as fh:
            m = tomllib.load(fh)
        if m.get("kind") == "blueprint" or entry.get("kind") == "blueprint":
            # the checked package.toml decides, not the kind a repository index says; a disagreement is refused too
            self.rm_quiet(tmp)
            if m.get("kind") != "blueprint":
                raise Refused("%s: the index says kind blueprint but package.toml says %s" % (name, m.get("kind")))
            raise Refused("%s is a blueprint: hs blueprint apply %s" % (name, name), "pkg.blueprint")
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
        sl = self.pkg.pkg_slots.manifest_problems(name, self.pkg.pkg_slots.doc_of(self.pkg.capability_toml(tmp), m))
        if sl:
            self.rm_quiet(tmp)
            raise Refused("%s: slots: %s" % (name, sl[0]))
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
        bp = self.pkg.pkg_binary.install_problems(m, tmp)     # the staged copy, before it replaces the old one (hobnix/core#1138)
        if bp:
            self.rm_quiet(tmp)
            raise Refused("%s: %s" % (name, bp[0][1]), bp[0][0])
        why = self.stage_problems(name, tmp, r_name, m)
        if why:
            self.rm_quiet(tmp)
            raise Refused("%s: %s" % (name, why), "pkg.rows")
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
                tree = git("rev-parse", "%s:%s" % (ref, entry["path"]), cwd=self.clone_dir(r_name)).decode().strip()
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

    def stage_problems(self, name, tmp, r_name, m):
        """The staged copy before it replaces anything (#1072): manifest findings (an app route to an admin page ...) and the rows the loader
        refuses (scripts/lib/pkg-stage-check.sh, the one place that knows the row rules). -> "" or one line; fails closed when the check cannot run.
        Nothing is vendored, no event is written and the old copy stays where it is until this is empty."""
        # only the trust rule here (an admin page is never public); the rest of the app contract is `hs pkg validate`, as before
        found = [str(x) for x in self.pkg.pkg_app.check(m, tmp, False)[0] if "an admin page is never public" in str(x)]
        script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib", "pkg-stage-check.sh").replace("\\", "/")
        try:
            res = subprocess.run([os.environ.get("HS_BASH") or "bash", script, name, tmp, r_name], capture_output=True, timeout=120)
            lines = [ln.replace("\t", ": ", 1) for ln in res.stdout.decode("utf-8", "replace").splitlines() if ln]
            if res.returncode not in (0, 1) or (res.returncode == 1 and not lines):
                found.append("the check of its commands could not run")
            else:
                found += lines
        except (OSError, subprocess.SubprocessError):
            found.append("the check of its commands could not run")
        clean = [clean_text(x)[:200] for x in found]   # a hostile package text never reaches the terminal as it is
        return "; ".join(clean[:5]) + ("; and %d more" % (len(clean) - 5) if len(clean) > 5 else "") if clean else ""

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

    def confine_text(self, name, commit):
        """The prompt lines about the commands of the package that run confined (flag `confine`, ADR 0014: partial). `commit` None = the installed copy."""
        try:
            if commit is None:
                with open(os.path.join(self.state, "current", name, "commands.tsv"), encoding="utf-8") as f:
                    text = f.read()
            else:
                r_name, entry, _, _ = self.choose_installed(name, self.recorded(name)["repo"])
                text = self.read_at(r_name, entry, commit, "commands.tsv").decode("utf-8", "replace")
        except (OSError, Refused, subprocess.SubprocessError):
            return []
        proto = self.pkg.pkg_protocol
        return proto.confine_lines([w for _, w in proto.confine_rows_of(text)])

    def new_permissions(self, name, commit):
        """The permissions the release `commit` declares: (declared list or None, the ones the installed copy lacks)."""
        r_name, entry, _, _ = self.choose_installed(name, self.recorded(name)["repo"])
        raw = self.read_at(r_name, entry, commit, "package.toml")
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
            repos = [c[0] for c in self.catalog(True).get(name, [])]
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
        if entry.get("yanked"):
            raise Refused(self.yanked_text(name, entry) + " (the installed copy is %s)" % have.get("version", "?"))
        if commit == have.get("commit"):
            return None
        ev, hv, ht = self.pkg.semver_key(entry["version"]), self.pkg.semver_key(have["version"]), have.get("tag", "")
        indexed = bool(entry.get("_index"))
        # same version under a newer tag: a beta that became the release (release tags only; an index version is what the package says)
        if not (ev > hv or (not indexed and ev == hv and (TAG.match(ht) or BETA_TAG.match(ht)) and tag_key(tag) > tag_key(ht))):
            return None
        d = self.clone_dir(r_name)
        # no recorded commit (see recorded): show the whole new package against the empty tree
        old = have.get("commit") or EMPTY_TREE
        if indexed:
            self.ensure_commit(self.all()[r_name], commit, fetch=False)     # the plan never runs git fetch: hs pkg fetch does
            try:
                self.ensure_commit(self.all()[r_name], old, fetch=False)
            except Refused:
                old = EMPTY_TREE
        text = git("diff", "--stat", "-p", old, commit, "--", entry["path"], cwd=d).decode("utf-8", "replace")
        return old, tag, commit, text

    # ── show: what a package is and would ask, read from the verified tag, nothing installed (docs/PLAN-app-lifecycle.md Q2, D4) ──
    def verified_package(self, name, repo=None):
        """(repo name, entry, tag, commit, manifest dict) from the newest verified tag; Refused with the reason (unknown, unsigned, unverified)"""
        try:
            r_name, entry, tag, commit = self.choose(name, repo)
        except Refused as e:
            # a repository whose newest tag does not verify drops out of the catalog silently: say why instead of "no such package"
            why = []
            for n, r in self.all().items():
                if repo and n != repo:
                    continue
                try:
                    if r.get("index"):
                        self.read_index(r)
                    else:
                        self.verified_tag(r)
                except Refused as x:
                    if "no release tag" not in str(x):
                        why.append(str(x))
            if why and "no package" in str(e):
                raise Refused("%s: not shown, no verified release: %s" % (name, "; ".join(why)))
            raise
        self.check_entry(name, entry, r_name)
        path = entry["path"]
        if not re.match(r"^[A-Za-z0-9._/-]+$", path) or ".." in path.split("/"):
            raise Refused("%s: the path %r in index.toml is not allowed" % (r_name, path))
        try:
            m = tomllib.loads(self.read_at(r_name, entry, commit, "package.toml").decode("utf-8"))
        except tomllib.TOMLDecodeError as e:
            raise Refused("%s: package.toml is not valid (%s)" % (name, e))
        if m.get("name") != name or m.get("version") != entry.get("version"):
            raise Refused("%s: package.toml (name %s, version %s) does not match the index (%s)" % (name, m.get("name"), m.get("version"), entry.get("version")))
        return r_name, entry, tag, commit, m

    @staticmethod
    def steps(m):
        """the fixed step vocabulary of the install job for this package (Q3); the job refuses to differ from what was shown"""
        app = m.get("app") or {}
        needs = list(m.get("needs") or []) + list(m.get("requires") or [])
        out = [("read", "Fetch the verified release")]
        if needs:
            out.append(("needs", "Meet what it needs: %s" % ", ".join(needs)))
        if m.get("kind") == "recipe":
            if m.get("ask"):
                out.append(("ask", "Ask the questions"))
            out.append(("run", "Run the recipe"))
            if app.get("health"):
                out.append(("check", "Check that it answers"))
            return out + [("done", "Show where to open it")]
        out.append(("on", "Switch it on"))
        if m.get("kind") == "capability" and m.get("module"):
            out.append(("rebuild", "Rebuild the system"))
        return out + [("check", "Check that it works")]

    def show(self, name, repo=None):
        """the lines of `hs sys pkg show`: key TAB value ...; an empty value is -, a list is a comma list"""
        r_name, entry, tag, commit, m = self.verified_package(name, repo)
        app = m.get("app") or {}
        uses = app.get("uses") or {}
        routes = app.get("routes") or {}

        def f(v):
            if isinstance(v, (list, tuple)):
                v = ",".join(str(x) for x in v)
            v = " ".join(str(v if v is not None else "").split())
            return v or "-"
        rows = [("status", "ok"), ("name", name), ("kind", m.get("kind", "?")), ("repo", r_name), ("version", m.get("version")), ("tag", tag), ("commit", commit),
                ("title", m.get("title")), ("description", m.get("description")), ("description_de", m.get("description_de")),
                ("audience", m.get("audience", "generic")), ("requires_core", m.get("requires_core")), ("icon", m.get("icon")),
                ("category", m.get("category")), ("app_version", m.get("app_version")), ("upstream", m.get("upstream")),
                ("needs", list(m.get("needs") or []) + list(m.get("requires") or [])), ("input", m.get("input", "none")),
                ("instances", app.get("instances")), ("ram_mb", uses.get("ram_mb")), ("disk_gb", uses.get("disk_gb")),
                ("ports", uses.get("ports")), ("gpu", "yes" if uses.get("gpu") else "no")]
        out = ["\t".join([k, f(v)]) for k, v in rows]
        for shot in m.get("screenshots") or []:
            out.append("\t".join(["screenshot", f(shot)]))
        for rt, v in sorted(routes.items()):
            if isinstance(v, dict):
                out.append("\t".join(["route", f(rt), f(v.get("port")), f(v.get("scheme", "http")), f(v.get("exposure", "private-ok")), "yes" if rt == routes.get("default") else "no"]))
        for a in m.get("ask") or []:
            out.append("\t".join(["ask"] + [f(a.get(k)) for k in ("key", "label", "type", "choices", "default", "pattern", "when")]))
        for n, t in self.steps(m):
            out.append("\t".join(["step", n, t]))
        out += self.slot_lines(r_name, entry, commit, m)
        return out

    def slot_lines(self, r_name, entry, commit, m):
        """`slot_off TAB <slot> TAB <name>` for every slot of the release whose `requires` is off on this server (the install dialog says it adds a
        card once <name> is on). Best effort: a package without slots, or one that cannot be read, adds no line."""
        try:
            try:
                cap = tomllib.loads(self.read_at(r_name, entry, commit, "capability.toml").decode("utf-8"))
            except (subprocess.SubprocessError, Refused, tomllib.TOMLDecodeError):
                cap = None
            hs_ext = self.pkg.pkg_slots._hs_ext()
            on = set(hs_ext.capabilities()) | hs_ext.applied_recipes()
            return ["\t".join(["slot_off", s, r]) for s, r in self.pkg.pkg_slots.requires_off(self.pkg.pkg_slots.doc_of(cap, m), on)]
        except Exception:
            return []

    def asset(self, name, file, repo=None):
        """the bytes of the icon or a screenshot of the verified tag; nothing else of the package is served"""
        r_name, entry, tag, commit, m = self.verified_package(name, repo)
        allowed = list(m.get("screenshots") or [])
        icon = str(m.get("icon") or "")
        if icon and not icon.startswith("ph:"):
            allowed.append(icon)
        if file not in allowed:
            raise Refused("%s has no store file %s (the icon and the screenshots of its package.toml are served)" % (name, file))
        lim = 20 * 1024 if file == icon else 300 * 1024
        data = self.read_at(r_name, entry, commit, file)
        if len(data) > lim:
            raise Refused("%s: %s is larger than %d bytes" % (name, file, lim))
        if file == icon:
            if not file.endswith(".svg"):
                raise Refused("%s: the icon %s is not an svg file" % (name, file))
            why = self.pkg.pkg_app.svg_problem(data.decode("utf-8", "replace"))
            if why:
                raise Refused("%s: the icon %s %s" % (name, file, why))
        elif not self.pkg.pkg_app.PICTURE.match(file):
            raise Refused("%s: %s is not a png or webp picture" % (name, file))
        return data

    def choose_installed(self, name, repo):
        cat = [c for c in self.catalog(True).get(name, []) if c[0] == repo]
        if not cat:
            raise Refused("%s is not in %s any more" % (name, repo))
        if cat[0][1].get("_unavailable"):
            raise Refused("%s: %s" % (name, cat[0][1]["_unavailable"]))
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
                for flag in ("--key", "--index"):
                    if flag in rest and (rest.index(flag) + 1 >= len(rest) or rest[rest.index(flag) + 1].startswith("--")):
                        raise Refused("usage: repo add <name> <url> (--key <allowed_signers file> [--index <address>] | --unsigned); %s needs a value" % flag)
                key = rest[rest.index("--key") + 1] if "--key" in rest else None
                index = rest[rest.index("--index") + 1] if "--index" in rest else None
                R.add(rest[1], rest[2], key=key, unsigned="--unsigned" in rest, index=index)
            elif sub == "remove":
                R.remove(rest[1])
            elif sub == "migrate":
                # machine lines: kind TAB package TAB old repository TAB new repository (- = none); --dry-run changes nothing
                for kind, n, old, new in R.migrate(apply="--dry-run" not in rest):
                    print("	".join([kind, n, old, new]))
            else:
                raise Refused("repo list | add <name> <url> (--key <file> | --unsigned) | remove <name> | migrate [--dry-run]")
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
                    if e.get("yanked"):
                        continue       # withdrawn: not offered
                    print("\t".join([r_name, pname, e.get("kind", "?"), str(e.get("version")), have.get(pname, {}).get("version", "-")]))
        elif cmd == "show":
            repo = rest[rest.index("--repo") + 1] if "--repo" in rest else None
            try:
                lines = R.show(rest[0], repo)
            except (Refused, AttributeError, TypeError, KeyError) as e:
                print("status\trefused")
                print("reason\t%s" % " ".join(str(e).split()))
                return 1
            print("\n".join(lines))
        elif cmd == "blueprint":     # blueprint list [lang] | show <name> [lang] | record <name>: lib/pkg_blueprint.py (hs blueprint, hs sys blueprint)
            sys.path.insert(0, os.path.join(pkg.HERE, "lib"))
            import pkg_blueprint
            sub = rest[0] if rest else ""
            if sub == "list":
                rows = pkg_blueprint.listing(R, pkg, rest[1] if len(rest) > 1 else "en")
                if rows:
                    print("\n".join(rows))
            elif sub == "show" and len(rest) > 1:
                lines, bad = pkg_blueprint.show(R, pkg, rest[1], rest[2] if len(rest) > 2 else "en")
                print("\n".join(lines) if not bad else "\n".join("error\t" + b for b in bad))
                return 1 if bad else 0
            elif sub == "record" and len(rest) > 1:
                pkg_blueprint.record(R, pkg, rest[1])
            else:
                print("usage: blueprint list [lang] | show <name> [lang] | record <name>", file=sys.stderr)
                return 2
        elif cmd == "asset":
            repo = rest[rest.index("--repo") + 1] if "--repo" in rest else None
            sys.stdout.buffer.write(R.asset(rest[0], rest[1], repo))
        elif cmd == "market":
            # everything a person can install, as data (hs sys pkg market): package, kind, repository, available version, installed version
            # (- = no copy in current/), state (new|current|update|waits|orphan), core (yes|no), audience, title. A package of a repository that
            # is gone (or no longer lists it) is an orphan: its copy stays until `hs pkg remove`.
            have = pkg.installed()
            cur = os.path.join(R.state, "current")
            seen = set()
            for pname, rows in sorted(R.catalog(True).items()):
                for r_name, e, tag, _ in rows:
                    ver = str(e.get("version"))
                    inst = "-"
                    if os.path.isdir(os.path.join(cur, pname)):
                        inst = str(have.get(pname, {}).get("version", "?"))
                    if e.get("_unavailable"):       # not offered; an installed copy is shown as it is, with the reason in the title
                        if inst != "-":
                            seen.add(pname)
                            print("	".join([pname, e.get("kind", "?"), r_name, ver, inst, "current", "yes" if e.get("core") else "no",
                                             e.get("audience", "generic"), ("%s (update not available: %s)" % (e.get("title") or pname, e["_unavailable"])).replace("	", " ")]))
                        continue
                    if inst == "-":
                        state = "new"
                    elif inst == ver:
                        state = "current"
                    else:
                        try:
                            state = "update" if pkg.semver_key(ver) > pkg.semver_key(inst) else "current"
                        except ValueError:
                            state = "update"
                    if e.get("yanked"):
                        if inst == "-":
                            continue    # withdrawn: not offered; an installed copy just stays as it is
                        state = "current"
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
            for pname, rows in sorted(R.catalog(True).items()):
                there = os.path.isdir(os.path.join(R.state, "current", pname)) or pname in builtin
                if there or rows[0][1].get("kind") == "blueprint" or not (rows[0][1].get("core") or pname in applied):   # a blueprint is applied, never installed
                    continue
                if rows[0][1].get("_unavailable"):       # a core package that cannot be had is a failure, not a silent skip
                    bad += 1
                    print("%s: %s" % (pname, rows[0][1]["_unavailable"]), file=sys.stderr)
                    continue
                try:
                    v, r_name, tag = R.install(pname, rows[0][0])
                    print("%s %s from %s (%s)" % (pname, v, r_name, tag))
                except Refused as e:
                    bad += 1
                    print("%s: %s" % (pname, e), file=sys.stderr)
                    if e.code:
                        print("code" + chr(9) + e.code, file=sys.stderr)
            return 1 if bad else 0
        elif cmd == "install":
            repo = rest[rest.index("--repo") + 1] if "--repo" in rest else None
            want = rest[rest.index("--tag") + 1] if "--tag" in rest else None
            v, r_name, tag = R.install(rest[0], repo, want)
            print("%s %s from %s (%s)" % (rest[0], v, r_name, tag))
            print("permissions it declares (not enforced, it runs as root): %s" % pkg.pkg_perms.describe(R.last_permissions))
            for ln in R.confine_text(rest[0], None):
                print(ln)
            if R.last_permissions is None:
                print("warning: %s" % pkg.pkg_perms.missing_text(rest[0]), file=sys.stderr)
        elif cmd == "update":
            res = R.diff(rest[0])
            if res is None:
                print("current")
                return 0
            old, tag, commit, text = res
            print(text)
            new, fresh = R.new_permissions(rest[0], commit)
            print("permissions it declares (not enforced, it runs as root): %s" % pkg.pkg_perms.describe(new))
            for ln in R.confine_text(rest[0], commit):
                print(ln)
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
        rf = os.environ.get("HS_PKG_REFUSAL")
        if e.code and rf:      # hs pkg: the script shows it through refuse_code (ADR 0028)
            with open(rf, "w", encoding="utf-8") as f:
                f.write("%s\t%s\n" % (e.code, " ".join(str(e).split())))
        else:
            print(str(e), file=sys.stderr)
            if e.code:
                print("code\t" + e.code, file=sys.stderr)
        return 1
    except IndexError:
        print("missing argument", file=sys.stderr)
        return 1
    return 0
