"""The [integrations.<name>] blocks of a package.toml (hobnix/core#926, docs/PLAN-packages.md "Integrations"). Python stdlib only, no CLI.
A package (recipe, extension or capability) says what it offers to others, so another package finds it and its local API without copy and paste:
  [integrations.media]                         <name> is any lowercase id; the core knows no names
  api_url    = "http://{host}:7878"            the local API; {host} is the address of the instance, only http(s), no spaces
  key_file   = "/var/lib/hs/radarr/api-key"    absolute path of the API key on the server (read only through scripts/lib/secret.sh), no ".."
  key_header = "X-Api-Key"                     optional: the header the app wants the key in (default X-Api-Key)
  <any other key> = "text"                     passed through as a plain string (at most 200 chars, no control chars, no comma)
All envelope keys are optional. A package may offer several integrations. Nothing here reads a key: rows give its path, the shell side asks
secret_state. A package that wants a key declares `permissions = ["integration:<name>"]` (pkg_perms.py); `grant` checks it.
"""
import re

NAME = re.compile(r"^[a-z][a-z0-9-]*$")
ENVELOPE = ("api_url", "key_file", "key_header")
URL = re.compile(r"^https?://[A-Za-z0-9._{}-]+(:[0-9]{1,5})?(/[^\s]*)?$")
HEADER = re.compile(r"^[A-Za-z][A-Za-z0-9-]{0,39}$")
PLAIN = re.compile(r"^[^\x00-\x1f\x7f,]{0,200}$")
MAX_EXTRA = 20


def manifest_problems(m):
    """[text] for the integrations table of one package.toml dict."""
    ig = m.get("integrations")
    if ig is None:
        return []
    if not isinstance(ig, dict):
        return ["integrations must be a table"]
    out = []
    for n, b in ig.items():
        p = f"integrations.{n}"
        if not NAME.match(str(n)):
            out.append(f"{p}: the name is not a lowercase id")
        if not isinstance(b, dict):
            out.append(f"{p} must be a table")
            continue
        u = b.get("api_url")
        if u is not None and (not isinstance(u, str) or not URL.match(u)):
            out.append(f"{p}.api_url must be an http(s) URL without spaces ({{host}} stands for the instance)")
        f = b.get("key_file")
        if f is not None and (not isinstance(f, str) or not f.startswith("/") or ".." in f.split("/") or re.search(r"\s", f)):
            out.append(f"{p}.key_file must be an absolute path without .. or spaces")
        h = b.get("key_header")
        if h is not None and (not isinstance(h, str) or not HEADER.match(h)):
            out.append(f"{p}.key_header must be a header name")
        extra = [k for k in b if k not in ENVELOPE]
        if len(extra) > MAX_EXTRA:
            out.append(f"{p} has more than {MAX_EXTRA} extra keys")
        for k in extra:
            if not re.match(r"^[a-z][a-z0-9_]{0,39}$", str(k)):
                out.append(f"{p}.{k}: the key is not a lowercase word")
            elif not isinstance(b[k], str) or not PLAIN.match(b[k]):
                out.append(f"{p}.{k} must be plain text (at most 200 characters, no comma, no control character)")
    return out


def _dash(v):
    return v if v else "-"


def rows(manifests, on, only=None):
    """[[package, integration, source, api_url, key_file, extras]] of the valid blocks of the packages whose name is in `on` (recipe installed,
    extension or capability on), sorted; empty fields are "-"; extras = k=v comma list of the keys beyond the envelope."""
    out = []
    for _, m in manifests:
        if m.get("name") not in on or manifest_problems(m):
            continue
        for n, b in sorted((m.get("integrations") or {}).items()):
            if only and n != only:
                continue
            ex = ",".join(f"{k}={b[k]}" for k in sorted(b) if k not in ENVELOPE)
            out.append([m["name"], n, m.get("kind", "-"), _dash(b.get("api_url")), _dash(b.get("key_file")), _dash(ex)])
    return sorted(out)


def grant(manifests, on, integration, caller):
    """(key_file, None) when `caller` may have the key of `integration`, else (None, reason). A capability needs no permission; an extension
    must declare integration:<name> (a declared check only: permissions are not enforced yet, hobnix/server#239); a recipe is refused."""
    me = next((m for _, m in manifests if m.get("name") == caller), None)
    if me is None:
        return None, f"{caller}: no such package"
    if me.get("kind") == "recipe":
        return None, f"{caller} is a recipe: only an extension or a capability may ask for a key"
    if me.get("kind") == "extension" and f"integration:{integration}" not in (me.get("permissions") or []):
        return None, f"{caller} does not declare permissions = [\"integration:{integration}\"]"
    hits = [r for r in rows(manifests, on, integration) if r[4] != "-"]
    if not hits:
        return None, f"no available package offers {integration} with a key_file"
    return hits[0][4], None
