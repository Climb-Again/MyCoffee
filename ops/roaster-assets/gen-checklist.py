#!/usr/bin/env python3
"""Regenerate ops/roaster-assets/CHECKLIST.md from the live backend snapshot.

Usage:
    python3 ops/roaster-assets/gen-checklist.py            # fetch live snapshot
    python3 ops/roaster-assets/gen-checklist.py snap.json  # use a saved snapshot

Live fetch needs APP_TOKEN (or INGEST_TOKEN) in the environment; the Railway
host is on the cloud session's allow-list (CLAUDE.md §7). Tracks backlog
#132-#134: the roaster logo + blurb content Radu supplies.

Marks a roaster's Logo/Blurb ticked (checklist only — the real source of truth
is the DB once #133 backfills it):
  - Logo  = a file logos/<slug>.* exists in this folder.
  - Blurb = the slug appears in blurbs.md as a "## <slug>" section with body text.
"""
import collections
import datetime
import glob
import json
import os
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = "https://mycoffee-production-bd43.up.railway.app"


def load_snapshot():
    if len(sys.argv) > 1:
        with open(sys.argv[1]) as f:
            return json.load(f)
    tok = os.environ.get("APP_TOKEN") or os.environ.get("INGEST_TOKEN")
    if not tok:
        sys.exit("no APP_TOKEN/INGEST_TOKEN in env and no snapshot file given")
    req = urllib.request.Request(
        f"{BASE}/api/snapshot", headers={"Authorization": f"Bearer {tok}"}
    )
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read())


def have_logo(slug):
    return bool(glob.glob(os.path.join(HERE, "logos", slug + ".*")))


def load_blurb_slugs():
    path = os.path.join(HERE, "blurbs.md")
    slugs = set()
    if not os.path.exists(path):
        return slugs
    cur, body = None, ""
    for line in open(path):
        if line.startswith("## "):
            if cur and body.strip():
                slugs.add(cur)
            cur, body = line[3:].strip(), ""
        else:
            body += line
    if cur and body.strip():
        slugs.add(cur)
    return slugs


def esc(s):
    return (s or "").replace("|", "\\|")


def main():
    snap = load_snapshot()
    v = snap["vocab"]
    roasters = v["roasters"]
    countries = {c["id"]: c.get("name") for c in v["countries"]}
    coffees = snap.get("coffees", [])
    counts = collections.Counter(
        c["roasterId"] for c in coffees if c.get("roasterId") is not None
    )
    blurb_slugs = load_blurb_slugs()

    rows = [
        (
            r["name"],
            r["slug"],
            countries.get(r.get("country_id"), "") or "",
            counts.get(r["id"], 0),
            "✅" if have_logo(r["slug"]) else "☐",
            "✅" if r["slug"] in blurb_slugs else "☐",
        )
        for r in roasters
    ]
    rows.sort(key=lambda x: (-x[3], x[0].lower()))
    used = [r for r in rows if r[3] > 0]
    unused = [r for r in rows if r[3] == 0]

    out = []
    w = out.append
    w("# Roaster content checklist — logos + blurbs")
    w("")
    w(
        f"_Generated {datetime.date.today().isoformat()} from the live backend "
        f"snapshot ({len(roasters)} roasters, {len(coffees)} coffees). "
        "Regenerate with `python3 ops/roaster-assets/gen-checklist.py`._"
    )
    w("")
    w(
        "Tracks backlog **#132–#134**. Drop a logo as `logos/<slug>.png` "
        "(name the file by roaster; the `slug` below is the key I map it to). "
        "Paste blurbs in chat — I stage them into `blurbs.md` keyed by slug."
    )
    w("")
    w("- **Logo** / **Blurb**: ☐ = missing, ✅ = provided.")
    w("")
    w(f"## In your library ({len(used)} roasters, by # coffees)")
    w("")
    w("| Logo | Blurb | Roaster | slug | Country | Coffees |")
    w("|---|---|---|---|---|---|")
    for name, slug, country, n, lg, bl in used:
        w(f"| {lg} | {bl} | {esc(name)} | `{slug}` | {esc(country)} | {n} |")
    w("")
    w(
        f"## Seeded but unused — 0 coffees ({len(unused)}) — low priority / test fixtures"
    )
    w("")
    w("| Logo | Blurb | Roaster | slug | Country | Coffees |")
    w("|---|---|---|---|---|---|")
    for name, slug, country, n, lg, bl in unused:
        w(f"| {lg} | {bl} | {esc(name)} | `{slug}` | {esc(country)} | {n} |")
    w("")

    with open(os.path.join(HERE, "CHECKLIST.md"), "w") as f:
        f.write("\n".join(out) + "\n")
    print(f"wrote CHECKLIST.md — {len(used)} in-library, {len(unused)} unused")


if __name__ == "__main__":
    main()
