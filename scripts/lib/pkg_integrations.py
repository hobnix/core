"""The [integrations.media] block of a package.toml (hobnix/core#926, docs/PLAN-packages.md "Integrations"). Python stdlib only, no CLI.
A media app (radarr, sonarr, jellyfin, sabnzbd ...) says what it exposes so an extension can find it without copy and paste:
  [integrations.media]
  kind       = "movies"                     movies | series | player | downloader
  api_url    = "http://{host}:7878"         the local API; {host} is the address of the instance, only http(s), no spaces
  key_file   = "/var/lib/hs/radarr/api-key" absolute path of the API key on the server (read only through scripts/lib/secret.sh), no ".."
  key_header = "X-Api-Key"                  optional: the header the app wants the key in (default X-Api-Key)
Only a recipe declares it. Nothing here reads the key: media_rows gives its path, the shell side asks secret_state.
"""
import re

MEDIA_KINDS = ("movies", "series", "player", "downloader")
MEDIA_KEYS = {"kind", "api_url", "key_file", "key_header"}
URL = re.compile(r"^https?://[A-Za-z0-9._{}-]+(:[0-9]{1,5})?(/[^\s]*)?$")
HEADER = re.compile(r"^[A-Za-z][A-Za-z0-9-]{0,39}$")


def manifest_problems(m):
    """[text] for the integrations table of one package.toml dict."""
    ig = m.get("integrations")
    if ig is None:
        return []
    if not isinstance(ig, dict):
        return ["integrations must be a table"]
    out = []
    for k in ig:
        if k != "media":
            out.append(f"integrations.{k} is not known (media)")
    md = ig.get("media")
    if md is None:
        return out
    if not isinstance(md, dict):
        return out + ["integrations.media must be a table"]
    if m.get("kind") != "recipe":
        out.append("integrations.media is for a recipe")
    for k in md:
        if k not in MEDIA_KEYS:
            out.append(f"integrations.media.{k} is not known")
    if md.get("kind") not in MEDIA_KINDS:
        out.append("integrations.media.kind is not " + ", ".join(MEDIA_KINDS))
    u = md.get("api_url")
    if not isinstance(u, str) or not URL.match(u):
        out.append("integrations.media.api_url must be an http(s) URL without spaces ({host} stands for the instance)")
    f = md.get("key_file")
    if not isinstance(f, str) or not f.startswith("/") or ".." in f.split("/") or re.search(r"\s", f):
        out.append("integrations.media.key_file must be an absolute path without .. or spaces")
    h = md.get("key_header", "X-Api-Key")
    if not isinstance(h, str) or not HEADER.match(h):
        out.append("integrations.media.key_header must be a header name")
    return out


def media_rows(manifests, on):
    """[[name, kind, api_url, key_file, key_header, title]] of the recipes with a valid media block whose name is in `on` (the installed apps)."""
    out = []
    for _, m in manifests:
        md = (m.get("integrations") or {}).get("media")
        if m.get("kind") != "recipe" or m.get("name") not in on or not isinstance(md, dict) or manifest_problems(m):
            continue
        out.append([m["name"], md["kind"], md["api_url"], md["key_file"], md.get("key_header", "X-Api-Key"), m.get("title", "")])
    return sorted(out)
