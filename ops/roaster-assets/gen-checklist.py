#!/usr/bin/env python3
"""Regenerate ops/roaster-assets/CHECKLIST.md from the live backend snapshot.

Usage:
    python3 ops/roaster-assets/gen-checklist.py            # fetch live snapshot
    python3 ops/roaster-assets/gen-checklist.py snap.json  # use a saved snapshot

Live fetch needs APP_TOKEN (or INGEST_TOKEN) in the environment; the Railway
host is on the cloud session's allow-list (CLAUDE.md §7). Tracks backlog
#132-#134: the roaster logo + blurb content Radu supplies.

Marks a roaster's Logo/Blurb ticked:
  - Blurb = the roaster's `blurb` column is non-empty in the live snapshot (the
    DB — the actual source of truth the app reads). Was previously keyed on a
    "## <slug>" section existing in blurbs.md, which reported ✅ for text that had
    been staged but never written to the DB (only migrations 029/030 had run),
    hiding a 15-vs-64 gap until #207/038 backfilled the rest. Staging is not
    delivery; this column now tracks delivery.
  - Logo  = the roaster's `logoUrl` is non-empty in the live snapshot, i.e. the
    app actually shows one. A file staged in logos/<slug>.* but not wired into
    `roasters.logo_url` renders as ◐, not ✅ — the same staged-vs-delivered gap
    the Blurb column shed in #207, closed here too (2026-09-14). The three
    states are deliberate rather than a binary: ◐ says "the art exists, it just
    needs a migration", which is a different job from ☐ "nobody has found a
    logo yet".
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


def staged_logo(slug):
    """A logo file sitting in this folder — staged, not necessarily delivered."""
    return bool(glob.glob(os.path.join(HERE, "logos", slug + ".*")))


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
    # average rating per roaster (over coffees that carry a rating)
    rating_sum = collections.defaultdict(float)
    rating_n = collections.Counter()
    for c in coffees:
        rid = c.get("roasterId")
        rat = c.get("rating")
        if rid is None or rat is None:
            continue
        try:
            rat = float(rat)  # NUMERIC can arrive as a JSON string
        except (TypeError, ValueError):
            continue
        rating_sum[rid] += rat
        rating_n[rid] += 1

    rows = []
    for r in roasters:
        rid = r["id"]
        avg = (rating_sum[rid] / rating_n[rid]) if rating_n[rid] else None
        rows.append(
            {
                "name": r["name"],
                "slug": r["slug"],
                "country": countries.get(r.get("country_id"), "") or "",
                "n": counts.get(rid, 0),
                "avg": avg,
                # Delivered (in the DB, so the app shows it) vs merely staged
                # (a file in logos/ that no migration has wired up).
                "logo": bool((r.get("logoUrl") or "").strip()),
                "logo_staged": staged_logo(r["slug"]),
                "blurb": bool((r.get("blurb") or "").strip()),
            }
        )

    used = [r for r in rows if r["n"] > 0]
    unused = [r for r in rows if r["n"] == 0]

    # In-library worklist order: incomplete first (missing logo OR blurb), then by
    # rating desc (unrated last), then by coffee count desc — so content lands on
    # the best-rated coffees first.
    def rank(r):
        complete = r["logo"] and r["blurb"]
        return (complete, -(r["avg"] if r["avg"] is not None else -1), -r["n"])

    used.sort(key=rank)
    unused.sort(key=lambda r: r["name"].lower())

    def cell(r):
        lg = "✅" if r["logo"] else ("◐" if r["logo_staged"] else "☐")
        bl = "✅" if r["blurb"] else "☐"
        avg = f"{r['avg']:.1f}" if r["avg"] is not None else "—"
        return (
            f"| {lg} | {bl} | {esc(r['name'])} | `{r['slug']}` | "
            f"{esc(r['country'])} | {r['n']} | {avg} |"
        )

    done_ct = sum(1 for r in used if r["logo"] and r["blurb"])
    staged_only_ct = sum(1 for r in rows if r["logo_staged"] and not r["logo"])
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
    w(
        "- **Both columns now track DELIVERY, not staging.** ✅ = live in the DB, "
        "so the app actually shows it. ☐ = missing. **Logo ◐** = the art is "
        "staged in `logos/` but no migration has wired it into "
        "`roasters.logo_url` yet — real work done, just not delivered."
    )
    w(
        "- This distinction is the whole point of #207: the Blurb column used to "
        "tick ✅ for text merely staged in `blurbs.md`, and reported everything "
        "green while 95 of 110 roasters had no blurb in the DB at all."
    )
    w(
        "- **★avg** = average rating across that roaster's rated coffees "
        "(— = none rated yet)."
    )
    w(
        "- Sorted **incomplete first** (still missing a logo or blurb), then by "
        "**★avg descending** — so the top rows are the highest-rated coffees still "
        "needing content."
    )
    w("")
    w(
        f"## In your library ({len(used)} roasters — {done_ct} complete, "
        f"{len(used) - done_ct} still need content)"
    )
    w("")
    w("| Logo | Blurb | Roaster | slug | Country | Coffees | ★avg |")
    w("|---|---|---|---|---|---|---|")
    for r in used:
        w(cell(r))
    w("")
    w(
        f"## Seeded but unused — 0 coffees ({len(unused)}) — low priority / test fixtures"
    )
    w("")
    w("| Logo | Blurb | Roaster | slug | Country | Coffees | ★avg |")
    w("|---|---|---|---|---|---|---|")
    for r in unused:
        w(cell(r))
    w("")

    with open(os.path.join(HERE, "CHECKLIST.md"), "w") as f:
        f.write("\n".join(out) + "\n")
    print(
        f"wrote CHECKLIST.md — {len(used)} in-library, {len(unused)} unused, "
        f"{staged_only_ct} logo(s) staged but not wired into roasters.logo_url"
    )


if __name__ == "__main__":
    main()
