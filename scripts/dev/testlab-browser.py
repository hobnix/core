#!/usr/bin/env python3
"""Test-lab stage 6 (hobnix/server#432): a headless browser signs in to the web interface of the installed VM and opens every page of the
navigation (web/src/nav.js of the tested checkout). A page fails when the HTTP status is not 200, the script throws (pageerror), the console
logs an error, or the page stays empty.

UNVERIFIED: written without Incus, a browser or the playwright package. Not tested on hardware yet.

  testlab-browser.py run --url http://<vm>:8480 --nav <nav.js> --out <result-browser.json> [--user adminuser] [--timeout 120]
            [--axe-js <axe.min.js> --axe-baseline <axe-baseline.tsv>]   #487: also run axe-core on every page; fails on NEW findings only
  testlab-browser.py pages <nav.js>          the paths it would open (no browser needed)
  testlab-browser.py live --url ... --scenarios <testlab-live.tsv> --out <result-live.json> [--limit SECONDS] [--ssh adminuser@vm]
                                             #485: open a page, start a change from a second channel (ssh), the OPEN page must show the new state
                                             without a reload within the limit (default: scripts/lib/live-limits.tsv, class `hook`); --limit 0 must fail

The password comes from HS_NESTED_PASSWORD (never argv). Exit codes: 0 all pages fine, 1 a page failed, 3 no browser here (playwright missing),
4 the web interface did not answer.
"""
import argparse
import json
import os
import re
import sys
import time
import urllib.request


def pages(nav_js):
    """The unique paths of the navigation tree, in order. Paths with a parameter are not opened."""
    with open(nav_js, encoding="utf-8") as f:
        text = f.read()
    seen, out = set(), []
    for p in re.findall(r"path:\s*'(/[^']*)'", text):
        if ":" in p or p in seen:
            continue
        seen.add(p)
        out.append(p)
    return out


def axe_key(path, v, node):
    """One finding as a baseline row: page path, axe rule id, the first CSS selector of the node (tab separated)."""
    target = node.get("target") or ["-"]
    return "\t".join((path, v["id"], target[0] if isinstance(target[0], str) else "-"))

def load_axe_baseline(path):
    """The accepted findings (rows of scripts/dev/axe-baseline.tsv). A missing file or one with only comments means none are accepted."""
    rows = set()
    if path and os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            for line in f:
                if line.strip() and not line.startswith("#"):
                    rows.add(line.rstrip("\r\n"))
    return rows


def axe_new(path, violations, baseline):
    """The findings of one page that are not in the baseline: list of (key, rule id, impact, selector). Fails the stage when not empty."""
    out = []
    for v in violations:
        for node in v.get("nodes", []):
            k = axe_key(path, v, node)
            if k not in baseline:
                out.append((k, v["id"], v.get("impact") or "-", k.split("\t")[2]))
    return out


def axe_run(page, axe_src):
    """Inject axe-core and return its violations of the open page (needs a browser: not run by the tests)."""
    page.evaluate(axe_src)
    return page.evaluate("axe.run(document, {resultTypes: ['violations']}).then(r => r.violations)")


def wait_up(url, seconds):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        try:
            urllib.request.urlopen(url + "/", timeout=5).read(1)
            return True
        except Exception:
            time.sleep(3)
    return False


def run(a):
    paths = pages(a.nav)
    pw = os.environ.get("HS_NESTED_PASSWORD", "")
    if not pw:
        print("HS_NESTED_PASSWORD is not set", file=sys.stderr)
        return 2
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        print("playwright is not installed here: stage 6 cannot run", file=sys.stderr)
        return 3
    if not wait_up(a.url, a.timeout):
        print("the web interface at %s did not answer within %ss" % (a.url, a.timeout), file=sys.stderr)
        return 4
    results = []
    axe_src, baseline = None, load_axe_baseline(a.axe_baseline)
    if a.axe_js and os.path.exists(a.axe_js):
        with open(a.axe_js, encoding="utf-8") as f:
            axe_src = f.read()
    elif a.axe_js:
        print("axe-core not found at %s: the axe check is skipped" % a.axe_js, file=sys.stderr)
    with sync_playwright() as pwr:
        try:
            browser = pwr.chromium.launch(headless=True)
        except Exception as e:   # no browser binary
            print("no headless browser could start: %s" % e, file=sys.stderr)
            return 3
        ctx = browser.new_context(viewport={"width": 1280, "height": 900})
        login = ctx.request.post(a.url + "/api/login", data={"realm": "local", "user": a.user, "password": pw})
        results.append({"step": "sign in as %s" % a.user, "ok": login.ok})
        if login.ok:
            for p in paths:
                errors = []
                page = ctx.new_page()
                page.on("pageerror", lambda e, errors=errors: errors.append("script error: %s" % e))
                page.on("console", lambda m, errors=errors: errors.append("console: %s" % m.text) if m.type == "error" else None)
                rec = {"step": "open %s" % p, "ok": False}
                try:
                    resp = page.goto(a.url + p, wait_until="networkidle", timeout=30000)
                    status = resp.status if resp else 0
                    body = page.inner_text("body").strip()
                    if status != 200:
                        errors.append("HTTP %s" % status)
                    if not body:
                        errors.append("the page is empty")
                    if "/login" in page.url and p != "/login":
                        errors.append("sent back to the sign-in page")
                    if axe_src and not errors:
                        new = axe_new(p, axe_run(page, axe_src), baseline)
                        if new:
                            errors.append("axe: %d new finding(s): %s" % (len(new), ", ".join("%s %s" % (n[1], n[3]) for n in new[:3])))
                except Exception as e:
                    errors.append(str(e)[:200])
                rec["ok"] = not errors
                if errors:
                    rec["error"] = "; ".join(errors[:3])
                results.append(rec)
                page.close()
                print("  %s  %s" % ("ok  " if rec["ok"] else "FAIL", rec["step"]), flush=True)
        browser.close()
    ok = all(r["ok"] for r in results)
    with open(a.out, "w") as f:
        json.dump({"stage": "browser", "ok": ok, "steps": results}, f, indent=1)
    return 0 if ok else 1


def load_limits(path):
    out = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            if line.strip() and not line.startswith("#"):
                k, v = line.split("\t")[:2]
                out[k] = float(v)
    return out


def load_scenarios(path):
    """name, path, before, after, limit class, command (columns of scripts/dev/testlab-live.tsv)"""
    rows = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            if line.strip() and not line.startswith("#"):
                c = line.rstrip("\n").split("\t")
                if len(c) >= 6:
                    rows.append(dict(zip(("name", "path", "before", "after", "klass", "cmd"), c[:6])))
    return rows


def measure(sc, limit, page_text, trigger, clock=time.monotonic, sleep=time.sleep, poll=0.1):
    """One scenario with an OPEN page and no reload: page_text() is what the page shows now, trigger() starts the change from a second channel.
    -> (ok, seconds, message). Fails when `before` is not shown first, when `after` is not shown within `limit` seconds, or at limit 0."""
    if sc["before"] not in page_text():
        return False, 0.0, "the page did not show %r before the change" % sc["before"]
    t0 = clock()
    trigger()
    while True:
        took = clock() - t0
        if took > limit:
            return False, took, "%r not shown within %.1f s (limit %.1f)" % (sc["after"], took, limit)
        if sc["after"] in page_text():
            if limit <= 0:
                return False, took, "limit is %.1f s" % limit
            return True, took, ""
        sleep(poll)


def run_live(a):
    limits = load_limits(a.limits)
    scenarios = load_scenarios(a.scenarios)
    pw = os.environ.get("HS_NESTED_PASSWORD", "")
    if not pw:
        print("HS_NESTED_PASSWORD is not set", file=sys.stderr)
        return 2
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        print("playwright is not installed here: the live stage cannot run", file=sys.stderr)
        return 3
    import subprocess
    if not wait_up(a.url, a.timeout):
        return 4
    results = []
    with sync_playwright() as pwr:
        try:
            browser = pwr.chromium.launch(headless=True)
        except Exception as e:
            print("no headless browser could start: %s" % e, file=sys.stderr)
            return 3
        ctx = browser.new_context(viewport={"width": 1280, "height": 900})
        if not ctx.request.post(a.url + "/api/login", data={"realm": "local", "user": a.user, "password": pw}).ok:
            print("sign in failed", file=sys.stderr)
            return 1
        for sc in scenarios:
            limit = a.limit if a.limit is not None else limits[sc["klass"]]
            page = ctx.new_page()
            page.goto(a.url + sc["path"], wait_until="networkidle", timeout=30000)
            page.wait_for_function("t => document.body.innerText.includes(t)", arg=sc["before"], timeout=15000)
            ok, took, msg = measure(sc, limit, lambda: page.inner_text("body"),
                                    lambda: subprocess.run(["ssh", "-o", "BatchMode=yes", a.ssh, sc["cmd"]], check=False, timeout=120))
            page.close()
            results.append({"step": "%s (%s)" % (sc["name"], sc["path"]), "ok": ok, "seconds": round(took, 2), "limit": limit, **({"error": msg} if msg else {})})
            print("  %s  %s  %.2f s (limit %.1f)" % ("ok  " if ok else "FAIL", sc["name"], took, limit), flush=True)
        browser.close()
    ok = all(r["ok"] for r in results)
    with open(a.out, "w") as f:
        json.dump({"stage": "browser-live", "ok": ok, "steps": results}, f, indent=1)
    return 0 if ok else 1


def main(argv):
    ap = argparse.ArgumentParser(prog="testlab-browser")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("pages")
    p.add_argument("nav")
    p = sub.add_parser("run")
    p.add_argument("--url", required=True)
    p.add_argument("--nav", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--user", default="adminuser")
    p.add_argument("--timeout", type=int, default=120)
    p.add_argument("--axe-js", default=None)
    p.add_argument("--axe-baseline", default=None)
    p = sub.add_parser("live")
    p.add_argument("--url", required=True)
    p.add_argument("--scenarios", required=True)
    p.add_argument("--limits", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib", "live-limits.tsv"))
    p.add_argument("--out", required=True)
    p.add_argument("--ssh", required=True)
    p.add_argument("--limit", type=float, default=None)
    p.add_argument("--user", default="adminuser")
    p.add_argument("--timeout", type=int, default=120)
    a = ap.parse_args(argv)
    if a.cmd == "live":
        return run_live(a)
    if a.cmd == "pages":
        print("\n".join(pages(a.nav)))
        return 0
    return run(a)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
